import SwiftUI

private func matches(_ c: Card, _ q: String) -> Bool {
    if q.isEmpty { return true }
    let l = q.lowercased()
    return c.h.contains(q) || c.r.contains { $0.lowercased().contains(l) } || c.d.contains { $0.t.contains(q) }
}

/// 不熟: the words you swiped left. Study them here.
struct UnknownView: View {
    @EnvironmentObject var store: Store
    @AppStorage("goal") private var goal = 3
    @State private var studying = false
    @State private var toning = false
    @State private var toneGame = false
    @State private var particles = false
    @State private var scrambling = false
    @State private var readingOrder = false
    @State private var blanks = false
    @State private var memory = false
    @State private var swiping = false
    @State private var writing = false
    @State private var freeWriting = false
    @State private var idiomWriting = false
    @State private var numbers = false
    @State private var dragon = false
    @State private var gaming = false
    @State private var helping = false
    /// 遊戲: the grid of games open, and the one picked (opened once the grid has closed)
    @State private var gamesOpen = false
    @State private var pickedGame: PracticeGame?
    @State private var statsOpen = false
    /// 要複習 → practise just the words due. (One value that carries the words: the cover opens with them. Two
    /// separate states, the words and an "open" flag, opened the cover with the words of before, none: an empty
    /// practice even with words to review.)
    @State private var review: ReviewRun?
    @State private var detail: Card?
    @State private var query = ""

    var body: some View {
        // the words of the 練習範圍 (all of 不熟 when none is chosen)
        let list = store.practiceCards.filter { matches($0, query) }
        let due = store.dueCards
        List {
            Section {
            } header: {
                // the ways to practise, two to a row, all in the same soft green.
                // In the header, not a row: a row's rounded corners would cut the tiles' corners off
                let pool = store.practiceCards
                VStack(spacing: 12) {
                WeekPanel()
                PracticeScopeMenu()
                ReviewBar(due: store.allDueCards.count, stats: { statsOpen = true }) { hand in
                    review = ReviewRun(words: store.allDueCards, hand: hand)
                }
                // 開始練習 and the handwriting ones here; every game behind one button (遊戲), chosen from a grid with
                // what each does; 怎麼練習 across the whole width
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    PracticeTile(title: tr("開始練習"), icon: "graduationcap.fill", enabled: !pool.isEmpty || !due.isEmpty) { studying = true }
                    PracticeTile(title: tr("手寫練習"), icon: "pencil.and.scribble", enabled: !store.isSv) { writing = true }
                    PracticeTile(title: tr("自由寫字"), icon: "square.grid.3x3", enabled: !store.isSv) { freeWriting = true }
                    // (華語: 四字格 from their meaning)
                    if store.lang == 1 {
                        PracticeTile(title: tr("四字格手寫"), icon: "square.grid.2x2.fill", enabled: store.zh != nil) { idiomWriting = true }
                    }
                    // (台語: the numbers, 白 and 文)
                    if store.lang == 0 {
                        PracticeTile(title: tr("數字練習"), icon: "number", enabled: true) { numbers = true }
                    }
                }
                PracticeTile(title: tr("遊戲"), icon: "gamecontroller", enabled: true) { gamesOpen = true }
                PracticeTile(title: tr("怎麼練習"), icon: "questionmark.circle", enabled: true, quiet: true) { helping = true }
                }
                .padding(.vertical, 6)
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section(store.practiceName == trs("全部不熟的詞") ? tr("不熟的詞（\(store.unknownCount)）")
                    : tr("\(store.practiceName)・不熟的詞（\(list.count)／\(store.unknownCount)）")) {
                if list.isEmpty {
                    Text(query.isEmpty ? trs("在「新詞」往左滑的詞會出現在這裡。") : trs("找不到。"))
                        .foregroundStyle(T.muted)
                }
                ForEach(list) { c in
                    Button { detail = c } label: {
                        HStack(spacing: 8) {
                            if store.isInWeek(c.k) { Image(systemName: "calendar").ffFont(.caption).foregroundStyle(T.blueInk) }
                            WordRow(card: c, streak: store.streak(c), goal: goal)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())          // the whole row, not only the word
                    }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button { store.mark(c, known: true, undoable: false) } label: { Label(tr("熟悉"), systemImage: "checkmark") }
                                .tint(T.btnEdge)
                            Button { store.toggleWeek(c.k) } label: {
                                Label(store.isInWeek(c.k) ? trs("移出本週") : trs("本週學習"), systemImage: "calendar")
                            }
                                .tint(T.blueEdge)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.forget(c) } label: { Label(tr("移回新詞"), systemImage: "arrow.uturn.backward") }
                                .tint(T.oliveEdge)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        // (under the top bar, not in it: on an iPad it would push the reading and settings buttons out)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: trs("漢字、羅馬字或意思"))

        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
        .fullScreenCover(isPresented: $studying) { StudyView().environmentObject(store) }
        .fullScreenCover(item: $review) { r in
            if r.hand { StudyView(words: r.words, writeOnly: true, saveAs: "reviewWrite").environmentObject(store) }
            else { StudyView(words: r.words, saveAs: "review").environmentObject(store) }
        }
        .fullScreenCover(isPresented: $blanks) { StudyView(blanksOnly: true).environmentObject(store) }
        .fullScreenCover(isPresented: $toning) { ToneView().environmentObject(store) }
        .fullScreenCover(isPresented: $toneGame) { ToneGameView().environmentObject(store) }
        .fullScreenCover(isPresented: $particles) { JaParticleQuiz().environmentObject(store) }
        .fullScreenCover(isPresented: $scrambling) { ScrambleView().environmentObject(store) }
        .fullScreenCover(isPresented: $memory) { MemoryView().environmentObject(store) }
        .fullScreenCover(isPresented: $swiping) { PracticeSwipeView().environmentObject(store) }
        .fullScreenCover(isPresented: $writing) { HandwritingView().environmentObject(store) }
        .fullScreenCover(isPresented: $freeWriting) { FreeWritingView().environmentObject(store) }
        .fullScreenCover(isPresented: $idiomWriting) { IdiomWriteView().environmentObject(store) }
        .fullScreenCover(isPresented: $numbers) { NumbersView().environmentObject(store) }
        .fullScreenCover(isPresented: $dragon) { WordDragonView().environmentObject(store) }
        .fullScreenCover(isPresented: $gaming) { FallingGameView().environmentObject(store) }
        .sheet(isPresented: $helping) { PracticeHelp(goal: goal).environmentObject(store) }
        .sheet(isPresented: $gamesOpen, onDismiss: openPickedGame) {
            GamePicker(games: games) { pickedGame = $0; gamesOpen = false }.environmentObject(store)
        }
        .sheet(isPresented: $statsOpen) { NavigationStack { ReviewStatsView() }.environmentObject(store).macTextSize() }
        .fullScreenCover(isPresented: $readingOrder) { ScrambleView(readingMode: true).environmentObject(store) }
    }
}

/// 熟悉: known words. Review them as cards; swiping left sends a word back to 不熟.
struct KnownView: View {
    @EnvironmentObject var store: Store
    @State private var mode = 0
    @State private var reviewKeys: [String] = []
    @State private var pos = 0
    @State private var detail: Card?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text(tr("卡片複習")).tag(0)
                Text(tr("列表")).tag(1)
                if store.isZh ? !store.topics.isEmpty : !store.freqTopics.isEmpty { Text(tr("學習進度")).tag(2) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            if mode == 2 { HSKProgressView() } else if mode == 0 { review } else { list }
        }
        .appBackground()

        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
        .onAppear { if reviewKeys.isEmpty { shuffle() } }
    }

    private var reviewCards: [Card] {
        guard pos < reviewKeys.count else { return [] }
        var out: [Card] = []
        for k in reviewKeys[pos...] {
            if let c = store.byKey[k], store.status(c) == 1 { out.append(c) }
            if out.count == 4 { break }
        }
        return out
    }

    private var review: some View {
        let cards = reviewCards
        return VStack(spacing: 14) {
            Text(store.knownCount == 0 ? "" : "\(min(pos, reviewKeys.count)) / \(reviewKeys.count)")
                .ffFont(.footnote).foregroundStyle(T.muted)
            if cards.isEmpty {
                Spacer()
                Text(store.knownCount == 0 ? trs("在「新詞」往右滑的詞會出現在這裡。") : trs("這一輪複習完了！"))
                    .foregroundStyle(T.muted)
                if store.knownCount > 0 {
                    Button(tr("再複習一輪")) { shuffle() }.prominentButton(T.btnEdge)
                }
                Spacer()
            } else {
                DeckArea(cards: cards, leftLabel: trs("不熟"), rightLabel: trs("記得")) { card, right in
                    if !right { store.mark(card, known: false, undoable: false) }
                    advance(past: card)
                }
            }
        }
        .padding()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        let cards = store.knownCards.filter { matches($0, query) }
        return List {
            // the search under 卡片複習 / 列表 (not above them, where .searchable puts it)
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.muted)
                    TextField(tr("漢字、羅馬字或意思"), text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .clearButton($query)
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section(tr("熟悉的詞（\(store.knownCount)）")) {
                ForEach(cards) { c in
                    Button { detail = c } label: {
                        WordRow(card: c).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button { store.mark(c, known: false, undoable: false) } label: { Label(tr("不熟"), systemImage: "xmark") }
                                .tint(T.rustEdge)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func shuffle() {
        reviewKeys = store.knownCards.map(\.k).shuffled()
        pos = 0
    }

    private func advance(past card: Card) {
        if let i = reviewKeys[pos...].firstIndex(of: card.k) { pos = i + 1 } else { pos += 1 }
    }
}


/// 遊戲: every game, chosen from a grid with what each does
enum PracticeGame: String, Identifiable { case swipe, blanks, scramble, readingOrder, tones, toneBalls, particles, memory, falling, dragon
    var id: String { rawValue } }

extension UnknownView {
    /// the games there are for this language and these words
    var games: [(game: PracticeGame, icon: String, title: String, text: String, enabled: Bool)] {
        let pool = store.practiceCards, due = store.dueCards
        var a: [(PracticeGame, String, String, String, Bool)] = [
            (.swipe, "hand.draw", trs("滑卡練習"), trs("像「新詞」一樣滑卡片：往右是會，往左是不會。"), !pool.isEmpty || !due.isEmpty),
            (.blanks, "text.badge.checkmark", trs("例句填空"), trs("看例句，把空著的詞選回去。"), (pool + due).contains { !store.blanks($0).isEmpty }),
            (.scramble, "rectangle.3.group", trs("排句子"), trs("例句被打亂了，照意思把詞排回去。"), !pool.isEmpty),
            (.readingOrder, "character.book.closed", trs("看字排讀音"), trs("只看漢字，把讀音照順序排。"), !pool.isEmpty && !store.isSv),
        ]
        if store.isJa {
            a.append((.particles, "puzzlepiece", trs("助詞練習"), trs("選句子裡缺的助詞。"), true))
        } else {
            a.append((.tones, "waveform", trs("聲調練習"), trs("聽發音，選聲調對的拼法。"), !store.isHak && !store.isSv))
            a.append((.toneBalls, "circle.hexagongrid.fill", trs("聲調色球"), trs("聽一個詞，照每個字的聲調點顏色球。"), !store.isSv))
        }
        a.append((.memory, "square.grid.2x2", trs("翻牌配對"), trs("一次翻兩張牌，把漢字和它的讀音配起來。"), pool.count > 1))
        a.append((.falling, "arrow.down.circle", trs("掉下來的字"), trs("詞從上面掉下來：在它掉到底以前點對的那一個，越來越快。"), pool.count > 3))
        a.append((.dragon, "link", trs("詞龍"), store.isSv ? trs("接龍：打一個用上一個詞最後一個字母開頭的詞，App 再接下去。") : trs("接龍：打一個用上一個詞最後一個字開頭的詞，App 再接下去。"), true))
        return a.map { (game: $0.0, icon: $0.1, title: $0.2, text: $0.3, enabled: $0.4) }
    }

    func openPickedGame() {
        guard let g = pickedGame else { return }
        pickedGame = nil
        switch g {
        case .swipe: swiping = true
        case .blanks: blanks = true
        case .scramble: scrambling = true
        case .readingOrder: readingOrder = true
        case .tones: toning = true
        case .toneBalls: toneGame = true
        case .particles: particles = true
        case .memory: memory = true
        case .falling: gaming = true
        case .dragon: dragon = true
        }
    }
}

struct GamePicker: View {
    let games: [(game: PracticeGame, icon: String, title: String, text: String, enabled: Bool)]
    let pick: (PracticeGame) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(games, id: \.game) { g in
                        Button { pick(g.game) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: g.icon).font(.system(size: 26, weight: .semibold))
                                    .foregroundStyle(g.enabled ? T.btnInk : T.muted)
                                Text(g.title).ffFont(.headline).foregroundStyle(g.enabled ? T.glyph : T.muted)
                                Text(g.text).ffFont(.caption).foregroundStyle(T.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                            .background(RoundedRectangle(cornerRadius: 16).fill(g.enabled ? T.btn : T.fn.opacity(0.6)))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(g.enabled ? T.btnEdge : T.fnEdge, lineWidth: 1.5))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .disabled(!g.enabled)
                    }
                }
                .padding()
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(tr("遊戲"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// one practice button in 不熟 (half the width, the soft green)
struct PracticeTile: View {
    let title: String
    let icon: String
    var enabled = true
    /// not a way of practising (怎麼練習): the plain colour
    var quiet = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .ffFont(.subheadline, .semibold)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
                .foregroundStyle(quiet ? T.glyph : (enabled ? T.btnInk : T.muted))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(quiet ? T.fn.opacity(0.8) : (enabled ? T.btn : T.fn.opacity(0.6))))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(quiet ? T.fnEdge : (enabled ? T.btnEdge : T.fnEdge), lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 不熟 → 練習範圍: all of 不熟, or one level / group (華語: HSK / TOCFL words or characters; 台語: 常用詞 / 常用字)
struct PracticeScopeMenu: View {
    @EnvironmentObject var store: Store
    @State private var groupsOpen = false
    /// 創作範圍 / 編輯: the sheet (nil name: a new 範圍)
    @State private var scopeSheet: ScopeSheet?
    struct ScopeSheet: Identifiable { let name: String?; var id: String { name ?? "\u{1}new" } }
    @State private var csvFile: ShareItem?

    /// the 練習範圍's words as a CSV file (the same columns as 設定's 匯出「不熟」), named after it
    private func exportCSV() {
        let name = store.practiceName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("方方-" + name + ".csv")
        do {
            try Data(store.csv(store.practiceCards).utf8).write(to: url)
            csvFile = ShareItem(url: url)
        } catch {}
    }
    var body: some View {
        let ts = store.practiceTopics
        let all = store.allTopicProgress()
        let words = ts.filter { store.isZh ? $0.id < Lang.charTopicBase : $0.id < Lang.freqCharBase }
        let chars = ts.filter { store.isZh ? $0.id > Lang.charTopicBase : $0.id >= Lang.freqCharBase }
        let groups = store.groupIds
        let unknown = Set(store.unknownCards.map(\.k))
        if !ts.isEmpty || !groups.isEmpty || !store.savedKeys.isEmpty {
            Menu {
                Button {
                    store.practiceGroup = nil; store.practiceTopic = -1
                } label: {
                    if store.practiceGroup == nil && store.practiceTopic < 0 {
                        Label(tr("全部不熟的詞（\(store.unknownCount)）"), systemImage: "checkmark")
                    } else {
                        Text(tr("全部不熟的詞（\(store.unknownCount)）"))
                    }
                }
                // 收藏: the words you saved
                let nSaved = store.savedKeys.count
                if nSaved > 0 {
                    Button { store.practiceGroup = Store.savedScope } label: {
                        Label(tr("收藏的詞（\(nSaved)）"), systemImage: store.practiceGroup == Store.savedScope ? "checkmark" : "bookmark")
                    }
                }
                // 自己的範圍: made with 創作範圍 (some 影片詞組 together)
                let scopes = store.groupFolders
                if !scopes.isEmpty {
                    Section(trs("自己的範圍")) {
                        ForEach(scopes, id: \.self) { f in
                            Button {
                                store.practiceGroup = "folder:" + f
                            } label: {
                                let n = Set(store.folderGroups(f).flatMap { store.groupKeys($0) }).filter { unknown.contains($0) }.count
                                Label(tr("\(f)（不熟 \(n)）"), systemImage: store.practiceGroup == "folder:" + f ? "checkmark" : "square.stack")
                            }
                        }
                    }
                }
                // (影片詞組: the words chosen from one video in Safari 查詞)
                if !groups.isEmpty {
                    Menu(trs("影片詞組")) {
                        ForEach(groups, id: \.self) { g in groupButton(g, unknown) }
                        Divider()
                        Button { groupsOpen = true } label: { Label(tr("看全部影片詞組"), systemImage: "list.bullet.rectangle") }
                    }
                }
                if !words.isEmpty {
                    Menu(store.isZh ? trs("詞（等級）") : trs("常用詞")) {
                        Picker(tr("詞"), selection: $store.practiceTopic) {
                            ForEach(words) { t in Text(tr("\(t.name)（不熟 \(all[t.id]?.unknown ?? 0)）")).tag(t.id) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                if !chars.isEmpty {
                    Menu(store.isZh ? trs("漢字（等級）") : trs("常用字")) {
                        Picker(tr("字"), selection: $store.practiceTopic) {
                            ForEach(chars) { t in Text(tr("\(t.name)（不熟 \(all[t.id]?.unknown ?? 0)）")).tag(t.id) }
                        }
                        .pickerStyle(.inline)
                    }
                }
                // the range's words as a file (for Anki and the like)
                Divider()
                Button { exportCSV() } label: { Label(tr("匯出這個範圍（CSV）"), systemImage: "square.and.arrow.up") }
                if !groups.isEmpty {
                    Divider()
                    Button { scopeSheet = ScopeSheet(name: nil) } label: { Label(tr("創作範圍"), systemImage: "plus") }
                    if let g = store.practiceGroup, g.hasPrefix("folder:"), store.isFolderRef(g) {
                        Button { scopeSheet = ScopeSheet(name: String(g.dropFirst(7))) } label: {
                            Label(tr("編輯「\(String(g.dropFirst(7)))」"), systemImage: "pencil")
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: store.practiceGroup.map { $0 == Store.savedScope ? "bookmark" : ($0.hasPrefix("folder:") ? "square.stack" : "film") } ?? "scope").foregroundStyle(T.btnInk)
                    Text(tr("練習範圍")).foregroundStyle(T.muted)
                    Text(store.practiceName).foregroundStyle(T.glyph).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(store.practiceCards.count)").ffFont(.footnote, mono: true).foregroundStyle(T.muted)
                    Image(systemName: "chevron.up.chevron.down").ffFont(.caption).foregroundStyle(T.muted)
                }
                .ffFont(.subheadline)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $groupsOpen) { VideoGroupsView().environmentObject(store) }
            .sheet(item: $csvFile) { f in ShareSheet(url: f.url) }
            .sheet(item: $scopeSheet) { sh in
                ScopeEditor(editing: sh.name) { n in store.practiceGroup = "folder:" + n }.environmentObject(store)
            }
        }
    }

    private func groupButton(_ g: String, _ unknown: Set<String>) -> some View {
        Button {
            store.practiceGroup = g
        } label: {
            let n = store.groupKeys(g).filter { unknown.contains($0) }.count
            Label(tr("\(store.groupName(g))（不熟 \(n)）"), systemImage: store.practiceGroup == g ? "checkmark" : "film")
        }
    }
}

/// 不熟 → 怎麼練習: what each way of practising does, one box each
struct PracticeHelp: View {
    let goal: Int
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    private var items: [(icon: String, title: String, text: String)] {
        var a: [(String, String, String)] = [
            ("calendar", trs("本週學習"), trs("從不熟的詞選這個星期要學的（或在列表往右滑 → 本週學習），一週後做期末測驗；答錯的詞可以留到下一週。")),
            ("graduationcap.fill", trs("開始練習"), tr("各種題目混在一起練。連續答對 \(goal) 次，詞就會移到「熟悉」；在列表往右滑可以直接移過去。")),
            ("hand.draw", trs("滑卡練習"), tr("像「新詞」一樣滑卡片：往右是會、往左是不會。不會直接放到「熟悉」，而是和其他練習一樣算答對／答錯；連續答對 \(goal) 次才到「熟悉」，過幾天再出來複習。")),
            ("text.badge.checkmark", trs("例句填空"), trs("只做例句填空題。")),
            ("pencil.line", trs("寫字題"), trs("開始練習和本週學習裡也有寫字題：看意思和讀音，一個字一個字把整個詞寫出來，按「對答案」以後自己說寫對了沒有。可以在「設定 → 卡片與練習」關掉。")),
            ("rectangle.3.group", trs("排句子"), trs("例句被打亂了，照華語的意思把詞排回去。")),
            ("character.book.closed", trs("看字排讀音"), trs("只看漢字，把讀音照順序排。")),
            ("waveform", trs("聲調練習"), trs("聽發音，選出聲調正確的拼法（先用不熟的詞，再用常用詞）。")),
            ("circle.hexagongrid.fill", trs("聲調色球"), trs("聽一個詞，照每個字的聲調點顏色球（顏色是設定裡選的聲調顏色）。每個字都算，全對有連對加分。")),
            ("square.grid.2x2", trs("翻牌配對"), trs("不熟的詞做成牌，一半是漢字，一半是讀音；一次翻兩張，把漢字和它的讀音配起來。")),
        ]
        do {
            a.append(("pencil.and.scribble", trs("手寫練習"), store.isZh ? trs("選要寫的字（不熟的漢字、HSK／TOCFL 的漢字等級、認識的漢字或自己打的字），看字、讀音和意思，用手指或 Apple Pencil 在格子裡寫。「描字」會在格子裡放一個淡淡的字，藥水條顯示描得多像；點上面的字看有這個字的詞，打勾表示這個字會了。") : trs("選要寫的字（不熟的詞的字、熟悉的詞的字或自己打的字），看字、讀音和意思，用手指或 Apple Pencil 在格子裡寫。「描字」會在格子裡放一個淡淡的字，藥水條顯示描得多像；點上面的字看有這個字的詞，打勾表示這個字會了。")))
        }
        if store.lang == 1 {
            a.append(("square.grid.2x2.fill", trs("四字格手寫"), trs("看一個四字格（成語）的意思和讀音，把四個字寫出來，寫完對答案、自己說寫對了沒有。寫錯的在這一輪最後再出現一次，寫錯的可以加到不熟。可以選常見的成語、所有成語，或練習範圍裡四個字的詞。")))
        }
        if store.lang == 0 {
            a.append(("number", trs("數字練習"), trs("台語的數字有白、文兩套讀音。算數：用拼音寫出算式的答案（聲調符號可有可無）。白還是文：一個數字在一個場合（量詞、電話、年紀、算數），選它在那裡怎麼講。")))
        }
        a.append(("scope", trs("練習範圍"), trs("只練一個等級（或一組）的不熟的詞或字，或收藏的詞；也可以把範圍匯出成 CSV。")))
        return a
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items, id: \.title) { it in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: it.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(T.btnInk)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(it.title).ffFont(.headline).foregroundStyle(T.glyph)
                                Text(it.text).ffFont(.subheadline).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.fnEdge, lineWidth: 1))
                    }
                }
                .padding()
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(tr("怎麼練習"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


/// 要複習 tapped: the words due then, and how to practise them (手寫 or not)
struct ReviewRun: Identifiable {
    let id = UUID()
    let words: [Card]
    let hand: Bool
}
