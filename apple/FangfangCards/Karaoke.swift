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
    /// 跳跳球: a ball hopping onto each syllable of the line being sung, `ballLeadKey` seconds ahead of it
    static let ballKey = "lyricsBall"
    static let ballLeadKey = "lyricsBallLead"
    /// the 字 being sung grows (as on the lyrics page)
    static let swellKey = "karaokeSwell"
}

/// one line, made once per song (and again when the colours, readings or language change)
struct KaraokeLine {
    let text: AttributedString
    let reading: AttributedString?
    /// the line in syllables (a 漢字 each; a word in letters each, with the space after it), for the ball
    let pieces: [AttributedString]
    /// how many letters each piece has (0: punctuation, spaces)
    let letters: [Int]

    init(text: AttributedString, reading: AttributedString?) {
        self.text = text
        self.reading = reading
        var ps: [AttributedString] = []
        let chars = text.characters
        var run: AttributedString.Index? = nil
        var i = chars.startIndex
        while i < chars.endIndex {
            let c = chars[i]
            let next = chars.index(after: i)
            let han = c.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x3FFFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }
            if han {
                if let r = run { ps.append(AttributedString(text[r..<i])); run = nil }
                ps.append(AttributedString(text[i..<next]))
            } else if c == " " {
                if let r = run { ps.append(AttributedString(text[r..<next])); run = nil }
                else if !ps.isEmpty { ps[ps.count - 1] += AttributedString(text[i..<next]) }
                else { ps.append(AttributedString(text[i..<next])) }
            } else if run == nil {
                run = i
            }
            i = next
        }
        if let r = run { ps.append(AttributedString(text[r..<chars.endIndex])) }
        pieces = ps
        letters = ps.map { String($0.characters).filter { $0.isLetter || $0.isNumber }.count }
    }
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
    @ObservedObject private var yt = YtPlayer.shared
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
    @AppStorage(KaraokeSettings.ballKey) private var ball = false
    @AppStorage(KaraokeSettings.ballLeadKey) private var ballLead = 0.3
    @AppStorage(KaraokeSettings.swellKey) private var swell = false
    /// (跳跳球) where each syllable of the line being sung is
    @State private var pieceFrames: [Int: CGRect] = [:]

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
                            lineView(i, font: font, rfont: rfont, big: big, small: small)
                        }
                        Color.clear.frame(height: 420)
                    }
                    .animation(.easeInOut(duration: 0.45), value: current)
                }
                .scrollDisabled(true)
                .onReceive(LyricsBeat.shared.$line.removeDuplicates()) { l in
                    if l != current { pieceFrames = [:] }
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

    /// one line: the one being sung full size (in its syllables for 跳跳球 / 字變大), the others smaller and dim.
    /// (one size for every line, the others made smaller by scaling: the change between them glides instead of
    /// jumping. Its own function: all of it in the page's body was too much for the compiler)
    @ViewBuilder private func lineView(_ i: Int, font: Font, rfont: Font, big: CGFloat, small: CGFloat) -> some View {
        let on = i == current
        let dim: Double = on ? 1 : (i == last && current < 0 ? 0.75 : 0.38)
        let ink: Color = colours ? T.glyph : (on ? T.glyph : T.muted)
        VStack(spacing: 4 * size) {
            lineText(i, on: on, font: font, big: big)
            if let r = lines[i].reading { Text(r).font(rfont).foregroundStyle(T.muted) }
        }
        .foregroundStyle(ink)
        .multilineTextAlignment(.center)
        .scaleEffect(on ? 1 : small / big)
        .opacity(dim)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .id(i)
    }

    @ViewBuilder private func lineText(_ i: Int, on: Bool, font: Font, big: CGFloat) -> some View {
        if (ball || swell) && on {
            // (跳跳球 / 字變大: the line in its syllables, each where the ball can find it, the one being sung growing;
            // room above for the ball)
            KaraokePieces(line: i, pieces: lines[i].pieces, letters: lines[i].letters, font: font, swell: swell) { k, r in
                pieceFrames[k] = r
            }
            .padding(.top, ball ? big * 0.6 : 0)
            .overlay { if ball { KaraokeBall(line: i, letters: lines[i].letters, frames: pieceFrames, lead: ballLead, size: big) } }
            .coordinateSpace(.named("karaokeLine"))
        } else {
            Text(lines[i].text).font(font)
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
                // (歌的語言: the lyrics read in another language)
                if let h = lyrics.song {
                    SongLanguageMenu(song: h)
                        .foregroundStyle(T.btnInk)
                        .simultaneousGesture(TapGesture().onEnded { show() })
                }
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
                } else if yt.following {
                    // (YouTube in the app)
                    Button { yt.togglePause(); show() } label: {
                        Image(systemName: yt.playing ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 40, height: 40)
                    }
                    .softButton()
                    .accessibilityLabel(yt.playing ? tr("暫停") : tr("播放"))
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
    @AppStorage(KaraokeSettings.ballKey) private var ball = false
    @AppStorage(KaraokeSettings.ballLeadKey) private var ballLead = 0.3
    @AppStorage(KaraokeSettings.swellKey) private var swell = false
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
                    Toggle(tr("正在唱的字變大"), isOn: $swell)
                }
                Section {
                    Toggle(tr("跳跳球"), isOn: $ball)
                    if ball {
                        Stepper(value: $ballLead, in: 0...3, step: 0.05) {
                            Text(tr("提早 \(String(format: "%.2f", ballLead)) 秒"))
                        }
                    }
                } footer: {
                    Text(tr("一顆球跳到下一個要唱的字上面，比唱的時候早這麼多秒。")).ffFont(.footnote)
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

/// pieces in rows, wrapping like text, each row in the middle
struct CenterWrap: Layout {
    var spacing: CGFloat = 0
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let w = rows.map(\.width).max() ?? 0
        let h = rows.reduce(0) { $0 + $1.height }
        return CGSize(width: min(w, proposal.width ?? w), height: h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in arrange(bounds.width, subviews) {
            var x = bounds.minX + max(0, (bounds.width - r.width) / 2)
            for i in r.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (r.height - s.height)), proposal: .unspecified)
                x += s.width + spacing
            }
            y += r.height
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        var cur: [Int] = [], w: CGFloat = 0, h: CGFloat = 0
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !cur.isEmpty && w + spacing + s.width > width {
                rows.append((cur, w, h)); cur = []; w = 0; h = 0
            }
            w += (cur.isEmpty ? 0 : spacing) + s.width
            h = max(h, s.height)
            cur.append(i)
        }
        if !cur.isEmpty { rows.append((cur, w, h)) }
        return rows
    }
}

/// 跳跳球: a ball bouncing from syllable to syllable of the line being sung, landing on each `lead` seconds before
/// it's sung; squashed a little as it lands and takes off
struct KaraokeBall: View {
    let line: Int
    let letters: [Int]
    let frames: [Int: CGRect]
    let lead: Double
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { _ in
            let spotNow = spot()
            Canvas { ctx, _ in
                guard let p = spotNow else { return }
                let r = size * 0.16
                let air = 4 * p.f * (1 - p.f)
                let squash = (1 - min(1, air * 3)) * 0.28
                let w = r * (1 + squash), h = r * (1 - squash)
                let cy = p.y - h - 3
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.7, y: cy - r * 1.7, width: r * 3.4, height: r * 3.4)), with: .color(T.btnEdge.opacity(0.35)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - w, y: cy - h, width: w * 2, height: h * 2)), with: .color(T.btnInk))
            }
        }
        .allowsHitTesting(false)
    }

    /// where the ball is now: (x, the top of the syllables it's between, how far between them 0…1)
    @MainActor private func spot() -> (x: CGFloat, y: CGFloat, f: CGFloat)? {
        let syl = letters.indices.filter { letters[$0] > 0 }
        guard !syl.isEmpty else { return nil }
        let total = Double(letters.reduce(0, +))
        var frac = 0.0
        if let p = LyricsBridge.shared.placeAhead(lead) {
            frac = p.line > line ? 1 : (p.line < line ? 0 : p.frac)
        }
        let at = frac * total
        // (each syllable starts after the letters before it)
        var starts: [Double] = []
        var acc = 0.0
        for k in syl { starts.append(acc); acc += Double(letters[k]) }
        var s = 0
        for j in starts.indices where starts[j] <= at { s = j }
        guard let a = frames[syl[s]] else { return nil }
        if s == syl.count - 1 || at >= total { return (a.midX, a.minY, 0) }
        guard let b = frames[syl[s + 1]] else { return (a.midX, a.minY, 0) }
        let f = CGFloat(min(1, max(0, (at - starts[s]) / max(0.001, starts[s + 1] - starts[s]))))
        let hop = size * 0.5
        return (a.midX + (b.midX - a.midX) * f, a.minY + (b.minY - a.minY) * f - hop * 4 * f * (1 - f), f)
    }
}

/// the line being sung in its syllables (for 跳跳球 and 字變大): each piece's place told back; with swell, the
/// syllable being sung grows, as on the lyrics page
struct KaraokePieces: View {
    let line: Int
    let pieces: [AttributedString]
    let letters: [Int]
    let font: Font
    let swell: Bool
    let frame: (Int, CGRect) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { _ in
            let cur = swell ? sungPiece() : -1
            CenterWrap {
                ForEach(pieces.indices, id: \.self) { k in
                    Text(pieces[k]).font(font)
                        .scaleEffect(k == cur ? 1.3 : 1, anchor: .bottom)
                        .brightness(k == cur ? 0.12 : 0)
                        .zIndex(k == cur ? 1 : 0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.62), value: cur)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("karaokeLine")) } action: { frame(k, $0) }
                }
            }
        }
    }

    /// the syllable being sung now (-1: none)
    @MainActor private func sungPiece() -> Int {
        guard let p = LyricsBridge.shared.placeAhead(0), p.line == line else { return -1 }
        let total = Double(letters.reduce(0, +))
        guard total > 0 else { return -1 }
        let at = p.frac * total
        var acc = 0.0, cur = -1
        for k in letters.indices where letters[k] > 0 {
            if acc <= at { cur = k }
            acc += Double(letters[k])
        }
        return p.frac >= 0.999 ? -1 : cur
    }
}
