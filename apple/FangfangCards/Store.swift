import Foundation
import SwiftUI

@MainActor
final class Store: ObservableObject {
    /// one store for the app and for Shortcuts actions that run while the app isn't open
    static let shared = Store()
    @Published private(set) var cards: [Card] = []
    @Published private(set) var loaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var progress = Progress() {
        didSet { recount() }
    }
    // counted once per change instead of on every screen redraw
    private(set) var seenCount = 0
    private(set) var unknownCount = 0
    private(set) var knownCount = 0
    private var newStart = 0          // every card before this index has been seen
    private var saveTask: Task<Void, Never>?
    @Published private(set) var canUndo = false
    @Published var backupFolderName: String?
    @Published var lastBackup: Date?

    private(set) var byKey: [String: Card] = [:]
    /// the full dictionary for 轉換 (loaded in the background the first time it's needed)
    @Published private(set) var dict: Dict?
    @Published private(set) var dictError: String?
    private var dictLoading = false
    private(set) var syl: [String: [String]] = [:]
    private(set) var places: [String] = []
    private(set) var topics: [Topic] = []
    /// 台語: the most common words and characters in groups of 500 (常用詞 1–500 …), for 新詞 and 學習進度
    @Published private(set) var freqTopics: [Topic] = []
    private var freqTopic: [String: Int] = [:]
    private var rank: [String: Int] = [:]
    private var pools: [Int: [Card]] = [:]          // common words by syllable count, for wrong answers
    private var undoStack: [(key: String, status: Int?, added: Double?, streak: Int?)] = []

    // MARK: 華語 mode
    /// the cards shown are 華語 ones (the 台語 deck waits in `other` meanwhile)
    @Published private(set) var isZh = false { didSet { T.zh = isZh } }
    /// the language shown: 0 台語, 1 華語, 2 粵語 (粵語 uses the 華語 pages, with its own dictionary)
    @Published private(set) var lang = 0 { didSet { T.yue = lang == 2 } }
    /// a hint to show (粵語 without a Cantonese voice on the device)
    @Published var speechHint: String?
    var isYue: Bool { lang == 2 }
    /// which of 華語 / 粵語 the dictionary in `zh` is (1 or 2)
    private var zhKind: Int { zh?.isYue == true ? 2 : 1 }
    /// switching language: the other deck is being loaded
    @Published private(set) var switching = false
    /// the 華語 dictionary (zh.json), once loaded
    @Published private(set) var zh: ZhDict?
    @Published private(set) var zhError: String?
    /// 華語 reading shown: 0 拼音, 1 注音 (published, so every page redraws when it changes)
    @Published var zhRom = Lang.zhRom { didSet { UserDefaults.standard.set(zhRom, forKey: Lang.romKey) } }
    /// the word list the 華語 cards follow: 0 HSK 3.0, 1 TOCFL
    @Published var zhList = Lang.zhList {
        didSet {
            guard zhList != oldValue else { return }
            UserDefaults.standard.set(zhList, forKey: Lang.listKey)
            UserDefaults.standard.set(-1, forKey: "zhTopic")
            rebuildZhDeck()
        }
    }
    /// changes when the deck is made again (pages showing it start over)
    @Published private(set) var listVersion = 0
    /// 華語 reading of: 0 臺灣, 1 大陸
    @Published var zhPlace = Lang.zhPlace { didSet { UserDefaults.standard.set(zhPlace, forKey: Lang.placeKey) } }
    private struct Deck { var cards: [Card] = []; var byKey: [String: Card] = [:]; var rank: [String: Int] = [:]; var pools: [Int: [Card]] = [:]; var topics: [Topic] = []; var kind = 0 }
    /// which language the deck waiting in `other` is (0 台語, 1 華語, 2 粵語)
    private var otherKind: Int { other?.kind ?? -1 }
    /// the one of 華語 / 粵語 used last (read in the background in 台語 mode, ready for switching)
    private static let lastZhKey = "lastZhKind"
    private var other: Deck?
    /// how many 華語 words are cards to swipe (the most common ones; every word is in the dictionary)
    static let zhDeckSize = 20000

    private var progressURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("progress.json")
    }

    // MARK: loading

    func load() {
        guard !loaded else { return }
        guard let url = Bundle.main.url(forResource: "cards", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            loadError = "找不到 cards.json"; return
        }
        do {
            let deck = try JSONDecoder().decode(DeckFile.self, from: data)
            cards = deck.cards
            syl = deck.syl ?? [:]
            places = deck.places ?? []
            topics = deck.topics ?? []
        } catch {
            loadError = "字典讀取失敗：\(error.localizedDescription)"; return
        }
        for (i, c) in cards.enumerated() {
            byKey[c.k] = c
            rank[c.k] = i
        }
        for c in cards.prefix(4000) { pools[c.syllables, default: []].append(c) }
        makeFreqTopics()
        if let d = try? Data(contentsOf: progressURL),
           let p = try? JSONDecoder().decode(Progress.self, from: d) {
            progress = p
        }
        loaded = true
        if Lang.isZh { setLanguage(Lang.current) }
        // both dictionaries are read when the app starts (in the background), so neither has to be waited for later
        loadDict()
        if !Lang.isZh { preloadZh() }
        migrateSenses()
        restoreBackupState()
        syncNow()
    }

    /// saves a moment later, off the main thread, so swiping never waits for the disk
    func save(syncChars: Bool = true) {
        // (a swipe does its own word's characters only: going through every 熟悉 word each time was slow)
        if syncChars { syncCharCards() }
        WidgetBridge.progressChanged(self)
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, let self, self.loaded,
                  let d = try? JSONEncoder().encode(self.progress) else { return }
            let url = self.progressURL
            await Task.detached { try? d.write(to: url, options: .atomic) }.value
        }
    }

    /// immediate save (when the app goes to the background)
    func saveNow() {
        saveTask?.cancel()
        guard loaded, let d = try? JSONEncoder().encode(progress) else { return }
        try? d.write(to: progressURL, options: .atomic)
    }

    private func recount() {
        var s = 0, u = 0, k = 0
        // only the language shown (台語 and 華語 words are counted apart)
        for (key, v) in progress.status where Lang.kind(key) == lang {
            if v != 0 { s += 1 }
            if v == 1 { k += 1 } else if v == 2 { u += 1 }
        }
        seenCount = s; unknownCount = u; knownCount = k
        newStart = 0
    }

    // MARK: lists

    // MARK: switching language

    func setLanguage(zh wantZh: Bool) { setLanguage(wantZh ? 1 : 0) }

    /// 0 台語, 1 華語, 2 粵語
    func setLanguage(_ want0: Int) {
        let want = min(max(want0, 0), 2)
        UserDefaults.standard.set(want, forKey: Lang.key)
        guard want != lang, !switching else { return }
        if want != 0 { UserDefaults.standard.set(want, forKey: Store.lastZhKey) }
        func shown(_ l: Int) { lang = l; isZh = l != 0; zhRom = Lang.zhRom; undoStack = []; canUndo = false; recount() }
        if want == 0 {
            if otherKind == 0 { swapDecks() }
            shown(0)
            return
        }
        // the deck waiting is the one wanted (台語 → 華語 / 粵語)
        if lang == 0, otherKind == want {
            swapDecks(); shown(want)
            return
        }
        switching = true
        Task {
            let result = await zhLoadTask(priority: .userInitiated, kind: want).value
            switch result {
            case .success(let (d, deck)):
                useZh(d, deck: deck)
            case .failure(let e):
                zhError = "\(Lang.names[want])詞典讀取失敗：\(e.localizedDescription)"
                UserDefaults.standard.set(lang, forKey: Lang.key)
                zhLoad = nil
            }
            switching = false
        }
    }

    /// the 華語 dictionary and deck being read (shared, so reading it at start-up and switching to 華語 meanwhile
    /// read it only once)
    private var zhLoad: Task<Result<(ZhDict, Deck), Error>, Never>?
    private var zhLoadKind = 0

    /// kind: 1 華語 (zh.json), 2 粵語 (yue.json)
    private func zhLoadTask(priority: TaskPriority, kind: Int) -> Task<Result<(ZhDict, Deck), Error>, Never> {
        if let t = zhLoad, zhLoadKind == kind { return t }
        let keys = Array(progress.status.keys.filter { Lang.kind($0) == kind }) + Array(progress.saved.keys.filter { Lang.kind($0) == kind })
        let size = Store.zhDeckSize
        let loadedDict = zh?.isYue == (kind == 2) ? zh : nil
        let list = zhList
        let t = Task.detached(priority: priority) { () -> Result<(ZhDict, Deck), Error> in
            do {
                let d: ZhDict
                if let have = loadedDict { d = have } else {
                    guard let url = Bundle.main.url(forResource: kind == 2 ? "yue" : "zh", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
                    d = try ZhDict(data: try Data(contentsOf: url, options: .mappedIfSafe))
                    // 粵語: the radicals (部首查字) from the 華語 data, if it's there
                    if d.isYue, let zu = Bundle.main.url(forResource: "zh", withExtension: "json"),
                       let zd = try? Data(contentsOf: zu, options: .mappedIfSafe) { d.borrowRadicals(from: zd) }
                }
                return .success((d, Store.makeZhDeck(d, list: list, keys: keys, size: size)))
            } catch { return .failure(error) }
        }
        zhLoad = t; zhLoadKind = kind
        return t
    }

    /// reads the 華語 (or 粵語, if that was used last) dictionary in the background (at start-up, in 台語 mode),
    /// ready for switching
    func preloadZh() {
        guard zh == nil else { return }
        let kind = UserDefaults.standard.integer(forKey: Store.lastZhKey) == 2 ? 2 : 1
        Task {
            if case .success(let (d, deck)) = await zhLoadTask(priority: .utility, kind: kind).value { useZh(d, deck: deck) }
        }
    }

    /// a 華語 / 粵語 dictionary is read: keep it, and use its deck now (if that language is wanted) or keep it
    /// for switching
    private func useZh(_ d: ZhDict, deck d0: Deck) {
        var deck = d0
        let kind = d.isYue ? 2 : 1
        deck.kind = kind
        // (the other one of 華語 / 粵語, read in the background, finishing after this one was chosen: not kept)
        if lang != 0, kind != Lang.current { return }
        let first = zh == nil
        zh = d
        zhLoad = nil
        // words already in 熟悉: their characters' cards too (and saved, so other devices get them)
        if first { save() }        // (save() first marks the character cards)
        if Lang.current == kind {
            guard lang != kind else { return }
            if lang == 0 { other = Deck(cards: cards, byKey: byKey, rank: rank, pools: pools, topics: topics, kind: 0) }
            cards = deck.cards; byKey = deck.byKey; rank = deck.rank; pools = deck.pools; topics = deck.topics
            lang = kind; isZh = true; zhRom = Lang.zhRom; undoStack = []; canUndo = false; recount()
            newStart = 0; queueTopic = -1
            save()
        } else if lang == 0 {
            other = deck
        }
        WidgetBridge.rebuildIfNeeded(self)      // the widgets can have the 華語 levels now
    }

    func clearZhError() { zhError = nil }

    /// the 華語 cards: the words of a word list (HSK 3.0 or TOCFL), level by level, the more common ones first
    /// in each level (an older zh.json without levels: the most common words)
    nonisolated private static func makeZhDeck(_ d: ZhDict, list: Int, keys: [String], size: Int) -> Deck {
        var deck = Deck()
        var order = d.entries.indices.filter { d.entries[$0].level(list) > 0 }
        order.sort { (d.entries[$0].level(list), $0) < (d.entries[$1].level(list), $1) }
        if order.isEmpty { order = Array(0..<min(d.cardCount, size)) }
        deck.cards.reserveCapacity(order.count)
        var counts: [Int: Int] = [:]
        for (n, i) in order.enumerated() {
            let c = d.card(i, list: list)
            deck.cards.append(c)
            deck.byKey[c.k] = c
            deck.rank[c.k] = n
            if n < 4000 { deck.pools[c.syllables, default: []].append(c) }
            let l = d.entries[i].level(list)
            if l > 0 { counts[l, default: 0] += 1 }
        }
        deck.topics = counts.keys.sorted().map { Topic(id: $0, name: d.isYue ? "常用詞 \(($0 - 1) * Lang.yueGroup + 1)–\($0 * Lang.yueGroup)" : Lang.levelName(list, $0), count: counts[$0]!) }
        // the character cards, after the words: level by level of the word list's character list, the more
        // common first; then the more common characters the list doesn't have
        let corder = d.chars.indices.sorted { a, b in
            let la = d.chars[a].level(list), lb = d.chars[b].level(list)
            return (la == 0 ? 99 : la, a) < (lb == 0 ? 99 : lb, b)
        }
        var ccounts: [Int: Int] = [:]
        for i in corder {
            let c = d.charCard(i, list: list)
            deck.rank[c.k] = deck.cards.count
            deck.cards.append(c)
            deck.byKey[c.k] = c
            if let t = c.cats?.first { ccounts[t, default: 0] += 1 }
        }
        deck.topics += ccounts.keys.sorted().map { t in
            Topic(id: t, name: t == Lang.moreChars ? "漢字・更多常用字"
                    : "漢字・" + (d.isYue ? Lang.yueCharLevelName(t - Lang.charTopicBase) : Lang.levelName(list, t - Lang.charTopicBase)), count: ccounts[t]!)
        }
        // rarer words you already have in 不熟 / 熟悉 / 收藏
        for k in keys where deck.byKey[k] == nil {
            if let i = d.index[k] { deck.byKey[k] = d.card(i, list: list) }
        }
        return deck
    }

    /// 設定 → 簡體字 changed: the 華語 / 粵語 cards are made again (their 漢字 shown the new way)
    func simplifiedChanged() { rebuildZhDeck(); objectWillChange.send() }

    /// another word list for the 華語 cards (HSK ⇄ TOCFL): the deck is made again
    private func rebuildZhDeck() {
        guard let d = zh, !switching else { return }
        switching = true
        let kind = zhKind
        let keys = Array(progress.status.keys.filter { Lang.kind($0) == kind }) + Array(progress.saved.keys.filter { Lang.kind($0) == kind })
        let list = zhList, size = Store.zhDeckSize
        Task {
            var deck = await Task.detached(priority: .userInitiated) { Store.makeZhDeck(d, list: list, keys: keys, size: size) }.value
            deck.kind = kind
            if lang == kind {
                cards = deck.cards; byKey = deck.byKey; rank = deck.rank; pools = deck.pools; topics = deck.topics
                newStart = 0; queueTopic = -1; undoStack = []; canUndo = false
            } else {
                other = deck
            }
            switching = false
            listVersion += 1
        }
    }

    private func swapDecks() {
        guard let o = other else { return }
        other = Deck(cards: cards, byKey: byKey, rank: rank, pools: pools, topics: topics, kind: lang)
        cards = o.cards; byKey = o.byKey; rank = o.rank; pools = o.pools; topics = o.topics
        newStart = 0; queueTopic = -1
    }

    /// a word of the language shown as a card (華語: rarer dictionary words become cards when they're needed)
    func card(for k: String) -> Card? {
        if let c = byKey[k] { return c }
        if let c = other?.byKey[k] { return c }          // the other language's word (from Shortcuts, widgets)
        if isZh, Lang.kind(k) == lang, lang == zhKind, let ch = Lang.charOf(k), let d = zh, let i = d.charIndex[ch] {
            let c = d.charCard(i, list: zhList)
            byKey[k] = c
            return c
        }
        guard isZh, Lang.kind(k) == lang, lang == zhKind, let d = zh, let i = d.index[k] else { return nil }
        let c = d.card(i, list: zhList)
        byKey[k] = c
        return c
    }

    /// a word of either language (for syncing: the other language's words are kept too)
    private func isWord(_ k: String) -> Bool {
        byKey[k] != nil || other?.byKey[k] != nil
            || (Lang.isZhKey(k) && (zh == nil || Lang.kind(k) != zhKind || zh?.index[k] != nil || Lang.charOf(k).map { zh?.charIndex[$0] != nil } == true))
    }

    // MARK: 本週學習 (this week's words)

    private var weekLang: String { ["tw", "zh", "yue"][lang] }

    /// this week's words (in the language shown), in the order they were picked
    var weekCards: [Card] {
        progress.week.filter { $0.value > 0 && isShownLanguage($0.key) }
            .sorted { $0.value < $1.value }
            .compactMap { card(for: $0.key) }
    }
    func isInWeek(_ k: String) -> Bool { (progress.week[k] ?? -1) > 0 }

    /// when this week started (nil = no week going)
    var weekStartDate: Date? {
        guard let t = progress.weekStart[weekLang], t > 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }
    /// days left of the week (0 = it's time for the test)
    var weekDaysLeft: Int {
        guard let s = weekStartDate else { return 7 }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: s),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        return max(0, 7 - days)
    }

    func toggleWeek(_ k: String) { setWeek([k], on: !isInWeek(k)) }

    func setWeek(_ keys: [String], on: Bool) {
        var now = Date().timeIntervalSince1970
        for k in keys {
            now += 0.001                       // keeps the order they were picked in
            progress.week[k] = on ? now : -now
        }
        // the first word picked starts the week
        if on, weekStartDate == nil { progress.weekStart[weekLang] = Date().timeIntervalSince1970 }
        if weekCards.isEmpty, let t = progress.weekStart[weekLang], t > 0 { progress.weekStart[weekLang] = -Date().timeIntervalSince1970 }
        save()
    }

    /// the week is over: its words are taken out (`keep` = words that go on to next week, which starts now)
    func finishWeek(keep: [String] = []) {
        let now = Date().timeIntervalSince1970
        for c in weekCards where !keep.contains(c.k) { progress.week[c.k] = -now }
        if keep.isEmpty {
            progress.weekStart[weekLang] = -now
        } else {
            progress.weekStart[weekLang] = now + 0.001
            for k in keep { progress.week[k] = now + 0.002 }
        }
        save()
    }

    // MARK: word lists

    /// the words of a level of the word list (HSK / TOCFL), in order
    func levelCards(_ level: Int) -> [Card] { cards.filter { inTopic($0, level) } }

    /// 台語 常用詞 / 常用字 groups: the cards are the most common first, so every 500 words (or characters) a group
    private func makeFreqTopics() {
        var nw = 0, nc = 0
        var counts: [Int: Int] = [:]
        for c in cards {
            let t: Int
            if c.h.count == 1 { t = Lang.freqCharBase + nc / Lang.freqSize; nc += 1 }
            else { t = Lang.freqWordBase + nw / Lang.freqSize; nw += 1 }
            freqTopic[c.k] = t
            counts[t, default: 0] += 1
        }
        freqTopics = counts.keys.sorted().map { Topic(id: $0, name: Lang.freqName($0, count: counts[$0]!), count: counts[$0]!) }
    }

    /// a card is in a topic: a 分類 or level (its cats), or a 台語 常用 group
    func inTopic(_ c: Card, _ t: Int) -> Bool {
        if Lang.isFreqTopic(t) { return !c.isZh && freqTopic[c.k] == t }
        return c.cats?.first == t || (!c.isZh && c.cats?.contains(t) == true)
    }

    /// many words at once to 熟悉 (or back to 新詞)
    func markAll(_ list: [Card], known: Bool) {
        let now = Date().timeIntervalSince1970
        var p = progress        // changed on a copy and put back once (counted once, not once per word)
        for c in list {
            if known {
                guard p.status[c.k] != 1 else { continue }
                p.status[c.k] = 1; p.streak[c.k] = nil
            } else {
                guard (p.status[c.k] ?? 0) != 0 else { continue }
                p.status[c.k] = 0; p.streak[c.k] = nil
            }
            p.added[c.k] = now
        }
        progress = p
        undoStack = []; canUndo = false
        save()
    }

    /// hskProgress for every topic at once (one pass over the cards)
    func allTopicProgress() -> [Int: (total: Int, known: Int, unknown: Int)] {
        var out: [Int: (total: Int, known: Int, unknown: Int)] = [:]
        for c in cards {
            let t: Int
            if !c.isZh, let f = freqTopic[c.k] { t = f } else if let l = c.cats?.first { t = l } else { continue }
            var p = out[t] ?? (0, 0, 0)
            p.total += 1
            switch progress.status[c.k] { case 1?: p.known += 1; case 2?: p.unknown += 1; default: break }
            out[t] = p
        }
        return out
    }

    /// progress on a level of the word list (HSK / TOCFL): (words, 熟悉, 不熟)
    func hskProgress(_ level: Int) -> (total: Int, known: Int, unknown: Int) {
        var t = 0, k = 0, u = 0
        for c in cards where inTopic(c, level) {
            t += 1
            switch progress.status[c.k] { case 1?: k += 1; case 2?: u += 1; default: break }
        }
        return (t, k, u)
    }

    /// 華語 漢字 you know: every character of a word in 熟悉 is known (also when it's in a word that's still in
    /// 不熟); the characters of 不熟 words that aren't in any 熟悉 word are 不熟. total = the characters of the
    /// word list's words, and of any other word you have marked
    func zhCharProgress() -> (total: Int, known: Int, unknown: Int) {
        let c = zhCharSets()
        return (c.all.count, c.known.count, c.unknown.count)
    }

    /// the characters for 認識的漢字: all of them in the order they come in the cards (the word list level by
    /// level, then any other word you've marked), and which are 熟悉 / 不熟
    func zhCharSets() -> (all: [String], known: Set<String>, unknown: Set<String>) {
        func hans(_ s: String) -> [String] { Array(s.unicodeScalars).filter { Zhuyin.isHan($0) }.map { String($0) } }
        var known = Set<String>(), unknown = Set<String>(), seen = Set<String>(), all: [String] = []
        func add(_ cs: [String]) { for ch in cs where seen.insert(ch).inserted { all.append(ch) } }
        // every card you can swipe: the word list's words and all the character cards
        for c in cards { add(hans(c.h)) }
        for (k, v) in progress.status where v != 0 && Lang.kind(k) == lang {
            let cs = hans(String(k.split(separator: "\t", maxSplits: 1).first ?? ""))
            add(cs)
            if v == 1 { known.formUnion(cs) } else if v == 2 { unknown.formUnion(cs) }
        }
        unknown.subtract(known)
        // a character card marked 不熟 after its words were learned (held in 認識的漢字): 不熟 wins
        for (k, v) in progress.status where v == 2 {
            guard let ch = Lang.charOf(k) else { continue }
            known.remove(ch); unknown.insert(ch)
        }
        return (all, known, unknown)
    }

    /// 華語: every character of a 熟悉 word is known, so its character card is marked 熟悉 too (you don't have
    /// to mark it again in the character lists). Done in one go, so the counts are worked out once.
    func syncCharCards() {
        guard let d = zh, !d.chars.isEmpty else { return }
        let kind = d.isYue ? 2 : 1
        var want: [String] = []
        var seen = Set<String>()
        for (k, v) in progress.status where v == 1 && Lang.charOf(k) == nil && Lang.kind(k) == kind {
            guard let t = k.firstIndex(of: "\t") else { continue }
            for u in k[..<t].unicodeScalars where Zhuyin.isHan(u) {
                let ch = String(u)
                guard seen.insert(ch).inserted, d.charIndex[ch] != nil else { continue }
                let ck = Lang.charKey(ch, yue: d.isYue)
                switch progress.status[ck] {
                case 1?: break
                // marked 不熟 by hand after the word was learned: left as it is
                case 2? where (progress.added[ck] ?? 0) >= (progress.added[k] ?? 0): break
                default: want.append(ck)
                }
            }
        }
        guard !want.isEmpty else { return }
        var p = progress
        let now = Date().timeIntervalSince1970
        for ck in want { p.status[ck] = 1; p.added[ck] = now; p.streak[ck] = nil }
        progress = p
    }

    /// 認識的漢字: hold a character to make it 熟悉 or 不熟 (its character card); false = it has no card
    @discardableResult
    func setCharKnown(_ ch: String, _ known: Bool) -> Bool {
        guard let c = card(for: Lang.charKey(ch)) else { return false }
        mark(c, known: known, undoable: false)
        return true
    }

    /// each language's cards and topics, whichever is shown now (for the widgets; 華語 once it has loaded)
    var twDeck: (cards: [Card], topics: [Topic]) {
        if !isZh { return (cards, topics) }
        if let o = other, o.kind == 0 { return (o.cards, o.topics) }
        return ([], [])
    }
    var zhDeck: (cards: [Card], topics: [Topic]) {
        if isZh { return (cards, topics) }
        if let o = other, o.kind != 0 { return (o.cards, o.topics) }
        return ([], [])
    }

    /// the words of the language shown
    func isShownLanguage(_ k: String) -> Bool { Lang.kind(k) == lang }

    func status(_ c: Card) -> Int? { progress.status[c.k] }
    func streak(_ c: Card) -> Int { progress.streak[c.k] ?? 0 }

    /// next unseen words, most common first
    private var queueTopic = -1
    /// next unseen words, most common first; topic = a 分類 index or -1 for everything
    func newQueue(_ n: Int, topic: Int = -1) -> [Card] {
        if topic != queueTopic { queueTopic = topic; newStart = 0 }
        var out: [Card] = []
        var i = newStart
        var first: Int?
        while i < cards.count && out.count < n {
            if (progress.status[cards[i].k] ?? 0) == 0 && (topic < 0 || (Lang.isFreqTopic(topic) ? inTopic(cards[i], topic) : cards[i].cats?.contains(topic) == true)) {
                if first == nil { first = i }
                out.append(cards[i])
            }
            i += 1
        }
        newStart = first ?? cards.count
        return out
    }

    /// newest first
    private func list(_ s: Int) -> [Card] {
        progress.status.compactMap { $0.value == s && isShownLanguage($0.key) ? card(for: $0.key) : nil }
            .sorted { (progress.added[$0.k] ?? 0) > (progress.added[$1.k] ?? 0) }
    }
    var unknownCards: [Card] { list(2) }

    /// 不熟 → 練習範圍: practise only the 不熟 words of one level / group (-1 = all of 不熟).
    /// 華語: an HSK / TOCFL level (words) or 100 + level (characters); 台語: a 常用詞 / 常用字 group.
    @Published var practiceTopicZh = UserDefaults.standard.object(forKey: "practiceTopic.zh") as? Int ?? -1 {
        didSet { UserDefaults.standard.set(practiceTopicZh, forKey: "practiceTopic.zh") }
    }
    @Published var practiceTopicTw = UserDefaults.standard.object(forKey: "practiceTopic.tw") as? Int ?? -1 {
        didSet { UserDefaults.standard.set(practiceTopicTw, forKey: "practiceTopic.tw") }
    }
    var practiceTopic: Int {
        get { isZh ? practiceTopicZh : practiceTopicTw }
        set { if isZh { practiceTopicZh = newValue } else { practiceTopicTw = newValue } }
    }
    /// the practice topics there are now (the levels / groups that have words)
    var practiceTopics: [Topic] { isZh ? topics : freqTopics }
    /// the 不熟 words to practise (練習範圍)
    var practiceCards: [Card] {
        let u = unknownCards
        let t = practiceTopic
        guard t >= 0, practiceTopics.contains(where: { $0.id == t }) else { return u }
        return u.filter { inTopic($0, t) }
    }
    var practiceName: String {
        practiceTopics.first(where: { $0.id == practiceTopic })?.name ?? trs("全部不熟的詞")
    }
    var knownCards: [Card] { list(1) }

    // MARK: changes

    /// swipe: right = known, left = unknown
    func mark(_ c: Card, known: Bool, undoable: Bool = true) {
        if undoable {
            undoStack.append((c.k, progress.status[c.k], progress.added[c.k], progress.streak[c.k]))
            if undoStack.count > 50 { undoStack.removeFirst() }
            canUndo = true
        }
        // one change to progress (so the counts are worked out, and the screen redrawn, once)
        var p = progress
        p.status[c.k] = known ? 1 : 2
        p.added[c.k] = Date().timeIntervalSince1970
        if known { p.streak[c.k] = nil } else if p.streak[c.k] == nil { p.streak[c.k] = 0 }
        if known { knowChars(of: c.k, in: &p) }
        progress = p
        save(syncChars: false)
    }

    /// 華語: a word marked 熟悉 makes its characters' cards 熟悉 too (what syncCharCards does, for one word)
    private func knowChars(of k: String, in p: inout Progress) {
        guard let d = zh, !d.chars.isEmpty, Lang.charOf(k) == nil, Lang.kind(k) == (d.isYue ? 2 : 1), let t = k.firstIndex(of: "\t") else { return }
        let now = Date().timeIntervalSince1970
        for u in k[..<t].unicodeScalars where Zhuyin.isHan(u) {
            let ch = String(u)
            guard d.charIndex[ch] != nil else { continue }
            let ck = Lang.charKey(ch, yue: d.isYue)
            switch p.status[ck] {
            case 1?: break
            case 2? where (p.added[ck] ?? 0) >= (p.added[k] ?? 0): break
            default: p.status[ck] = 1; p.added[ck] = now; p.streak[ck] = nil
            }
        }
    }

    func undo() {
        guard let u = undoStack.popLast() else { return }
        var p = progress
        p.status[u.key] = u.status
        p.added[u.key] = u.added
        p.streak[u.key] = u.streak
        progress = p
        canUndo = !undoStack.isEmpty
        save(syncChars: false)
    }

    /// back to the new-word pile (kept as status 0 so other devices learn about it when syncing)
    func forget(_ c: Card) {
        progress.status[c.k] = 0
        progress.added[c.k] = Date().timeIntervalSince1970
        progress.streak[c.k] = nil
        save()
    }

    /// study answer; returns true when the word has been learned (moved to 熟悉)
    @discardableResult
    func answer(_ c: Card, correct: Bool, goal: Int) -> Bool {
        guard progress.status[c.k] == 2 else { return false }
        if correct {
            let s = (progress.streak[c.k] ?? 0) + 1
            if s >= goal {
                progress.status[c.k] = 1
                progress.added[c.k] = Date().timeIntervalSince1970
                progress.streak[c.k] = nil
                save()
                return true
            }
            progress.streak[c.k] = s
        } else {
            progress.streak[c.k] = 0
        }
        save()
        return false
    }

    /// words starred (☆) in the 轉換 tab go to 不熟 (unless switched off in 設定)
    func addFromConverter(_ saved: [String]) {
        guard loaded, UserDefaults.standard.object(forKey: "convSync") as? Bool ?? true else { return }
        let now = Date().timeIntervalSince1970
        var n = 0
        var p = progress
        for s in saved {
            let k = s.split(separator: "\t", omittingEmptySubsequences: false).prefix(2).joined(separator: "\t")
            guard byKey[k] != nil, (p.status[k] ?? 0) == 0 else { continue }
            p.status[k] = 2
            p.added[k] = now
            p.streak[k] = 0
            n += 1
        }
        if n > 0 { progress = p; save() }
    }

    func loadDict() {
        guard dict == nil, !dictLoading else { return }
        dictLoading = true
        Task {
            let result: Result<Dict, Error> = await Task.detached(priority: .userInitiated) { () -> Result<Dict, Error> in
                do {
                    guard let url = Bundle.main.url(forResource: "dict", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
                    let data = try Data(contentsOf: url)
                    return .success(Dict(try JSONDecoder().decode(DictRaw.self, from: data)))
                } catch { return .failure(error) }
            }.value
            switch result {
            case .success(let d):
                d.setUserWords(Set(self.ownKeys))       // your 自訂 words join the dictionary
                self.dict = d
            case .failure(let e): self.dictError = "字典讀取失敗：\(e.localizedDescription)"
            }
            self.dictLoading = false
        }
    }

    /// the place's other way(s) of saying a card's word: (羅馬字, 方音)
    func alsoSaid(_ card: Card, _ rom: Int, _ place: Int) -> [(rom: String, zy: String)] {
        guard !card.isZh, place >= 0, let d = dict else { return [] }
        let r = min(max(rom, 0), 2)
        return d.alsoSaid(card.k, place).map { (d.codes($0, r, place), d.codes($0, 3, place)) }
    }

    /// a card's 漢字: in tone colours when 聲調顏色 is on
    func cardHan(_ card: Card, _ place: Int, base: Color) -> AttributedString {
        if let s = card.zs, let d = zh { return d.hanText(card.h, Lang.zhPlace == 1 ? (card.zl ?? s) : s, base: base) }
        if ToneColors.system != 0, let d = dict { return d.hanText(card.k, place, base: base) }
        var a = AttributedString(card.h); a.swiftUI.foregroundColor = base
        return a
    }

    /// a card's reading, with syllables guessed for the place in red
    func cardRom(_ card: Card, _ rom: Int, _ place: Int) -> AttributedString {
        if let s = card.zs, let d = zh { return d.reading(Lang.zhPlace == 1 ? (card.zl ?? s) : s, Lang.zhRom) }
        let r = min(max(rom, 0), 2)
        if ToneColors.system != 0, let d = dict { return d.wordText(card.k, r, place) }      // 聲調顏色
        if place >= 0, let d = dict, !d.guessedSyllables(card.k, place).isEmpty { return d.wordText(card.k, r, place) }
        return AttributedString(card.rom(r, place))
    }
    func cardZy(_ card: Card, _ place: Int) -> AttributedString {
        if card.isZh { return AttributedString() }      // 華語: one reading line (拼音 or 注音)
        if place >= 0 || ToneColors.system != 0, let d = dict { return d.wordText(card.k, 3, place) }
        return AttributedString(card.zy(place))
    }

    /// a card's example in 羅馬字, in the chosen place's readings when the dictionary is loaded
    /// (guessed readings are red)
    func exampleRom(_ card: Card, _ x: Example, _ rom: Int, _ place: Int) -> AttributedString {
        if let w = x.w, let d = zh { return d.sentence(ZhDict.pieces(x.h, w), Lang.zhRom, Lang.zhPlace) }
        let r = min(max(rom, 0), 2)
        guard place >= 0 || ToneColors.system != 0, let d = dict, let e = dictExample(d, card, x) else { return AttributedString(x.r[r]) }
        return d.sentenceText(e[1], r, place: place, han: e[0], zh: e.count > 2 ? e[2] : nil)
    }

    /// a card's example in 漢字; with a place, the words that place says differently are swapped in (pink)
    func exampleHan(_ card: Card, _ x: Example, _ place: Int) -> AttributedString {
        if let w = x.w, let d = zh { return d.sentenceHan(ZhDict.pieces(x.h, w), Lang.zhPlace, base: T.blueInk) }
        if place >= 0 || ToneColors.system != 0, let d = dict, let e = dictExample(d, card, x) {
            return d.exampleHanText(e[0], e[1], place: place, zh: e.count > 2 ? e[2] : nil, base: T.blueInk)
        }
        var a = AttributedString(x.h); a.swiftUI.foregroundColor = T.blueInk
        return a
    }

    /// 例句填空: the example with the word blanked out, in the chosen place's readings
    func blankRom(_ card: Card, _ x: Example, _ rom: Int, _ place: Int) -> AttributedString? {
        if let w = x.w, let d = zh { return d.sentence(ZhDict.pieces(x.h, w), Lang.zhRom, Lang.zhPlace, blank: card.h) }
        let r = min(max(rom, 0), 2)
        if place >= 0, let d = dict, let e = dictExample(d, card, x),
           let ps = d.blankSentencePieces(e[1], han: e[0], word: Dict.codesOf(card.k).split(separator: " ").map(String.init), r, place: place) {
            return guessColored(ps, guess: T.guessInk)
        }
        return x.br.map { AttributedString($0[r]) }
    }

    /// does any example of this card have a guessed reading for the place?
    func cardHasGuess(_ card: Card, _ place: Int) -> Bool {
        guard !card.isZh, place >= 0, let d = dict else { return false }
        return card.d.contains { $0.x.contains { x in dictExample(d, card, x).map { d.hasGuess($0[1], han: $0[0], place: place) } ?? false } }
    }

    private func dictExample(_ d: Dict, _ card: Card, _ x: Example) -> [String]? {
        d.raw.ex[card.k]?.joined().first(where: { $0.count > 3 && $0[0] == x.h && $0[3] == x.n })
    }

    /// the card's own reading for the place is worked out by rule, not stated by the dictionary
    func isGuessed(_ card: Card, _ place: Int) -> Bool {
        guard !card.isZh, place >= 0, cardDiffers(card, place), let d = dict else { return false }
        return !d.isStated(card.k, place)
    }

    /// the card's reading in the place differs from 通行 (not counting 臺南/高雄 o → or, which is the same sound)
    func cardDiffers(_ card: Card, _ place: Int) -> Bool {
        if card.isZh { return false }
        if let d = dict { return d.differsFromCommon(card.k, place) }
        return card.differs(in: place)
    }

    /// status of a dictionary word in the cards: nil = not a card
    func cardStatus(_ key: String) -> Int? {
        guard card(for: key) != nil else { return nil }
        return progress.status[key] ?? 0
    }

    /// ☆ in 轉換: add to 不熟, or tap again to take it back out to 新詞
    func toggleUnknown(_ key: String) {
        guard let c = card(for: key) else { return }
        if progress.status[key] == 2 { forget(c) } else { mark(c, known: false, undoable: false) }
    }

    // MARK: 收藏 (轉換)

    func isSaved(_ key: String) -> Bool { (progress.saved[key] ?? -1) > 0 }

    func toggleSaved(_ key: String) {
        let now = Date().timeIntervalSince1970
        progress.saved[key] = isSaved(key) ? -now : now
        save()
    }

    // MARK: 自訂 (your own words)

    /// your own words, newest first
    var ownKeys: [String] { progress.own.filter { $0.value > 0 }.sorted { $0.value > $1.value }.map { $0.key } }
    func isOwn(_ key: String) -> Bool { (progress.own[key] ?? -1) > 0 }

    func addOwn(_ key: String) {
        progress.own[key] = Date().timeIntervalSince1970
        save()
        applyOwn()
    }
    func removeOwn(_ key: String) {
        progress.own[key] = -Date().timeIntervalSince1970
        save()
        applyOwn()
    }
    /// let 轉換 and 詞典 know about the current list
    func applyOwn() { dict?.setUserWords(Set(ownKeys)) }

    /// how common a word is (its place in the card order)
    func rankOf(_ key: String) -> Int { rank[key] ?? Int.max }

    /// words not yet seen go to 不熟 (words already in 不熟 / 熟悉 stay where they are)
    func addUnknown(_ keys: [String]) {
        let now = Date().timeIntervalSince1970
        var n = 0
        var p = progress
        for k in keys where card(for: k) != nil && (p.status[k] ?? 0) == 0 {
            p.status[k] = 2
            p.added[k] = now
            p.streak[k] = 0
            n += 1
        }
        if n > 0 { progress = p; save() }
    }

    func saveAll(_ keys: [String]) {
        let now = Date().timeIntervalSince1970
        var p = progress
        for (i, k) in keys.enumerated() where (p.saved[k] ?? -1) <= 0 { p.saved[k] = now + Double(keys.count - i) * 0.001 }
        progress = p
        save()
    }

    func unsave(_ keys: [String]) {
        let now = Date().timeIntervalSince1970
        var p = progress
        for k in keys { p.saved[k] = -now }
        progress = p
        save()
    }

    // MARK: 收藏 of one meaning / one sentence

    func isSaved(_ s: SavedSense) -> Bool { (progress.senses[s.id] ?? -1) > 0 }

    func toggleSaved(_ s: SavedSense) {
        let now = Date().timeIntervalSince1970
        progress.senses[s.id] = isSaved(s) ? -now : now
        save()
    }

    func unsave(_ s: SavedSense) {
        progress.senses[s.id] = -Date().timeIntervalSince1970
        save()
    }

    /// saved meanings, newest first
    var savedSenses: [SavedSense] {
        progress.senses.filter { $0.value > 0 }.sorted { $0.value > $1.value }.compactMap { SavedSense(id: $0.key) }
            .filter { $0.ex.isEmpty && isShownLanguage($0.key) }
    }

    /// words with at least one meaning saved (the blue star in 轉換)
    var savedSenseKeys: Set<String> { Set(savedSenses.map(\.key)) }

    /// an earlier version could save single sentences: each becomes its whole meaning
    func migrateSenses() {
        var changed = false
        let now = Date().timeIntervalSince1970
        for (id, t) in progress.senses where t > 0 {
            guard let s = SavedSense(id: id), !s.ex.isEmpty else { continue }
            let m = SavedSense(key: s.key, sense: s.sense).id
            if (progress.senses[m] ?? -1) < t { progress.senses[m] = t }
            progress.senses[id] = -now
            changed = true
        }
        if changed { save() }
    }

    /// saved words, newest first
    var savedKeys: [String] {
        progress.saved.filter { $0.value > 0 && isShownLanguage($0.key) }.sorted { $0.value > $1.value }.map { $0.key }
    }

    /// 收藏 as the same nine-column CSV
    func savedCSV(_ d: Dict) -> String {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var rows = ["詞;皓羅;詞性;釋義;例句;例句皓羅;例句華語;音檔;例句音檔"]
        for k in savedKeys {
            let h = Dict.hanOf(k), r = d.word(k, 0, -1)
            let audio = d.raw.au[k].map { "\($0)(1)" } ?? ""
            let senses = d.senses(k)
            if senses.isEmpty { rows.append([h, r, "", "", "", "", "", audio, ""].map(q).joined(separator: ";")) }
            for s in senses {
                let x = s.ex.first
                rows.append([h, r, s.pos, s.text, x?[0] ?? "", x.map { $0.count > 1 ? d.sentence($0[1], 0) : "" } ?? "",
                             x.map { $0.count > 2 ? $0[2] : "" } ?? "", audio, x.map { $0.count > 3 ? $0[3] : "" } ?? ""]
                    .map(q).joined(separator: ";"))
            }
        }
        // saved meanings: one row each with everything that belongs to the meaning; its sentences (and their
        // recordings) one after another in the same columns, separated by <br> (a line break in Anki)
        for s in savedSenses {
            let senses = d.senses(s.key)
            guard s.sense < senses.count else { continue }
            let m = senses[s.sense]
            let h = Dict.hanOf(s.key), r = d.word(s.key, 0, -1)
            let audio = d.raw.au[s.key].map { "\($0)(1)" } ?? ""
            let xs = m.ex
            rows.append([h, r, m.pos, m.text,
                         xs.map { $0[0] }.joined(separator: "<br>"),
                         xs.map { $0.count > 1 ? d.sentence($0[1], 0) : "" }.joined(separator: "<br>"),
                         xs.map { $0.count > 2 ? $0[2] : "" }.joined(separator: "<br>"),
                         audio,
                         xs.map { $0.count > 3 ? $0[3] : "" }.joined(separator: "<br>")]
                .map(q).joined(separator: ";"))
        }
        return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
    }

    /// every word back to 新詞 (stamped with the time, so synced devices reset too)
    func resetAll() {
        let now = Date().timeIntervalSince1970
        var p = Progress()
        for k in progress.status.keys { p.status[k] = 0; p.added[k] = now }
        progress = p
        undoStack = []
        canUndo = false
        save()
    }

    // MARK: study helpers

    /// wrong answers for a multiple-choice question
    func distractors(for c: Card, count: Int = 3) -> [Card] {
        var pool = pools[c.syllables] ?? []
        if pool.count < 20 { pool = Array(cards.prefix(4000)) }
        var out: [Card] = []
        var usedH: Set<String> = [c.h], usedM: Set<String> = [c.firstMeaning], usedR: Set<String> = [c.r[0]]
        var tries = 0
        while out.count < count && tries < 200 {
            tries += 1
            guard let x = pool.randomElement() else { break }
            if usedH.contains(x.h) || usedM.contains(x.firstMeaning) || usedR.contains(x.r[0]) { continue }
            usedH.insert(x.h); usedM.insert(x.firstMeaning); usedR.insert(x.r[0])
            out.append(x)
        }
        return out
    }

    // MARK: export / import

    /// nine columns, semicolon separated, one row per meaning (same as the website's 收藏 CSV)
    func csv(_ list: [Card]) -> String {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == ";" || $0 == "\"" || $0 == "\n" })
                ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var rows = ["詞;皓羅;詞性;釋義;例句;例句皓羅;例句華語;音檔;例句音檔"]
        for c in list {
            for d in c.d {
                let x = d.x.first
                let audio = c.isZh ? "" : (c.a.map { "\($0)(1)" } ?? "")
                let xr = x.map { x in c.isZh ? String(exampleRom(c, x, 0, -1).characters) : x.r[0] } ?? ""
                let xn = c.isZh ? "" : (x?.n ?? "")
                rows.append([c.h, c.isZh ? String(cardRom(c, 0, -1).characters) : c.r[0], d.p, d.t, x?.h ?? "", xr, x?.z ?? "", audio, xn]
                    .map(q).joined(separator: ";"))
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
    }

    /// Merge another device's / an older backup's progress: for each word the newer change wins.
    /// Returns how many words changed. (Worked on a copy and put back once: changing `progress` a word at a time
    /// recounted everything after every word, which made a big backup take a long time.)
    func mergeProgress(_ obj: [String: Any]) -> Int {
        var p = progress
        let r = Self.merge(&p, obj, from: 0, to: Int.max, isWord: isWord)
        progress = p
        if r.ownChanged { applyOwn() }
        return r.n
    }

    /// the merge itself, on a copy. The words (status) can be done a slice at a time: from..<to of them, in key
    /// order (the rest — 收藏, 本週, 自訂 — with the first slice).
    private static func merge(_ p: inout Progress, _ obj: [String: Any], from: Int, to: Int,
                              isWord: (String) -> Bool) -> (n: Int, ownChanged: Bool) {
        let status = obj["status"] as? [String: Int] ?? [:]
        let added = obj["added"] as? [String: Double] ?? [:]
        let streak = obj["streak"] as? [String: Int] ?? [:]
        var n = 0
        var ownChanged = false
        if from == 0 {
            for (k, t) in obj["saved"] as? [String: Double] ?? [:] where abs(t) > abs(p.saved[k] ?? 0) {
                if (t > 0) != ((p.saved[k] ?? -1) > 0) { n += 1 }
                p.saved[k] = t
            }
            for (k, t) in obj["week"] as? [String: Double] ?? [:] where abs(t) > abs(p.week[k] ?? 0) {
                if (t > 0) != ((p.week[k] ?? -1) > 0) { n += 1 }
                p.week[k] = t
            }
            // the week that was started (or ended) last wins: a start is a time, an end is minus that time
            for (k, t) in obj["weekStart"] as? [String: Double] ?? [:] where abs(t) > abs(p.weekStart[k] ?? 0) {
                p.weekStart[k] = t
            }
            for (k, t) in obj["senses"] as? [String: Double] ?? [:] where abs(t) > abs(p.senses[k] ?? 0) {
                if (t > 0) != ((p.senses[k] ?? -1) > 0) { n += 1 }
                p.senses[k] = t
            }
            for (k, t) in obj["own"] as? [String: Double] ?? [:] where abs(t) > abs(p.own[k] ?? 0) {
                if (t > 0) != ((p.own[k] ?? -1) > 0) { n += 1; ownChanged = true }
                p.own[k] = t
            }
        }
        let keys = status.keys.sorted()
        guard from < keys.count else { return (n, ownChanged) }
        for k in keys[from..<min(to, keys.count)] where isWord(k) {
            let s = status[k]!
            let theirs = added[k] ?? 0, mine = p.added[k] ?? -1
            if theirs > mine || (p.status[k] == nil && theirs >= mine) {
                if p.status[k] != s { n += 1 }
                p.status[k] = s
                p.added[k] = theirs
                p.streak[k] = s == 2 ? max(streak[k] ?? 0, p.streak[k] ?? 0) : nil
            } else if s == 2, p.status[k] == 2, let t = streak[k], t > (p.streak[k] ?? 0), theirs == mine {
                p.streak[k] = t
            }
        }
        return (n, ownChanged)
    }

    /// importing a backup, a slice at a time, so a progress bar can show how far it is (0–1)
    @MainActor
    func importBackup(_ data: Data, progress report: @escaping (Double) -> Void) async -> String {
        report(0.02)
        let parsed = await Task.detached(priority: .userInitiated) { () -> [String: Any]? in
            try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }.value
        guard let obj = parsed else { return "讀不到這個檔案。" }
        report(0.12)
        guard obj["app"] as? String == "fangfang-cards" else { return importBackup(data) }
        let total = (obj["status"] as? [String: Int])?.count ?? 0
        var p = progress
        var n = 0, own = false
        let step = 1500
        var from = 0
        repeat {
            let r = Self.merge(&p, obj, from: from, to: from + step, isWord: isWord)
            n += r.n; own = own || r.ownChanged
            from += step
            report(0.12 + 0.78 * (total == 0 ? 1 : min(1, Double(from) / Double(total))))
            await Task.yield()
        } while from < total
        progress = p
        if own { applyOwn() }
        report(0.95)
        await Task.yield()
        save()
        report(1)
        return "已匯入，更新了 \(n) 個詞。"
    }

    func backupData() -> Data {
        let obj: [String: Any] = [
            "app": "fangfang-cards", "version": 1,
            "exported": ISO8601DateFormatter().string(from: Date()),
            "status": progress.status, "added": progress.added, "streak": progress.streak,
            "saved": progress.saved, "own": progress.own, "senses": progress.senses,
            "week": progress.week, "weekStart": progress.weekStart,
        ]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// Accepts this app's backup, or a 方方 website / Safari extension backup
    /// (its saved words are added to 不熟). Returns a message for the user.
    func importBackup(_ data: Data) -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "讀不到這個檔案。"
        }
        let app = obj["app"] as? String
        if app == "fangfang-cards" {
            let n = mergeProgress(obj)
            save()
            return "已匯入，更新了 \(n) 個詞。"
        }
        if app == "fangfang", let saved = obj["saved"] as? [String] {
            var n = 0, m = 0
            let now = Date().timeIntervalSince1970
            var p = progress
            for s in saved {
                let k = s.split(separator: "\t", omittingEmptySubsequences: false).prefix(2).joined(separator: "\t")
                if (p.saved[k] ?? -1) <= 0 { p.saved[k] = now; m += 1 }
                guard byKey[k] != nil, p.status[k] != 2 else { continue }
                p.status[k] = 2
                p.added[k] = now
                p.streak[k] = 0
                n += 1
            }
            progress = p
            save()
            return "已把方方收藏的 \(m) 個詞加到「轉換 → 收藏」，\(n) 個詞加到「不熟」。"
        }
        return "這不是方方的備份檔。"
    }
}
