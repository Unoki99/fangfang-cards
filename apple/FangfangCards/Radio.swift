import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
import MediaToolbox
import Combine
import UserNotifications

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
    @Published private(set) var state: State = .idle { didSet { listenClock() } }
    /// (練習統計: the minutes listened, added to the day every few minutes and when the radio stops)
    private var listeningSince: Date?
    private var clockTask: Task<Void, Never>?
    private func listenClock() {
        if state == .playing {
            if listeningSince == nil { listeningSince = Date() }
            if clockTask == nil {
                clockTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 180_000_000_000)
                        self?.flushListening()
                    }
                }
            }
        } else {
            flushListening()
            listeningSince = nil
            clockTask?.cancel(); clockTask = nil
        }
    }
    private func flushListening() {
        guard let t = listeningSince else { return }
        let now = Date()
        Store.shared.addListening(now.timeIntervalSince(t) / 60, kind: 0)
        listeningSince = state == .playing ? now : nil
    }
    /// what the station says is playing (a song's name), when it says
    @Published private(set) var nowPlaying: String?
    /// the 電台 sheet is open
    @Published var sheetOpen = false
    /// 電台送來的資料: what the station playing has sent (newest first), to see which stations say the song
    @Published private(set) var metaLog: [(time: Date, lines: [String])] = []

    fileprivate func logMeta(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        if let last = metaLog.first, last.lines == lines { return }
        metaLog.insert((Date(), lines), at: 0)
        if metaLog.count > 30 { metaLog.removeLast(metaLog.count - 30) }
    }

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
        // (電台鬧鐘: its notification tapped; set again for the next morning)
        UNUserNotificationCenter.current().delegate = RadioAlarmDelegate.shared
        if alarmOn { Task { @MainActor in self.armAlarm() } }
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
        keepAwake(false)
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
        if sleepAt != nil && level >= 1 { sleepTask?.cancel(); sleepAt = nil }
        keepAwake(alarmOn)
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
        p.volume = (Player.shared.playing == nil ? 1 : duckVolume) * level
        player = p
        p.play()
        for _ in 0..<48 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return false }
            if item.status == .failed { break }
            if p.timeControlStatus == .playing {
                state = .playing
                metaLog = []
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
        let st = current
        let m = RadioMeta(country: st?.country, raw: { [weak self] lines in
            Task { @MainActor in self?.logMeta(lines) }
        }) { [weak self] title in
            Task { @MainActor in
                guard let self else { return }
                // (the station's own name, an address: not a song)
                if let t = title, let n = st?.name, t.lowercased() == n.lowercased() { return }
                self.nowPlaying = title
                self.updateNowPlaying()
            }
        }
        let out = AVPlayerItemMetadataOutput(identifiers: nil)
        out.setDelegate(m, queue: .main)
        item.add(out)
        meta = m
        RadioClip.shared.attach(to: item)        // (the last seconds kept, for a saved word's sentence)
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
    /// (the sleep timer's fade out, the alarm's fade in: 0…1)
    private var level: Float = 1 { didSet { if Player.shared.playing == nil { player?.volume = level } } }

    // MARK: sleep timer and alarm

    /// 睡眠定時: when the radio fades out and stops
    @Published private(set) var sleepAt: Date?
    private var sleepTask: Task<Void, Never>?
    func sleep(minutes: Int?) {
        sleepTask?.cancel()
        guard let m = minutes, m > 0 else { sleepAt = nil; return }
        let at = Date().addingTimeInterval(Double(m) * 60)
        sleepAt = at
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, at.timeIntervalSinceNow - 30) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            // (half a minute softer and softer)
            for i in 0...30 {
                if Task.isCancelled { self.level = 1; return }
                self.level = 1 - Float(i) / 30
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            self.stop()
            self.level = 1
            self.sleepAt = nil
            self.keepAwake(self.alarmOn)
        }
    }

    /// 電台鬧鐘: the time (hour, minute) and the station; on or off
    @Published var alarmOn = UserDefaults.standard.bool(forKey: "radioAlarmOn") { didSet { UserDefaults.standard.set(alarmOn, forKey: "radioAlarmOn"); armAlarm() } }
    @Published var alarmTime = (UserDefaults.standard.object(forKey: "radioAlarmTime") as? Date) ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())! {
        didSet { UserDefaults.standard.set(alarmTime, forKey: "radioAlarmTime"); armAlarm() }
    }
    @Published var alarmStation = UserDefaults.standard.string(forKey: "radioAlarmStation") ?? "" {
        didSet { UserDefaults.standard.set(alarmStation, forKey: "radioAlarmStation"); armAlarm() }
    }
    private var alarmTask: Task<Void, Never>?
    private var silence: AVAudioPlayer?

    /// the next time the alarm rings
    var nextAlarm: Date {
        let c = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let today = Calendar.current.date(bySettingHour: c.hour ?? 7, minute: c.minute ?? 0, second: 0, of: Date())!
        return today > Date() ? today : Calendar.current.date(byAdding: .day, value: 1, to: today)!
    }

    /// set (or take away) the alarm: the app waits for it (it has to stay open in the background, the radio's way of
    /// staying awake), and a notification rings too, in case the app was closed
    func armAlarm() {
        alarmTask?.cancel()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["radioAlarm"])
        keepAwake(alarmOn && !isOn)
        guard alarmOn, let st = stations.first(where: { $0.id == alarmStation }) ?? stations.first else { return }
        let at = nextAlarm
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = tr("電台鬧鐘")
        content.body = tr("\(st.name)：點這裡開始聽")
        content.sound = .default
        content.userInfo = ["station": st.id]
        let comps = Calendar.current.dateComponents([.hour, .minute], from: at)
        center.add(UNNotificationRequest(identifier: "radioAlarm", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        alarmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, at.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.ring(st)
        }
    }

    /// the alarm: the station, from silence up to full in half a minute
    private func ring(_ st: RadioStation) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["radioAlarm"])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["radioAlarm"])
        level = 0
        play(st)
        Task { [weak self] in
            for i in 1...30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self?.level = Float(i) / 30
            }
        }
        // (tomorrow again)
        Task { [weak self] in try? await Task.sleep(nanoseconds: 70_000_000_000); self?.armAlarm() }
    }

    /// the alarm's notification tapped (the app had been closed)
    func alarmTapped(_ stationID: String?) {
        guard let st = stations.first(where: { $0.id == stationID }) ?? stations.first else { return }
        if !isOn { level = 1; play(st) }
    }

    /// (waiting for the alarm with no radio on: a silent sound keeps the app awake in the background)
    private func keepAwake(_ on: Bool) {
        if !on { silence?.stop(); silence = nil; return }
        guard silence == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let rate = 8000, n = rate                       // one second of silence, over and over
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        d.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 2)); d.append("WAVEfmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append("data".data(using: .ascii)!); u32(UInt32(n * 2)); d.append(Data(count: n * 2))
        silence = try? AVAudioPlayer(data: d)
        silence?.numberOfLoops = -1
        silence?.volume = 0
        silence?.play()
    }
    private var unduck: Task<Void, Never>?

    /// quieter while a word is read out loud; back up a moment after
    private func duck(_ on: Bool) {
        unduck?.cancel()
        guard let p = player else { return }
        if on { p.volume = duckVolume * level; return }
        unduck = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let p = self?.player else { return }
            let lv = self?.level ?? 1
            for i in 1...8 { p.volume = ((self?.duckVolume ?? 0.15) + Float(i) / 8 * 0.85) * lv; try? await Task.sleep(nanoseconds: 40_000_000) }
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

/// the song's name, when the stream sends it: every field of each update is read (ICY's StreamTitle, the ID3 tags
/// of HLS streams: title and artist apart, "title=…,artist=…" texts), and text in an older encoding (Big5, GBK,
/// Shift-JIS, as many Chinese and Japanese stations send) is read as that, not as garbled Latin letters
final class RadioMeta: NSObject, AVPlayerItemMetadataOutputPushDelegate {
    let changed: (String?) -> Void
    /// (everything the station sent, for 電台送來的資料)
    let raw: ([String]) -> Void
    let country: String?
    init(country: String?, raw: @escaping ([String]) -> Void, _ changed: @escaping (String?) -> Void) {
        self.country = country; self.raw = raw; self.changed = changed
    }
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let items = groups.flatMap(\.items)
        guard !items.isEmpty else { return }
        let changed = self.changed, raw = self.raw, country = self.country
        Task {
            var fields: [(key: String, value: String)] = []
            for it in items {
                let key = it.identifier?.rawValue ?? it.key.map { String(describing: $0) } ?? "?"
                var text: String?
                if let d = (try? await it.load(.dataValue)) ?? nil, let t = RadioText.decode(d, country) { text = t }
                if text == nil, let s = (try? await it.load(.stringValue)) ?? nil { text = RadioText.repair(s, country) }
                if let t = text?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)), !t.isEmpty {
                    fields.append((key, t))
                }
            }
            raw(fields.map { "\($0.key)：\($0.value)" })
            changed(RadioText.song(fields))
        }
    }
}

/// reading what stations send
enum RadioText {
    private static func enc(_ cf: CFStringEncodings) -> String.Encoding {
        String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue)))
    }
    static let big5 = enc(.big5_HKSCS_1999), gbk = enc(.GB_18030_2000), sjis = enc(.shiftJIS)

    /// bytes → text: UTF-8 when it is that; else the older encoding that gives the most real characters
    static func decode(_ d: Data, _ country: String?) -> String? {
        var bytes = [UInt8](d)
        // (ID3 text frames: a first byte saying the encoding; 1 and 2 are UTF-16)
        if let f = bytes.first, f <= 3, bytes.count > 1 {
            if f == 1 || f == 2 { return String(data: Data(bytes.dropFirst()), encoding: f == 1 ? .utf16 : .utf16BigEndian) }
            bytes.removeFirst()
        }
        while bytes.last == 0 { bytes.removeLast() }
        if bytes.isEmpty { return nil }
        if !bytes.contains(where: { $0 >= 0x80 }) { return String(bytes: bytes, encoding: .ascii) }
        if let u = String(bytes: bytes, encoding: .utf8) { return u }
        var best: (String, Double)? = nil
        let order: [(String.Encoding, String)] = [(big5, "TW HK MO"), (gbk, "CN SG"), (sjis, "JP")]
        for (e, home) in order {
            guard let t = String(bytes: bytes, encoding: e) else { continue }
            var sc = score(t, kana: e == sjis)
            if let c = country, home.contains(c) { sc += 0.15 }
            if best == nil || sc > best!.1 { best = (t, sc) }
        }
        if let b = best, b.1 > 0.3 { return b.0 }
        return String(bytes: bytes, encoding: .isoLatin1)
    }

    /// text the player already read as Latin letters (é, Ã, ¤…): read again from its bytes
    static func repair(_ s: String, _ country: String?) -> String {
        let sc = s.unicodeScalars
        guard sc.contains(where: { $0.value >= 0x80 }), sc.allSatisfy({ $0.value <= 0xFF }) else { return s }
        let bytes = Data(sc.map { UInt8($0.value) })
        return decode(bytes, country) ?? s
    }

    /// how much a text looks like real words: 漢字, kana, letters; little of the odd ones
    /// (kana count as real only when reading as Japanese: in a Chinese title read the wrong way they're a sign of it)
    private static func score(_ t: String, kana: Bool) -> Double {
        var good = 0, bad = 0, all = 0, usual = 0
        for u in t.unicodeScalars {
            all += 1
            if common.contains(Character(u)) { usual += 1 }
            switch u.value {
            case 0x4E00...0x9FFF: good += 1
            case 0x3040...0x30FF: if kana { good += 1 } else { bad += 1 }
            case 0x20...0x7E, 0x3000...0x303F, 0xFF01...0xFF5E: break
            case 0xE000...0xF8FF, 0xFFFD, 0x3400...0x4DBF, 0x20000...0x2FFFF, 0xFF61...0xFF9F,
                 0x0370...0x04FF, 0x3100...0x312F, 0x3200...0x33FF: bad += 1
            default: if u.properties.generalCategory == .control { bad += 1 }
            }
        }
        guard all > 0 else { return 0 }
        return (Double(good - 3 * bad) + 1.5 * Double(usual)) / Double(all)
    }
    /// characters common in song titles and names (繁體 and 简体): read the wrong way, a title turns into rare ones
    private static let common = Set("的一是不了人我在有他這这中大來来上國国個个到說说們们為为子和你地出道也時时年得就那要下以生會会自著着去之過过家學学對对可她裡里后後小麼么心多天而能好都然沒没日於于起還还發发成事只作當当想看文無无開开手十用主行方又如前所本見见經经頭头面公同三已老從从動动兩两长長知民樣样現现分將将外但身些與与高意進进把法此實实回二理美點点月明其種种聲声全工己話话兒儿者向情部正名定女問问力機机給给等幾几很業业最間间新什打便位因重被走電电四第門门相次東东政海口使教西再平真聽听世氣气信北少關关並并內内加化由卻却代軍军產产入先山五太水萬万市眼體体別别處处總总才場场師师書书比住員员九笑性通目華华報报立馬马命張张活難难神數数件安表原車车白應应路期叫死常提感金何更反合放做系計计或司利受光王果親亲界及今京務务制解各任至清物台象記记邊边共風风戰战乾干接它許许八特覺觉望直服毛林題题建南度統统色字請请交愛爱讓让認认算論论百吃義义科怎元社術术結结六功指思非流每青管夫連连遠远資资隊队跟帶带花快條条院變变聯联言權权往展該该領领傳传近留紅红治決决周保達达辦办運运武半候七必城父強强步完革深區区即求品士轉转量空甚眾众技輕轻程告江語语英基派滿满式李息寫写呢識识極极令黃黄德收臉脸錢钱黨党倒未持取設设始版雙双歷历越史商千片容研像找友孩站廣广改議议形委早房音火際际則则首單单據据導导影失拿網网香似斯專专石若兵弟誰谁校讀读志飛飞觀观爭争究包組组造落視视濟济喜離离坐集編编寶宝談谈府拉黑且隨随格盡尽劍剑講讲布殺杀微怕母調调局根曾準准團团段終终樂乐切級级克精哪官示冷域歌唱夢梦淚泪雨雪夜晚星陽阳春秋冬夏雲云草樹树鳥鸟魚鱼念待永憶忆朋戀恋寂寞溫温柔傷伤痛哭吻抱牽牵街燈灯亮昨舊旧故幸福麗丽男壞坏假錯错藍蓝綠绿銀银歲岁秒鐘钟杰倫伦惠妹俊鄧邓紫棋菲陳陈奕迅劉刘楊杨蔡依孫孙燕姿薛謙谦榮荣浩易米津玄宇田島岛")

    /// the song from an update's fields: "artist - title" when both are there
    static func song(_ fields: [(key: String, value: String)]) -> String? {
        func find(_ keys: [String]) -> String? {
            fields.first { f in keys.contains { f.key.lowercased().contains($0) } }?.value
        }
        var title = find(["tit2", "/title", "streamtitle", "title"])
        var artist = find(["tpe1", "/artist", "artist", "tpe2"])
        // ("title=\"晴天\",artist=\"周杰倫\"", "text=\"…\" song_spot=…" as some stations write it)
        for f in fields {
            let v = f.value
            if let t = attr(v, "title") ?? attr(v, "text") { title = t; if let a = attr(v, "artist") { artist = a } }
        }
        guard var t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if t.lowercased().hasPrefix("http") { return nil }
        // (StreamTitle='…';)
        if let r = t.range(of: #"StreamTitle='([^']*)'"#, options: .regularExpression) {
            t = String(t[r]).replacingOccurrences(of: "StreamTitle='", with: "").replacingOccurrences(of: "'", with: "")
        }
        if let a = artist?.trimmingCharacters(in: .whitespaces), !a.isEmpty, !t.contains(a) { return a + " - " + t }
        return t
    }
    private static func attr(_ v: String, _ name: String) -> String? {
        guard let r = v.range(of: name + #"\s*=\s*"([^"]*)""#, options: .regularExpression) else { return nil }
        let m = String(v[r])
        guard let q = m.firstIndex(of: "\"") else { return nil }
        let inner = m[m.index(after: q)...].dropLast()
        return inner.isEmpty ? nil : String(inner)
    }
}

// MARK: - views

/// 電台送來的資料: everything the station playing has sent with its sound (newest first)
struct RadioMetaLog: View {
    @ObservedObject private var radio = RadioPlayer.shared
    var body: some View {
        List {
            Section {
                if radio.metaLog.isEmpty {
                    Text(tr("這個電台到現在什麼都沒送：它沒有說在放什麼歌。")).foregroundStyle(T.muted)
                }
                ForEach(Array(radio.metaLog.enumerated()), id: \.offset) { _, e in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.time.formatted(date: .omitted, time: .standard)).ffFont(.caption).foregroundStyle(T.muted)
                        ForEach(e.lines, id: \.self) { l in
                            Text(l).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                        }
                    }
                }
            } footer: {
                Text(tr("電台和聲音一起送來的文字（例如歌名和歌手）。中文用舊的編碼（Big5、GBK）送的也讀得懂。有些電台只在自己的網站上寫在放什麼歌，聲音裡什麼都沒有。")).ffFont(.footnote)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("電台送來的資料"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
            RadioTimersSection()
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
                // what the station sends (to see whether it says the song)
                NavigationLink { RadioMetaLog() } label: {
                    Label(tr("電台送來的資料"), systemImage: "info.circle").foregroundStyle(T.muted)
                }
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

// MARK: - the radio's last seconds (a sentence's sound)

/// keeps the last 15 seconds of what the radio plays (in memory only), so a word saved from the 歌詞 page while
/// listening can keep the real line as its sound. Only streams Apple's player hands out as sound can be kept this
/// way (most stations; not ones sent in short pieces, HLS).
final class RadioClip {
    static let shared = RadioClip()
    static let seconds = 15.0

    private let lock = NSLock()
    private var ring: [Float] = []
    private var at = 0, filled = 0
    private var rate = 44_100.0
    private var channels = 2
    private var nonInterleaved = true

    /// the clips' folder (Documents/Clips: kept with the app's other files, and in its backups)
    static var folder: URL {
        let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Clips")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func url(_ path: String) -> URL { folder.appendingPathComponent(String(path.dropFirst(5))) }

    /// listens to this stream (from now on)
    func attach(to item: AVPlayerItem) {
        Task {
            guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }
            var cb = MTAudioProcessingTapCallbacks(
                version: kMTAudioProcessingTapCallbacksVersion_0,
                clientInfo: Unmanaged.passUnretained(self).toOpaque(),
                init: { _, info, storage in storage.pointee = info },
                finalize: nil,
                prepare: { tap, _, format in
                    let me = Unmanaged<RadioClip>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    me.prepare(format.pointee)
                },
                unprepare: nil,
                process: { tap, frames, _, list, framesOut, flagsOut in
                    guard MTAudioProcessingTapGetSourceAudio(tap, frames, list, flagsOut, nil, framesOut) == noErr else { return }
                    let me = Unmanaged<RadioClip>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    me.take(list, Int(framesOut.pointee))
                })
            var tap: MTAudioProcessingTap?
            guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &cb, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
                  let tap else { return }
            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            await MainActor.run { item.audioMix = mix }
        }
    }

    private func prepare(_ f: AudioStreamBasicDescription) {
        lock.lock(); defer { lock.unlock() }
        rate = f.mSampleRate > 0 ? f.mSampleRate : 44_100
        channels = max(1, Int(f.mChannelsPerFrame))
        nonInterleaved = f.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        ring = [Float](repeating: 0, count: Int(rate * Self.seconds))
        at = 0; filled = 0
    }

    /// (the sound, as one channel, into the ring)
    private func take(_ list: UnsafeMutablePointer<AudioBufferList>, _ frames: Int) {
        guard frames > 0, lock.try() else { return }
        defer { lock.unlock() }
        guard !ring.isEmpty else { return }
        let bufs = UnsafeMutableAudioBufferListPointer(list)
        let n = ring.count
        for i in 0..<frames {
            var v: Float = 0
            if nonInterleaved {
                var c = 0
                for b in bufs { if let d = b.mData?.assumingMemoryBound(to: Float.self), i < Int(b.mDataByteSize) / 4 { v += d[i]; c += 1 } }
                if c > 0 { v /= Float(c) }
            } else if let b = bufs.first, let d = b.mData?.assumingMemoryBound(to: Float.self) {
                for ch in 0..<channels where i * channels + ch < Int(b.mDataByteSize) / 4 { v += d[i * channels + ch] }
                v /= Float(channels)
            }
            ring[at] = v
            at = (at + 1) % n
        }
        filled = min(n, filled + frames)
    }

    /// the last seconds as a sound file ("clip:<file>"; nil: nothing kept, e.g. a station sent in pieces)
    func save() -> String? {
        lock.lock()
        let n = ring.count, count = filled
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count { samples[i] = ring[(at - count + i + n) % n] }
        let r = rate
        lock.unlock()
        guard count > Int(r) else { return nil }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: r, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { p in buf.floatChannelData![0].update(from: p.baseAddress!, count: count) }
        let name = UUID().uuidString + ".m4a"
        let url = Self.folder.appendingPathComponent(name)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: r, AVNumberOfChannelsKey: 1,
                                       AVEncoderBitRateKey: 64_000]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buf)
        } catch { return nil }
        return "clip:" + name
    }
}

/// the 電台鬧鐘's notification: tapped (or arriving while the app is open) → the station plays
final class RadioAlarmDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = RadioAlarmDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == "radioAlarm" else { return }
        let id = response.notification.request.content.userInfo["station"] as? String
        await MainActor.run { RadioPlayer.shared.alarmTapped(id) }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // (the app is open: the radio is already starting, no banner needed)
        notification.request.identifier == "radioAlarm" ? [] : [.banner, .sound]
    }
}

/// 睡眠定時 and 電台鬧鐘, in the 電台 sheet
struct RadioTimersSection: View {
    @ObservedObject private var radio = RadioPlayer.shared
    var body: some View {
        Section {
            // 睡眠定時
            HStack {
                Label(tr("睡眠定時"), systemImage: "moon.zzz")
                Spacer()
                if let at = radio.sleepAt {
                    Text(at, style: .timer).monospacedDigit().foregroundStyle(T.muted)
                }
                Menu {
                    ForEach([15, 30, 45, 60, 90], id: \.self) { m in
                        Button(tr("\(m) 分鐘")) { radio.sleep(minutes: m) }
                    }
                    if radio.sleepAt != nil { Button(tr("關掉"), role: .destructive) { radio.sleep(minutes: nil) } }
                } label: {
                    Text(radio.sleepAt == nil ? trs("關") : trs("改")).foregroundStyle(T.btnInk)
                }
            }
            // 電台鬧鐘
            Toggle(isOn: $radio.alarmOn) { Label(tr("電台鬧鐘"), systemImage: "alarm") }
            if radio.alarmOn {
                DatePicker(tr("時間"), selection: $radio.alarmTime, displayedComponents: .hourAndMinute)
                Picker(tr("電台"), selection: $radio.alarmStation) {
                    ForEach(radio.stations) { st in Text(st.name).tag(st.id) }
                }
                Text(tr("下次：\(radio.nextAlarm.formatted(date: .abbreviated, time: .shortened))")).ffFont(.footnote).foregroundStyle(T.muted)
            }
        } header: {
            Text(tr("定時"))
        } footer: {
            Text(tr("睡眠定時：時間到了電台慢慢變小聲，然後停。電台鬧鐘：時間到了電台從很小聲慢慢變大聲。App 要開著放在背景（不要從 App 切換器滑掉），這樣它才能自己開電台；手機最好接著充電。App 被關掉的話，時間到了會跳出通知，點一下就開始聽。"))
        }
    }
}
