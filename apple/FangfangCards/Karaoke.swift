import SwiftUI
import Combine

// 卡拉 OK: the whole screen the song's lyrics. The line being sung lit and large, the others dim; the lines move up
// by themselves as the song goes (no scrolling). Tap the screen for the controls: close, Aa (size, font, colours,
// readings), play / pause, 對時.

enum KaraokeSettings {
    static let sizeKey = "karaokeSize"
    static let fontKey = "karaokeFont"
    static let coloursKey = "karaokeColours"
    static let readingsKey = "karaokeReadings"
}

/// one line, made once per song (and again when the colours, readings or language change)
struct KaraokeLine {
    let text: AttributedString
    let reading: AttributedString?
}

@MainActor
enum KaraokeLines {
    /// the song's lines: in the tone colours (or plain), with their readings when asked for
    static func make(_ lines: [String], colours: Bool, readings: Bool) -> [KaraokeLine] {
        let store = Store.shared
        let sys = colours ? ToneColors.system : 0
        // (the song's own language when it's tagged with one: 歌的語言)
        let l = SongLanguage.shared.lang(LyricsBridge.shared.song, store)
        if l == 0, let d = store.dict {
            let e = ConvertEngine(dict: d)
            // (the readings picked for this song in its lyrics)
            e.songKey = LyricsBridge.shared.song.map { SongLanguage.songKey($0.trackName, $0.artistName) }
            let place = UserDefaults.standard.object(forKey: "place") as? Int ?? -1
            let rom = min(max(UserDefaults.standard.integer(forKey: "rom"), 0), 3)
            return lines.map { line in
                let items = e.convert(line).items
                let tones = d.convItemTones(items, place)
                func build(_ mode: Int) -> AttributedString {
                    var out = AttributedString()
                    for p in e.pieces(items, mode: mode, rom: rom, place: place) {
                        var t = p.text
                        if t.hasPrefix(" ") { out += AttributedString(" "); t.removeFirst() }
                        if sys != 0, let i = p.item, i >= 0, let tt = tones[i] {
                            out += mode == 0 ? d.hanToneText(t, tones: tt.tones, system: sys, base: T.glyph)
                                             : d.toneText(tt.tokens, mode == 2 ? 3 : rom, place, tones: tt.tones, system: sys)
                        } else {
                            out += AttributedString(t)
                        }
                    }
                    return out
                }
                return KaraokeLine(text: build(0), reading: readings ? build(rom == 3 ? 2 : 1) : nil)
            }
        }
        if (1...4).contains(l), let z = SongLanguage.shared.dict(l, store) {
            let romIndex = min(max(store.zhRom, 0), 1)
            return lines.map { line in
                let ps = z.convertPieces(line)
                let han = sys != 0 ? z.sentenceHan(ps, store.zhPlace, base: T.glyph, colours: sys) : AttributedString(line)
                return KaraokeLine(text: han, reading: readings ? z.sentence(ps, romIndex, store.zhPlace, colours: sys) : nil)
            }
        }
        // (瑞典語, or the dictionary not read yet: the words as they are)
        return lines.map { KaraokeLine(text: AttributedString($0), reading: nil) }
    }
}

struct KaraokeView: View {
    @ObservedObject private var lyrics = LyricsBridge.shared
    @ObservedObject private var songs = SongPlayer.shared
    @ObservedObject private var songLangs = SongLanguage.shared
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @AppStorage(KaraokeSettings.sizeKey) private var size = 1.0
    @AppStorage(KaraokeSettings.fontKey) private var fontStyle = 0
    @AppStorage(KaraokeSettings.coloursKey) private var colours = true
    @AppStorage(KaraokeSettings.readingsKey) private var readings = false
    /// the line being sung (only when it changes: not the word, the whole page isn't redrawn a dozen times a second)
    @State private var current = -1
    /// the last line sung, kept lit dimly through the music between lines
    @State private var last = -1
    @State private var controls = true
    @State private var hideJob: Task<Void, Never>?
    @State private var settings = false
    @State private var lines: [KaraokeLine] = []

    var body: some View {
        let big: CGFloat = (hSize == .regular ? 46 : 30) * size
        let small: CGFloat = (hSize == .regular ? 30 : 20) * size
        let font = DictFont.font(big, weight: .bold, style: fontStyle) ?? .system(size: big, weight: .bold)
        let rfont = DictFont.font(big * 0.5, weight: .medium, style: fontStyle) ?? .system(size: big * 0.5, weight: .medium)
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: (hSize == .regular ? 26 : 18) * size) {
                        // (room above the first line and below the last, so every line can sit in the middle)
                        Color.clear.frame(height: 320)
                        ForEach(lines.indices, id: \.self) { i in
                            let on = i == current
                            // (one size for every line, the others made smaller by scaling: the change between them
                            // glides instead of jumping)
                            VStack(spacing: 4 * size) {
                                Text(lines[i].text).font(font)
                                if let r = lines[i].reading { Text(r).font(rfont).foregroundStyle(T.muted) }
                            }
                            .foregroundStyle(colours ? T.glyph : (on ? T.glyph : T.muted))
                            .multilineTextAlignment(.center)
                            .scaleEffect(on ? 1 : small / big)
                            .opacity(on ? 1 : (i == last && current < 0 ? 0.75 : 0.38))
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .id(i)
                        }
                        Color.clear.frame(height: 420)
                    }
                    .animation(.easeInOut(duration: 0.45), value: current)
                }
                .scrollDisabled(true)
                .onReceive(LyricsBeat.shared.$line.removeDuplicates()) { l in
                    current = l
                    if l >= 0 { last = l }
                    guard last >= 0 else { return }
                    withAnimation(.easeInOut(duration: 0.6)) { proxy.scrollTo(last, anchor: UnitPoint(x: 0.5, y: 0.42)) }
                }
                .onChange(of: lyrics.version) { _, _ in
                    current = -1; last = -1
                    rebuild()
                    proxy.scrollTo(0, anchor: .center)
                }
                .onChange(of: size) { _, _ in
                    if last >= 0 { proxy.scrollTo(last, anchor: UnitPoint(x: 0.5, y: 0.42)) }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { show() }

            if controls { controlsView.transition(.opacity) }
        }
        .appBackground()
        .statusBarHidden(true)
        .onChange(of: colours) { _, _ in rebuild() }
        .onChange(of: readings) { _, _ in rebuild() }
        .onChange(of: store.lang) { _, _ in rebuild() }
        .onChange(of: songLangs.tags) { _, _ in rebuild() }
        .onChange(of: songLangs.dicts.count) { _, _ in rebuild() }
        .sheet(isPresented: $settings) {
            KaraokeSettingsView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
                .tint(AppTint.accent)
        }
        .onAppear {
            lyrics.karaoke = true
            UIApplication.shared.isIdleTimerDisabled = true
            rebuild()
            current = LyricsBeat.shared.line
            last = current
            show()
        }
        .onDisappear {
            lyrics.karaoke = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func rebuild() {
        lines = KaraokeLines.make(lyrics.lineTexts, colours: colours, readings: readings)
    }

    /// close, the song's name and Aa on top; play / pause and 對時 at the bottom (gone again after a few seconds)
    private var controlsView: some View {
        VStack {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 40, height: 40) }
                    .softButton()
                    .accessibilityLabel(tr("關閉"))
                if let h = lyrics.song {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(h.trackName).ffFont(.subheadline, .semibold).lineLimit(1)
                        Text(h.artistName).ffFont(.caption).foregroundStyle(T.muted).lineLimit(1)
                    }
                }
                Spacer()
                Button { settings = true; show() } label: {
                    Image(systemName: "textformat.size").font(.system(size: 18)).frame(width: 40, height: 40)
                }
                .softButton()
                .accessibilityLabel(tr("字的大小、字體"))
                if songs.active {
                    Button { songs.togglePause(); show() } label: {
                        Image(systemName: songs.playing ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 40, height: 40)
                    }
                    .softButton()
                    .accessibilityLabel(songs.playing ? tr("暫停") : tr("播放"))
                }
            }
            .padding(.horizontal).padding(.top, 8)
            Spacer()
            LyricsNudge()
                .padding(.horizontal).padding(.bottom, 12)
                .simultaneousGesture(TapGesture().onEnded { show() })
        }
    }

    /// the controls shown, then hidden after 4 seconds without a tap (not while the settings are open)
    private func show() {
        withAnimation(.easeInOut(duration: 0.25)) { controls = true }
        hideJob?.cancel()
        hideJob = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled && !settings { withAnimation(.easeInOut(duration: 0.4)) { controls = false } }
        }
    }
}

/// 卡拉 OK's Aa: the size, the font, the colours, the readings
private struct KaraokeSettingsView: View {
    @AppStorage(KaraokeSettings.sizeKey) private var size = 1.0
    @AppStorage(KaraokeSettings.fontKey) private var fontStyle = 0
    @AppStorage(KaraokeSettings.coloursKey) private var colours = true
    @AppStorage(KaraokeSettings.readingsKey) private var readings = false
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("字的大小")) {
                    HStack(spacing: 12) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(T.muted)
                        Slider(value: $size, in: 0.6...1.8, step: 0.05)
                        Image(systemName: "textformat.size.larger").foregroundStyle(T.muted)
                    }
                    Text("\(Int((size * 100).rounded()))%").ffFont(.caption).foregroundStyle(T.muted).monospacedDigit()
                }
                Section(tr("字體")) {
                    Picker(tr("字體"), selection: $fontStyle) {
                        ForEach(DictFont.names.indices, id: \.self) { i in
                            Text(trs(DictFont.names[i])).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle(tr("聲調顏色"), isOn: $colours)
                    if !store.isSv { Toggle(tr("讀音（在每一句下面）"), isOn: $readings) }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("卡拉 OK"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
