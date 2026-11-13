import AppIntents
import SwiftUI
import AVFoundation

// 方方查詞（小視窗）: a Shortcuts action that shows the dictionary entries for a word in a small card on top
// of whatever app you're in (iOS / iPadOS / macOS 26). The card has buttons to play the recording,
// save to 收藏, add to 不熟, or open the entry in the app.

/// the dictionaries, loaded once per launch for Shortcuts actions
@MainActor
final class IntentDict {
    static let shared = IntentDict()
    private var dict: Dict?
    private var zh: [Int: ZhDict] = [:]
    func get() throws -> Dict {
        if let d = dict { return d }
        if let d = Store.shared.dict { dict = d; return d }
        guard let url = DataFiles.url("dict") else { throw CocoaError(.fileNoSuchFile) }
        let d = Dict(try JSONDecoder().decode(DictRaw.self, from: Data(contentsOf: url)))
        dict = d
        return d
    }
    /// 華語 (1), 粵語 (2) or 客語 (3)
    func zhDict(_ kind: Int) throws -> ZhDict {
        if let d = zh[kind] { return d }
        if let d = Store.shared.zh, d.lang == kind { zh[kind] = d; return d }
        guard (1...5).contains(kind), let url = DataFiles.url(["zh", "zh", "yue", "hak", "ja", "sv"][kind]) else { throw CocoaError(.fileNoSuchFile) }
        let accent = min(max(UserDefaults.standard.integer(forKey: Lang.hakPlaceKey), 0), Lang.hakAccents.count - 1)
        let d = try ZhDict(data: try Data(contentsOf: url, options: .mappedIfSafe), accent: accent, from: url)
        zh[kind] = d
        return d
    }
}

/// the language the small window looks the word up in (chosen on the window; -1 = not chosen yet)
enum SnippetLanguage {
    static let key = "snippetLanguage"
    static var current: Int { UserDefaults.standard.object(forKey: key) as? Int ?? -1 }
    static func set(_ l: Int) { UserDefaults.standard.set(l, forKey: key) }
}

/// one entry on the card
struct SnippetRow: Identifiable {
    let key: String
    let han: String
    let rom: AttributedString
    let zy: AttributedString
    let gloss: String
    let audio: String?
    let saved: Bool
    let status: Int?            // nil = not a card, 0 new, 1 熟悉, 2 不熟
    var id: String { key }
}

@available(iOS 26.0, *)
struct PopupLookUpIntent: AppIntent {
    static let title: LocalizedStringResource = "方方查詞（小視窗）"
    static let description = IntentDescription("在畫面上用小視窗查這個詞：先選語言（台語、華語、粵語、客語），漢字、讀音或英文都可以查。可以聽發音、收藏、加到「不熟」，不用打開 App。")

    @Parameter(title: "詞")
    var word: String

    static var parameterSummary: some ParameterSummary {
        Summary("用小視窗查 \(\.$word)")
    }

    func perform() async throws -> some IntentResult & ShowsSnippetIntent {
        // (a new word: the language is chosen again on the window)
        SnippetLanguage.set(-1)
        return .result(snippetIntent: LookUpSnippetIntent(word: word.trimmingCharacters(in: .whitespacesAndNewlines)))
    }
}

/// the window's language buttons: picks the language and the window looks the word up in it
@available(iOS 26.0, *)
struct ChooseSnippetLanguageIntent: AppIntent {
    static let title: LocalizedStringResource = "選語言"
    static let isDiscoverable = false
    @Parameter var language: Int
    init() {}
    init(language: Int) { self.language = language }
    func perform() async throws -> some IntentResult {
        SnippetLanguage.set(language)
        return .result()
    }
}

@available(iOS 26.0, *)
struct LookUpSnippetIntent: SnippetIntent {
    static let title: LocalizedStringResource = "方方查詞結果"
    static let isDiscoverable = false

    @Parameter(title: "詞")
    var word: String

    init() {}
    init(word: String) { self.word = word }

    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        let lang = SnippetLanguage.current
        guard (0..<Lang.names.count).contains(lang) else {
            return .result(view: LookUpSnippetView(word: word, lang: -1, rows: [], more: false))
        }
        let store = Store.shared
        store.load()
        let rows: [SnippetRow]
        var total = 0
        if lang == 0 {
            let d = try IntentDict.shared.get()
            let rom = UserDefaults.standard.object(forKey: "rom") as? Int ?? 0
            let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
            let r = Lookup.run(d, word)
            var keys: [String] = []
            for k in r.taigi + r.exact + r.pattern + r.contains + r.patternZh + r.gloss + r.defs where !keys.contains(k) { keys.append(k) }
            // (English: Wiktionary's meanings)
            for k in TwEnglish.search(word, limit: 10) where !keys.contains(k) { keys.append(k) }
            total = keys.count
            rows = keys.prefix(4).map { k -> SnippetRow in
                var gloss = ""
                if ZhMeaning.english(0), case let en = TwEnglish.meanings(k), !en.isEmpty { gloss = en.prefix(3).joined(separator: "; ") }
                else if let g = d.gl[k], !g.isEmpty { gloss = g.prefix(5).map { $0.t }.joined(separator: "、") }
                else if let t = d.defText(k) {
                    gloss = t.replacingOccurrences(of: #"\d+\.\s*"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: "\n", with: "／")
                }
                return SnippetRow(key: k, han: Dict.hanOf(k), rom: d.wordText(k, TwRom.lat(rom), place),
                                  zy: rom == 3 ? AttributedString() : d.wordText(k, 3, place), gloss: gloss,
                                  audio: d.raw.au[k].map { Audio.wordPath($0) },
                                  saved: store.isSaved(k), status: store.cardStatus(k))
            }
        } else {
            let d = try IntentDict.shared.zhDict(lang)
            let romKey = lang == 2 ? Lang.yueRomKey : (lang == 3 ? Lang.hakRomKey : "zhRom")
            let rom = UserDefaults.standard.integer(forKey: romKey)
            let place = lang == 1 ? UserDefaults.standard.integer(forKey: "zhPlace") : 0
            let f = d.search(word, place: place)
            var idx: [Int] = []
            for i in f.mandarin + f.words + f.english + f.starts + f.parts.indices.flatMap({ f.partWords[$0] }) + f.contains + f.defs where !idx.contains(i) { idx.append(i) }
            total = idx.count
            rows = idx.prefix(4).map { i -> SnippetRow in
                let e = d.entries[i]
                let syl = e.syl(place)
                let gloss = (ZhMeaning.english(lang) || e.senses.isEmpty) && e.en != nil
                    ? e.enList.prefix(3).joined(separator: "; ") : (e.senses.first?.text ?? "")
                return SnippetRow(key: e.k, han: e.h, rom: d.reading(syl, rom),
                                  zy: lang == 1 ? d.reading(syl, rom == 0 ? 1 : 0) : AttributedString(), gloss: gloss,
                                  audio: lang == 1 ? "tts:" + e.h : e.audio,
                                  saved: store.isSaved(e.k), status: store.cardStatus(e.k))
            }
        }
        return .result(view: LookUpSnippetView(word: word, lang: lang, rows: rows, more: total > rows.count))
    }
}

@available(iOS 26.0, *)
struct LookUpSnippetView: View {
    let word: String
    /// -1: choosing the language
    let lang: Int
    let rows: [SnippetRow]
    let more: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            languageButtons
            if lang >= 0 {
                if rows.isEmpty {
                    Text(tr("找不到「\(word)」。")).foregroundStyle(T.muted)
                }
                ForEach(rows) { row in
                    let c = T.langColors(lang)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 8) {
                            Text(row.han).ffFont(.title3, .semibold).foregroundStyle(T.glyph)
                            Text(row.rom).latFont(16).foregroundStyle(T.greenInk)
                                .pill(T.greenInk)
                            if !row.zy.characters.isEmpty {
                                Text(row.zy).ffFont(.footnote).foregroundStyle(T.purpleInk)
                                    .pill(T.purpleInk)
                            }
                            Spacer(minLength: 0)
                        }
                        if !row.gloss.isEmpty {
                            Text(row.gloss).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.8)).lineLimit(2)
                        }
                        buttons(row)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(T.fn))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.edge, lineWidth: 1.5))
                }
                if more {
                    Button(intent: OpenLookUpIntent(word: word)) {
                        Label(tr("在 App 裡看全部"), systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered).tint(T.btnInk)
                }
            }
        }
        .padding()
        .background(T.bg)
    }

    /// the four languages, each in its colour (the one chosen filled in)
    private var languageButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            if lang < 0 { Text(tr("用哪一種語言查「\(word)」？")).ffFont(.subheadline).foregroundStyle(T.glyph) }
            HStack(spacing: 6) {
                ForEach(0..<Lang.names.count, id: \.self) { l in
                    let c = T.langColors(l)
                    Button(intent: ChooseSnippetLanguageIntent(language: l)) {
                        Text(trs(Lang.names[l])).ffFont(.subheadline, .semibold)
                            .foregroundStyle(c.ink)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background(RoundedRectangle(cornerRadius: 10).fill(l == lang || lang < 0 ? c.fill : c.fill.opacity(0.35)))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.edge, lineWidth: l == lang ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private func buttons(_ row: SnippetRow) -> some View {
        HStack(spacing: 8) {
            if let a = row.audio {
                Button(intent: PlayRecordingIntent(path: a)) { Image(systemName: "play.fill") }
                    .buttonStyle(.bordered).tint(T.greenInk)
            }
            Button(intent: ToggleSavedIntent(key: row.key)) {
                Label(row.saved ? trs("已收藏") : trSaveVerb(), systemImage: row.saved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(.bordered).tint(T.oliveInk)
            if let st = row.status {
                if st == 1 {
                    Text(tr("熟悉")).ffFont(.caption).foregroundStyle(T.greenInk)
                } else {
                    Button(intent: ToggleUnknownIntent(key: row.key)) {
                        Label(st == 2 ? trs("在不熟") : trs("加到不熟"), systemImage: st == 2 ? "star.fill" : "star")
                    }
                    .buttonStyle(.bordered).tint(T.rustInk)
                }
            }
            Spacer(minLength: 0)
            Button(intent: OpenLookUpIntent(word: row.han)) { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.bordered).tint(T.btnInk)
        }
        .ffFont(.caption)
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - the card's buttons

@available(iOS 26.0, *)
struct PlayRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "播放發音"
    static let isDiscoverable = false
    @Parameter var path: String
    init() {}
    init(path: String) { self.path = path }

    @MainActor
    func perform() async throws -> some IntentResult {
        // play over whatever app is on screen (needs the "audio" background mode, see FangfangCards-Info.plist)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        Player.shared.play(path)
        // wait for the download to start playing, then for it to finish
        try? await Task.sleep(nanoseconds: 300_000_000)
        // stay until the recording has played, so it isn't cut off
        for _ in 0..<50 {
            if Player.shared.playing != path { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        return .result()
    }
}

@available(iOS 26.0, *)
struct ToggleSavedIntent: AppIntent {
    static let title: LocalizedStringResource = "收藏／取消收藏"
    static let isDiscoverable = false
    @Parameter var key: String
    init() {}
    init(key: String) { self.key = key }

    @MainActor
    func perform() async throws -> some IntentResult {
        let s = Store.shared
        s.load()
        s.toggleSaved(key)
        s.saveNow()
        return .result()
    }
}

@available(iOS 26.0, *)
struct ToggleUnknownIntent: AppIntent {
    static let title: LocalizedStringResource = "加到不熟"
    static let isDiscoverable = false
    @Parameter var key: String
    init() {}
    init(key: String) { self.key = key }

    @MainActor
    func perform() async throws -> some IntentResult {
        let s = Store.shared
        s.load()
        s.toggleUnknown(key)
        s.saveNow()
        return .result()
    }
}

@available(iOS 26.0, *)
struct OpenLookUpIntent: AppIntent {
    static let title: LocalizedStringResource = "在方方詞卡打開"
    static let isDiscoverable = false
    static let openAppWhenRun = true
    @Parameter var word: String
    init() {}
    init(word: String) { self.word = word }

    @MainActor
    func perform() async throws -> some IntentResult {
        Router.shared.lookUp(word)
        return .result()
    }
}

extension View {
    /// a reading in a rounded box of its own colour, matching the card's buttons
    func pill(_ c: Color) -> some View {
        padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(c.opacity(0.14)))
            .overlay(Capsule().stroke(c.opacity(0.55), lineWidth: 1))
    }
}
