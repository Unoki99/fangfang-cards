import Foundation
import AVFoundation
import SwiftUI

/// Plays MOE recordings from the 方方 website; every clip played once is kept for offline use.
@MainActor
final class Player: ObservableObject {
    static let shared = Player()

    @Published private(set) var playing: String?
    @Published private(set) var failed: String?
    private var player: AVAudioPlayer?
    private var token = 0

    private var cacheDir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func play(_ path: String) {
        // (客語: no voice to read it)
        if path.isEmpty || (Lang.isHak && path.hasPrefix("tts:")) { return }
        player?.stop()
        token += 1
        let my = token
        playing = path
        failed = nil
        // 華語: the device's own voice
        AudioMix.wordStarts()
        if path.hasPrefix("tts:") {
            ZhSpeech.shared.onFinish = { [weak self] in if my == self?.token { self?.playing = nil }; AudioMix.wordEnds() }
            ZhSpeech.shared.speak(String(path.dropFirst(4)))
            return
        }
        ZhSpeech.shared.stop()
        Task {
            do {
                let data = try await self.load(path)
                guard my == self.token else { return }
                let p = try AVAudioPlayer(data: data)
                let v = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.8
                p.volume = Float(v)
                self.player = p
                p.play()
                let length = p.duration
                try? await Task.sleep(nanoseconds: UInt64((length + 0.1) * 1_000_000_000))
                if my == self.token { self.playing = nil; AudioMix.wordEnds() }
            } catch {
                AudioMix.wordEnds()
                guard my == self.token else { return }
                self.playing = nil
                self.failed = path
            }
        }
    }

    private func load(_ path: String) async throws -> Data {
        // (a sentence's sound kept from the radio)
        if path.hasPrefix("clip:") { return try Data(contentsOf: RadioClip.url(path)) }
        // a whole web address (粵語 recordings on Wikimedia Commons) or a file of the 台語 recordings
        let web = path.hasPrefix("https://")
        let name = web ? "web-" + String(path.split(separator: "/").last ?? "") : path.replacingOccurrences(of: "/", with: "_")
        let file = cacheDir.appendingPathComponent(String(name.suffix(200)))
        if let d = try? Data(contentsOf: file), !d.isEmpty { return d }
        let url: URL
        if web {
            guard let u = URL(string: path) ?? URL(string: path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? path) else { throw URLError(.badURL) }
            url = u
        } else {
            let base = UserDefaults.standard.string(forKey: "audioBase") ?? Audio.defaultBase
            let b = base.hasSuffix("/") ? base : base + "/"
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            guard let u = URL(string: b + encoded) else { throw URLError(.badURL) }
            url = u
        }
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { throw URLError(.fileDoesNotExist) }
        try? data.write(to: file, options: .atomic)
        return data
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheDir)
    }
}

/// Round ▶ button in the 方方 style; turns red briefly if the recording can't be found.
struct PlayButton: View {
    let path: String
    var size: CGFloat = 34
    /// on a swipe card: frosted instead of Liquid Glass, which would stretch while the card is dragged
    var onCard = false
    @ObservedObject private var player = Player.shared
    private let glassOn = false   // the Liquid Glass look was taken out

    /// 客語: no device voice reads it (only the word's own recording, when there is one)
    private var silent: Bool { path.isEmpty || (Lang.isHak && path.hasPrefix("tts:")) }

    var body: some View {
        if silent { EmptyView() } else { button }
    }

    @ViewBuilder private var button: some View {
        let on = player.playing == path
        let bad = player.failed == path
        let icon = Image(systemName: "play.fill")
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(T.glyph)
            .frame(width: size, height: size)
        Button {
            player.play(path)
        } label: {
            if onCard && glassOn {
                icon
                    .background(Circle().fill(bad ? T.rustEdge.opacity(0.8) : (on ? T.btnEdge.opacity(0.9) : T.btnEdge.opacity(0.35))))
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.08), T.btnEdge.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1.5))
            } else {
                icon.glassSurface(Circle(),
                              tint: bad ? T.rustEdge.opacity(0.8) : (on ? T.btnEdge.opacity(0.9) : T.btnEdge.opacity(0.4)),
                              interactive: true,
                              fallback: bad ? T.rust : (on ? T.btnEdge : T.btn.opacity(0.6)),
                              edge: bad ? T.rustEdge : T.btnEdge)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("播放"))
    }
}


/// A word read out loud while 音樂 plays an Apple Music song. That song plays outside the app (iOS's music player), so
/// the app's own sound took the speaker from it: the song stopped, and play didn't start it again. Now a word's sound
/// mixes with the song, which goes quieter for it and back up after.
@MainActor
enum AudioMix {
    private static var token = 0
    private static var mixing = false

    /// (before a word's sound)
    static func wordStarts() {
        token += 1
        guard SongPlayer.shared.active, SongPlayer.shared.mode == .full else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        mixing = true
    }

    /// (a word's sound done: the song back up a moment later, unless another word starts first)
    static func wordEnds(after seconds: Double = 0.3) {
        guard mixing else { return }
        let my = token
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard my == token, mixing else { return }
            mixing = false
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
    }
}
