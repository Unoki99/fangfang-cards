import Foundation
import SwiftUI
import Combine

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

    /// the words of the song, one line each (from the timed version when there's no plain one)
    var text: String? {
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

/// the song's lyrics for the 歌詞 window: each time the station says a new song is playing, its lyrics are looked up
@MainActor
final class LyricsBridge: ObservableObject {
    static let shared = LyricsBridge()
    /// 換歌的時候自己找歌詞: on by default
    static let autoKey = "lyricsAuto"
    /// the lyrics shown in the 歌詞 window (its own text: 轉換's is left alone)
    static let textKey = "lyricsText"
    /// a new song's lyrics (台語's 轉換 keeps its text itself, so it's told)
    static let changed = Notification.Name("ffLyricsChanged")

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
        job?.cancel()
        looking = true
        job = Task {
            let found = await LyricsSource.find(p)
            guard !Task.isCancelled else { return }
            looking = false
            if let first = found.first { put(first); songFor = p } else { notFound = p }
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

    /// this song in the window (in the app's characters: 繁體, unless 簡體 is chosen)
    func put(_ h: LyricHit) {
        guard let text = h.text else { return }
        let simp = UserDefaults.standard.bool(forKey: Simp.key)
        var t = text
        if Lang.current <= 3, !simp, !keepSimplified, let trad = LyricsSource.traditional(text) { t = trad }
        UserDefaults.standard.set(t, forKey: Self.textKey)
        if song?.id != h.id { songFor = nil }
        song = h
        notFound = nil
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let h = lyrics.song {
                VStack(spacing: 0) {
                    header(h)
                    // a new song: the old words burst into sparkles of their colours, the new ones fade in
                    ZStack {
                        words.id("\(lyrics.version)-\(store.lang)")
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
        .appBackground()
        .modifier(LyricsBar(on: !inConvert))
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
            SaveSongButton(size: 18, song: h)
                .padding(.horizontal, 4)
            Button { picking = true } label: { Image(systemName: "magnifyingglass") }
                .softButton()
                .accessibilityLabel(tr("找別的歌詞"))
        }
        .padding(.horizontal).padding(.vertical, 8)
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
    @State private var query = ""
    @State private var hits: [LyricHit] = []
    @State private var busy = false
    @State private var searched = false
    @State private var failed = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        List {
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
            } footer: {
                Text(tr("電台有送歌名的話會自己找。沒有的話可以自己打歌名（控制中心的「音樂辨識」可以聽出手機正在放的歌）。歌詞來自 LRCLIB（lrclib.net）。"))
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
                    Button { LyricsBridge.shared.lookUp(s.query); LyricsBridge.showInConvert() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).foregroundStyle(T.glyph).lineLimit(1)
                            Text(detail(s)).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                        }
                    }
                    .contextMenu {
                        Button { UIPasteboard.general.string = s.artist.isEmpty ? s.title : s.artist + " - " + s.title } label: {
                            Label(tr("複製歌名"), systemImage: "doc.on.doc")
                        }
                        Button { open("https://music.apple.com/search?term=", s) } label: { Label(tr("在 Apple Music 找"), systemImage: "music.note") }
                        Button { open("https://www.youtube.com/results?search_query=", s) } label: { Label(tr("在 YouTube 找"), systemImage: "play.rectangle") }
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
