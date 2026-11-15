import Foundation
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif
#if !WIDGET_EXT
import AVFoundation
#endif

// Shared by the app and the widget (both targets compile this folder).
// The app writes the words of each 分類 and your progress into the App Group folder; the widget reads them.
// The widget's 收藏 button writes to an inbox that the app takes over the next time it's opened.

/// one word on the widget, with everything already written out in the app's spelling and 腔口
struct WidgetWord: Codable, Hashable {
    let k: String            // key (漢字\tcodes)
    let h: String            // 漢字
    let a: Int?              // MOE word recording
    let r: [String]          // 皓羅, 台羅, 白話字
    let z: String            // 方音
    let p: String            // word class
    let m: String            // the meaning (the one the example belongs to)
    let xh: String?          // example 漢字
    let xr: [String]?        // example 皓羅, 台羅, 白話字
    let xz: String?          // example 華語
    let xn: String?          // example recording name
    // the same texts in colour (聲調顏色, guessed readings…), piece by piece; nil in older files
    var hc: [WSeg]? = nil    // 漢字
    var rc: [[WSeg]]? = nil  // 皓羅, 台羅, 白話字
    var zc: [WSeg]? = nil    // 方音
    var xhc: [WSeg]? = nil   // example 漢字
    var xrc: [[WSeg]]? = nil // example 皓羅, 台羅, 白話字
}

/// a piece of text in one colour ("rrggbb"; nil = the widget's own colour for that line)
struct WSeg: Codable, Hashable {
    let t: String
    let c: String?
}

struct WidgetCategory: Codable, Hashable {
    let i: Int               // 分類 id (-1 = 常用詞)
    let n: String            // name
    let c: Int               // number of words
}

struct WidgetState: Codable {
    var rom = 0
    var place = -1
    var saved: [String] = []
    var known: [String] = []
    /// how solid the widget background is (0 = see-through, 1 = solid); 設定 → 小工具
    var bg: Double? = nil
    /// the 不熟 words (both languages), for "只顯示不熟的詞"
    var unknown: [String]? = nil
}

/// the widget's 分類 ids besides the 台語 分類 (0…): 常用詞, the 不熟 words, the 華語 levels
enum WidgetCat {
    static let common = -1
    static let twUnknown = -2
    static let zhUnknown = -3
    /// 華語 word list level n (HSK / TOCFL, as chosen in the app): 10000 + n; its character level: 10100 + n
    static let zhBase = 10000

    /// each language's levels: 10000 × its number (華語 10000, 粵語 20000, 客語 30000, 日語 40000, 瑞典語 50000)
    static func base(_ kind: Int) -> Int { kind <= 1 ? zhBase : kind * 10000 }
    /// each language's 不熟 words (台語 -2, 華語 -3, the others -12, -13, -14, -15)
    static func unknown(_ kind: Int) -> Int { kind == 0 ? twUnknown : (kind == 1 ? zhUnknown : -10 - kind) }
    static func isUnknown(_ id: Int) -> Bool { id == twUnknown || id == zhUnknown || (id <= -12 && id >= -19) }
    /// whose a 分類 is (0 台語, 1 華語…)
    static func kind(of id: Int) -> Int {
        if id == zhUnknown { return 1 }
        if id <= -12 && id >= -19 { return -10 - id }
        if id >= zhBase { return id / 10000 }
        return 0
    }
}

/// a 收藏 change made on the widget: the app applies it the next time it's opened
struct WidgetInboxOp: Codable {
    let k: String
    let save: Bool
    let t: Double
    /// true = "I know this word" (✓ on the widget): the app moves it to 熟悉
    var known: Bool? = nil
    /// true = 加到不熟 (from Safari 查詞), false = taken back out to 新詞
    var unknown: Bool? = nil
}

enum WidgetShared {
    /// The shared folder's group. Built in Xcode it's the one in Info.plist, but a sideloaded IPA (AltStore,
    /// SideStore, Sideloadly…) is signed again with the sideloader's account, which renames the app (and the widget)
    /// and its group, e.g. com.unoki99.fangfangcards.ABCDE12345 and group.com.unoki99.fangfangcards.ABCDE12345,
    /// while Info.plist still has the old name. So the group the app really has is looked for: the first of these
    /// that iOS gives a folder for. The app and the widget find the same one, as both come from the app's name.
    static let groupID: String = {
        let plist = (Bundle.main.object(forInfoDictionaryKey: "FFAppGroup") as? String) ?? "group.com.unoki99.fangfangcards"
        // the app's name, also from inside the widget (its name is the app's with .widget in it)
        let bid = Bundle.main.bundleIdentifier ?? ""
        let app = bid.replacingOccurrences(of: ".widget", with: "")
        var tries = [plist, "group." + app]
        // the sideloader's team id on the end of the app's name: on the end of the group too
        let base = "com.unoki99.fangfangcards"
        if app.hasPrefix(base + "."), let team = app.split(separator: ".").last {
            tries.append(plist + "." + team)
            tries.append("group." + base + "." + team)
        }
        for g in tries where FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g) != nil { return g }
        return plist
    }()
    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("widget", isDirectory: true)
    }
    static var defaults: UserDefaults? { UserDefaults(suiteName: groupID) }

    static func url(_ name: String) -> URL? {
        guard let f = folder else { return nil }
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f.appendingPathComponent(name)
    }
    static func categoryFile(_ id: Int) -> String { "words-\(id).json" }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let u = url(name), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let u = url(name), let d = try? JSONEncoder().encode(value) else { return }
        try? d.write(to: u, options: .atomic)
    }

    static func categories() -> [WidgetCategory] { read([WidgetCategory].self, "categories.json") ?? [] }
    static func words(_ cat: Int) -> [WidgetWord] { read([WidgetWord].self, categoryFile(cat)) ?? [] }
    static func state() -> WidgetState { read(WidgetState.self, "state.json") ?? WidgetState() }
    static func inbox() -> [WidgetInboxOp] { read([WidgetInboxOp].self, "inbox.json") ?? [] }

    /// saved words as the widget should show them: the app's list plus changes made on the widget
    static func savedNow() -> Set<String> {
        var s = Set(state().saved)
        for op in inbox() where op.known == nil && op.unknown == nil { if op.save { s.insert(op.k) } else { s.remove(op.k) } }
        return s
    }

    /// 不熟 words as the widget should see them (✓ on the widget takes a word out)
    static func unknownNow() -> Set<String> {
        var s = Set(state().unknown ?? [])
        for op in inbox() {
            if op.known == true { s.remove(op.k) }
            if let u = op.unknown { if u { s.insert(op.k) } else { s.remove(op.k) } }     // (from Safari 查詞)
        }
        return s
    }

    /// 熟悉 words as the widget should see them: the app's list plus ✓ pressed on the widget
    static func knownNow() -> Set<String> {
        var s = Set(state().known)
        for op in inbox() {
            if op.known == true { s.insert(op.k) } else if op.known == false { s.remove(op.k) }
        }
        return s
    }

    /// ✓ on the widget: known ↔ not known (pressing it again takes it back)
    static func toggleKnownFromWidget(_ key: String) {
        let known = !knownNow().contains(key)
        var ops = inbox()
        ops.append(WidgetInboxOp(k: key, save: false, t: Date().timeIntervalSince1970, known: known))
        write(ops, "inbox.json")
    }

    /// the word on show for a 分類 stays until the next hour or →, even after ✓ (it just won't come back later)
    static func pinned(_ cat: Int, slot: String) -> String? {
        guard let v = defaults?.string(forKey: "pin-\(cat)"), v.hasPrefix(slot + "|") else { return nil }
        return String(v.dropFirst(slot.count + 1))
    }
    static func pin(_ cat: Int, slot: String, key: String) { defaults?.set(slot + "|" + key, forKey: "pin-\(cat)") }

    static func toggleSavedFromWidget(_ key: String) {
        let save = !savedNow().contains(key)
        var ops = inbox()
        ops.append(WidgetInboxOp(k: key, save: save, t: Date().timeIntervalSince1970))
        write(ops, "inbox.json")
    }

    /// the same recording paths as the app (Audio.wordPath / examplePath)
    static func wordPath(_ id: Int) -> String { "audio/\(id / 1000)/\(id)(1).mp3" }
    static func examplePath(_ name: String) -> String {
        let id = Int(name.split(separator: "-").first ?? "0") ?? 0
        return "leku/\(id / 1000)/\(name).mp3"
    }

    /// "→ next word": counts per 分類
    static func nextCount(_ cat: Int) -> Int { defaults?.integer(forKey: "next-\(cat)") ?? 0 }
    static func bumpNext(_ cat: Int) { defaults?.set(nextCount(cat) + 1, forKey: "next-\(cat)") }
}

// MARK: widget buttons

/// ▶ on the widget: the app plays the recording in the background (needs the "audio" background mode)
struct PlayWidgetAudioIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "播放發音"
    static let isDiscoverable = false
    @Parameter(title: "音檔") var path: String
    init() {}
    init(path: String) { self.path = path }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXT
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        Player.shared.play(path)
        try? await Task.sleep(nanoseconds: 300_000_000)
        for _ in 0..<50 {                       // stay until the recording has played
            if Player.shared.playing != path { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
        return .result()
    }
}

/// 收藏 on the widget
struct ToggleWidgetSaveIntent: AppIntent {
    static let title: LocalizedStringResource = "收藏／取消收藏"
    static let isDiscoverable = false
    @Parameter(title: "詞") var key: String
    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        WidgetShared.toggleSavedFromWidget(key)
        return .result()
    }
}

/// ✓ on the widget: I know this word (moves to 熟悉 and won't come up again; press again to take it back)
struct MarkWidgetKnownIntent: AppIntent {
    static let title: LocalizedStringResource = "標成熟悉"
    static let isDiscoverable = false
    @Parameter(title: "詞") var key: String
    init() {}
    init(key: String) { self.key = key }

    func perform() async throws -> some IntentResult {
        WidgetShared.toggleKnownFromWidget(key)
        return .result()
    }
}

/// → on the widget: another word from the same 分類
struct NextWidgetWordIntent: AppIntent {
    static let title: LocalizedStringResource = "下一個詞"
    static let isDiscoverable = false
    @Parameter(title: "分類") var category: Int
    init() {}
    init(category: Int) { self.category = category }

    func perform() async throws -> some IntentResult {
        WidgetShared.bumpNext(category)
        return .result()
    }
}

// MARK: - 動態島 (iPhone): a 不熟 word while you're away from the app

// Leaving the app starts it: the word on the left, its reading over its meaning on the right (small, to fit).
// Pressed and held, it opens: the word bigger, 下一個 / 熟悉, and a button for each language chosen in
// 設定 → 詞典資料 → 動態島, which opens that language's dictionary in the app. Coming back to the app ends it.
#if canImport(ActivityKit)
struct IslandAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var key: String
        var word: [WSeg]
        var reading: [WSeg]
        var meaning: String
        /// whose word (0 台語, 1 華語…), and the languages to show buttons for
        var kind: Int
        var langs: [Int]
        /// the app's theme: background, panel, panel edge, text, muted text, accent ("rrggbb")
        var colors: [String]
    }
}

enum IslandWords {
    // The words come from the app itself, not the App Group (an app installed without one has the island too):
    // leaving the app, it keeps a handful of its 不熟 words, ready written out, in its own settings; the island's
    // buttons run in the app, so they find them there. 熟悉 pressed on the island waits there too, for the app.
    static let poolKey = "islandPool"
    static let knownKey = "islandKnown"

    static var pool: [IslandAttributes.ContentState] {
        guard let d = UserDefaults.standard.data(forKey: poolKey) else { return [] }
        return (try? JSONDecoder().decode([IslandAttributes.ContentState].self, from: d)) ?? []
    }
    static func keep(_ states: [IslandAttributes.ContentState]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(states), forKey: poolKey)
    }
    static var knownOnIsland: [String] { UserDefaults.standard.stringArray(forKey: knownKey) ?? [] }

    /// another word (not the one on show, not one marked 熟悉 on the island)
    static func next(after s: IslandAttributes.ContentState) -> IslandAttributes.ContentState? {
        let known = Set(knownOnIsland)
        let p = pool.filter { $0.key != s.key && !known.contains($0.key) }
        guard var n = p.randomElement() else { return nil }
        n.langs = s.langs; n.colors = s.colors
        return n
    }
    /// 熟悉 on the island: for the app, the next time it's opened
    static func markKnown(_ key: String) {
        var k = knownOnIsland
        if !k.contains(key) { k.append(key) }
        UserDefaults.standard.set(k, forKey: knownKey)
    }
    static func state(_ w: WidgetWord, kind: Int, langs: [Int], colors: [String], rom: Int = 0) -> IslandAttributes.ContentState {
        let i = min(max(rom, 0), max(w.r.count - 1, 0))
        let reading = w.rc.flatMap { $0.isEmpty ? nil : $0[min(i, $0.count - 1)] } ?? [WSeg(t: w.r.isEmpty ? w.z : w.r[i], c: nil)]
        return .init(key: w.k, word: w.hc ?? [WSeg(t: w.h, c: nil)], reading: reading, meaning: w.m,
                     kind: kind, langs: langs, colors: colors)
    }
}

/// 下一個 on the island: another 不熟 word
struct NextIslandWordIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "下一個不熟的詞"
    static let isDiscoverable = false
    init() {}
    func perform() async throws -> some IntentResult {
        for a in Activity<IslandAttributes>.activities {
            if let n = IslandWords.next(after: a.content.state) { await a.update(ActivityContent(state: n, staleDate: nil)) }
        }
        return .result()
    }
}

/// 熟悉 on the island: the word to 熟悉 (the app takes it over when it's opened), and the next one
struct KnownIslandWordIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "標成熟悉"
    static let isDiscoverable = false
    @Parameter(title: "詞") var key: String
    init() {}
    init(key: String) { self.key = key }
    func perform() async throws -> some IntentResult {
        IslandWords.markKnown(key)
        for a in Activity<IslandAttributes>.activities {
            if let n = IslandWords.next(after: a.content.state) { await a.update(ActivityContent(state: n, staleDate: nil)) }
        }
        return .result()
    }
}
#endif
