import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// 動態島 (iPhone): leaving the app puts one of your 不熟 words in the Dynamic Island (and on the lock screen);
// coming back ends it. Pressed and held it opens with 下一個 and a button for each language chosen in
// 設定 → 詞典資料 → 動態島: fangfangcards://dict?lang=… opens that language's dictionary.
@MainActor
enum IslandLive {
    static let onKey = "islandOn"
    static let langsKey = "islandLangs"
    static var on: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    /// the languages with a button (台語 and 華語 at first)
    static var langs: [Int] {
        get { UserDefaults.standard.array(forKey: langsKey) as? [Int] ?? [0, 1] }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: langsKey) }
    }
    /// which words, for each language: "" the 練習範圍 chosen in 不熟 (the same words the games use); "unknown" all its 不熟 words; "topic:<id>" a level's (TOCFL / HSK…) words not 熟悉 yet;
    /// "group:<id>" an 影片詞組's, "folder:<name>" a folder's (the 不熟 and new ones)
    static func source(_ lang: Int) -> String { UserDefaults.standard.string(forKey: "islandScope.\(lang)") ?? "" }
    static func setSource(_ lang: Int, _ v: String) { UserDefaults.standard.set(v, forKey: "islandScope.\(lang)") }
    static func cards(_ store: Store) -> [Card] {
        let src = source(store.lang)
        let notKnown: (Card) -> Bool = { store.wordStatus($0.k) != 1 }
        if src.hasPrefix("topic:"), let t = Int(src.dropFirst(6)), store.practiceTopics.contains(where: { $0.id == t }) {
            return store.cards.filter { store.inTopic($0, t) && notKnown($0) }
        }
        if src.hasPrefix("group:") || src.hasPrefix("folder:") {
            let gs = src.hasPrefix("group:") ? [String(src.dropFirst(6))] : store.folderGroups(String(src.dropFirst(7)))
            let cs = gs.flatMap { store.groupKeys($0) }.compactMap { store.card(for: $0) }.filter(notKnown)
            if !cs.isEmpty { return cs }
        }
        if src == "unknown" { return store.unknownCards }
        // (練習範圍: its 不熟 words; all of 不熟 when it has none left)
        let p = store.practiceCards
        return p.isEmpty ? store.unknownCards : p
    }

    static var supported: Bool {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    static func start(_ store: Store) {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        guard supported, on else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            UserDefaults.standard.set(trs("iOS 的「即時動態」關著：設定 → 方方詞卡 → 即時動態。"), forKey: "islandError"); return
        }
        // (already there: leaving again, e.g. by pulling down Control Center)
        if !Activity<IslandAttributes>.activities.isEmpty { return }
        // (a handful of the language's 不熟 words, written out the way the app shows them, for 下一個)
        let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
        let colors = T.islandColors, ls = langs, rom = UserDefaults.standard.integer(forKey: "rom")
        let states = cards(store).shuffled().prefix(60).map {
            IslandWords.state(WidgetBridge.word(store, $0, place), kind: store.lang, langs: ls, colors: colors, rom: rom)
        }
        IslandWords.keep(Array(states))
        guard let first = states.first else {
            UserDefaults.standard.set(trs("選的詞裡沒有還沒學會的詞。"), forKey: "islandError"); return
        }
        do {
            _ = try Activity.request(attributes: IslandAttributes(), content: ActivityContent(state: first, staleDate: nil), pushType: nil)
            UserDefaults.standard.removeObject(forKey: "islandError")
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: "islandError")
        }
        #endif
    }

    /// 熟悉 pressed on the island: the words to 熟悉
    static func takeKnown(_ store: Store) {
        #if canImport(ActivityKit)
        let ks = IslandWords.knownOnIsland
        guard !ks.isEmpty else { return }
        for k in ks where store.wordStatus(k) != 1 { store.setWord(k, status: 1) }
        UserDefaults.standard.removeObject(forKey: IslandWords.knownKey)
        #endif
    }

    static func end() {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        for a in Activity<IslandAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        #endif
    }

    /// fangfangcards://dict?lang=1: that language's dictionary (true when the link was one of these)
    static func open(_ url: URL, _ store: Store) -> Bool {
        guard url.scheme == "fangfangcards", url.host == "dict" else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let n = items.first(where: { $0.name == "lang" })?.value.flatMap(Int.init)
        if let n, n != store.lang { store.setLanguage(n) }
        UserDefaults.standard.set(0, forKey: "dictTab")
        Router.shared.settingsOpen = false
        Router.shared.tab = 4
        // (the island itself tapped, not a language's button: the word shown on it)
        if let w = items.first(where: { $0.name == "word" })?.value, !w.isEmpty {
            Router.shared.islandEntry = .init(key: w)
        }
        return true
    }
}

/// the island's word, as its entry in the dictionary (once the language's dictionary is ready, after a switch)
struct IslandEntrySheet: View {
    let key: String
    @EnvironmentObject var store: Store
    var body: some View {
        if let c = store.card(for: key) {
            CardSheet(card: c)
        } else {
            VStack(spacing: 14) {
                ProgressView()
                Text(String(key.split(separator: "\t").first ?? Substring(key))).ffFont(.title, .semibold).foregroundStyle(T.glyph)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .onAppear { store.loadDict() }
        }
    }
}

/// 設定 → 詞典資料 → 動態島: on / off, and the languages with a button on it
struct IslandSettingsSection: View {
    @EnvironmentObject var store: Store
    @AppStorage(IslandLive.onKey) private var on = true
    @State private var langs = IslandLive.langs
    @State private var source = ""

    var body: some View {
        if IslandLive.supported {
            Section {
                Toggle(isOn: $on) { Text(tr("離開 App 的時候顯示")) }
                // (which words: this language's 不熟 words, a level, an 影片詞組 or a folder of them)
                Picker(selection: Binding(get: { source }, set: { source = $0; IslandLive.setSource(store.lang, $0) })) {
                    Text(tr("跟練習範圍一樣（\(store.practiceName)）")).tag("")
                    Text(tr("全部不熟的詞")).tag("unknown")
                    let ts = store.practiceTopics
                    if !ts.isEmpty {
                        Section(store.isZh ? trs("等級（還沒熟悉的詞）") : trs("常用詞（還沒熟悉的詞）")) {
                            ForEach(ts) { t in Text(t.name).tag("topic:\(t.id)") }
                        }
                    }
                    if !store.groupFolders.isEmpty {
                        Section(trs("自己的範圍")) {
                            ForEach(store.groupFolders, id: \.self) { f in Text(f).tag("folder:" + f) }
                        }
                    }
                    if !store.groupIds.isEmpty {
                        Section(trs("影片詞組")) {
                            ForEach(store.groupIds, id: \.self) { g in Text(store.groupName(g)).tag("group:" + g) }
                        }
                    }
                } label: {
                    Text(tr("\(trs(Lang.names[min(max(store.lang, 0), Lang.names.count - 1)]))顯示哪些詞"))
                }
                .disabled(!on)
                .onAppear { source = IslandLive.source(store.lang) }
                ForEach(0..<Lang.names.count, id: \.self) { l in
                    Toggle(isOn: Binding(get: { langs.contains(l) }, set: { v in
                        if v { if !langs.contains(l) { langs.append(l) } } else { langs.removeAll { $0 == l } }
                        IslandLive.langs = langs
                    })) {
                        HStack(spacing: 8) {
                            Circle().fill(T.langColors(l).edge).frame(width: 10, height: 10)
                            Text(tr("\(trs(Lang.names[l]))的按鈕"))
                        }
                    }
                    .disabled(!on)
                }
            } header: {
                Text(tr("動態島"))
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("離開 App 的時候，動態島顯示一個不熟的詞（左邊是詞，右邊是讀音），平常是「不熟」的練習範圍裡的詞。點一下動態島就打開那個詞的詞條。按住動態島會打開：看得到意思，可以換下一個詞，按語言的按鈕就打開那個語言的詞典。回到 App 的時候就收起來。"))
                    // (why it didn't show the last time)
                    if let e = UserDefaults.standard.string(forKey: "islandError") {
                        Text(tr("上一次沒有顯示：\(e)")).foregroundStyle(T.rustInk)
                    }
                }
            }
        }
    }
}
