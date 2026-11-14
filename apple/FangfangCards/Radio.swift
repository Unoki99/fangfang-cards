import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
import Combine

// 電台: radio in the languages of the app, to listen to while practising.
// The stations come from Radio Browser (radio-browser.info), a free directory that is checked every day. A
// station is kept by its Radio Browser id and the name it was found by, not only its address: when a stream
// stops working (stations move their streams now and then), the app asks Radio Browser for the station's
// address again, then searches for it by name, and only then falls back to the last address that worked.

/// a station in 我的電台
struct RadioStation: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    /// the language it's listed under (Lang: 0 台語 … 5 瑞典語)
    var lang: Int
    /// Radio Browser's id (nil: an address typed in by hand, or a starter station not looked up yet)
    var uuid: String?
    /// what to search for when the station has to be found again (nil: an address typed in by hand)
    var query: String?
    /// (with the search: the country, ISO code, e.g. TW)
    var country: String?
    /// the last address that played
    var url: String?
    var favicon: String?
    /// a starter station (shown in the list until removed)
    var starter = false
}

// MARK: - Radio Browser

/// a station as Radio Browser lists it
struct RBStation: Decodable, Identifiable, Hashable {
    var id: String { stationuuid }
    let stationuuid: String
    let name: String
    let url: String
    let urlResolved: String
    let favicon: String
    let tags: String
    let language: String
    let countrycode: String
    let codec: String
    let bitrate: Int
    let clickcount: Int
    let ok: Bool

    enum K: String, CodingKey {
        case stationuuid, name, url, url_resolved, favicon, tags, language, countrycode, codec, bitrate, clickcount, lastcheckok
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        stationuuid = try c.decode(String.self, forKey: .stationuuid)
        name = ((try? c.decode(String.self, forKey: .name)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        urlResolved = (try? c.decode(String.self, forKey: .url_resolved)) ?? ""
        favicon = (try? c.decode(String.self, forKey: .favicon)) ?? ""
        tags = (try? c.decode(String.self, forKey: .tags)) ?? ""
        language = (try? c.decode(String.self, forKey: .language)) ?? ""
        countrycode = (try? c.decode(String.self, forKey: .countrycode)) ?? ""
        codec = (try? c.decode(String.self, forKey: .codec)) ?? ""
        bitrate = (try? c.decode(Int.self, forKey: .bitrate)) ?? 0
        clickcount = (try? c.decode(Int.self, forKey: .clickcount)) ?? 0
        ok = ((try? c.decode(Int.self, forKey: .lastcheckok)) ?? 1) == 1
    }
    /// the address to play
    var stream: String { urlResolved.isEmpty ? url : urlResolved }
}

enum RadioDirectory {
    /// Radio Browser's servers (any of them answers; the next one is tried when one doesn't)
    static let servers = ["https://de1.api.radio-browser.info", "https://de2.api.radio-browser.info",
                          "https://nl1.api.radio-browser.info", "https://at1.api.radio-browser.info",
                          "https://all.api.radio-browser.info"]
    /// the server that answered last (tried first next time)
    nonisolated(unsafe) private static var good = 0

    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 8
        c.httpAdditionalHeaders = ["User-Agent": "FangfangCards/1.0"]
        return URLSession(configuration: c)
    }()

    private static func get(_ path: String, _ query: [URLQueryItem] = []) async throws -> Data {
        var last: Error = URLError(.cannotConnectToHost)
        for i in 0..<servers.count {
            let n = (good + i) % servers.count
            guard var u = URLComponents(string: servers[n] + path) else { continue }
            if !query.isEmpty { u.queryItems = query }
            guard let url = u.url else { continue }
            do {
                let (d, r) = try await session.data(from: url)
                guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                good = n
                return d
            } catch { last = error }
        }
        throw last
    }

    /// search by name, language (Radio Browser's English name, e.g. "cantonese") and/or country (e.g. "TW")
    static func search(name: String? = nil, language: String? = nil, tag: String? = nil, country: String? = nil,
                       limit: Int = 40) async throws -> [RBStation] {
        var q = [URLQueryItem(name: "hidebroken", value: "true"), URLQueryItem(name: "order", value: "clickcount"),
                 URLQueryItem(name: "reverse", value: "true"), URLQueryItem(name: "limit", value: String(limit))]
        if let name, !name.isEmpty { q.append(URLQueryItem(name: "name", value: name)) }
        if let language, !language.isEmpty { q.append(URLQueryItem(name: "language", value: language)) }
        if let tag, !tag.isEmpty { q.append(URLQueryItem(name: "tag", value: tag)) }
        if let country, !country.isEmpty { q.append(URLQueryItem(name: "countrycode", value: country)) }
        let d = try await get("/json/stations/search", q)
        var seen = Set<String>()
        // (one station is often listed more than once, by different people: the most played one is kept)
        return try JSONDecoder().decode([RBStation].self, from: d).filter { s in
            !s.stream.isEmpty && seen.insert(s.name.lowercased() + "|" + s.stream).inserted
        }
    }

    /// the station as it's listed now (its address may have changed)
    static func station(_ uuid: String) async -> RBStation? {
        guard let d = try? await get("/json/stations/byuuid/" + uuid) else { return nil }
        return (try? JSONDecoder().decode([RBStation].self, from: d))?.first
    }

    /// tells Radio Browser the station was played (its list of popular stations is made from these)
    static func clicked(_ uuid: String) {
        Task.detached { _ = try? await get("/json/url/" + uuid) }
    }

    /// a playlist address (.pls / .m3u): the first stream in it
    static func unwrapPlaylist(_ s: String) async -> String {
        let low = s.lowercased()
        guard low.hasSuffix(".pls") || low.hasSuffix(".m3u"), low.hasPrefix("https://"),
              let u = URL(string: s), let res = try? await session.data(from: u),
              let text = String(data: res.0, encoding: .utf8) ?? String(data: res.0, encoding: .isoLatin1) else { return s }
        for line in text.split(whereSeparator: \.isNewline) {
            var l = line.trimmingCharacters(in: .whitespaces)
            if let eq = l.firstIndex(of: "="), l.lowercased().hasPrefix("file") { l = String(l[l.index(after: eq)...]) }
            if l.hasPrefix("http") { return l }
        }
        return s
    }
}

/// the words to search Radio Browser with, for each language of the app
enum RadioLang {
    /// Radio Browser's language names (stations list them in English, lower case; some write them in Chinese)
    static let languages: [[String]] = [
        ["taiwanese", "hokkien", "min nan", "台語"],
        ["mandarin", "chinese", "華語", "國語"],
        ["cantonese", "粵語", "廣東話"],
        ["hakka", "客家", "客語"],
        ["japanese"],
        ["swedish"],
    ]
    static let countries = [["TW"], ["TW", "CN"], ["HK", "MO"], ["TW"], ["JP"], ["SE"]]

    /// the stations a language starts with: found by name in Radio Browser the first time they're played
    static let starters: [(lang: Int, name: String, query: String, country: String?)] = [
        (0, "國立教育廣播電台", "教育廣播", "TW"),
        (0, "寶島聯播網", "寶島", "TW"),
        (0, "Rti 中央廣播電臺", "Rti", "TW"),
        (1, "飛碟電台 UFO", "飛碟", "TW"),
        (1, "Hit FM", "Hit FM", "TW"),
        (1, "中廣流行網 i like radio", "中廣", "TW"),
        (1, "中國之聲", "中国之声", "CN"),
        (2, "香港電台第一台", "RTHK Radio 1", "HK"),
        (2, "香港電台第二台", "RTHK Radio 2", "HK"),
        (2, "商業電台 叱咤903", "903", "HK"),
        (3, "講客廣播電台", "講客", "TW"),
        (3, "寶島客家廣播電台", "客家", "TW"),
        (4, "NHK ラジオ第1", "NHK", "JP"),
        (4, "J-WAVE", "J-WAVE", "JP"),
        (5, "Sveriges Radio P1", "P1", "SE"),
        (5, "Sveriges Radio P4 Stockholm", "P4 Stockholm", "SE"),
        (5, "Sveriges Radio P3", "P3", "SE"),
    ]
}

// MARK: - the player

@MainActor
final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()

    enum State: Equatable { case idle, connecting, playing, failed(String) }

    @Published var stations: [RadioStation] = [] { didSet { save() } }
    @Published private(set) var current: RadioStation?
    @Published private(set) var state: State = .idle
    /// what the station says is playing (a song's name), when it says
    @Published private(set) var nowPlaying: String?
    /// the 電台 sheet is open
    @Published var sheetOpen = false

    private let key = "radioStations"
    private var player: AVPlayer?
    private var job: Task<Void, Never>?
    private var watch: [NSKeyValueObservation] = []
    private var bag = Set<AnyCancellable>()
    /// (the stream playing now: its notifications)
    private var itemBag = Set<AnyCancellable>()
    private var meta: RadioMeta?
    /// times the station was started again after it stopped by itself (since it last played for a while)
    private var retries = 0

    var isOn: Bool { state == .playing || state == .connecting }

    private init() {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode([RadioStation].self, from: d) {
            stations = s
        } else {
            stations = RadioLang.starters.map {
                RadioStation(name: $0.name, lang: $0.lang, query: $0.query, country: $0.country, starter: true)
            }
        }
        // a word read out loud: the radio goes quiet for it
        Player.shared.$playing
            .removeDuplicates()
            .sink { [weak self] p in self?.duck(p != nil) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] n in self?.interrupted(n) }
            .store(in: &bag)
        remoteCommands()
    }

    private func save() {
        if let d = try? JSONEncoder().encode(stations) { UserDefaults.standard.set(d, forKey: key) }
    }

    // MARK: playing

    func toggle(_ s: RadioStation) {
        if current?.id == s.id && isOn { stop() } else { play(s) }
    }

    func play(_ s: RadioStation) {
        _ = LyricsBridge.shared          // (the songs' lyrics into 轉換 from now on)
        job?.cancel()
        current = s
        state = .connecting
        nowPlaying = nil
        updateNowPlaying()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        job = Task { [weak self] in await self?.connect(s) }
    }

    func stop() {
        job?.cancel()
        job = nil
        teardown()
        state = .idle
        nowPlaying = nil
        retries = 0
        updateNowPlaying()
    }

    /// the addresses to try, in order: the station as Radio Browser lists it now, then a search by its name,
    /// then the last address that worked
    private func connect(_ s: RadioStation) async {
        var tried = Set<String>()
        func attempt(_ u: String, _ found: RBStation?) async -> Bool {
            guard !Task.isCancelled, !u.isEmpty, tried.insert(u).inserted else { return false }
            let stream = await RadioDirectory.unwrapPlaylist(u)
            guard await open(stream) else { return false }
            remember(s, url: u, found: found)
            return true
        }
        // 1. the station's own id: its address now
        if let id = s.uuid, let rb = await RadioDirectory.station(id), rb.ok || s.url == nil {
            if await attempt(rb.stream, rb) { return }
        }
        // 2. typed in by hand: that address
        if s.query == nil, let u = s.url, await attempt(u, nil) { return }
        // 3. found again by name (the station may have a new entry, under a new id)
        if let q = s.query ?? (s.uuid != nil ? s.name : nil) {
            let found = (try? await RadioDirectory.search(name: q, country: s.country, limit: 12)) ?? []
            for rb in best(found, for: s) where rb.ok {
                if await attempt(rb.stream, rb) { return }
            }
        }
        // 4. the last address that worked
        if let u = s.url, await attempt(u, nil) { return }
        guard !Task.isCancelled else { return }
        teardown()
        state = .failed(tr("連不上這個電台"))
        updateNowPlaying()
    }

    /// the search results most like the station: the same name first, then the most played
    private func best(_ list: [RBStation], for s: RadioStation) -> [RBStation] {
        let want = s.name.lowercased()
        return list.sorted { a, b in
            let ea = a.name.lowercased() == want, eb = b.name.lowercased() == want
            if ea != eb { return ea }
            return a.clickcount > b.clickcount
        }
    }

    /// keeps what worked: the address, and the station's (perhaps new) id
    private func remember(_ s: RadioStation, url: String, found: RBStation?) {
        guard let i = stations.firstIndex(where: { $0.id == s.id }) else { current?.url = url; return }
        var t = stations[i]
        t.url = url
        if let f = found {
            t.uuid = f.stationuuid
            if t.query == nil { t.query = t.name }
            if t.country == nil, !f.countrycode.isEmpty { t.country = f.countrycode }
            if (t.favicon ?? "").isEmpty, !f.favicon.isEmpty { t.favicon = f.favicon }
            RadioDirectory.clicked(f.stationuuid)
        }
        if t != stations[i] { stations[i] = t }
        current = t
    }

    /// plays the address; true once sound is coming (false: it failed, or nothing came for 12 seconds)
    private func open(_ address: String) async -> Bool {
        guard let url = URL(string: address) ?? URL(string: address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") else { return false }
        teardown()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = true
        p.volume = Player.shared.playing == nil ? 1 : duckVolume
        player = p
        p.play()
        for _ in 0..<48 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return false }
            if item.status == .failed { break }
            if p.timeControlStatus == .playing {
                state = .playing
                watchItem(item, p)
                updateNowPlaying()
                return true
            }
        }
        teardown()
        return false
    }

    /// a stream that stops by itself: started again (a few times), found again if its address stopped working
    private func watchItem(_ item: AVPlayerItem, _ p: AVPlayer) {
        let m = RadioMeta { [weak self] title in Task { @MainActor in self?.nowPlaying = title; self?.updateNowPlaying() } }
        let out = AVPlayerItemMetadataOutput(identifiers: nil)
        out.setDelegate(m, queue: .main)
        item.add(out)
        meta = m
        watch = [
            item.observe(\.status) { [weak self] it, _ in
                if it.status == .failed { Task { @MainActor in self?.dropped() } }
            },
        ]
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .merge(with: NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item))
            .sink { [weak self] _ in self?.dropped() }
            .store(in: &itemBag)
        // played for a minute: it's working again
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if self?.player === p, p.timeControlStatus == .playing { self?.retries = 0 }
        }
    }

    private func dropped() {
        guard state == .playing, let s = current else { return }
        retries += 1
        if retries > 3 {
            teardown()
            state = .failed(tr("電台斷線了"))
            updateNowPlaying()
            return
        }
        play(s)
    }

    private func teardown() {
        watch = []
        itemBag = []
        meta = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }

    // MARK: word audio, phone calls

    private let duckVolume: Float = 0.15
    private var unduck: Task<Void, Never>?

    /// quieter while a word is read out loud; back up a moment after
    private func duck(_ on: Bool) {
        unduck?.cancel()
        guard let p = player else { return }
        if on { p.volume = duckVolume; return }
        unduck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let p = self?.player else { return }
            for i in 1...8 { p.volume = (self?.duckVolume ?? 0.15) + Float(i) / 8 * 0.85; try? await Task.sleep(nanoseconds: 40_000_000) }
        }
    }

    /// a call or an alarm: the radio stops, and starts again after if the phone says so
    private func interrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended, state == .playing || state == .connecting, let s = current {
            let opt = AVAudioSession.InterruptionOptions(rawValue: n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            if opt.contains(.shouldResume) { play(s) } else { stop() }
        }
    }

    // MARK: lock screen and Control Center

    private func remoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            guard let self, let s = self.current else { return .noActionableNowPlayingItem }
            if !self.isOn { self.play(s) }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        c.stopCommand.addTarget { [weak self] _ in self?.stop(); return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, let s = self.current else { return .noActionableNowPlayingItem }
            self.toggle(s)
            return .success
        }
        c.nextTrackCommand.isEnabled = false
        c.previousTrackCommand.isEnabled = false
    }

    private func updateNowPlaying() {
        guard let s = current, state != .idle else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying ?? s.name,
            MPMediaItemPropertyArtist: nowPlaying == nil ? trs(Lang.names[s.lang]) : s.name,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        info[MPMediaItemPropertyAlbumTitle] = tr("方方詞卡")
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: 我的電台

    func add(_ rb: RBStation, lang: Int) {
        if stations.contains(where: { $0.uuid == rb.stationuuid }) { return }
        stations.append(RadioStation(name: rb.name, lang: lang, uuid: rb.stationuuid, query: rb.name,
                                     country: rb.countrycode.isEmpty ? nil : rb.countrycode,
                                     url: rb.stream, favicon: rb.favicon.isEmpty ? nil : rb.favicon))
    }

    func add(name: String, url: String, lang: Int) {
        stations.append(RadioStation(name: name, lang: lang, url: url))
    }

    func remove(_ s: RadioStation) {
        if current?.id == s.id { stop(); current = nil }
        stations.removeAll { $0.id == s.id }
    }

    func has(_ rb: RBStation) -> Bool { stations.contains { $0.uuid == rb.stationuuid } }

    /// the starter stations again (the ones removed come back; the others stay as they are)
    func restoreStarters() {
        for st in RadioLang.starters where !stations.contains(where: { $0.starter && $0.name == st.name }) {
            stations.append(RadioStation(name: st.name, lang: st.lang, query: st.query, country: st.country, starter: true))
        }
    }

    /// plays a search result without adding it
    func preview(_ rb: RBStation, lang: Int) {
        play(RadioStation(name: rb.name, lang: lang, uuid: rb.stationuuid, query: rb.name,
                          country: rb.countrycode.isEmpty ? nil : rb.countrycode, url: rb.stream))
    }
}

/// the song's name, when the stream sends it (ICY / ID3 metadata)
final class RadioMeta: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    let changed: (String?) -> Void
    init(_ changed: @escaping (String?) -> Void) { self.changed = changed }
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let item = groups.first?.items.first { $0.commonKey == .commonKeyTitle || $0.identifier == .icyMetadataStreamTitle }
            ?? groups.first?.items.first
        guard let item else { return }
        let changed = self.changed
        Task {
            let v: String? = (try? await item.load(.stringValue)) ?? nil
            let t = v?.trimmingCharacters(in: .whitespacesAndNewlines)
            changed((t?.isEmpty ?? true) ? nil : t)
        }
    }
}

// MARK: - views

/// in the top bar, next to ⚙︎: opens 電台 (lit while a station plays)
struct RadioButton: View {
    @ObservedObject private var radio = RadioPlayer.shared
    var body: some View {
        Button { radio.sheetOpen = true } label: {
            Image(systemName: radio.isOn ? "radio.fill" : "radio")
                .foregroundStyle(radio.isOn ? T.btnInk : T.glyph)
                .symbolEffect(.pulse, isActive: radio.state == .connecting)
        }
        .accessibilityLabel(tr("電台"))
    }
}

/// 電台, shown from the app itself (like 設定), so it stays open while the pages behind change
struct RadioSheetModifier: ViewModifier {
    @ObservedObject private var radio = RadioPlayer.shared
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue
    func body(content: Content) -> some View {
        content.sheet(isPresented: $radio.sheetOpen) {
            NavigationStack {
                RadioView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { radio.sheetOpen = false } } }
            }
            .environmentObject(Store.shared)
            .macTextSize()
            .fontDesign((AppTheme(rawValue: theme) ?? .night).fontDesign)
            .preferredColorScheme(.dark)
            .tint(AppTint.accent)
        }
    }
}

struct RadioView: View {
    @ObservedObject private var radio = RadioPlayer.shared
    @ObservedObject private var lyrics = LyricsBridge.shared
    @State private var adding = false
    @State private var finding = false

    /// the app's language first, then the others
    private var order: [Int] {
        let l = Lang.current
        return [l] + (0..<Lang.count).filter { $0 != l }
    }

    var body: some View {
        List {
            nowSection
            ForEach(order, id: \.self) { l in
                let list = radio.stations.filter { $0.lang == l }
                if !list.isEmpty {
                    Section(trs(Lang.names[l])) {
                        ForEach(list) { s in row(s) }
                    }
                }
            }
            Section {
                Button { finding = true } label: { Label(tr("找電台"), systemImage: "magnifyingglass") }
                Button { LyricsBridge.showInConvert() } label: { Label(tr("歌詞"), systemImage: "music.note.list") }
                NavigationLink { SavedSongsView() } label: { Label(tr("我的歌"), systemImage: "bookmark") }
                Button { adding = true } label: { Label(tr("輸入網址"), systemImage: "link") }
                Button { radio.restoreStarters() } label: { Label(tr("加回預設電台"), systemImage: "arrow.counterclockwise") }
            } footer: {
                Text(tr("電台來自 Radio Browser（radio-browser.info）。電台換了網址的時候，App 會自己再找一次。")).ffFont(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("電台"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $finding) { NavigationStack { RadioSearchView() }.preferredColorScheme(.dark).tint(AppTint.accent) }
        .sheet(isPresented: $adding) { NavigationStack { RadioAddView() }.preferredColorScheme(.dark).tint(AppTint.accent) }
    }

    @ViewBuilder private var nowSection: some View {
        if let s = radio.current, radio.state != .idle {
            Section {
                HStack(spacing: 12) {
                    RadioIcon(url: s.favicon)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.name).ffFont(.headline).lineLimit(1)
                        Group {
                            switch radio.state {
                            case .connecting: Text(tr("連線中…"))
                            case .playing: Text(radio.nowPlaying ?? trs(Lang.names[s.lang]))
                            case .failed(let m): Text(m)
                            case .idle: EmptyView()
                            }
                        }
                        .ffFont(.subheadline).foregroundStyle(T.muted).lineLimit(2)
                    }
                    Spacer()
                    // the song playing: 存到我的歌
                    if radio.state == .playing { SaveSongButton(size: 24) }
                    Button { radio.toggle(s) } label: {
                        Image(systemName: radio.isOn ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 34))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(T.btnInk)
                }
                .padding(.vertical, 4)
                // the song's lyrics: 轉換 → 歌詞 (漢字 and reading side by side, the whole page)
                Button { LyricsBridge.showInConvert() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note.list").foregroundStyle(T.btnInk)
                        if let h = lyrics.song {
                            Text(tr("歌詞：\(h.trackName)")).lineLimit(1)
                        } else if lyrics.looking {
                            Text(tr("找歌詞…")).foregroundStyle(T.muted)
                        } else {
                            Text(tr("歌詞")).foregroundStyle(T.muted)
                        }
                    }
                }
            } header: { Text(tr("正在聽")) }
        }
    }

    private func row(_ s: RadioStation) -> some View {
        let on = radio.current?.id == s.id && radio.isOn
        return Button { radio.toggle(s) } label: {
            HStack(spacing: 12) {
                RadioIcon(url: s.favicon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).foregroundStyle(on ? T.btnInk : T.glyph).lineLimit(1)
                    if s.query == nil, let u = s.url {
                        Text(u).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                    }
                }
                Spacer()
                if on && radio.state == .connecting { ProgressView() }
                else { Image(systemName: on ? "stop.fill" : "play.fill").foregroundStyle(on ? T.btnInk : T.muted) }
            }
        }
        .swipeActions {
            Button(role: .destructive) { radio.remove(s) } label: { Label(tr("刪除"), systemImage: "trash") }
        }
    }
}

/// a station's logo (or a radio)
struct RadioIcon: View {
    let url: String?
    var body: some View {
        Group {
            if let u = url, let link = URL(string: u), u.hasPrefix("https://") {
                AsyncImage(url: link) { img in img.resizable().scaledToFit() } placeholder: { plain }
            } else { plain }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
    private var plain: some View {
        Image(systemName: "radio").foregroundStyle(T.muted).frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 7).fill(T.fn))
    }
}

/// 找電台: Radio Browser, by name or by language
struct RadioSearchView: View {
    @ObservedObject private var radio = RadioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var lang = Lang.current
    @State private var text = ""
    @State private var results: [RBStation] = []
    @State private var busy = false
    @State private var failed = false
    @State private var job: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<Lang.count, id: \.self) { l in
                            Button { lang = l; run() } label: {
                                Text(trs(Lang.names[l])).ffFont(.subheadline, .semibold)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(lang == l ? T.btnEdge.opacity(0.35) : T.fn))
                                    .overlay(Capsule().stroke(lang == l ? T.btnInk : T.fnEdge, lineWidth: 1))
                                    .foregroundStyle(lang == l ? T.btnInk : T.glyph)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } footer: {
                Text(tr("不打字：這個語言最多人聽的電台。打了字：用電台的名字找。")).ffFont(.footnote)
            }
            if busy {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if failed {
                Text(tr("連不上 Radio Browser，等一下再試試看。")).foregroundStyle(T.muted)
            } else if results.isEmpty {
                Text(tr("找不到電台")).foregroundStyle(T.muted)
            } else {
                Section {
                    ForEach(results) { r in resultRow(r) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(tr("電台名稱")))
        .onSubmit(of: .search) { run() }
        .onChange(of: text) { if text.isEmpty { run() } }
        .navigationTitle(tr("找電台"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } } }
        .task { run() }
    }

    private func resultRow(_ r: RBStation) -> some View {
        let on = radio.current?.uuid == r.stationuuid && radio.isOn
        let added = radio.has(r)
        return HStack(spacing: 12) {
            RadioIcon(url: r.favicon)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).foregroundStyle(on ? T.btnInk : T.glyph).lineLimit(1)
                Text(detail(r)).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
            }
            Spacer()
            Button { on ? radio.stop() : radio.preview(r, lang: lang) } label: {
                Image(systemName: on ? "stop.fill" : "play.fill").frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            Button { radio.add(r, lang: lang) } label: {
                Image(systemName: added ? "checkmark" : "plus").frame(width: 30, height: 30)
            }
            .buttonStyle(.borderless)
            .disabled(added)
            .accessibilityLabel(tr("加到我的電台"))
        }
    }

    private func detail(_ r: RBStation) -> String {
        var parts = [String]()
        if !r.countrycode.isEmpty { parts.append(r.countrycode) }
        if !r.language.isEmpty { parts.append(r.language) }
        if r.bitrate > 0 { parts.append("\(r.bitrate) kbps") }
        if !r.tags.isEmpty { parts.append(r.tags.split(separator: ",").prefix(3).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private func run() {
        job?.cancel()
        busy = true
        failed = false
        let l = lang, q = text.trimmingCharacters(in: .whitespaces)
        job = Task {
            var out: [RBStation] = []
            var seen = Set<String>()
            var anyOK = false
            func take(_ list: [RBStation]) { for s in list where seen.insert(s.stationuuid).inserted { out.append(s) } }
            if q.isEmpty {
                // the language's most played stations: by language, then by country (+ language tags)
                for name in RadioLang.languages[l] {
                    if let r = try? await RadioDirectory.search(language: name, limit: 40) { anyOK = true; take(r) }
                    if Task.isCancelled { return }
                }
                if out.count < 15 {
                    for c in RadioLang.countries[l].prefix(1) {
                        if let r = try? await RadioDirectory.search(country: c, limit: 40) { anyOK = true; take(r) }
                    }
                }
            } else {
                if let r = try? await RadioDirectory.search(name: q, limit: 60) { anyOK = true; take(r) }
            }
            if Task.isCancelled { return }
            out.sort { $0.clickcount > $1.clickcount }
            results = out.filter(\.ok)
            failed = !anyOK
            busy = false
        }
    }
}

/// 輸入網址: a station's stream address, typed or pasted
struct RadioAddView: View {
    @ObservedObject private var radio = RadioPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var url = ""
    @State private var lang = Lang.current

    private var valid: Bool {
        let u = url.trimmingCharacters(in: .whitespaces).lowercased()
        return (u.hasPrefix("http://") || u.hasPrefix("https://")) && u.count > 10
    }

    var body: some View {
        Form {
            Section {
                TextField(tr("名稱"), text: $name)
                TextField("https://…", text: $url)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker(tr("語言"), selection: $lang) {
                    ForEach(0..<Lang.count, id: \.self) { Text(trs(Lang.names[$0])).tag($0) }
                }
            } footer: {
                Text(tr("貼上電台串流的網址（.mp3、.aac、.m3u8 或 .pls）。用網址加的電台，網址換了就要再加一次；用「找電台」加的，App 會自己找新的網址。")).ffFont(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("輸入網址"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button(tr("取消")) { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button(tr("加入")) {
                    let u = url.trimmingCharacters(in: .whitespaces)
                    let n = name.trimmingCharacters(in: .whitespaces)
                    radio.add(name: n.isEmpty ? (URL(string: u)?.host ?? u) : n, url: u, lang: lang)
                    dismiss()
                }
                .disabled(!valid)
            }
        }
    }
}
