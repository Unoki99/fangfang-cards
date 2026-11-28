import SwiftUI
import UIKit
import WebKit

// YouTube (iPhone / iPad): YouTube or YouTube Music in a browser of the app's own, over everything in a window of
// its own. Look a song up there and play it; 收起 shrinks it to a small card in a corner (the video stays seen, as
// YouTube asks: nothing over it, no sound without the video), and the lyrics follow the song in 轉換 → 歌詞 like the
// radio's and 找歌來聽's: the page says what's playing and where it is, the lyrics come from LRCLIB. Leaving the app
// pauses it (YouTube doesn't allow playing from the background).

/// what the page says is playing
struct YtNow: Equatable {
    var id = ""
    var title = ""
    var artist = ""
    var d = 0.0
    var music = false
}

/// one report from the page (a few times a second)
private struct YtTick: Sendable {
    var id = "", title = "", artist = ""
    var t = 0.0, d = 0.0, rate = 1.0
    var paused = true, music = false, ad = false

    init(_ m: [String: Any]) {
        id = m["id"] as? String ?? ""
        title = (m["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        artist = (m["artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        t = (m["t"] as? NSNumber)?.doubleValue ?? 0
        d = (m["d"] as? NSNumber)?.doubleValue ?? 0
        rate = (m["rate"] as? NSNumber)?.doubleValue ?? 1
        paused = (m["paused"] as? NSNumber)?.boolValue ?? true
        music = (m["music"] as? NSNumber)?.boolValue ?? false
        ad = (m["ad"] as? NSNumber)?.boolValue ?? false
    }
}

@MainActor
final class YtPlayer: ObservableObject {
    static let shared = YtPlayer()
    /// 0 YouTube, 1 YouTube Music
    static let siteKey = "ytSite"
    static let sites = ["https://m.youtube.com/", "https://music.youtube.com/"]

    /// the YouTube window shown (big or as the small card)
    @Published private(set) var open = false
    /// the whole screen (false: the small card in a corner)
    @Published private(set) var expanded = true
    @Published private(set) var now: YtNow?
    @Published private(set) var playing = false
    @Published private(set) var canBack = false

    private var web: WKWebView?
    private let messages = YtMessages()
    private let nav = YtNav()
    /// where the video was at the page's last report, and when that was (between reports: counted on from there)
    private var lastT = 0.0
    private var lastAt = Date()
    private var rate = 1.0

    /// the video's speed (歌詞's 速度), kept for the next videos too: set again whenever YouTube's own differs (a new
    /// video starts at 1×)
    @Published var speed: Double = UserDefaults.standard.object(forKey: "ytSpeed") as? Double ?? 1 {
        didSet { UserDefaults.standard.set(speed, forKey: "ytSpeed"); applySpeed() }
    }
    func applySpeed() { run("v.playbackRate=\(speed);") }
    /// (the song whose lyrics were looked for: the video and its name)
    private var lyricsFor = ""
    private var lyricsJob: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    private init() {
        // leaving the app: the song pauses
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in YtPlayer.shared.pause() }
        })
        // back in the app: the window shown again and drawn again (its card's place made anew), and the page
        // loaded again if iOS took it away meanwhile
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in YtPlayer.shared.cameBack() }
        })
    }

    @Published private(set) var redraw = 0

    func cameBack() {
        guard open else { return }
        YtOverlay.reshow()
        redraw += 1
        // (no report from the page in the 3 seconds after coming back: its process was stopped while away)
        let back = Date()
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if open, lastTick < back { pageLost() }
        }
    }

    /// (when the page last said anything)
    private var lastTick = Date()

    /// WebKit's page process stopped (iOS does that to apps in the background): the same video again, where it was
    func pageLost() {
        guard let w = web else { return }
        if let id = now?.id, !id.isEmpty {
            let base = UserDefaults.standard.integer(forKey: Self.siteKey) == 1 ? "https://music.youtube.com/watch?v=" : "https://m.youtube.com/watch?v="
            if let u = URL(string: base + id + "&t=\(Int(lastT))s") { w.load(URLRequest(url: u)); return }
        }
        if w.url != nil { w.reload() } else { load(UserDefaults.standard.integer(forKey: Self.siteKey)) }
    }

    /// seconds into the video now
    var position: Double { playing ? lastT + Date().timeIntervalSince(lastAt) * rate : lastT }

    /// (the YouTube header at the top of the page, kept out of the small card)
    var headerHeight: Double {
        #if targetEnvironment(macCatalyst)
        return 56
        #else
        return UserDefaults.standard.integer(forKey: Self.siteKey) == 1 ? 0 : 48
        #endif
    }

    func webView() -> WKWebView {
        if let w = web { return w }
        let c = WKWebViewConfiguration()
        c.allowsInlineMediaPlayback = true
        c.mediaTypesRequiringUserActionForPlayback = []
        #if !targetEnvironment(macCatalyst)
        c.allowsPictureInPictureMediaPlayback = false
        // (as Safari: YouTube's own pages for a phone, not its "open the app" ones)
        c.applicationNameForUserAgent = "Version/17.0 Mobile/15E148 Safari/604.1"
        #endif
        c.userContentController.add(messages, name: "ff")
        c.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 700), configuration: c)
        w.allowsBackForwardNavigationGestures = true
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.backgroundColor = .black
        w.navigationDelegate = nav
        w.uiDelegate = nav
        web = w
        return w
    }

    /// the YouTube window opened, the whole screen
    func show() {
        YtOverlay.install()
        let w = webView()
        if w.url == nil { load(UserDefaults.standard.integer(forKey: Self.siteKey)) }
        open = true
        expand()
    }

    /// YouTube or YouTube Music
    func load(_ site: Int) {
        let s = min(max(site, 0), Self.sites.count - 1)
        UserDefaults.standard.set(s, forKey: Self.siteKey)
        if let u = URL(string: Self.sites[s]) { webView().load(URLRequest(url: u)) }
    }

    func expand() {
        withAnimation(.snappy) { expanded = true }
        YtOverlay.takeKeys(true)
    }

    /// 收起: the small card in a corner
    func collapse() {
        withAnimation(.snappy) { expanded = false }
        YtOverlay.takeKeys(false)
    }

    /// 收起 and the lyrics (轉換 → 歌詞)
    func showLyrics() {
        collapse()
        LyricsBridge.showInConvert()
    }

    /// the YouTube window closed: the song stops, the lyrics stay (no longer following)
    func close() {
        pause()
        withAnimation(.snappy) { open = false }
        YtOverlay.takeKeys(false)
        lyricsJob?.cancel()
        if !SongPlayer.shared.active {
            LyricsBridge.shared.clock = nil
            LyricsBridge.shared.seeker = nil
        }
        now = nil
        lyricsFor = ""
    }

    /// the radio or 找歌來聽 starts: YouTube pauses, and the lyrics no longer follow it
    func yieldToOther() {
        guard web != nil else { return }
        pause()
        if open {
            LyricsBridge.shared.clock = nil
            LyricsBridge.shared.seeker = nil
        }
        lyricsFor = ""
    }

    /// the video as a song the lyrics editor (歌詞對時) knows: its own number from the video, so your own lyrics for
    /// it are kept like 找歌來聽's songs
    var editSong: SongHit? {
        guard let n = now, !n.id.isEmpty else { return nil }
        return SongHit(trackId: Self.trackId(n.id), trackName: n.title, artistName: n.artist, collectionName: nil,
                       artworkUrl100: "https://i.ytimg.com/vi/\(n.id)/mqdefault.jpg", previewUrl: nil,
                       trackTimeMillis: n.d > 0 ? Int(n.d * 1000) : nil)
    }

    /// a video's number for your own lyrics (the same each time; far above Apple's song numbers)
    static func trackId(_ video: String) -> Int {
        var h: UInt64 = 5381
        for b in video.utf8 { h = (h &* 33) &+ UInt64(b) }
        return 2_000_000_000_000 + Int(h % 900_000_000_000)
    }

    /// the lyrics looked up again (your own for the video deleted)
    func reloadLyrics() {
        guard let n = now else { return }
        lyricsFor = n.id + "|" + n.title
        findLyrics(n, lyricsFor)
    }

    /// the lyrics follow YouTube's video now (lyrics chosen by hand are then kept for it)
    var following: Bool { open && now != nil && !SongPlayer.shared.active && !RadioPlayer.shared.isOn }

    /// lyrics chosen by hand (找歌詞, 歌詞資料夾) while the video plays: used for it from now on
    func remember(_ h: LyricHit) {
        guard following, let n = now else { return }
        YtPicks.set(video: n.id, title: n.title, h)
    }

    func back() { if web?.canGoBack == true { web?.goBack() } }

    private func run(_ js: String) { web?.evaluateJavaScript("(function(){var v=document.querySelector('video');if(!v)return;" + js + "})()") }

    func pause() {
        guard web != nil else { return }
        run("v.pause();")
        if playing { lastT = position; lastAt = Date() }
        playing = false
    }

    func play() {
        if RadioPlayer.shared.isOn { RadioPlayer.shared.stop() }
        if SongPlayer.shared.active { SongPlayer.shared.stop() }
        run("v.play();")
        hook()
    }

    func togglePause() { if playing { pause() } else { play() } }

    /// 跳到 a line: the video goes there
    func seek(_ t: Double) {
        let t = max(0, t)
        run("v.currentTime=\(t);")
        lastT = t; lastAt = Date()
    }

    /// the lyrics follow the video: its time, and 跳到 moves it
    private func hook() {
        let b = LyricsBridge.shared
        let clock: @MainActor () -> Double? = { YtPlayer.shared.open ? YtPlayer.shared.position : nil }
        let seeker: @MainActor (Double) -> Void = { YtPlayer.shared.seek($0) }
        b.clock = clock
        b.seeker = seeker
    }

    fileprivate func got(_ x: YtTick) {
        lastTick = Date()
        let cb = web?.canGoBack ?? false
        if cb != canBack { canBack = cb }
        // (an ad: its time isn't the song's; the lyrics wait)
        if x.ad {
            if playing { lastT = position; lastAt = Date(); playing = false }
            return
        }
        let was = playing
        lastT = x.t; lastAt = Date(); rate = x.rate > 0 ? x.rate : 1
        if abs(rate - speed) > 0.01 { applySpeed() }
        if playing == x.paused { playing = !x.paused }
        // (started playing here: the radio and 找歌來聽 stop, the lyrics follow this)
        if playing && !was {
            if RadioPlayer.shared.isOn { RadioPlayer.shared.stop() }
            if SongPlayer.shared.active { SongPlayer.shared.stop() }
            hook()
        }
        guard !x.id.isEmpty, !x.title.isEmpty else { return }
        // (the radio or 找歌來聽 is playing (YouTube paused for it): the lyrics are theirs. The page, still on its
        // video, kept saying what's playing, and that took the lyrics and their clock back from the Apple Music
        // song: its lyrics stopped lighting up)
        if SongPlayer.shared.active || RadioPlayer.shared.isOn { return }
        let n = YtNow(id: x.id, title: x.title, artist: x.artist, d: x.d, music: x.music)
        if now != n { now = n }
        // (the video and its name: a name corrected a moment after a new video starts is looked up again)
        let key = n.id + "|" + n.title
        if key != lyricsFor {
            lyricsFor = key
            hook()
            findLyrics(n, key)
        }
    }

    /// where a video's lyrics come from first: 0 the lyrics database (LRCLIB), its subtitles when it has none;
    /// 1 the video's own subtitles, LRCLIB when it has none
    static let lyricsSourceKey = "ytLyricsSource"
    static var subtitlesFirst: Bool { UserDefaults.standard.integer(forKey: lyricsSourceKey) == 1 }

    /// 用這部影片的字幕: this video's subtitles as its lyrics, from now on (this video only: they're timed to it);
    /// false when it has none
    func useSubtitles() async -> Bool {
        guard let n = now, let lrc = await subtitleLyrics(), now?.id == n.id else { return false }
        let h = LyricsFolder.saveVideo(id: n.id, title: n.title, artist: n.artist, lrc: lrc)
        YtPicks.set(video: n.id, title: n.title, h, nameToo: false)
        LyricsBridge.shared.put(h)
        return true
    }

    /// the lyrics for the video: picked before, else LRCLIB's (the first search that finds any; timed ones first,
    /// then those about as long) or the video's subtitles, whichever is set to go first
    private func findLyrics(_ n: YtNow, _ key: String) {
        lyricsJob?.cancel()
        let b = LyricsBridge.shared
        b.waitFor(n.title)
        // (lyrics picked for this video before; else the 歌詞 folder's file for it, the computer version's "[yt-…]")
        // (then your own lyrics whose song's name is in the video's)
        // (your own lyrics made for this video in 歌詞對時 first)
        if let o = OwnLyrics.shared.get(Self.trackId(n.id)) { b.put(o.hit); return }
        let subsFirst = Self.subtitlesFirst
        // (the 歌詞 folder's file for the video: lyrics picked on the computer always; made from its subtitles only
        // when subtitles go first, else after LRCLIB)
        if let h = YtPicks.get(video: n.id, title: n.title) ?? LyricsFolder.forVideo(n.id, subtitles: subsFirst)
            ?? YtPicks.ownMatch(title: n.title, artist: n.artist) { b.put(h); return }
        lyricsJob = Task {
            // (subtitles first: the video's own, when it has any)
            if subsFirst, let lrc = await self.subtitleLyrics() {
                guard lyricsFor == key else { return }
                b.put(LyricsFolder.saveVideo(id: n.id, title: n.title, artist: n.artist, lrc: lrc))
                return
            }
            var hits: [LyricHit] = []
            for q in Self.queries(n.title, n.artist, n.music) {
                if let r = try? await LyricsSource.search(q) {
                    hits = r.filter { !$0.instrumental && $0.text != nil }
                    if !hits.isEmpty { break }
                }
                if Task.isCancelled { return }
            }
            guard lyricsFor == key else { return }
            let len = now?.d ?? n.d
            let best = hits.min { a, c in Self.score(a, len) < Self.score(c, len) }
            if let best { b.put(best); return }
            // (none on LRCLIB: the video's own subtitles made into timed lyrics, kept in the 歌詞 folder, so they're
            // there next time and on the other devices)
            if !subsFirst, let h = LyricsFolder.forVideo(n.id) { b.put(h); return }
            if !subsFirst, let lrc = await self.subtitleLyrics(), lyricsFor == key {
                b.put(LyricsFolder.saveVideo(id: n.id, title: n.title, artist: n.artist, lrc: lrc))
                return
            }
            guard lyricsFor == key else { return }
            b.noneFound(n.title)
        }
    }

    /// the video's subtitles as timed lyrics (LRC): a Chinese track the video has (not YouTube's automatic one when
    /// there's another), else its first; nil when it has none
    func subtitleLyrics() async -> String? {
        guard let web else { return nil }
        let js = """
        try {
          const mp = document.querySelector('#movie_player');
          const pr = (mp && mp.getPlayerResponse && mp.getPlayerResponse()) || window.ytInitialPlayerResponse;
          const ts = (pr && pr.captions && pr.captions.playerCaptionsTracklistRenderer && pr.captions.playerCaptionsTracklistRenderer.captionTracks) || [];
          if (!ts.length) return "";
          const zh = t => /^(zh|yue|nan|hak)/i.test(t.languageCode || "");
          const own = t => t.kind !== "asr";
          const t = ts.find(x => zh(x) && own(x)) || ts.find(own) || ts.find(zh) || ts[0];
          const r = await fetch(t.baseUrl + (t.baseUrl.includes("fmt=") ? "" : "&fmt=json3"), { credentials: "include" });
          if (!r.ok) return "";
          const j = await r.json();
          const out = [];
          for (const e of (j.events || [])) {
            if (!e.segs) continue;
            const s = e.segs.map(x => x.utf8 || "").join("").replace(/\\s*\\n\\s*/g, " ").trim();
            if (s) out.push([(e.tStartMs || 0) / 1000, s]);
          }
          return JSON.stringify(out);
        } catch (e) { return ""; }
        """
        guard let r = try? await web.callAsyncJavaScript(js, contentWorld: .page) as? String, !r.isEmpty,
              let d = r.data(using: .utf8), let rows = try? JSONSerialization.jsonObject(with: d) as? [[Any]], !rows.isEmpty else { return nil }
        var lines: [String] = []
        for row in rows {
            guard row.count == 2, let t = (row[0] as? NSNumber)?.doubleValue, let s = row[1] as? String else { continue }
            let m = Int(t) / 60, sec = t - Double(m * 60)
            lines.append(String(format: "[%02d:%05.2f]", m, sec) + s)
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// (lower is better: timed first, then the nearest length)
    private static func score(_ h: LyricHit, _ len: Double) -> Double {
        let d = len > 0 && (h.duration ?? 0) > 0 ? abs((h.duration ?? 0) - len) : 60
        return (h.timedRows != nil ? 0 : 1000) + min(d, 999)
    }

    /// a video's name (and channel) → what to search for: the name without "Official MV" and the like, then each part
    /// of it, with and without the singer (as the computer version)
    static func queries(_ title: String, _ artist: String, _ music: Bool) -> [String] {
        func re(_ s: String, _ p: String) -> String { s.replacingOccurrences(of: p, with: " ", options: .regularExpression) }
        let singer = re(artist, #"(?i)\s*-\s*topic$|vevo$|官方頻道|official( channel)?|頻道"#).trimmingCharacters(in: .whitespaces)
        var s = title
        for junk in [#"(?i)official\s*(music\s*)?(video|mv|audio|lyric(s)?\s*video)"#, #"(?i)\b(mv|m/v|hd|4k|lyrics?|audio|live)\b"#,
                     #"官方(完整版)?|完整版|動態歌詞|歌詞版|字幕版|高音質|MV"#, #"(?i)\bfeat\.?.*$"#, #"\([^)]*\)"#, #"（[^）]*）"#] {
            s = re(s, junk)
        }
        let parts = s.components(separatedBy: CharacterSet(charactersIn: "-–—/|｜【】[]「」『』《》"))
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'"))) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        if music && !singer.isEmpty { out.append(title + " " + singer) }
        let whole = parts.joined(separator: " ")
        if !singer.isEmpty && !whole.contains(singer) { out.append(whole + " " + singer) }
        out.append(whole)
        for p in parts.sorted(by: { $0.count > $1.count }) {
            if !singer.isEmpty && !p.contains(singer) { out.append(p + " " + singer) }
            out.append(p)
        }
        var seen = Set<String>()
        return Array(out.map { $0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .prefix(8))
    }

    /// (in the page: what's playing, a few times a second)
    private static let script = """
    (function(){
      if (window.__ffYt) return; window.__ffYt = true;
      function tick(){
        try {
          var v = document.querySelector('video');
          var m = navigator.mediaSession && navigator.mediaSession.metadata;
          var u = new URL(location.href);
          var music = location.hostname.indexOf('music.') === 0;
          var id = u.searchParams.get('v') || '';
          var title = (m && m.title) || '';
          var artist = (m && m.artist) || '';
          if (!title && id) title = document.title.replace(/\\s*-\\s*YouTube( Music)?\\s*$/, '');
          var ad = !!document.querySelector('.ad-showing, .ad-interrupting');
          window.webkit.messageHandlers.ff.postMessage({id: id, title: title, artist: artist,
            t: v ? v.currentTime : 0, d: (v && isFinite(v.duration)) ? v.duration : 0,
            paused: v ? v.paused : true, rate: v ? v.playbackRate : 1, music: music, ad: ad});
        } catch (e) {}
      }
      setInterval(tick, 300);
    })();
    """
}

/// the page's reports (kept apart: the content controller holds on to it)
private final class YtMessages: NSObject, WKScriptMessageHandler {
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let d = m.body as? [String: Any] else { return }
        let x = YtTick(d)
        Task { @MainActor in YtPlayer.shared.got(x) }
    }
}

/// links: YouTube's own pages stay here; "open the app" links (youtube://…) go nowhere; a link for a new window
/// opens here
private final class YtNav: NSObject, WKNavigationDelegate, WKUIDelegate {
    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction) async -> WKNavigationActionPolicy {
        let s = a.request.url?.scheme?.lowercased() ?? ""
        return s == "http" || s == "https" || s == "about" || s == "blob" || s == "data" ? .allow : .cancel
    }

    func webViewWebContentProcessDidTerminate(_ w: WKWebView) {
        Task { @MainActor in YtPlayer.shared.pageLost() }
    }

    func webView(_ w: WKWebView, createWebViewWith c: WKWebViewConfiguration, for a: WKNavigationAction, windowFeatures f: WKWindowFeatures) -> WKWebView? {
        if a.targetFrame == nil, let u = a.request.url { w.load(URLRequest(url: u)) }
        return nil
    }
}

/// the YouTube browser itself (the one kept by YtPlayer: the song goes on while the window changes size)
private struct YtWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView { YtPlayer.shared.webView() }
    func updateUIView(_ v: WKWebView, context: Context) {}
}

// MARK: - its window

/// YouTube's own window over the app (and over the lyrics bar): the whole screen, or only the small card takes
/// touches
enum YtOverlay {
    /// the small card's place in the window
    static var cardFrame: CGRect = .zero
    static func setCard(_ r: CGRect) -> Bool { if cardFrame != r { cardFrame = r }; return true }
    private static var window: UIWindow?
    private static weak var appWindow: UIWindow?

    @MainActor static func install() {
        guard window == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
        appWindow = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        let w = PassWindow(windowScene: scene)
        let host = UIHostingController(rootView: YtHost().environmentObject(Store.shared))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.windowLevel = .normal + 2
        w.backgroundColor = .clear
        w.overrideUserInterfaceStyle = .dark
        w.isHidden = false
        window = w
    }

    /// (back in the app: the window over the app again)
    @MainActor static func reshow() {
        guard let w = window else { return }
        if let scene = w.windowScene, scene.activationState != .unattached {
            w.windowLevel = .normal + 2
            w.isHidden = false
        }
        w.rootViewController?.view.setNeedsLayout()
    }

    /// the whole screen: typing goes to YouTube's window; else back to the app's
    @MainActor static func takeKeys(_ on: Bool) {
        if on { window?.makeKey() } else { appWindow?.makeKey() }
    }

    private final class PassWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            let yt = YtPlayer.shared
            guard yt.open else { return nil }
            if yt.expanded || rootViewController?.presentedViewController != nil { return super.hitTest(point, with: event) }
            guard YtOverlay.cardFrame.contains(point) else { return nil }
            return super.hitTest(point, with: event)
        }
    }
}

/// the whole screen (a bar at the top: 收起, YouTube / YouTube Music, back, 歌詞, close) or the small card in a
/// corner (the video, and under it: play / pause, 歌詞, the whole screen, close). The card can be dragged.
struct YtHost: View {
    @ObservedObject private var yt = YtPlayer.shared
    @AppStorage(AppTheme.key) private var theme = AppTheme.night.rawValue
    @AppStorage(YtPlayer.siteKey) private var site = 0
    @Environment(\.horizontalSizeClass) private var hSize
    /// how far the card's been moved from its corner; remembered
    @AppStorage("ytCardX") private var cx = 0.0
    @AppStorage("ytCardY") private var cy = 0.0
    @State private var drag: CGSize = .zero
    /// 選歌詞 (找歌詞: LRCLIB, your own lyrics, the 歌詞 folder)
    @State private var picking = false

    private let barH = 52.0
    private let ctlH = 44.0

    var body: some View {
        let _ = AppTheme.sync(theme)
        let _ = yt.redraw
        GeometryReader { geo in
            let W = max(geo.size.width, 1), H = geo.size.height
            let webH = max(200, H - barH)
            let cardW = hSize == .regular ? 320.0 : 240.0
            let s = yt.expanded ? 1.0 : cardW / W
            let videoH = (W * 9 / 16) * s
            let clipH = yt.expanded ? webH : videoH
            let cardH = videoH + ctlH
            // (the card's corner: bottom right, above the tab bar and the lyrics bar; kept inside the window)
            let baseX = W - cardW - 12, baseY = H - cardH - (hSize == .compact ? 120 : 70)
            let x = min(W - cardW - 4, max(4, baseX + cx + drag.width))
            let y = min(H - cardH - 4, max(4, baseY + cy + drag.height))
            // (where the card is in the window, for its touches: worked out here each time it's drawn, not measured
            // afterwards, which could be left wrong after the app was away)
            let g = geo.frame(in: .global).origin
            let _ = YtOverlay.setCard(CGRect(x: g.x + x, y: g.y + y, width: cardW, height: cardH))
            ZStack(alignment: .topLeading) {
                if yt.open && yt.expanded {
                    T.bg.ignoresSafeArea()
                    topBar.frame(width: W, height: barH)
                }
                VStack(spacing: 0) {
                    YtWebView()
                        .frame(width: W, height: webH)
                        .scaleEffect(s, anchor: .topLeading)
                        .offset(y: yt.expanded ? 0 : -yt.headerHeight * s)
                        .frame(width: W * s, height: clipH, alignment: .topLeading)
                        .clipped()
                        .overlay {
                            // (the card: a tap on the video makes it big again)
                            if !yt.expanded { Color.white.opacity(0.001).onTapGesture { yt.expand() } }
                        }
                    if !yt.expanded { cardControls(baseX: baseX, baseY: baseY, W: W, H: H, cardW: cardW, cardH: cardH).frame(width: cardW, height: ctlH) }
                }
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: yt.expanded ? 0 : 12))
                .overlay(RoundedRectangle(cornerRadius: yt.expanded ? 0 : 12).stroke(yt.expanded ? Color.clear : T.fnEdge, lineWidth: 1.5))
                .shadow(color: .black.opacity(yt.expanded ? 0 : 0.5), radius: 10, y: 4)
                .offset(x: yt.expanded ? 0 : x, y: yt.expanded ? barH : y)
                .opacity(yt.open ? 1 : 0)
                .allowsHitTesting(yt.open)
            }
        }
        .sheet(isPresented: $picking) {
            NavigationStack { LyricsPage(inSheet: true) }
                .environmentObject(Store.shared)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
        .id(theme)
        .fontDesign((AppTheme(rawValue: theme) ?? .night).fontDesign)
        .preferredColorScheme(.dark)
        .tint(AppTint.accent)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { yt.collapse() } label: {
                Label(tr("收起"), systemImage: "chevron.down").labelStyle(.iconOnly).font(.system(size: 20, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(tr("收起"))
            Button { yt.back() } label: {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).frame(width: 32, height: 36)
            }
            .disabled(!yt.canBack).opacity(yt.canBack ? 1 : 0.35)
            .accessibilityLabel(tr("上一頁"))
            Picker("", selection: Binding(get: { site }, set: { v in site = v; yt.load(v) })) {
                Text("YouTube").tag(0)
                Text("YouTube Music").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            Spacer(minLength: 0)
            Button { picking = true } label: {
                Image(systemName: "text.badge.checkmark").font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel(tr("選歌詞"))
            Button { yt.showLyrics() } label: {
                Image(systemName: "music.note.list").font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel(tr("歌詞"))
            Button { yt.close() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 36, height: 36)
            }
            .accessibilityLabel(tr("關閉 YouTube"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(T.btnInk)
        .padding(.horizontal, 10)
        .background(T.fn.opacity(0.9))
    }

    private func cardControls(baseX: Double, baseY: Double, W: Double, H: Double, cardW: Double, cardH: Double) -> some View {
        HStack(spacing: 0) {
            ctl(yt.playing ? "pause.fill" : "play.fill", yt.playing ? tr("暫停") : tr("播放")) { yt.togglePause() }
            ctl("music.note.list", tr("歌詞")) { LyricsBridge.showInConvert() }
            ctl("arrow.up.left.and.arrow.down.right", tr("放大")) { yt.expand() }
            ctl("xmark", tr("關閉 YouTube")) { yt.close() }
        }
        .foregroundStyle(T.btnInk)
        .background(T.fn)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 6)
            .onChanged { drag = $0.translation }
            .onEnded { t in
                // (kept where it was let go, inside the window)
                let nx = min(W - cardW - 4, max(4, baseX + cx + t.translation.width))
                let ny = min(H - cardH - 4, max(4, baseY + cy + t.translation.height))
                cx = nx - baseX; cy = ny - baseY; drag = .zero
            })
    }

    private func ctl(_ icon: String, _ label: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 音樂: YouTube in the app, and the song it's playing
struct YtMusicSection: View {
    @ObservedObject private var yt = YtPlayer.shared
    @State private var picking = false
    var body: some View {
        Section {
            Button { YtPlayer.shared.show() } label: { Label(tr("YouTube"), systemImage: "play.rectangle") }
            if yt.open, let n = yt.now {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.title).ffFont(.headline).lineLimit(2)
                        if !n.artist.isEmpty { Text(n.artist).ffFont(.subheadline).foregroundStyle(T.muted).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    Button { yt.togglePause() } label: {
                        Image(systemName: yt.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 36))
                    }
                    .buttonStyle(.plain).foregroundStyle(T.btnInk)
                    .accessibilityLabel(yt.playing ? tr("暫停") : tr("播放"))
                }
                Button { LyricsBridge.showInConvert() } label: { Label(tr("歌詞"), systemImage: "music.note.list") }
                Button { picking = true } label: { Label(tr("選歌詞"), systemImage: "text.badge.checkmark") }
            }
        } footer: {
            Text(tr("在 App 裡開 YouTube 或 YouTube Music。找到歌以後按收起，影片會縮成角落的小窗，歌詞在 轉換 → 歌詞 跟著歌走。離開 App 的時候歌會停。"))
                .ffFont(.footnote)
        }
        .sheet(isPresented: $picking) {
            NavigationStack { LyricsPage(inSheet: true) }
                .environmentObject(Store.shared)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
    }
}
