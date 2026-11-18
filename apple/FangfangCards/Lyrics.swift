import Foundation
import SwiftUI
import Combine
import UIKit

// 歌詞: the song a station is playing (from the name the station sends with its stream), its lyrics from LRCLIB
// (lrclib.net, a free lyrics database), shown in a window of their own: the 漢字 on the left, the reading on the right;
// tap a word for its meaning, save it, add it to 不熟. Nothing can be typed there. The lyrics are only shown, never
// kept (only the song shown last, on this device).

/// a song in LRCLIB
struct LyricHit: Decodable, Identifiable, Hashable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double?
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?

    enum K: String, CodingKey { case id, trackName, artistName, albumName, duration, instrumental, plainLyrics, syncedLyrics }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        id = try c.decode(Int.self, forKey: .id)
        trackName = (try? c.decode(String.self, forKey: .trackName)) ?? ""
        artistName = (try? c.decode(String.self, forKey: .artistName)) ?? ""
        albumName = try? c.decode(String.self, forKey: .albumName)
        duration = try? c.decode(Double.self, forKey: .duration)
        instrumental = (try? c.decode(Bool.self, forKey: .instrumental)) ?? false
        plainLyrics = try? c.decode(String.self, forKey: .plainLyrics)
        syncedLyrics = try? c.decode(String.self, forKey: .syncedLyrics)
    }

    /// lyrics made here (自己的歌詞), not from LRCLIB
    init(id: Int, trackName: String, artistName: String, duration: Double?, plain: String?, synced: String?) {
        self.id = id
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = nil
        self.duration = duration
        self.instrumental = false
        self.plainLyrics = plain
        self.syncedLyrics = synced
    }

    /// the timed version's lines (LRC: "[01:23.45]words", a line may have several times): when each is sung, the
    /// empty ones (between verses) as "". nil when the song has no timed version.
    var timedRows: [(times: [Double], text: String)]? {
        guard let s = syncedLyrics, !s.isEmpty else { return nil }
        var out: [(times: [Double], text: String)] = []
        for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = Substring(raw)
            var times: [Double] = []
            while line.first == "[", let close = line.firstIndex(of: "]") {
                let stamp = line[line.index(after: line.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let sec = Double(parts[1]) { times.append(m * 60 + sec) } else { break }
                line = line[line.index(after: close)...]
            }
            if !times.isEmpty { out.append((times, line.trimmingCharacters(in: .whitespaces))) }
        }
        return out.contains(where: { !$0.text.isEmpty }) ? out : nil
    }

    /// the words of the song, one line each (the timed version's lines when there is one, so the times fit them;
    /// else the plain words)
    var text: String? {
        if let rows = timedRows {
            let t = rows.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
            if !t.isEmpty { return t }
        }
        if let p = plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty { return p }
        guard let s = syncedLyrics, !s.isEmpty else { return nil }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            line.replacingOccurrences(of: #"^(\[[0-9:.]+\]\s*)+"#, with: "", options: .regularExpression)
        }
        let t = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

enum LyricsSource {
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["User-Agent": "FangfangCards/1.0 (https://github.com/)"]
        return URLSession(configuration: c)
    }()

    static func search(_ q: String) async throws -> [LyricHit] {
        var u = URLComponents(string: "https://lrclib.net/api/search")!
        u.queryItems = [URLQueryItem(name: "q", value: q)]
        let (d, r) = try await session.data(from: u.url!)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([LyricHit].self, from: d)
    }

    /// what a station says is playing ("周杰倫 - 晴天 (Live)", "StreamTitle: …") → what to search for: the whole
    /// of it, then each part on its own (artist and title can come in either order)
    static func queries(_ playing: String) -> [String] {
        var s = playing
        for junk in [#"\([^)]*\)"#, #"（[^）]*）"#, #"\[[^\]]*\]"#, #"【[^】]*】"#, #"(?i)\b(now playing|on air|live)\b:?"#] {
            s = s.replacingOccurrences(of: junk, with: " ", options: .regularExpression)
        }
        let parts = s.components(separatedBy: CharacterSet(charactersIn: "-–—/|")).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'「」『』《》")))
        }.filter { !$0.isEmpty }
        var out = [parts.joined(separator: " ")]
        if parts.count > 1 { out += parts.sorted { $0.count > $1.count } }
        var seen = Set<String>()
        return out.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// songs for what's playing: the first search that finds any with words
    static func find(_ playing: String) async -> [LyricHit] {
        for q in queries(playing) {
            if let r = try? await search(q) {
                let good = r.filter { !$0.instrumental && $0.text != nil }
                if !good.isEmpty { return good }
            }
            if Task.isCancelled { return [] }
        }
        return []
    }

    /// 簡體 → 繁體 (nil when the text doesn't change or the phone can't do it)
    static func traditional(_ s: String) -> String? {
        guard let t = s.applyingTransform(StringTransform("Hans-Hant"), reverse: false), t != s else { return nil }
        return t
    }
}

/// where the song is: the line being sung (its number among the lines with words; -1 between them) and how far
/// into it (0…1). Kept apart from the lyrics, so only the words notice it changing.
@MainActor
final class LyricsBeat: ObservableObject {
    static let shared = LyricsBeat()
    /// (for words that don't follow a song)
    static let idle = LyricsBeat()
    @Published var line = -1
    @Published var frac = 0.0
}

/// the song's lyrics for the 歌詞 window: each time the station says a new song is playing, its lyrics are looked up
@MainActor
final class LyricsBridge: ObservableObject {
    static let shared = LyricsBridge()
    /// 換歌的時候自己找歌詞: on by default
    static let autoKey = "lyricsAuto"
    /// 歌詞: the readings beside (or under) the 漢字, on or off (off: only the 漢字, lighter on memory)
    static let readingsKey = "lyricsReadings"
    /// the lyrics shown in the 歌詞 window (its own text: 轉換's is left alone)
    static let textKey = "lyricsText"
    /// a new song's lyrics (台語's 轉換 keeps its text itself, so it's told)
    static let changed = Notification.Name("ffLyricsChanged")
    /// the line being sung, for the lyrics bar shown over the rest of the app
    static let barKey = "lyricsBarText"
    /// the bar's two places for a line: the one being sung, and the next one made ready under it (so a new line
    /// flows up already drawn, instead of popping in)
    static let barKeys = [barKey, "lyricsBarText2"]
    /// which of the two is the line being sung
    @Published private(set) var barSlot = 0
    /// 歌詞條: the line being sung shown over the other pages too, on by default
    static let floatKey = "lyricsFloat"
    /// the colours' glow in the lyrics (the page and the bar), apart from the rest of the app; on by default
    static let glowKey = "lyricsGlow"

    // ── following the song (timed lyrics): the song started when the station said so (or when it was chosen),
    // and the lines come at their times from then on; 對時 moves them earlier or later ──
    /// each time a line starts: (seconds into the song, the line's number among those with words, -1: none)
    private var cues: [(t: Double, line: Int)] = []
    /// the lines with words (as shown)
    private(set) var lineTexts: [String] = []
    /// when the song started
    private var started: Date?
    /// when the station said a new song was playing
    private var changedAt: Date?
    private var beatTimer: Timer?
    /// 找歌來聽: the player's own time (seconds into the song), instead of the time since the station said so
    var clock: (@MainActor () -> Double?)?
    /// 找歌來聽 (the whole song): 跳到 a line moves the song itself there
    var seeker: (@MainActor (Double) -> Void)?
    /// seconds into the song now (with 對時)
    private var songPos: Double? {
        guard let s = started else { return nil }
        let base = clock.map { $0() ?? 0 } ?? Date().timeIntervalSince(s)
        return base + offset
    }
    /// 對時: seconds the lyrics are moved (+: sooner)
    @Published private(set) var offset: Double = 0
    /// the lyrics follow the song (it has a timed version)
    @Published private(set) var timed = false
    /// the line after the one being sung (for the bar)
    @Published private(set) var nextLine = ""
    /// the bar closed for this song
    @Published var barHiddenFor: Int?
    /// something is open over the app's pages (a game, 設定…): the bar shows even on 轉換 → 歌詞
    @Published private(set) var appCovered = false

    /// 對時: the lyrics sooner (+) or later (−)
    func nudge(_ s: Double) { offset = ((offset + s) * 100).rounded() / 100; tick() }
    func resetOffset() { offset = 0; tick() }

    /// when a line is first sung (seconds into the song), for the list of lines
    func lineTime(_ n: Int) -> Double? { cues.first(where: { $0.line == n })?.t }

    /// to this line: 對時 moved so it's being sung now (a line sung more than once: the time nearest to now)
    func jump(toLine n: Int) {
        guard timed, let s = started, let pos = songPos else { return }
        guard let c = cues.filter({ $0.line == n }).min(by: { abs($0.t - pos) < abs($1.t - pos) }) else { return }
        if let seek = seeker { seek(c.t - offset + 0.05); tick(); return }
        let base = clock.map { $0() ?? 0 } ?? Date().timeIntervalSince(s)
        offset = ((c.t + 0.02 - base) * 100).rounded(.up) / 100
        tick()
    }

    /// the line before (−1) or after (+1) the one being sung
    func skipLine(_ d: Int) {
        guard timed, !lineTexts.isEmpty, let pos = songPos else { return }
        let cur = LyricsBeat.shared.line
        var target: Int
        if cur >= 0 { target = cur + d }
        else if d < 0 { target = cues.last(where: { $0.t <= pos && $0.line >= 0 })?.line ?? 0 }
        else { target = cues.first(where: { $0.t > pos && $0.line >= 0 })?.line ?? (lineTexts.count - 1) }
        target = min(max(target, 0), lineTexts.count - 1)
        jump(toLine: target)
    }

    private func follow(_ h: LyricHit, text: String, from start: Date) {
        beatTimer?.invalidate(); beatTimer = nil
        cues = []; lineTexts = text.components(separatedBy: "\n"); started = start; offset = 0
        if let rows = h.timedRows {
            var n = 0
            for row in rows {
                let line = row.text.isEmpty ? -1 : n
                if !row.text.isEmpty { n += 1 }
                for t in row.times { cues.append((t, line)) }
            }
            cues.sort { $0.t < $1.t }
        }
        timed = !cues.isEmpty
        LyricsBeat.shared.line = -1; LyricsBeat.shared.frac = 0
        nextLine = ""
        for k in Self.barKeys { UserDefaults.standard.set("", forKey: k) }
        if timed {
            let t = Timer(timeInterval: 0.08, repeats: true) { _ in Task { @MainActor in LyricsBridge.shared.tick() } }
            RunLoop.main.add(t, forMode: .common)
            beatTimer = t
        }
    }

    /// (every few hundredths of a second: the line and the place in it)
    private func tick() {
        guard timed, let pos = songPos else { return }
        var lo = 0, hi = cues.count - 1, k = -1
        while lo <= hi { let m = (lo + hi) / 2; if cues[m].t <= pos { k = m; lo = m + 1 } else { hi = m - 1 } }
        let line = k >= 0 ? cues[k].line : -1
        var frac = 0.0
        if k >= 0 {
            let t0 = cues[k].t, t1 = k + 1 < cues.count ? cues[k + 1].t : t0 + 5
            frac = min(1, max(0, (pos - t0) / max(0.5, t1 - t0)))
        }
        let q = (frac * 30).rounded(.down) / 30
        let beat = LyricsBeat.shared
        if beat.line != line {
            beat.line = line
            let text = line >= 0 && line < lineTexts.count ? lineTexts[line] : ""
            var next = ""
            var j = k + 1
            while j < cues.count { if cues[j].line >= 0 && cues[j].line != line { next = lineTexts.indices.contains(cues[j].line) ? lineTexts[cues[j].line] : ""; break }; j += 1 }
            // (the bar: the line made ready below comes up; the one going up is given the line after, once it's gone)
            let now = 1 - barSlot
            if UserDefaults.standard.string(forKey: Self.barKeys[now]) != text { UserDefaults.standard.set(text, forKey: Self.barKeys[now]) }
            barSlot = now
            nextLine = next
            NotificationCenter.default.post(name: Self.changed, object: nil)
            let other = Self.barKeys[1 - now]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.barSlot == now else { return }
                UserDefaults.standard.set(next, forKey: other)
                NotificationCenter.default.post(name: Self.changed, object: nil)
            }
        }
        if beat.frac != q { beat.frac = q }
        let covered = LyricsOverlay.appCovered
        if covered != appCovered { appCovered = covered }
    }

    /// the song shown
    @Published private(set) var song: LyricHit?
    /// (bumped with each new song: the window draws its words again)
    @Published private(set) var version = 0
    /// looking up the song the station started playing
    @Published private(set) var looking = false
    /// what the station said was playing, when no lyrics were found for it
    @Published private(set) var notFound: String?
    /// what the station said was playing when these lyrics were found for it (nil: chosen by hand)
    private(set) var songFor: String?
    /// the lyrics as 簡體 (normally 繁體 like the app)
    @Published var keepSimplified = false { didSet { if let s = song { put(s) } } }

    private var job: Task<Void, Never>?
    private var lastPlaying: String?
    private var bag = Set<AnyCancellable>()

    private init() {
        RadioPlayer.shared.$nowPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] p in self?.stationSays(p) }
            .store(in: &bag)
        // (another language chosen: 繁體 or not depends on it)
        Store.shared.$lang
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in if let s = self?.song { self?.put(s) } }
            .store(in: &bag)
    }

    private func stationSays(_ p: String?) {
        guard let p, p != lastPlaying, UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true,
              RadioPlayer.shared.isOn else { return }
        lastPlaying = p
        changedAt = Date()
        job?.cancel()
        looking = true
        job = Task {
            let found = await LyricsSource.find(p)
            guard !Task.isCancelled else { return }
            looking = false
            if let first = found.first { put(first, from: changedAt); songFor = p } else { notFound = p }
        }
    }

    /// a saved song's lyrics (我的歌)
    func lookUp(_ q: String) {
        job?.cancel()
        looking = true
        job = Task {
            let found = await LyricsSource.find(q)
            guard !Task.isCancelled else { return }
            looking = false
            if let first = found.first { put(first) } else { song = nil; notFound = q }
        }
    }

    /// 找歌來聽: a song started; its lyrics are being looked for (the old ones go)
    func waitFor(_ q: String) {
        job?.cancel()
        beatTimer?.invalidate(); beatTimer = nil
        timed = false; cues = []; nextLine = ""
        LyricsBeat.shared.line = -1; LyricsBeat.shared.frac = 0
        for k in Self.barKeys { UserDefaults.standard.set("", forKey: k) }
        song = nil
        notFound = nil
        looking = true
    }

    /// 找歌來聽: no lyrics found for the song
    func noneFound(_ q: String) {
        looking = false
        song = nil
        notFound = q
    }

    /// this song in the window (in the app's characters: 繁體, unless 簡體 is chosen)
    /// (from: when the song started: when the station said so; else now, when it's chosen by hand)
    func put(_ h: LyricHit, from: Date? = nil) {
        guard let text = h.text else { return }
        let simp = UserDefaults.standard.bool(forKey: Simp.key)
        var t = text
        if Lang.current <= 3, !simp, !keepSimplified, let trad = LyricsSource.traditional(text) { t = trad }
        UserDefaults.standard.set(t, forKey: Self.textKey)
        // (the same song again, 簡 ⇄ 繁: it goes on where it was)
        if song?.id != h.id || started == nil { follow(h, text: t, from: from ?? Date()) }
        else { let keep = offset; let st = started ?? Date(); follow(h, text: t, from: st); offset = keep }
        if song?.id != h.id { songFor = nil }
        song = h
        notFound = nil
        looking = false
        version += 1
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// 轉換 → 歌詞, the whole page (the radio's sheet closes)
    static func showInConvert() {
        UserDefaults.standard.set(2, forKey: "convertTab")
        Router.shared.tab = 3
        RadioPlayer.shared.sheetOpen = false
    }

    /// the lyrics are simplified characters the app shows as 繁體
    var canSwitchScript: Bool {
        guard let t = song?.text, Lang.current <= 3, !UserDefaults.standard.bool(forKey: Simp.key) else { return false }
        return LyricsSource.traditional(t) != nil
    }
}

/// 轉換 → 歌詞: the song's words, read only, the whole page: the 漢字 (in tone colours when they're on) on the left,
/// the chosen spelling on the right; tap a word for its meaning, to save it or add it to 不熟
struct LyricsWindow: View {
    /// (轉換's 歌詞 section: the page's own top bar has the spelling menu)
    var inConvert = false
    @ObservedObject private var lyrics = LyricsBridge.shared
    @ObservedObject private var radio = RadioPlayer.shared
    @EnvironmentObject var store: Store
    @State private var picking = false
    @State private var lineList = false
    @AppStorage(LyricsBridge.readingsKey) private var readings = true
    @AppStorage(LyricsBridge.glowKey) private var lyricsGlow = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
        SongPlayerBar()
        Group {
            if let h = lyrics.song {
                VStack(spacing: 0) {
                    header(h)
                    // a new song: the old words burst into sparkles of their colours, the new ones fade in
                    ZStack {
                        words.id("\(lyrics.version)-\(store.lang)")
                            .environment(\.noToneGlow, !lyricsGlow)
                            .transition(LyricsDissolve.transition(reduceMotion))
                    }
                    .frame(maxHeight: .infinity)
                    .animation(.linear(duration: LyricsDissolve.length), value: lyrics.version)
                }
            } else if lyrics.looking {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(tr("找歌詞…")).ffFont(.footnote).foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LyricsPage(embedded: true)
            }
        }
        .frame(maxHeight: .infinity)
        }
        .appBackground()
        .modifier(LyricsBar(on: !inConvert))
        .sheet(isPresented: $lineList) {
            NavigationStack { LyricsLineList() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
        .sheet(isPresented: $picking) {
            NavigationStack { LyricsPage(inSheet: true) }
                .environmentObject(Store.shared)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
    }

    private func header(_ h: LyricHit) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note").foregroundStyle(T.btnInk)
            VStack(alignment: .leading, spacing: 1) {
                Text(h.trackName).ffFont(.headline).lineLimit(1)
                Text(h.artistName).ffFont(.subheadline).foregroundStyle(T.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if lyrics.canSwitchScript {
                Button { lyrics.keepSimplified.toggle() } label: { Text(lyrics.keepSimplified ? "簡" : "繁").ffFont(.subheadline, .bold) }
                    .softButton()
                    .accessibilityLabel(tr("簡體或繁體"))
            }
            // (the readings side: off makes a long song lighter on memory)
            Button { readings.toggle() } label: {
                Text(tr("讀音")).ffFont(.subheadline, .semibold).opacity(readings ? 1 : 0.4)
            }
            .softButton()
            .accessibilityLabel(readings ? tr("關掉讀音那一邊") : tr("打開讀音那一邊"))
            LyricsGlowToggle().softButton()
            // (the song playing in 音樂: lyrics of your own, or these timed again)
            LyricsEditButton()
            if lyrics.timed {
                Button { lineList = true } label: { Image(systemName: "list.number") }
                    .softButton()
                    .accessibilityLabel(tr("跳到哪一行"))
            }
            SaveSongButton(size: 18, song: h)
                .padding(.horizontal, 4)
            Button { picking = true } label: { Image(systemName: "magnifyingglass") }
                .softButton()
                .accessibilityLabel(tr("找別的歌詞"))
        }
        .padding(.horizontal).padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            // (timed lyrics: 對時, when the words come too early or too late for the radio)
            if lyrics.timed { LyricsNudge().padding(.bottom, -34) }
        }
        .padding(.bottom, lyrics.timed ? 34 : 0)
    }

    /// the language's 轉換, in its 歌詞 form (no typing)
    @ViewBuilder private var words: some View {
        if store.isSv {
            ZhGate { z in SvConvertPane(dict: z, textKey: LyricsBridge.textKey, lyrics: true) }
        } else if store.isZh {
            ZhGate { z in ZhConvertPane(dict: z, textKey: LyricsBridge.textKey, lyrics: true) }
        } else {
            DictGate { d in ConvertPane(dict: d, textKey: LyricsBridge.textKey, lyrics: true) }
        }
    }
}

/// 找歌詞: search (filled in with what the station is playing); the song chosen is shown in the 歌詞 window
struct LyricsPage: View {
    var inSheet = false
    /// (inside the 歌詞 window, before there's a song)
    var embedded = false
    @ObservedObject private var radio = RadioPlayer.shared
    @ObservedObject private var lyrics = LyricsBridge.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LyricsBridge.autoKey) private var auto = true
    @AppStorage(LyricsBridge.floatKey) private var float = true
    @State private var query = ""
    @State private var hits: [LyricHit] = []
    @State private var busy = false
    @State private var searched = false
    @State private var failed = false
    @State private var job: Task<Void, Never>?
    @State private var songSearch = false

    var body: some View {
        List {
            Section {
                Button { songSearch = true } label: {
                    Label(tr("找歌來聽（Apple Music）"), systemImage: "play.circle")
                }
                LyricsEditButton(label: true)
            } footer: {
                Text(tr("找一首歌來放，歌詞會跟著歌走。")).ffFont(.footnote)
            }
            Section {
                HStack {
                    TextField(tr("歌名或歌手"), text: $query)
                        .submitLabel(.search)
                        .onSubmit { run() }
                    if busy { ProgressView() } else {
                        Button { run() } label: { Image(systemName: "magnifyingglass") }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let p = radio.nowPlaying, p != query {
                    Button { query = p; run() } label: {
                        Label(tr("電台正在放：\(p)"), systemImage: "dot.radiowaves.left.and.right").lineLimit(2)
                    }
                }
                Toggle(tr("換歌的時候自己找歌詞"), isOn: $auto)
                Toggle(tr("在其他頁面顯示歌詞條"), isOn: $float)
            } footer: {
                Text(tr("電台有送歌名的話會自己找。沒有的話可以自己打歌名（控制中心的「音樂辨識」可以聽出手機正在放的歌）。歌詞來自 LRCLIB（lrclib.net）。有時間的歌詞會跟著歌走，正在唱的詞會變大；跟電台對不上的話，用「對時」的按鈕往前或往後調。"))
                    .ffFont(.footnote)
            }
            if failed {
                Text(tr("連不上 LRCLIB，等一下再試試看。")).foregroundStyle(T.muted)
            } else if searched && hits.isEmpty && !busy {
                Text(tr("找不到這首歌的歌詞")).foregroundStyle(T.muted)
            }
            if !hits.isEmpty {
                Section {
                    ForEach(hits) { h in
                        Button { lyrics.put(h); if inSheet { dismiss() } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(h.trackName).foregroundStyle(T.glyph).lineLimit(1)
                                    Text(detail(h)).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                                }
                                Spacer()
                                if lyrics.song?.id == h.id { Image(systemName: "checkmark").foregroundStyle(T.btnInk) }
                            }
                        }
                    }
                } footer: {
                    Text(tr("選一首：漢字和讀音會並排顯示，點詞就看得到意思、可以收藏。")).ffFont(.footnote)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .modifier(LyricsTitle(title: embedded ? nil : tr("找歌詞")))
        .sheet(isPresented: $songSearch) {
            NavigationStack { SongSearchView() }
                .environmentObject(Store.shared)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
        .toolbar {
            if inSheet { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } } }
        }
        .onAppear {
            if hits.isEmpty {
                query = lyrics.song.map { $0.artistName + " " + $0.trackName } ?? radio.nowPlaying ?? lyrics.notFound ?? ""
                if !query.isEmpty { run() }
            }
        }
    }

    private func detail(_ h: LyricHit) -> String {
        var p = [h.artistName]
        if let a = h.albumName, !a.isEmpty, a != h.trackName { p.append(a) }
        if let d = h.duration, d > 0 { p.append(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)) }
        return p.joined(separator: " · ")
    }

    private func run() {
        job?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        busy = true; failed = false
        job = Task {
            var found: [LyricHit] = []
            var reached = true
            do { found = try await LyricsSource.search(q).filter { !$0.instrumental && $0.text != nil } } catch { reached = false }
            if reached && found.isEmpty { found = await LyricsSource.find(q) }
            if Task.isCancelled { return }
            hits = found
            failed = !reached
            searched = true
            busy = false
        }
    }
}

// MARK: - 我的歌: songs heard on the radio, kept to find again later

struct SavedSong: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var artist: String
    /// the station it was heard on
    var station: String?
    var lang: Int
    var date = Date()

    /// "周杰倫 晴天": to search with
    var query: String { [artist, title].filter { !$0.isEmpty }.joined(separator: " ") }
}

@MainActor
final class SongList: ObservableObject {
    static let shared = SongList()
    private let key = "savedSongs"
    @Published private(set) var songs: [SavedSong] = []

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([SavedSong].self, from: d) { songs = s }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(songs) { UserDefaults.standard.set(d, forKey: key) }
    }

    /// the song playing now: the lyrics' names when they were found, else what the station says ("Artist - Title")
    static func current() -> (title: String, artist: String)? {
        let radio = RadioPlayer.shared
        if let h = LyricsBridge.shared.song, let p = radio.nowPlaying, LyricsBridge.shared.songFor == p {
            return (h.trackName, h.artistName)
        }
        guard let p = radio.nowPlaying?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty else {
            if let h = LyricsBridge.shared.song { return (h.trackName, h.artistName) }
            return nil
        }
        for sep in [" - ", " – ", " — ", " / "] {
            if let r = p.range(of: sep) {
                let a = p[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                let t = p[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if !a.isEmpty && !t.isEmpty { return (t, a) }
            }
        }
        return (p, "")
    }

    func has(_ title: String, _ artist: String) -> Bool {
        songs.contains { $0.title.lowercased() == title.lowercased() && $0.artist.lowercased() == artist.lowercased() }
    }

    /// the song (the one playing now, or the one given) in the list, or out of it again
    func toggle(_ given: (title: String, artist: String)? = nil) {
        guard let c = given ?? Self.current() else { return }
        if has(c.title, c.artist) {
            songs.removeAll { $0.title.lowercased() == c.title.lowercased() && $0.artist.lowercased() == c.artist.lowercased() }
        } else {
            let st = RadioPlayer.shared.current
            songs.insert(SavedSong(title: c.title, artist: c.artist, station: st?.name, lang: st?.lang ?? Lang.current), at: 0)
        }
        save()
    }



    func remove(_ s: SavedSong) { songs.removeAll { $0.id == s.id }; save() }
}

/// ♡ for the song playing now: kept in 我的歌
struct SaveSongButton: View {
    @ObservedObject private var list = SongList.shared
    @ObservedObject private var radio = RadioPlayer.shared
    @ObservedObject private var lyrics = LyricsBridge.shared
    var size: CGFloat = 22
    /// the song whose lyrics are shown (nil: the one playing now)
    var song: LyricHit? = nil
    var body: some View {
        let target = song.map { (title: $0.trackName, artist: $0.artistName) } ?? SongList.current()
        let can = target != nil
        let saved = target.map { list.has($0.title, $0.artist) } ?? false
        Button { withAnimation(.snappy) { list.toggle(target) } } label: {
            Image(systemName: saved ? "bookmark.fill" : "bookmark")
                .font(.system(size: size))
                .foregroundStyle(saved ? T.btnInk : (can ? T.glyph : T.muted.opacity(0.5)))
        }
        .buttonStyle(.plain)
        .disabled(!can)
        .accessibilityLabel(saved ? tr("從我的歌拿掉") : tr("存到我的歌"))
    }
}

/// 我的歌: the songs saved, newest first; tap one for its lyrics
struct SavedSongsView: View {
    @ObservedObject private var list = SongList.shared
    @Environment(\.openURL) private var openURL
    @State private var filter: Int? = nil
    @ObservedObject private var player = SongPlayer.shared
    /// the song being looked for in the catalogue
    @State private var finding: String?
    /// the songs the catalogue doesn't have (only their lyrics were shown)
    @State private var missing: Set<String> = []

    var body: some View {
        List {
            if list.songs.isEmpty {
                Text(tr("還沒有存歌。聽電台的時候按書籤，歌名和歌手就會存在這裡。")).foregroundStyle(T.muted)
            } else {
                let langs = Array(Set(list.songs.map(\.lang))).sorted()
                if langs.count > 1 {
                    Picker(tr("語言"), selection: $filter) {
                        Text(tr("全部")).tag(Int?.none)
                        ForEach(langs, id: \.self) { Text(trs(Lang.names[min(max($0, 0), Lang.count - 1)])).tag(Int?.some($0)) }
                    }
                }
                ForEach(list.songs.filter { filter == nil || $0.lang == filter }) { s in
                    Button { play(s) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).foregroundStyle(T.glyph).lineLimit(1)
                                Text(detail(s)).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if finding == s.id { ProgressView() }
                            else if missing.contains(s.id) {
                                Image(systemName: "text.alignleft").foregroundStyle(T.muted)
                                    .accessibilityLabel(tr("找不到這首歌，只有歌詞"))
                            } else {
                                Image(systemName: "play.circle").foregroundStyle(T.btnInk)
                            }
                        }
                    }
                    .disabled(finding != nil)
                    .contextMenu {
                        Button { UIPasteboard.general.string = s.artist.isEmpty ? s.title : s.artist + " - " + s.title } label: {
                            Label(tr("複製歌名"), systemImage: "doc.on.doc")
                        }
                        Button { open("https://music.apple.com/search?term=", s) } label: { Label(tr("在 Apple Music 找"), systemImage: "music.note") }
                        Button { open("https://www.youtube.com/results?search_query=", s) } label: { Label(tr("在 YouTube 找"), systemImage: "play.rectangle") }
                        Button { LyricsBridge.shared.lookUp(s.query); LyricsBridge.showInConvert() } label: {
                            Label(tr("只看歌詞"), systemImage: "text.alignleft")
                        }
                        Button(role: .destructive) { list.remove(s) } label: { Label(tr("刪除"), systemImage: "trash") }
                    }
                    .swipeActions {
                        Button(role: .destructive) { list.remove(s) } label: { Label(tr("刪除"), systemImage: "trash") }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("我的歌"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !list.songs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: list.songs.map { s in s.artist.isEmpty ? s.title : s.artist + " - " + s.title }.joined(separator: "\n")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(tr("分享清單"))
                }
            }
        }
    }

    /// the song from Apple's catalogue, playing, its lyrics following it; not there: only its lyrics, as before
    private func play(_ s: SavedSong) {
        finding = s.id
        Task {
            let hit = await player.find(title: s.title, artist: s.artist)
            finding = nil
            if let hit {
                player.play(hit)
            } else {
                missing.insert(s.id)
                LyricsBridge.shared.lookUp(s.query)
            }
            LyricsBridge.showInConvert()
        }
    }

    private func detail(_ s: SavedSong) -> String {
        var p: [String] = []
        if !s.artist.isEmpty { p.append(s.artist) }
        if let st = s.station { p.append(st) }
        p.append(s.date.formatted(date: .abbreviated, time: .omitted))
        return p.joined(separator: " · ")
    }

    private func open(_ base: String, _ s: SavedSong) {
        if let q = s.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let u = URL(string: base + q) { openURL(u) }
    }
}

/// the 歌詞 page's own title and spelling menu (not inside 轉換, whose top bar has them)
private struct LyricsBar: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content
                .navigationTitle(tr("歌詞"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { CompactReadingMenu().fixedSize() } }
        } else { content }
    }
}

private struct LyricsTitle: ViewModifier {
    let title: String?
    func body(content: Content) -> some View {
        if let title { content.navigationTitle(title).navigationBarTitleDisplayMode(.inline) } else { content }
    }
}

/// the 歌詞 page's two boxes: side by side (iPad, Mac), or the reading under the 漢字 (iPhone)
struct LyricsColumns<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        let layout = UIDevice.current.userInterfaceIdiom == .phone
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
        layout { content }
    }
}

// MARK: - the old lyrics turning into sparkles

/// a song's words leaving: they fade and blur away while sparkles in their colours rise out of them
struct LyricsDissolve: ViewModifier, Animatable {
    /// 0: the words as they are … 1: gone
    var p: Double
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }

    func body(content: Content) -> some View {
        content
            // (the words are gone in the first third; the sparkles stay on after them)
            .opacity(max(0, 1 - p * 3))
            .blur(radius: min(1, p * 3) * 9)
            .scaleEffect(1 + min(1, p * 3) * 0.03)
            .overlay {
                if p > 0.001 && p < 0.999 { SparkleDust(p: p).allowsHitTesting(false) }
            }
    }

    /// how long the sparkles last (seconds)
    static let length = 2.6

    /// leaving: sparkles; coming: fading in once the sparkles are mostly gone (Reduce Motion: only a fade)
    static func transition(_ reduce: Bool) -> AnyTransition {
        if reduce { return .opacity.animation(.easeInOut(duration: 0.35)) }
        return .asymmetric(
            insertion: .opacity.animation(.easeIn(duration: 0.9).delay(length * 0.55)),
            removal: .modifier(active: LyricsDissolve(p: 1), identity: LyricsDissolve(p: 0)).animation(.linear(duration: length)))
    }
}

/// the sparkles: scattered over the words, drifting up, twinkling, then gone
private struct SparkleDust: View {
    let p: Double
    @AppStorage(ToneColors.key) private var system = 0

    private struct Grain { let x, y, dx, dy, size, phase: Double; let color: Int; let star: Bool }
    /// (the same scattering every time: made once)
    private static let grains: [Grain] = {
        var g = SystemRandomNumberGenerator()
        return (0..<170).map { _ in
            Grain(x: Double.random(in: 0...1, using: &g), y: Double.random(in: 0...1, using: &g),
                  dx: Double.random(in: -0.06...0.06, using: &g), dy: Double.random(in: -0.22 ... -0.04, using: &g),
                  size: Double.random(in: 1.5...4.2, using: &g), phase: Double.random(in: 0...(2 * .pi), using: &g),
                  color: Int.random(in: 0..<64, using: &g), star: Double.random(in: 0...1, using: &g) < 0.3)
        }
    }()

    /// the words' colours: the tone colours when they're on, the text's own colours when not
    private var colors: [Color] { system != 0 ? StarField.colors : [T.glyph, T.btnInk, T.greenInk] }

    var body: some View {
        let cs = colors
        Canvas { ctx, size in
            // (in quickly while the words fade, bright for a while, then fading out as they rise)
            let alphaAll = min(1, p / 0.15) * min(1, (1 - p) / 0.45)
            guard alphaAll > 0.01 else { return }
            for g in Self.grains {
                let x = (g.x + g.dx * p) * size.width
                let y = (g.y + g.dy * p) * size.height
                let tw = 0.55 + 0.45 * sin(g.phase + p * 26)
                let a = alphaAll * tw
                let c = cs[g.color % cs.count]
                let r = g.size * (1.15 - 0.45 * p)
                // a soft halo, then the grain itself
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 2.2, y: y - r * 2.2, width: r * 4.4, height: r * 4.4)),
                         with: .color(c.opacity(a * 0.22)))
                if g.star {
                    var s = Path()
                    let l = r * 2.4, w = r * 0.5
                    s.move(to: CGPoint(x: x, y: y - l))
                    s.addQuadCurve(to: CGPoint(x: x + l, y: y), control: CGPoint(x: x + w, y: y - w))
                    s.addQuadCurve(to: CGPoint(x: x, y: y + l), control: CGPoint(x: x + w, y: y + w))
                    s.addQuadCurve(to: CGPoint(x: x - l, y: y), control: CGPoint(x: x - w, y: y + w))
                    s.addQuadCurve(to: CGPoint(x: x, y: y - l), control: CGPoint(x: x - w, y: y - w))
                    ctx.fill(s, with: .color(c.opacity(a)))
                } else {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)), with: .color(c.opacity(a)))
                }
            }
        }
    }
}


// MARK: - 跟著唱: timed lyrics follow the song

/// 對時: the lyrics sooner or later by a quarter of a second or a second (the radio's sound comes later than the song's
/// start the station tells, by a different amount for each station)
struct LyricsNudge: View {
    @ObservedObject private var lyrics = LyricsBridge.shared
    var body: some View {
        HStack(spacing: 6) {
            Button { lyrics.skipLine(-1) } label: {
                Image(systemName: "backward.end").ffFont(.subheadline, .semibold).frame(minWidth: 30, minHeight: 28)
            }
            .softButton()
            .accessibilityLabel(tr("跳到上一行"))
            step("−1", -1, tr("歌詞晚一秒"))
            step("−¼", -0.25, tr("歌詞晚四分之一秒"))
            Button { lyrics.resetOffset() } label: {
                Text(lyrics.offset == 0 ? tr("對時") : Self.shown(lyrics.offset))
                    .monospacedDigit().ffFont(.caption, .semibold).foregroundStyle(lyrics.offset == 0 ? T.muted : T.btnInk)
                    .frame(minWidth: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("對時還原"))
            step("+¼", 0.25, tr("歌詞早四分之一秒"))
            step("+1", 1, tr("歌詞早一秒"))
            Button { lyrics.skipLine(1) } label: {
                Image(systemName: "forward.end").ffFont(.subheadline, .semibold).frame(minWidth: 30, minHeight: 28)
            }
            .softButton()
            .accessibilityLabel(tr("跳到下一行"))
        }
    }
    /// +0.25 s, −1.5 s, +2 s (no zeros at the end)
    static func shown(_ o: Double) -> String {
        var t = String(format: "%+.2f", o)
        while t.hasSuffix("0") { t.removeLast() }
        if t.hasSuffix(".") { t.removeLast() }
        return t + " s"
    }
    private func step(_ label: String, _ s: Double, _ name: String) -> some View {
        Button { lyrics.nudge(s) } label: {
            Text(label).ffFont(.subheadline, .semibold).monospacedDigit().frame(minWidth: 34, minHeight: 28)
        }
        .softButton()
        .accessibilityLabel(name)
    }
}

/// a word of the lyrics swells while it's sung (its line's words are spread over the time to the next line, by
/// their length); the other lines a little dimmer
struct BeatSwell: ViewModifier {
    @ObservedObject var beat: LyricsBeat
    /// the word's line (-2: always the line being sung, the bar's)
    let line: Int
    let f0: Double, f1: Double
    func body(content: Content) -> some View {
        let mine = line == -2 ? beat.line : line
        let inLine = beat.line >= 0 && beat.line == mine
        let on = inLine && f1 > f0 && beat.frac >= f0 && (beat.frac < f1 || f1 >= 0.999)
        content
            .scaleEffect(on ? 1.3 : 1, anchor: .bottom)
            .opacity(beat === LyricsBeat.idle || beat.line < 0 || inLine ? 1 : 0.6)
            .zIndex(on ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.62), value: on)
    }
}

/// 歌詞條: the line being sung over every page (above the tab bar), with the next one under it, the words in their
/// colours and tappable for their meaning; 對時 under them. Only while the radio plays a song with timed lyrics.
struct LyricsFloat: View {
    /// (the bar is moved by dragging its top row)
    var onDrag: (CGSize) -> Void = { _ in }
    var onDragEnd: (CGSize) -> Void = { _ in }
    @ObservedObject private var lyrics = LyricsBridge.shared
    @ObservedObject private var radio = RadioPlayer.shared
    @ObservedObject private var router = Router.shared
    @EnvironmentObject var store: Store
    @AppStorage(LyricsBridge.floatKey) private var on = true
    @AppStorage("convertTab") private var convertTab = 0
    @AppStorage(LyricsBridge.glowKey) private var lyricsGlow = true
    @ObservedObject private var songs = SongPlayer.shared

    var body: some View {
        if on, lyrics.timed, radio.isOn || songs.active, let h = lyrics.song, lyrics.barHiddenFor != h.id,
           !(router.tab == 3 && convertTab == 2 && !lyrics.appCovered), !radio.sheetOpen {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(T.muted).ffFont(.caption)
                        .accessibilityHidden(true)
                    Image(systemName: "music.note").foregroundStyle(T.btnInk).ffFont(.caption)
                    Text(h.trackName + " · " + h.artistName).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                    Spacer(minLength: 4)
                    if songs.active {
                        Button { songs.togglePause() } label: { Image(systemName: songs.playing ? "pause.fill" : "play.fill") }
                            .buttonStyle(.plain).foregroundStyle(T.btnInk)
                            .accessibilityLabel(songs.playing ? tr("暫停") : tr("播放"))
                    }
                    LyricsGlowToggle().buttonStyle(.plain)
                    Button { LyricsBridge.showInConvert() } label: { Image(systemName: "text.alignleft") }
                        .buttonStyle(.plain).foregroundStyle(T.muted)
                        .accessibilityLabel(tr("打開歌詞"))
                    Button { lyrics.barHiddenFor = h.id } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(T.muted)
                        .accessibilityLabel(tr("這首歌不顯示歌詞條"))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { onDrag($0.translation) }
                    .onEnded { onDragEnd($0.translation) })
                BarLines()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.noToneGlow, !lyricsGlow)
                if !lyrics.nextLine.isEmpty {
                    Text(lyrics.nextLine).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1)
                        .id(lyrics.nextLine)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
                LyricsNudge().frame(maxWidth: .infinity)
            }
            .animation(.easeInOut(duration: 0.4), value: lyrics.nextLine)
            .padding(12)
            .frame(maxWidth: 640)
            .background(RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            // (where it is: touches there go to the bar, everywhere else to the app under it)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { LyricsOverlay.barFrame = $0 }
            .onDisappear { LyricsOverlay.barFrame = .zero }
            .transition(.opacity)
        }
    }
}

/// the lyrics bar in a window of its own over the app, so it stays over the games and everything else opened full
/// screen too. It takes only the touches on the bar (and its word's sheet); the rest go to the app.
@MainActor
enum LyricsOverlay {
    /// the bar's place in the window (.zero: not shown)
    static var barFrame: CGRect = .zero
    private static var window: UIWindow?
    private static weak var appWindow: UIWindow?

    /// something open over the app's pages (a game, a sheet)
    static var appCovered: Bool { appWindow?.rootViewController?.presentedViewController != nil }

    static func install(_ store: Store) {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { install(store) }
            return
        }
        appWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        let w = PassWindow(windowScene: scene)
        let host = UIHostingController(rootView: LyricsFloatHost().environmentObject(store))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.windowLevel = .normal + 1
        w.backgroundColor = .clear
        w.overrideUserInterfaceStyle = .dark
        w.isHidden = false
        window = w
    }

    private final class PassWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            // (a word's sheet open from the bar: this window takes everything until it's closed)
            if rootViewController?.presentedViewController != nil { return super.hitTest(point, with: event) }
            guard LyricsOverlay.barFrame.insetBy(dx: -4, dy: -4).contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}

/// the bar's place: at the bottom (above the tab bar on iPhone) until it's dragged somewhere; remembered
struct LyricsFloatHost: View {
    @EnvironmentObject var store: Store
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue
    @Environment(\.horizontalSizeClass) private var hSize
    /// how far it's been moved from its place at the bottom
    @AppStorage("lyricsFloatX") private var fx = 0.0
    @AppStorage("lyricsFloatY") private var fy = 0.0
    @State private var drag: CGSize = .zero
    @State private var size: CGSize = .zero

    var body: some View {
        let _ = AppTheme.sync(theme)
        GeometryReader { geo in
            let bottom = hSize == .compact ? 58.0 : 16.0
            // (kept inside the window, whatever its size now)
            let mx = max(0, (geo.size.width - size.width) / 2)
            let up = max(0, geo.size.height - size.height - bottom)
            let clampX = { (v: Double) in min(mx, max(-mx, v)) }
            let clampY = { (v: Double) in min(bottom, max(-up, v)) }
            let x = clampX(fx + drag.width), y = clampY(fy + drag.height)
            Group {
                if store.loaded {
                    LyricsFloat(onDrag: { drag = $0 }, onDragEnd: { t in
                        fx = clampX(fx + t.width); fy = clampY(fy + t.height); drag = .zero
                    })
                    .padding(.horizontal, 12)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                }
            }
            .frame(width: geo.size.width)
            .position(x: geo.size.width / 2 + x, y: geo.size.height - bottom - size.height / 2 + y)
        }
        .id(theme)
        .fontDesign((AppTheme(rawValue: theme) ?? .night).fontDesign)
        .preferredColorScheme(.dark)
        .tint(AppTint.accent)
        .macTextSize()
    }
}


/// the colours' glow in the lyrics only (the page and the bar), on or off; the rest of the app keeps its own setting.
/// Shown when the tone colours and their glow are on.
struct LyricsGlowToggle: View {
    @AppStorage(ToneColors.key) private var system = 0
    @AppStorage(ToneColors.glowKey) private var glow = ToneColors.glowStandard
    @AppStorage(LyricsBridge.glowKey) private var lyricsGlow = true
    var body: some View {
        if system != 0 && glow {
            Button { lyricsGlow.toggle() } label: {
                Image(systemName: lyricsGlow ? "sparkles" : "sparkle")
                    .foregroundStyle(lyricsGlow ? AnyShapeStyle(T.btnInk) : AnyShapeStyle(T.muted))
            }
            .accessibilityLabel(lyricsGlow ? tr("關掉歌詞的顏色光暈") : tr("打開歌詞的顏色光暈"))
            .help(lyricsGlow ? tr("關掉歌詞的顏色光暈") : tr("打開歌詞的顏色光暈"))
        }
    }
}


/// 跳到哪一行: the song's lines with when they're sung; tap one and the lyrics go on from there
struct LyricsLineList: View {
    @ObservedObject private var lyrics = LyricsBridge.shared
    @ObservedObject private var beat = LyricsBeat.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(lyrics.lineTexts.indices, id: \.self) { n in
                    Button {
                        lyrics.jump(toLine: n)
                        dismiss()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(lyrics.lineTime(n).map(Self.time) ?? "")
                                .ffFont(.caption).monospacedDigit().foregroundStyle(T.muted)
                                .frame(minWidth: 40, alignment: .leading)
                            Text(lyrics.lineTexts[n])
                                .foregroundStyle(n == beat.line ? T.btnInk : T.glyph)
                                .fontWeight(n == beat.line ? .semibold : .regular)
                        }
                    }
                    .id(n)
                }
            }
            .onAppear { if beat.line >= 0 { proxy.scrollTo(beat.line, anchor: .center) } }
        }
        .navigationTitle(tr("跳到哪一行"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } } }
    }

    /// 1:05
    static func time(_ t: Double) -> String {
        let s = Int(max(0, t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}


/// the bar's line: two places on top of each other. The one being sung in view; the next one already drawn below it,
/// unseen. When the line changes, the old one flows up and fades, the new one rises into place.
struct BarLines: View {
    @ObservedObject private var lyrics = LyricsBridge.shared
    @State private var shown = LyricsBridge.shared.barSlot
    /// each place's lift (− up, + below) and how much it shows
    @State private var lift: [CGFloat] = [0, 34]
    @State private var seen: [Double] = [1, 0]
    private let rise: CGFloat = 34

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { k in
                BarLine(key: LyricsBridge.barKeys[k])
                    .offset(y: lift[k])
                    .opacity(seen[k])
                    .allowsHitTesting(k == shown)
                    .accessibilityHidden(k != shown)
            }
        }
        // (room around the line before the cut, so the swelling word and the glow aren't cropped; the cut only
        // hides the line going up and the one waiting below)
        .padding(EdgeInsets(top: 16, leading: 8, bottom: 8, trailing: 8))
        .clipped()
        .padding(EdgeInsets(top: -16, leading: -8, bottom: -8, trailing: -8))
        .onAppear { place(lyrics.barSlot, animated: false) }
        .onChange(of: lyrics.barSlot) { _, s in place(s, animated: true) }
    }

    private func place(_ s: Int, animated: Bool) {
        let old = 1 - s
        shown = s
        if animated {
            // (the new one starts below, in case it was moved)
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { lift[s] = rise }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                lift[s] = 0; seen[s] = 1
                lift[old] = -rise; seen[old] = 0
            }
            // (gone: back below, ready for the line after)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                guard shown == s else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { lift[old] = rise }
            }
        } else {
            lift[s] = 0; seen[s] = 1
            lift[old] = rise; seen[old] = 0
        }
    }
}

/// one of the bar's places: its line in the language's colours, tappable ("♪" between lines)
private struct BarLine: View {
    let key: String
    @EnvironmentObject var store: Store
    @AppStorage private var line: String

    init(key: String) {
        self.key = key
        _line = AppStorage(wrappedValue: "", key)
    }

    var body: some View {
        Group {
            if line.isEmpty {
                Text("♪").ffFont(.title3).foregroundStyle(T.muted)
            } else if store.isZh, !store.isSv, let z = store.zh {
                ZhConvertPane(dict: z, textKey: key, lyrics: true, bar: true).id(ObjectIdentifier(z))
            } else if !store.isZh, !store.isSv, let d = store.dict {
                ConvertPane(dict: d, textKey: key, lyrics: true, bar: true)
            } else {
                // (瑞典語, or the dictionary not read yet: the words as they are)
                Text(line).ffFont(.title3).foregroundStyle(T.glyph)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
