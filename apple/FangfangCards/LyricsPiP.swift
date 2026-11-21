import AVKit
import SwiftUI
import UIKit

// 浮動歌詞: the line being sung (its reading under it) and the next one, in a small window that stays over
// every other app: iOS's Picture in Picture (子母畫面), the only window an iPhone / iPad app may keep over other apps.
// No extra identifier or extension is needed: it's the app's own. The lyrics are drawn as pictures, a few a
// second, and shown as a "video" in it; its ▶︎ / ❚❚ plays and pauses the song, ±15 s jumps. (Words can't be clicked
// in it: iOS doesn't let a Picture in Picture window be touched except its own buttons.) On a Mac the iPad app gets
// it only when macOS gives iPad apps Picture in Picture; if not, the button says so.

enum LyricsPiPSettings {
    /// the letters' size (points) and the reading on or off
    static let sizeKey = "lyricsPiPSize"
    static let readingKey = "lyricsPiPReading"
}

@MainActor
final class LyricsPiP: NSObject, ObservableObject {
    static let shared = LyricsPiP()
    @Published private(set) var active = false
    @Published var message: String?

    private var layer: AVSampleBufferDisplayLayer?
    private var holder: UIView?
    private var controller: AVPictureInPictureController?
    private var timer: Timer?
    private var lastKey = ""
    private var lastLine = -1

    static var supported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    /// open or close it
    func toggle() {
        if active || controller?.isPictureInPictureActive == true { stop(); return }
        start()
    }

    func start() {
        guard Self.supported else {
            message = tr("這台裝置不能用子母畫面（Picture in Picture），所以沒辦法有浮動歌詞。")
            return
        }
        // (an audio session that plays along with the music, not over it: Picture in Picture needs one)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if controller == nil { build() }
        lastKey = ""
        render(force: true)
        // (iOS starts it only once the layer has a picture: a moment later)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, let c = self.controller else { return }
            if c.isPictureInPicturePossible { c.startPictureInPicture() }
            else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if c.isPictureInPicturePossible { c.startPictureInPicture() }
                    else { self.message = tr("子母畫面還沒準備好，再按一次試試看。") }
                }
            }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render(force: false) }
        }
    }

    func stop() {
        controller?.stopPictureInPicture()
        timer?.invalidate(); timer = nil
        active = false
    }

    private func build() {
        let l = AVSampleBufferDisplayLayer()
        l.videoGravity = .resizeAspect
        // (the layer has to be in a window for iOS to take it into Picture in Picture: a tiny, almost clear spot)
        let v = UIView(frame: CGRect(x: 0, y: 0, width: 2, height: 2))
        v.isUserInteractionEnabled = false
        v.alpha = 0.02
        l.frame = v.bounds
        v.layer.addSublayer(l)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let win = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first
        win?.addSubview(v)
        holder = v
        layer = l
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: l, playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: source)
        c.delegate = self
        controller = c
    }

    // MARK: the picture

    /// the lines now, drawn when something changed (the line, how far into it, the play state, the settings)
    private func render(force: Bool) {
        guard let layer else { return }
        let bridge = LyricsBridge.shared
        let beat = LyricsBeat.shared
        let lines = bridge.lineTexts
        let line = beat.line
        let size = UserDefaults.standard.object(forKey: LyricsPiPSettings.sizeKey) as? Double ?? 30
        let reading = UserDefaults.standard.object(forKey: LyricsPiPSettings.readingKey) as? Bool ?? true
        let frac = (beat.frac * 20).rounded() / 20
        let key = "\(line)|\(frac)|\(size)|\(reading)|\(SongPlayer.shared.playing)|\(YtPlayer.shared.playing)|\(lines.count)"
        if !force && key == lastKey { return }
        lastKey = key
        let text = lines.indices.contains(line) ? lines[line] : ""
        let next = bridge.nextLine
        if line != lastLine { lastLine = line; cached = nil }
        let made = cached ?? KaraokeLines.make([text, next], colours: true, readings: reading)
        cached = made
        let view = LyricsPiPView(line: made.first, next: made.count > 1 ? made[1] : nil, frac: frac, size: size,
                                 empty: lines.isEmpty ? (SongPlayer.shared.song?.trackName ?? tr("放一首歌")) : nil)
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let img = r.cgImage, let buf = Self.pixelBuffer(img), let sample = Self.sample(buf) else { return }
        if layer.status == .failed { layer.flush() }
        layer.enqueue(sample)
    }
    private var cached: [KaraokeLine]?

    private static func pixelBuffer(_ img: CGImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true,
                     kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, img.width, img.height, kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess,
              let p = pb else { return nil }
        CVPixelBufferLockBaseAddress(p, [])
        defer { CVPixelBufferUnlockBaseAddress(p, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(p), width: img.width, height: img.height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(p), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return p
    }

    private static func sample(_ pb: CVPixelBuffer) -> CMSampleBuffer? {
        var fmt: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt) == noErr,
              let f = fmt else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: f, sampleTiming: &timing,
                                                       sampleBufferOut: &sb) == noErr, let s = sb else { return nil }
        // (shown at once: these aren't frames of a video with times)
        if let arr = CMSampleBufferGetSampleAttachmentsArray(s, createIfNecessary: true), CFArrayGetCount(arr) > 0 {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        return s
    }
}

extension LyricsPiP: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.active = true }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
        Task { @MainActor in self.active = false; self.timer?.invalidate(); self.timer = nil }
    }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor in self.active = false; self.message = tr("子母畫面打不開：\(error.localizedDescription)") }
    }
}

extension LyricsPiP: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in
            let p = SongPlayer.shared
            // (YouTube in the app, when it's the one the lyrics follow)
            if !p.active && YtPlayer.shared.following {
                let y = YtPlayer.shared
                if playing && !y.playing { y.play() } else if !playing && y.playing { y.pause() }
            } else if playing && !p.playing { p.resume() } else if !playing && p.playing { p.pause() }
            self.lastKey = ""
        }
    }
    /// (a song without an end it knows: "live", so iOS shows no bar of its own)
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ c: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ c: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { SongPlayer.shared.active || !YtPlayer.shared.following ? !SongPlayer.shared.playing : !YtPlayer.shared.playing }
    }
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    nonisolated func pictureInPictureController(_ c: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            let p = SongPlayer.shared
            if !p.active && YtPlayer.shared.following { YtPlayer.shared.seek(YtPlayer.shared.position + skipInterval.seconds) }
            else if let t = p.position { p.seek(t + skipInterval.seconds) }
            completionHandler()
        }
    }
}

/// what Picture in Picture shows: the line being sung (lit up to where it's sung), its reading, and the next line
private struct LyricsPiPView: View {
    let line: KaraokeLine?
    let next: KaraokeLine?
    let frac: Double
    let size: Double
    let empty: String?

    var body: some View {
        VStack(alignment: .leading, spacing: size * 0.18) {
            if let empty {
                Text(empty).font(.system(size: size * 0.7, weight: .semibold)).foregroundStyle(T.muted).lineLimit(1)
            } else {
                if let l = line, !l.text.characters.isEmpty {
                    Text(l.text).font(.system(size: size, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.6)
                        .mask(alignment: .leading) {
                            // (the part already sung bright, the rest a little dimmer)
                            GeometryReader { g in
                                HStack(spacing: 0) {
                                    Rectangle().frame(width: g.size.width * max(0.02, frac))
                                    Rectangle().opacity(0.55)
                                }
                            }
                        }
                    if let r = l.reading { Text(r).font(.system(size: size * 0.55)).lineLimit(1).minimumScaleFactor(0.6) }
                } else {
                    Text("♪").font(.system(size: size)).foregroundStyle(T.muted)
                }
                if let n = next, !n.text.characters.isEmpty {
                    Text(n.text).font(.system(size: size * 0.66)).lineLimit(1).minimumScaleFactor(0.6).opacity(0.5)
                }
            }
        }
        .padding(.horizontal, size * 0.6).padding(.vertical, size * 0.4)
        .frame(width: size * 17, alignment: .leading)
        .frame(minHeight: size * 3.4)
        .background(T.bg)
        .environment(\.colorScheme, .dark)
    }
}

/// 浮動歌詞's place in the 歌詞 page: the button, the letters' size, the reading
struct LyricsPiPSection: View {
    @ObservedObject private var pip = LyricsPiP.shared
    @AppStorage(LyricsPiPSettings.sizeKey) private var size = 30.0
    @AppStorage(LyricsPiPSettings.readingKey) private var reading = true

    var body: some View {
        Section {
            Button { pip.toggle() } label: {
                Label(pip.active ? tr("關掉浮動歌詞") : tr("浮動歌詞（子母畫面）"), systemImage: pip.active ? "pip.exit" : "pip.enter")
            }
            HStack {
                Text(tr("字的大小"))
                Slider(value: $size, in: 20...48, step: 1)
                Text("\(Int(size))").monospacedDigit().foregroundStyle(T.muted)
            }
            Toggle(tr("浮動歌詞的讀音"), isOn: $reading)
        } footer: {
            Text(pip.message ?? tr("正在唱的那一句和讀音，在一個小視窗裡，蓋在其他 App 上面（iOS 的子母畫面）。可以拖到別的地方、縮放；▶︎／❚❚ 放或停歌，±15 秒往前往後跳。小視窗裡的詞不能點：要看意思回到 App。"))
                .ffFont(.footnote)
        }
    }
}
