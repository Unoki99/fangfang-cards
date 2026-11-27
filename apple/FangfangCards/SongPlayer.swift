import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
#if !targetEnvironment(macCatalyst)
import StoreKit
#endif

// 找歌來聽: look a song up in Apple's music catalogue (the iTunes Search API: free, no key), play it, and show its
// lyrics (LRCLIB) following it exactly: the player says where in the song it is, so no 對時 is needed.
// With Apple Music (a subscription, on iPhone and iPad) the whole song plays, through the phone's own music player;
// without it, Apple's 30-second preview.

/// a song in Apple's catalogue
struct SongHit: Codable, Identifiable, Hashable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let collectionName: String?
    let artworkUrl100: String?
    let previewUrl: String?
    let trackTimeMillis: Int?

    var id: Int { trackId }
    /// the cover, larger
    var art: URL? { artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "300x300bb")) } }
    var seconds: Double? { trackTimeMillis.map { Double($0) / 1000 } }
}

enum SongSource {
    private struct Reply: Decodable { let results: [SongHit] }
    /// (a lookup's results: anything that isn't a song is passed over)
    private struct Maybe: Decodable {
        let hit: SongHit?
        init(from d: Decoder) throws { hit = try? SongHit(from: d) }
    }
    private struct LookupReply: Decodable { let results: [Maybe] }

    /// these songs by their catalogue numbers (in the order given; the ones the store doesn't have left out)
    static func lookup(_ ids: [String], country: String) async throws -> [SongHit] {
        var found: [Int: SongHit] = [:]
        var i = 0
        while i < ids.count {
            let part = Array(ids[i..<min(ids.count, i + 150)])
            i += 150
            var u = URLComponents(string: "https://itunes.apple.com/lookup")!
            u.queryItems = [
                URLQueryItem(name: "id", value: part.joined(separator: ",")),
                URLQueryItem(name: "entity", value: "song"),
                URLQueryItem(name: "country", value: country),
            ]
            let (d, r) = try await URLSession.shared.data(from: u.url!)
            guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            for m in try JSONDecoder().decode(LookupReply.self, from: d).results { if let h = m.hit { found[h.trackId] = h } }
        }
        return ids.compactMap { Int($0).flatMap { found[$0] } }
    }

    /// songs for these words, in this country's store (two letters, "se", "tw"…)
    static func search(_ q: String, country: String) async throws -> [SongHit] {
        var u = URLComponents(string: "https://itunes.apple.com/search")!
        u.queryItems = [
            URLQueryItem(name: "term", value: q),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "country", value: country),
        ]
        let (d, r) = try await URLSession.shared.data(from: u.url!)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Reply.self, from: d).results
    }
}

@MainActor
final class SongPlayer: ObservableObject {
    static let shared = SongPlayer()

    /// the whole song (Apple Music) or Apple's 30-second preview
    enum Mode { case full, preview }

    @Published private(set) var song: SongHit?
    @Published private(set) var mode: Mode = .preview
    @Published private(set) var playing = false
    /// where the song is (seconds), for the bar under the cover
    var time: Double {
        get { SongClock.shared.time }
        set { if SongClock.shared.time != newValue { SongClock.shared.time = newValue } }
    }
    /// Apple Music can play whole songs here (nil: not asked yet)
    @Published private(set) var canFull: Bool?
    /// why it's only the preview (shown under the song), and whether 設定 can change it
    @Published private(set) var why: String?
    @Published private(set) var whySettings = false
    /// what plays one after the other (a playlist, 收藏的歌, or just the one song) and which one it's at
    @Published private(set) var queue: [SongHit] = []
    @Published private(set) var index = 0
    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }
    /// (to tell a song that ended from one paused)
    private var userPaused = false
    private var wasPlaying = false
    private var lastPos = 0.0
    /// (a whole song asked to play: still not playing after a while → the preview)
    private var watchdog: Task<Void, Never>?
    /// the store the songs are looked up in (two letters), from the Apple Music account when there is one
    private(set) var country: String?

    var active: Bool { song != nil }
    var length: Double {
        switch mode {
        case .full: return song?.seconds ?? 0
        case .preview: return av?.currentItem?.duration.seconds.isFinite == true ? av!.currentItem!.duration.seconds : 30
        }
    }

    private var av: AVPlayer?

    /// the song's speed (歌詞's 速度: slower to follow the words, 0.5×–1.5×), kept for the next songs too
    @Published var speed: Double = UserDefaults.standard.object(forKey: "songSpeed") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(speed, forKey: "songSpeed"); applySpeed() }
    }

    /// (the speed set on whichever player plays: Apple Music's, or the preview's)
    func applySpeed() {
        let r = Float(speed)
        switch mode {
        case .full:
            #if !targetEnvironment(macCatalyst)
            if music.playbackState == .playing { music.currentPlaybackRate = r }
            #endif
        case .preview:
            if let p = av {
                if #available(iOS 16.0, *) { p.defaultRate = r }
                if p.rate > 0 { p.rate = r }
            }
        }
    }
    private var endObserver: NSObjectProtocol?
    private var timer: Timer?
    private var lyricsJob: Task<Void, Never>?
    #if !targetEnvironment(macCatalyst)
    private var music: MPMusicPlayerApplicationController { MPMusicPlayerController.applicationQueuePlayer }
    #endif

    private init() {}

    // MARK: searching

    func search(_ q: String) async throws -> [SongHit] {
        let cc = await storeCountry()
        var found = try await SongSource.search(q, country: cc)
        // (華語 / 台語 songs the store here doesn't list: Taiwan's)
        if found.isEmpty && cc != "tw" { found = try await SongSource.search(q, country: "tw") }
        return found
    }

    /// a saved song (我的歌) in the catalogue: the one whose name (and singer) fit best; nil when it isn't there
    func find(title: String, artist: String) async -> SongHit? {
        let t = Self.norm(title), a = Self.norm(artist)
        guard !t.isEmpty else { return nil }
        var queries = [[artist, title].filter { !$0.isEmpty }.joined(separator: " ")]
        if !artist.isEmpty { queries.append(title) }
        // (the singer written another way, "Jay Chou" for 周杰倫: the same name exactly, at the end)
        var sameName: SongHit?
        for q in queries {
            guard let hits = try? await search(q) else { return sameName }
            var best: (hit: SongHit, score: Int)?
            for h in hits {
                let ht = Self.norm(h.trackName), ha = Self.norm(h.artistName)
                // the name: the same (4) or one inside the other (2); the singer too (+2)
                var sc = ht == t ? 4 : (!ht.isEmpty && (ht.contains(t) || t.contains(ht)) ? 2 : 0)
                if sc == 0 { continue }
                let singer = !a.isEmpty && !ha.isEmpty && (ha.contains(a) || a.contains(ha))
                if singer { sc += 2 }
                // (a singer was saved: it has to be theirs)
                if !a.isEmpty && !singer { if sc == 4 && sameName == nil { sameName = h }; continue }
                if best == nil || sc > best!.score { best = (h, sc) }
            }
            if let b = best { return b.hit }
        }
        return sameName
    }

    /// (to compare names: 繁體, small letters, no brackets, only letters and numbers)
    static func norm(_ s: String) -> String {
        var t = LyricsSource.traditionalForMatching(s) ?? s
        for junk in [#"\([^)]*\)"#, #"（[^）]*）"#, #"\[[^\]]*\]"#, #"(?i)\bfeat\..*$"#] {
            t = t.replacingOccurrences(of: junk, with: "", options: .regularExpression)
        }
        return String(t.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    func storeCountry() async -> String {
        if let c = country { return c }
        var c: String?
        #if !targetEnvironment(macCatalyst)
        if MPMediaLibrary.authorizationStatus() == .authorized {
            c = await withCheckedContinuation { (k: CheckedContinuation<String?, Never>) in
                SKCloudServiceController().requestStorefrontCountryCode { code, _ in k.resume(returning: code) }
            }
        }
        #endif
        let cc = (c ?? Locale.current.region?.identifier ?? "se").lowercased()
        if c != nil { country = cc }
        return cc
    }

    /// Apple Music: asked once (the phone asks the person), then remembered for the time the app is open
    func checkFull() async -> Bool {
        #if targetEnvironment(macCatalyst)
        canFull = false
        why = trs("Mac 上只能聽試聽（Apple 的整首歌播放器在 Mac 上不能用）。")
        return false
        #else
        var st = MPMediaLibrary.authorizationStatus()
        if st == .notDetermined {
            st = await withCheckedContinuation { (k: CheckedContinuation<MPMediaLibraryAuthorizationStatus, Never>) in
                MPMediaLibrary.requestAuthorization { k.resume(returning: $0) }
            }
        }
        guard st == .authorized else {
            canFull = false
            why = trs("方方詞卡還沒被允許用 Apple Music，所以只有試聽。到 設定 → 方方詞卡 → 媒體與 Apple Music 打開。")
            whySettings = true
            return false
        }
        whySettings = false
        // (the subscription isn't trusted to answer right: the song is tried anyway, the preview if it won't play)
        let caps = await withCheckedContinuation { (k: CheckedContinuation<SKCloudServiceCapability, Never>) in
            SKCloudServiceController().requestCapabilities { caps, _ in k.resume(returning: caps) }
        }
        canFull = caps.contains(.musicCatalogPlayback)
        if country == nil { _ = await storeCountry() }
        return true
        #endif
    }

    // MARK: playing

    /// play this song; with a list, the ones after it follow when it's done
    func play(_ h: SongHit, in list: [SongHit]? = nil) {
        let q = list ?? [h]
        queue = q
        index = q.firstIndex(where: { $0.id == h.id }) ?? 0
        start(h)
    }

    /// the next song in the list
    func next() {
        guard hasNext else { return }
        index += 1
        start(queue[index])
    }

    /// back to the start of the song (a few seconds in), or the one before
    func previous() {
        if (position ?? 0) > 3 || !hasPrevious { seek(0); return }
        index -= 1
        start(queue[index])
    }

    /// (the song played to its end: the next one, or it stops there)
    private func songEnded() {
        if hasNext && !editing { next() } else { playing = false; wasPlaying = false }
    }

    /// 歌詞對時 open: the song stays when it ends (the next one doesn't start)
    @Published var editing = false

    private func start(_ h: SongHit) {
        if RadioPlayer.shared.isOn { RadioPlayer.shared.stop() }
        // (YouTube in the app: paused, the lyrics follow this song)
        YtPlayer.shared.yieldToOther()
        halt()
        song = h
        time = 0
        userPaused = false; wasPlaying = false; lastPos = 0
        Task {
            let full = await checkFull()
            guard song?.id == h.id else { return }
            if full { playFull(h) } else { playPreview(h) }
            startClock()
            findLyrics(h)
        }
    }

    private func playFull(_ h: SongHit) {
        #if !targetEnvironment(macCatalyst)
        mode = .full
        let m = music
        why = nil
        // (the song downloaded into your Apple Music library: that copy, which plays without the internet too;
        // otherwise the song from Apple Music's catalogue)
        if let item = Self.libraryItem(h) {
            m.setQueue(with: MPMediaItemCollection(items: [item]))
        } else {
            m.setQueue(with: [String(h.trackId)])
        }
        m.prepareToPlay { [weak self] err in
            Task { @MainActor in
                guard let self, self.song?.id == h.id else { return }
                // (not in Apple Music in this country, or it can't be played: the preview)
                if let err {
                    self.why = trs("Apple Music 播不了這首，所以是試聽：") + err.localizedDescription
                        + (self.canFull == false ? trs("（Apple Music 說這個帳號不能播整首歌）") : "")
                    self.playPreview(h)
                } else {
                    m.play()
                    self.applySpeed()
                    self.watch(h)
                }
            }
        }
        hookLyricsClock()
        #else
        playPreview(h)
        #endif
    }

    /// a song in your own Apple Music library (added or downloaded), found by its Apple Music number. Asks once
    /// whether the app may look in the library.
    static func libraryItem(_ h: SongHit) -> MPMediaItem? {
        #if targetEnvironment(macCatalyst)
        return nil
        #else
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: break
        case .notDetermined: MPMediaLibrary.requestAuthorization { _ in }; return nil
        default: return nil
        }
        // (the Apple Music number can't be searched for: a query filtered by it stops the app. So the songs with
        // this title are looked up, and the one with this number is picked from them)
        let id = String(h.trackId)
        let q = MPMediaQuery.songs()
        q.addFilterPredicate(MPMediaPropertyPredicate(value: h.trackName, forProperty: MPMediaItemPropertyTitle, comparisonType: .equalTo))
        return (q.items ?? []).first { $0.playbackStoreID == id }
        #endif
    }

    /// (the whole song asked for: not playing after 8 seconds → the preview, and why)
    private func watch(_ h: SongHit) {
        #if !targetEnvironment(macCatalyst)
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, !Task.isCancelled, self.song?.id == h.id, self.mode == .full else { return }
            if self.music.playbackState != .playing && (self.position ?? 0) < 0.5 {
                self.music.stop()
                self.why = trs("Apple Music 沒有開始播這首，所以是試聽。") + (self.canFull == false ? trs("（Apple Music 說這個帳號不能播整首歌）") : "")
                self.playPreview(h)
            }
        }
        #endif
    }

    private func playPreview(_ h: SongHit) {
        mode = .preview
        hookLyricsClock()
        guard let s = h.previewUrl, let u = URL(string: s) else { playing = false; return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: u)
        av = p
        if let o = endObserver { NotificationCenter.default.removeObserver(o) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.playing = false; self?.songEnded() }
        }
        p.play()
        applySpeed()
        hookLyricsClock()
        nowPlaying()
    }

    /// the preview in iOS's "now playing" (the Dynamic Island, the lock screen)
    private func nowPlaying() {
        guard mode == .preview, let s = song, av != nil else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: s.trackName,
            MPMediaItemPropertyArtist: s.artistName,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position ?? 0,
        ]
        info[MPMediaItemPropertyPlaybackDuration] = length
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// the lyrics follow the player: its time, and 跳到 moves the song itself (the preview: the lyrics instead)
    private func hookLyricsClock() {
        let b = LyricsBridge.shared
        let clock: @MainActor () -> Double? = { [weak self] in self?.position }
        b.clock = clock
        if mode == .full {
            let seeker: @MainActor (Double) -> Void = { [weak self] t in self?.seek(t) }
            b.seeker = seeker
        } else {
            b.seeker = nil
        }
    }

    /// seconds into what's playing
    var position: Double? {
        switch mode {
        case .full:
            #if !targetEnvironment(macCatalyst)
            let t = music.currentPlaybackTime
            return t.isFinite ? t : nil
            #else
            return nil
            #endif
        case .preview:
            guard let t = av?.currentTime().seconds, t.isFinite else { return nil }
            return t
        }
    }

    func togglePause() {
        // (Apple Music: what its player is really doing; something else may have stopped it without us knowing)
        #if !targetEnvironment(macCatalyst)
        if mode == .full { if music.playbackState == .playing { pause() } else { resume() }; return }
        #endif
        if playing { pause() } else { resume() }
    }

    func pause() {
        switch mode {
        case .full:
            #if !targetEnvironment(macCatalyst)
            music.pause()
            #endif
        case .preview: av?.pause()
        }
        playing = false
        userPaused = true
    }

    func resume() {
        if RadioPlayer.shared.isOn { RadioPlayer.shared.stop() }
        switch mode {
        case .full:
            #if !targetEnvironment(macCatalyst)
            music.play()
            #endif
        case .preview:
            if let p = av {
                if let d = p.currentItem?.duration.seconds, d.isFinite, p.currentTime().seconds >= d - 0.2 { p.seek(to: .zero) }
                p.play()
            }
        }
        playing = true
        applySpeed()
        userPaused = false
    }

    func seek(_ t: Double) {
        let t = max(0, min(t, max(0, length - 0.5)))
        switch mode {
        case .full:
            #if !targetEnvironment(macCatalyst)
            music.currentPlaybackTime = t
            #endif
        case .preview:
            av?.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        time = t
    }

    /// stop and close the player (the lyrics stay, no longer following)
    func stop() {
        guard song != nil else { return }
        halt()
        song = nil
        queue = []; index = 0
        let b = LyricsBridge.shared
        b.clock = nil
        b.seeker = nil
    }

    private func halt() {
        lyricsJob?.cancel()
        watchdog?.cancel()
        timer?.invalidate(); timer = nil
        #if !targetEnvironment(macCatalyst)
        if mode == .full && song != nil { music.stop() }
        #endif
        av?.pause(); av = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        playing = false
    }

    private func startClock() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { _ in Task { @MainActor in SongPlayer.shared.poll() } }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func poll() {
        let pos = position
        if let p = pos { time = p }
        let now: Bool
        switch mode {
        case .full:
            #if !targetEnvironment(macCatalyst)
            now = music.playbackState == .playing
            #else
            now = false
            #endif
        case .preview: now = av?.timeControlStatus == .playing
        }
        if now != playing { playing = now; nowPlaying() }
        #if !targetEnvironment(macCatalyst)
        // (the whole song: Apple Music stops at its end; near the end, or nothing left playing → the next one)
        if mode == .full, song != nil, wasPlaying, !now, !userPaused {
            let len = length
            if (len > 0 && lastPos >= len - 3) || music.nowPlayingItem == nil {
                wasPlaying = false
                songEnded()
                return
            }
        }
        #endif
        if now { wasPlaying = true }
        if let p = pos { lastPos = p }
    }

    // MARK: its lyrics

    /// LRCLIB's lyrics for the song: a timed version of about the same length first
    private func findLyrics(_ h: SongHit) {
        lyricsJob?.cancel()
        let b = LyricsBridge.shared
        b.waitFor(h.artistName + " " + h.trackName)
        // (歌詞 of your own for this song: those, nothing looked up)
        if let own = OwnLyrics.shared.get(h.id) { b.put(own.hit); return }
        lyricsJob = Task {
            var hits: [LyricHit] = []
            for q in [h.artistName + " " + h.trackName, h.trackName] {
                hits = await LyricsSource.find(q)
                if Task.isCancelled { return }
                if hits.contains(where: { $0.timedRows != nil }) { break }
            }
            guard song?.id == h.id else { return }
            let len = h.seconds ?? 0
            let best = hits.min { a, b in score(a, len) < score(b, len) }
            if let best { b.put(best) } else { b.noneFound(h.artistName + " " + h.trackName) }
        }
    }

    /// the song's lyrics looked up again (自己的歌詞 deleted: LRCLIB's)
    func reloadLyrics() { if let s = song { findLyrics(s) } }

    /// (lower is better: timed first, then the nearest length)
    private func score(_ h: LyricHit, _ len: Double) -> Double {
        let d = len > 0 ? abs((h.duration ?? 0) - len) : 0
        return (h.timedRows != nil ? 0 : 1000) + min(d, 999)
    }
}

// MARK: - 找歌來聽

struct SongSearchView: View {
    /// (the song chosen: its lyrics open, 轉換 → 歌詞)
    var jumpToLyrics = true
    @ObservedObject private var player = SongPlayer.shared
    @ObservedObject private var library = MusicLibrary.shared
    @State private var naming = false
    @State private var namingSong: SongHit?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hits: [SongHit] = []
    @State private var busy = false
    @State private var failed = false
    @State private var searched = false
    @State private var job: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        List {
            Section {
                HStack {
                    TextField(tr("歌名或歌手"), text: $query)
                        .submitLabel(.search)
                        .focused($focused)
                        .onSubmit { run() }
                    if busy { ProgressView() } else {
                        Button { run() } label: { Image(systemName: "magnifyingglass") }
                            .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            } footer: {
                Text(player.canFull == false
                     ? tr("沒有 Apple Music 的話，只能聽 30 秒的試聽。試聽是從歌的中間開始，歌詞可以用「跳到哪一行」對上。")
                     : tr("有 Apple Music 的話整首歌都可以聽，歌詞會自己跟著歌走。沒有的話可以聽 30 秒的試聽。歌來自 Apple 的音樂目錄，歌詞來自 LRCLIB。"))
                    .ffFont(.footnote)
            }
            if failed {
                Text(tr("連不上，等一下再試試看。")).foregroundStyle(T.muted)
            } else if searched && hits.isEmpty && !busy {
                Text(tr("找不到這首歌")).foregroundStyle(T.muted)
            }
            if !hits.isEmpty {
                Section {
                    ForEach(hits) { h in
                        Button {
                            player.play(h)
                            if jumpToLyrics { dismiss(); LyricsBridge.showInConvert() }
                        } label: { row(h) }
                        .contextMenu { SongMenuItems(song: h) { namingSong = h; naming = true } }
                        .swipeActions(edge: .leading) {
                            Button { library.toggleSave(h) } label: {
                                Label(library.isSaved(h) ? tr("取消收藏") : trSaveVerb(), systemImage: library.isSaved(h) ? "bookmark.slash" : "bookmark")
                            }
                            .tint(T.btnInk)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .modifier(PlaylistNaming(open: $naming, song: namingSong))
        .navigationTitle(tr("找歌來聽"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } } }
        .onAppear {
            if hits.isEmpty {
                if let s = player.song { query = s.artistName + " " + s.trackName; run() } else { focused = true }
            }
        }
    }

    private func row(_ h: SongHit) -> some View {
        HStack(spacing: 12) {
            SongArt(url: h.art, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(h.trackName).foregroundStyle(T.glyph).lineLimit(1)
                Text(detail(h)).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if player.song?.id == h.id {
                Image(systemName: player.playing ? "speaker.wave.2.fill" : "speaker.fill").foregroundStyle(T.btnInk)
            }
        }
    }

    private func detail(_ h: SongHit) -> String {
        var p = [h.artistName]
        if let a = h.collectionName, !a.isEmpty, a != h.trackName { p.append(a) }
        if let d = h.seconds, d > 0 { p.append(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)) }
        return p.joined(separator: " · ")
    }

    private func run() {
        job?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        busy = true; failed = false; focused = false
        job = Task {
            var found: [SongHit] = []
            var reached = true
            do { found = try await player.search(q) } catch { reached = false }
            if Task.isCancelled { return }
            hits = found
            failed = !reached
            searched = true
            busy = false
        }
    }
}

/// a song's cover (a plain square while it loads)
struct SongArt: View {
    let url: URL?
    var size: CGFloat = 44
    var body: some View {
        AsyncImage(url: url) { img in
            img.resizable().scaledToFill()
        } placeholder: {
            ZStack { T.fn; Image(systemName: "music.note").foregroundStyle(T.muted) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16))
    }
}

/// the song playing: cover, name, play / pause, where it is (drag to move in the song), another song, close
struct SongPlayerBar: View {
    @ObservedObject private var player = SongPlayer.shared
    @State private var searching = false
    @State private var dragging: Double?

    var body: some View {
        if let s = player.song {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    SongArt(url: s.art, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.trackName).ffFont(.subheadline, .semibold).lineLimit(1)
                        Text(player.mode == .preview ? s.artistName + " · " + trs("試聽") : s.artistName)
                            .ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if player.queue.count > 1 {
                        Button { player.previous() } label: { Image(systemName: "backward.fill").frame(width: 24, height: 28) }
                            .buttonStyle(.plain).foregroundStyle(T.btnInk)
                            .accessibilityLabel(tr("上一首"))
                    }
                    Button { player.togglePause() } label: {
                        Image(systemName: player.playing ? "pause.fill" : "play.fill").frame(width: 30, height: 28)
                    }
                    .softButton()
                    .accessibilityLabel(player.playing ? tr("暫停") : tr("播放"))
                    if player.queue.count > 1 {
                        Button { player.next() } label: { Image(systemName: "forward.fill").frame(width: 24, height: 28) }
                            .buttonStyle(.plain).foregroundStyle(player.hasNext ? T.btnInk : T.muted)
                            .disabled(!player.hasNext)
                            .accessibilityLabel(tr("下一首"))
                    }
                    // (音樂: the radio button's window, on its 音樂 side: other songs, 收藏, 歌單)
                    Button {
                        UserDefaults.standard.set(1, forKey: "mediaTab")
                        RadioPlayer.shared.sheetOpen = true
                    } label: { Image(systemName: "music.note.list") }
                        .softButton()
                        .accessibilityLabel(tr("音樂"))
                    Button { player.stop() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(T.muted)
                        .accessibilityLabel(tr("停止播放"))
                }
                if player.mode == .preview, let w = player.why {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(w).ffFont(.caption2).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if player.whySettings, let u = URL(string: UIApplication.openSettingsURLString) {
                            Button(tr("打開設定")) { UIApplication.shared.open(u) }.ffFont(.caption)
                        }
                    }
                }
                SongProgress()
            }
            .padding(.horizontal).padding(.vertical, 8)
            .background(T.fn.opacity(0.6))
            .sheet(isPresented: $searching) {
                NavigationStack { SongSearchView() }
                    .environmentObject(Store.shared)
                    .preferredColorScheme(.dark)
                    .tint(AppTint.accent)
            }
        }
    }

    static func clock(_ t: Double) -> String {
        let s = Int(max(0, t.isFinite ? t : 0))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}


/// where the song is, four times a second: apart from SongPlayer, so only what shows it is redrawn that often (with
/// it inside SongPlayer every view watching the player, the lyrics page and the editor's whole page among them, was
/// drawn again four times a second, even paused)
@MainActor
final class SongClock: ObservableObject {
    static let shared = SongClock()
    @Published var time: Double = 0
}

/// the time, a bar to drag anywhere in the song, the length
struct SongProgress: View {
    var precise = false
    @ObservedObject private var clock = SongClock.shared
    @State private var dragging: Double?
    private var player: SongPlayer { SongPlayer.shared }
    var body: some View {
        let len = max(1, player.length)
        HStack(spacing: 8) {
            Text(precise ? LRC.shown(dragging ?? clock.time) : SongPlayerBar.clock(dragging ?? clock.time))
                .ffFont(.caption2).monospacedDigit().foregroundStyle(T.muted)
                .frame(minWidth: precise ? 52 : nil, alignment: .leading)
            Slider(value: Binding(get: { min(len, dragging ?? clock.time) }, set: { dragging = $0 }), in: 0...len,
                   onEditingChanged: { editing in
                if !editing, let d = dragging { player.seek(d); dragging = nil }
            })
            Text(SongPlayerBar.clock(len)).ffFont(.caption2).monospacedDigit().foregroundStyle(T.muted)
        }
    }
}
