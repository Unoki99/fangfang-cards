import SwiftUI
import PencilKit
import UIKit.UIGestureRecognizerSubclass
import CoreText

// 不熟 → 手寫練習 (華語): pick the characters (不熟的漢字, an HSK / TOCFL character level, the ones you know, or
// your own), then write each one with a finger or Apple Pencil while you see it, its reading and meaning.
// 描字 puts the character under the grid in 楷體, and a potion shows how closely the writing follows it.
// A round left half way carries on the next time.

// MARK: - 楷體

/// Apple's 楷體 (Kaiti TC, with Kaiti SC for the simplified characters TC doesn't have). iPhone and iPad don't
/// come with it but can download it from Apple (once, needs the internet); until then the system font is used.
enum Kaiti {
    static let tc = "STKaitiTC-Regular"
    static let sc = "STKaitiSC-Regular"
    /// 手寫練習's font (設定 or the menu at the top of 手寫練習): 楷體, 文楷 or 芫荽
    static let styleKey = "handwritingFont"
    /// the fonts: the name shown, the font's name, the file in the app (nil = Apple's 楷體, downloaded the first time)
    static let styles: [(name: String, ps: String, file: String?)] = [
        ("楷體", tc, nil),
        ("文楷", "LXGWWenKaiTC-Regular", "wenkai"),       // 霞鶩文楷 TC (OFL)
        ("芫荽", "Iansui-Regular", "iansui"),             // 芫荽 Iansui, for learning Taiwan's characters (OFL)
    ]
    static var style: Int { min(max(UserDefaults.standard.integer(forKey: styleKey), 0), styles.count - 1) }

    /// the fonts in the app, made usable (once): done in code, not in Info.plist
    private static let registerOnce: Void = {
        for s in styles {
            guard let f = s.file, UIFont(name: s.ps, size: 12) == nil,
                  let u = Bundle.main.url(forResource: f, withExtension: "ttf")
                    ?? Bundle.main.url(forResource: f, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
        }
    }()
    static func register() { _ = registerOnce }

    private static var appleReady: Bool { UIFont(name: tc, size: 12) != nil || UIFont(name: sc, size: 12) != nil }
    /// the chosen font can be used now
    static var ready: Bool {
        register()
        let s = styles[style]
        return s.file == nil ? appleReady : UIFont(name: s.ps, size: 12) != nil
    }

    /// Apple's 楷體 (the first choice, and what the others fall back on): downloads it if it isn't there yet;
    /// done(true) when the chosen font can be used
    static func prepare(_ done: @escaping (Bool) -> Void) {
        register()
        if UIFont(name: tc, size: 12) != nil && UIFont(name: sc, size: 12) != nil { done(ready); return }
        // a font in the app: no need to wait for the download
        if styles[style].file != nil && ready { done(true) }
        let descs = [tc, sc].map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, 0) } as CFArray
        var finished = false
        CTFontDescriptorMatchFontDescriptorsWithProgressHandler(descs, nil) { state, _ in
            if (state == .didFinish || state == .didFailWithError) && !finished {
                finished = true
                DispatchQueue.main.async { done(ready) }
            }
            return true
        }
    }

    /// the chosen font for SwiftUI's Text (by its name: SwiftUI doesn't keep a UIFont's fallbacks, and with them it
    /// could end up drawing in another font than the canvas does)
    static func swiftUI(_ size: CGFloat) -> Font {
        register()
        let chosen = styles[style].ps
        let names = [chosen] + ["LXGWWenKaiTC-Regular", tc, sc].filter { $0 != chosen }
        guard let n = names.first(where: { UIFont(name: $0, size: size) != nil }) else { return .system(size: size) }
        return .custom(n, fixedSize: size)
    }

    /// the chosen font at a size; what it doesn't have comes from 文楷, then 楷體 (TC, then SC), then the system font
    static func font(_ size: CGFloat) -> UIFont {
        register()
        let chosen = styles[style].ps
        var names = [chosen]
        for n in ["LXGWWenKaiTC-Regular", tc, sc] where n != chosen { names.append(n) }
        let have = names.filter { UIFont(name: $0, size: size) != nil }
        guard let first = have.first, let main = UIFont(name: first, size: size) else { return .systemFont(ofSize: size) }
        let cascade = have.dropFirst().map { UIFontDescriptor(name: $0, size: size) }
        return UIFont(descriptor: main.fontDescriptor.addingAttributes([.cascadeList: Array(cascade)]), size: size)
    }

    /// a character drawn in 楷體, filling a square (centred on the character's own shape)
    static func image(_ ch: String, side: CGFloat, scale: CGFloat, color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { r in
            let ctx = r.cgContext
            let attr = NSAttributedString(string: ch, attributes: [.font: font(side * 0.8), .foregroundColor: color])
            let line = CTLineCreateWithAttributedString(attr)
            ctx.saveGState()
            ctx.translateBy(x: 0, y: side)
            ctx.scaleBy(x: 1, y: -1)
            let b = CTLineGetImageBounds(line, ctx)
            ctx.textPosition = CGPoint(x: (side - b.width) / 2 - b.minX, y: (side - b.height) / 2 - b.minY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
    }
}

// MARK: - how closely the writing follows the character

enum TraceScore {
    static let n = 64

    /// which cells of an n × n grid have something drawn in them
    static func cells(_ img: UIImage) -> [Bool] {
        guard let cg = img.cgImage else { return [] }
        var buf = [UInt8](repeating: 0, count: n * n * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard ok else { return [] }
        return (0..<(n * n)).map { buf[$0 * 4 + 3] > 50 }
    }

    /// the cells near a drawn cell too (a little room either way)
    static func widen(_ g: [Bool], by r: Int) -> [Bool] {
        var out = g
        for y in 0..<n { for x in 0..<n where g[y * n + x] {
            for dy in -r...r { for dx in -r...r {
                let yy = y + dy, xx = x + dx
                if yy >= 0, yy < n, xx >= 0, xx < n { out[yy * n + xx] = true }
            } }
        } }
        return out
    }

    /// 0–1: how much of the character is covered, and how much of the writing is on the character
    static func score(target: [Bool], drawing: PKDrawing, side: CGFloat) -> Double {
        guard target.count == n * n, side > 0, !drawing.strokes.isEmpty else { return 0 }
        let ink = cells(drawing.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: CGFloat(n) / side))
        guard ink.count == n * n else { return 0 }
        let wideInk = widen(ink, by: 2), wideTarget = widen(target, by: 2)
        var t = 0, covered = 0, i = 0, on = 0
        for k in 0..<(n * n) {
            if target[k] { t += 1; if wideInk[k] { covered += 1 } }
            if ink[k] { i += 1; if wideTarget[k] { on += 1 } }
        }
        guard t > 0, i > 0 else { return 0 }
        let recall = Double(covered) / Double(t), precision = Double(on) / Double(i)
        return recall + precision > 0 ? 2 * recall * precision / (recall + precision) : 0
    }
}

// MARK: - the practice

struct HandwritingView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    /// the characters of this round (nil = choosing them)
    @State private var list: [String]?
    @State private var idx = 0
    @State private var resumed = false

    private struct Saved: Codable { let chars: [String]; let idx: Int }

    var body: some View {
        NavigationStack {
            Group {
                if let list {
                    HandwritingPad(chars: list, idx: $idx) { dismiss() }
                } else {
                    HandwritingSetup { chars in
                        idx = 0
                        list = chars
                        save()
                    }
                }
            }
            .overlay(alignment: .top) { ResumedNote(shown: $resumed).padding(.top, 4) }
            .appBackground()
            .navigationTitle("手寫練習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("結束")
                }
                if list != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { PracticeSave.clear("handwriting", zh: true); list = nil } label: {
                            Label("選字", systemImage: "square.grid.3x3")
                        }
                    }
                }
            }
        }
        .onAppear {
            guard list == nil, let s = PracticeSave.load(Saved.self, "handwriting", zh: true, scope: 0),
                  !s.chars.isEmpty, s.idx < s.chars.count else { return }
            list = s.chars; idx = s.idx; resumed = true
        }
        .onChange(of: idx) { save() }
    }

    private func save() {
        guard let list, idx < list.count else { PracticeSave.clear("handwriting", zh: true); return }
        PracticeSave.save(Saved(chars: list, idx: idx), "handwriting", zh: true, scope: 0)
    }
}

/// choosing what to write: a list, then the characters of it (all of them to start with)
private struct HandwritingSetup: View {
    @EnvironmentObject var store: Store
    let start: ([String]) -> Void
    @AppStorage("handwritingList") private var listID = "unknown"
    @AppStorage("handwritingShuffle") private var shuffle = false
    @AppStorage("handwritingOwn") private var own = ""
    @State private var off: Set<String> = []

    struct Source: Identifiable { let id: String; let name: String; let chars: [String] }

    private var sources: [Source] {
        let sets = store.zhCharSets()
        var out = [Source(id: "unknown", name: "不熟的漢字", chars: sets.all.filter { sets.unknown.contains($0) })]
        for t in store.topics where t.id > Lang.charTopicBase {
            out.append(Source(id: "level\(t.id)", name: t.name, chars: store.levelCards(t.id).compactMap { Lang.charOf($0.k) }))
        }
        out.append(Source(id: "known", name: "認識的漢字", chars: sets.all.filter { sets.known.contains($0) }))
        var seen = Set<String>()
        let mine = own.unicodeScalars.filter { Zhuyin.isHan($0) }.map { String($0) }.filter { seen.insert($0).inserted }
        out.append(Source(id: "own", name: "自己選的字", chars: mine))
        return out
    }

    var body: some View {
        let all = sources
        let src = all.first { $0.id == listID } ?? all[0]
        let picked = src.chars.filter { !off.contains($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // start first, at the top (the list of characters can be long)
                Button {
                    start(shuffle ? picked.shuffled() : picked)
                } label: {
                    Label("開始寫（\(picked.count) 個字）", systemImage: "pencil.and.scribble").frame(maxWidth: .infinity, minHeight: 44)
                }
                .prominentButton(T.greenEdge)
                .disabled(picked.isEmpty)
                Toggle("打亂順序", isOn: $shuffle)
                Picker("要寫的字", selection: $listID) {
                    ForEach(all) { s in Text(s.id == "own" ? s.name : "\(s.name)（\(s.chars.count)）").tag(s.id) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                .onChange(of: listID) { off = [] }
                if src.id == "own" {
                    TextField("打你要寫的字，例如：龍鳳書寫", text: $own)
                        .scaledFont(20)
                        .autocorrectionDisabled()
                        .clearButton($own)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                }
                if src.chars.isEmpty {
                    Text(src.id == "unknown" ? "還沒有不熟的漢字。" : (src.id == "own" ? "在上面打字。" : "這裡沒有字。"))
                        .ffFont(.footnote).foregroundStyle(T.muted)
                } else {
                    HStack(spacing: 10) {
                        Text("點字可以不選它。選了 \(picked.count)／\(src.chars.count) 個").ffFont(.footnote).foregroundStyle(T.muted)
                        Spacer()
                        Button("全選") { off = [] }.ffFont(.footnote, .semibold)
                        Button("全不選") { off = Set(src.chars) }.ffFont(.footnote, .semibold)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                        ForEach(src.chars, id: \.self) { ch in
                            let on = !off.contains(ch)
                            Button { if on { off.insert(ch) } else { off.remove(ch) } } label: {
                                Text(ch).scaledFont(24)
                                    .foregroundStyle(on ? T.blueInk : T.muted.opacity(0.5))
                                    .frame(width: 46, height: 46)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(on ? T.blue.opacity(0.6) : T.fn.opacity(0.4)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? T.blueEdge : T.fnEdge, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(ch)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }
}

/// writing the characters one by one
private struct HandwritingPad: View {
    let chars: [String]
    @Binding var idx: Int
    let finished: () -> Void
    @EnvironmentObject var store: Store
    /// changes when the pad is cleared (next character, or 清掉)
    @State private var clearCount = 0
    /// a faint character under the grid to trace
    @AppStorage("handwritingTrace") private var trace = false
    @State private var kaiti = Kaiti.ready
    @State private var downloading = false
    @State private var side: CGFloat = 0
    @State private var target: [Bool] = []
    @State private var score = 0.0
    @State private var drawn = false
    @State private var lastDrawing = PKDrawing()
    /// how big the writing square is (points); 格子大小 changes it, the shadow follows
    @AppStorage("handwritingPadSize") private var padSize = 380.0
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(Kaiti.styleKey) private var fontStyle = 0
    /// 華語's meanings in English (設定 → 主要解釋)
    @AppStorage(ZhMeaning.key) private var english = false
    @State private var penOpen = false
    /// the biggest the square can be on this screen (set from the space there is)
    @State private var maxPad: CGFloat = 520
    /// the character whose words are shown (tapping it at the top)
    @State private var wordsFor: WordsRef?
    @Environment(\.horizontalSizeClass) private var hSize
    static let sideWidth: CGFloat = 330
    /// room for the words beside the square (iPad, not in a narrow split view)
    private func isWide(_ size: CGSize) -> Bool { hSize == .regular && size.width >= 800 }
    struct WordsRef: Identifiable { let ch: String; var id: String { ch } }

    var body: some View {
        let ch = chars[min(idx, chars.count - 1)]
        GeometryReader { g in
            let w = isWide(g.size)
            HStack(alignment: .top, spacing: 0) {
                // iPad: the words with the character beside the square, to learn it in context
                if w { sideWords(ch).frame(width: Self.sideWidth).padding([.leading, .vertical]) }
                pad(ch, wide: w)
            }
            .onAppear { maxPad = fit(g.size) }
            .onChange(of: g.size) { maxPad = fit(g.size) }
            .onChange(of: hSize) { maxPad = fit(g.size) }
        }
        .sheet(item: $wordsFor) { w in
            CharWordsSheet(ch: w.ch).environmentObject(store)
        }
    }

    /// the biggest square that leaves room for everything else (wide and tall enough)
    private func fit(_ size: CGSize) -> CGFloat {
        let side = isWide(size) ? Self.sideWidth + 16 : 0
        return max(200, min(size.width - 32 - side, size.height - (trace ? 360 : 320)))
    }

    private func sideWords(_ ch: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("有「\(ch)」的詞").ffFont(.headline).foregroundStyle(T.glyph)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 4)
                Spacer(minLength: 8)
                // 中 / 英 (華語's meanings), standing next to the two rows of buttons
                HStack(alignment: .top, spacing: 6) {
                    if store.isZh { MeaningSwitch(vertical: true).frame(maxHeight: .infinity) }
                    RomButton(stacked: true)
                }
                .fixedSize(horizontal: false, vertical: true)     // (the switch as tall as the two rows)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 2)
            CharWordsList(ch: ch)
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var padSide: CGFloat { min(max(180, CGFloat(padSize)), maxPad) }

    private func pad(_ ch: String, wide: Bool) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                PotionBar(value: Double(idx + 1) / Double(chars.count), height: 20, showMarks: false, label: "手寫進度")
                Text("\(idx + 1)／\(chars.count)").latFont(14).monospacedDigit().foregroundStyle(T.muted)
            }
            header(ch, wide: wide)
            canvas(ch)
            if trace {
                HStack(spacing: 10) {
                    Text("描得像").ffFont(.footnote, .semibold).foregroundStyle(T.muted)
                    PotionBar(value: score, height: 22, showMarks: false, label: "描得像")
                    Text(drawn ? "\(Int((score * 100).rounded()))%" : "—").latFont(15).monospacedDigit().foregroundStyle(T.glyph)
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
            if downloading && Kaiti.styles[Kaiti.style].file == nil {
                Text("下載楷體中…（第一次要網路）").ffFont(.caption).foregroundStyle(T.muted)
            } else if !kaiti && trace && Kaiti.styles[Kaiti.style].file == nil {
                Text("楷體下載不了，先用系統的字。").ffFont(.caption).foregroundStyle(T.muted)
            }
            controls
            // 格子大小: the writing square, bigger or smaller (the shadow follows)
            HStack(spacing: 10) {
                Image(systemName: "square.resize.down").foregroundStyle(T.muted)
                Slider(value: Binding(get: { Double(padSide) }, set: { padSize = $0 }), in: 180...Double(max(181, maxPad)))
                    .tint(T.greenEdge)
                    .accessibilityLabel("格子大小")
                Image(systemName: "square.resize.up").foregroundStyle(T.muted)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: max(640, padSide + 32))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    // 字體: 楷體, 文楷 or 芫荽 (the character at the top and the one to trace)
                    Menu {
                        Picker("字體", selection: $fontStyle) {
                            ForEach(Kaiti.styles.indices, id: \.self) { Text(Kaiti.styles[$0].name).tag($0) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Label("字體", systemImage: "textformat")
                    }
                    .accessibilityLabel("字體：" + Kaiti.styles[Kaiti.style].name)
                    // 筆: which pen, how thick, 彩色
                    Button { penOpen = true } label: { Label("筆", systemImage: "pencil.tip") }
                        .popover(isPresented: $penOpen) {
                            PenSettings(compact: true).presentationCompactAdaptation(.popover)
                        }
                    // 彩色: the writing in the rainbow instead of the dark ink
                    Toggle(isOn: $rainbow) { Label("彩色", systemImage: "paintpalette") }
                        .toggleStyle(.button)
                    Toggle(isOn: $trace) { Label("描字", systemImage: "character.cursor.ibeam") }
                        .toggleStyle(.button)
                }
            }
        }
        .onAppear {
            if !Kaiti.ready {
                downloading = true
                Kaiti.prepare { ok in kaiti = ok; downloading = false; makeTarget(ch) }
            }
        }
        // another font: the character, the one to trace and the measuring follow it
        .onChange(of: fontStyle) {
            kaiti = Kaiti.ready
            if !kaiti { downloading = true; Kaiti.prepare { ok in kaiti = ok; downloading = false; makeTarget(ch) } }
            makeTarget(ch)
        }
        .onChange(of: idx) { score = 0; drawn = false; makeTarget(chars[min(idx, chars.count - 1)]) }
        // the square really got another size (not just laid out again): start the character over
        .onChange(of: side) { old, new in
            makeTarget(ch)
            if old > 0 && abs(old - new) > 2 { clearCount += 1; score = 0; drawn = false }
        }
        // 描字 turned on after writing: measure what's there
        .onChange(of: trace) { if trace { score = TraceScore.score(target: target, drawing: lastDrawing, side: side) } }
    }

    /// what the character is like: reading, meaning, recording
    private func info(_ ch: String) -> (reading: AttributedString, defs: [(p: String, t: String)], audio: String?) {
        // English: the dictionary's English for the character (when it has one)
        if english, store.isZh, let d = store.zh, let e = d.entry(char: ch, zy: ""), e.en != nil {
            let reading = store.card(for: Lang.charKey(ch)).map { store.cardRom($0, 0, -1) } ?? d.reading(e.syl(Lang.zhPlace), Lang.zhRom)
            return (reading, e.enList.prefix(2).map { ("", $0) }, store.card(for: Lang.charKey(ch))?.audio ?? "tts:" + ch)
        }
        if let c = store.card(for: Lang.charKey(ch)) {
            return (store.cardRom(c, 0, -1), c.d.prefix(2).map { ($0.p, $0.t) }, c.audio)
        }
        if let d = store.zh, let e = d.entry(char: ch, zy: "") {
            return (d.reading(e.syl(Lang.zhPlace), Lang.zhRom), e.senses.prefix(2).map { ("", $0.text) }, "tts:" + ch)
        }
        return (AttributedString(""), [], "tts:" + ch)
    }

    private func header(_ ch: String, wide: Bool) -> some View {
        let i = info(ch)
        return HStack(alignment: .center, spacing: 16) {
            // tap: the words with this character (to learn it in context); on an iPad they're beside the square
            if wide {
                Text(ch).font(Kaiti.swiftUI(64)).foregroundStyle(T.blueInk).id("\(kaiti)\(fontStyle)")
            } else {
                Button { wordsFor = WordsRef(ch: ch) } label: {
                    VStack(spacing: 0) {
                        Text(ch).font(Kaiti.swiftUI(64)).foregroundStyle(T.blueInk).id("\(kaiti)\(fontStyle)")
                        Label("看詞", systemImage: "text.magnifyingglass").ffFont(.caption2, .semibold).foregroundStyle(T.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SwellButtonStyle())
                .accessibilityLabel("看有「\(ch)」的詞")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(i.reading).latFont(24).toneGlow().foregroundStyle(T.greenInk)
                ForEach(Array(i.defs.enumerated()), id: \.offset) { n, d in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if i.defs.count > 1 { NumBadge(n: n + 1) }
                        if !d.p.isEmpty { Chip(text: d.p) }
                        Text(d.t).ffFont(.subheadline).foregroundStyle(T.glyph).lineLimit(2)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                if let a = i.audio { PlayButton(path: a, size: 40) }
                // 華語: the meanings in 華語 or English (the same switch as 設定 → 主要解釋, so the words follow it too)
                // 我會了: the character is known (its card 熟悉); tap again: 不熟
                if store.card(for: Lang.charKey(ch)) != nil { KnowCharButton(ch: ch) }
            }
        }
    }


    private func canvas(_ ch: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.75))
            // 米字格: the guide lines
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                Path { p in
                    p.move(to: CGPoint(x: w / 2, y: 0)); p.addLine(to: CGPoint(x: w / 2, y: h))
                    p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                    p.move(to: .zero); p.addLine(to: CGPoint(x: w, y: h))
                    p.move(to: CGPoint(x: w, y: 0)); p.addLine(to: CGPoint(x: 0, y: h))
                }
                .stroke(T.fnEdge, style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
                .onAppear { side = w }
                .onChange(of: w) { side = w }
            }
            if trace && side > 0 {
                // the same picture the writing is measured against
                Image(uiImage: Kaiti.image(ch, side: side, scale: 2, color: UIColor(T.glyph)))
                    .resizable()
                    .opacity(0.16)
                    .allowsHitTesting(false)
                    .id("\(ch)\(kaiti)\(side)\(fontStyle)")
            }
            WritingPad(clearCount: clearCount) { d in
                lastDrawing = d
                drawn = !d.strokes.isEmpty
                if trace { score = TraceScore.score(target: target, drawing: d, side: side) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .frame(width: padSide, height: padSide)
        .accessibilityLabel("寫字的地方")
    }

    private func makeTarget(_ ch: String) {
        guard side > 0 else { return }
        target = TraceScore.cells(Kaiti.image(ch, side: CGFloat(TraceScore.n), scale: 1, color: .white))
        if trace && drawn { score = TraceScore.score(target: target, drawing: lastDrawing, side: side) }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { go(-1) } label: { Label("上一個", systemImage: "chevron.left").frame(maxWidth: .infinity, minHeight: 40) }
                .softButton()
                .disabled(idx == 0)
            Button { clearCount += 1; score = 0; drawn = false } label: {
                Label("清掉", systemImage: "eraser").frame(maxWidth: .infinity, minHeight: 40)
            }
            .softButton()
            Button { go(1) } label: {
                Label(idx + 1 >= chars.count ? "完成" : "下一個", systemImage: "chevron.right").frame(maxWidth: .infinity, minHeight: 40)
            }
            .prominentButton(T.greenEdge)
        }
    }

    private func go(_ d: Int) {
        if d > 0 && idx + 1 >= chars.count {
            PracticeSave.clear("handwriting", zh: true)
            finished()
            return
        }
        idx = min(max(idx + d, 0), chars.count - 1)
        clearCount += 1
    }
}

/// the ink of 手寫練習: always the dark ink of the original theme, or (彩色) a new rainbow colour for every stroke
/// (so the stroke order is easy to follow); and how much the Apple Pencil's pressure changes the thickness
enum HandInk {
    /// the pen (kept under its old name: 0–2 were 筆壓's 粗細不變 / 一般 / 很敏感)
    static let pressureKey = "handwritingPressureLevel"
    /// how thick, 0–1 (from each pen's thinnest to its thickest)
    static let sizeKey = "handwritingPenSize"
    static let sizeDefault = 0.4
    static let rainbowKey = "handwritingRainbow"
    /// 延遲: how many seconds after the pen the writing shows up (0 = right away)
    static let delayKey = "handwritingInkDelay"
    /// the dark ink (the same on every theme)
    static let dark = UIColor(red: 0x1a / 255, green: 0x1a / 255, blue: 0x1c / 255, alpha: 1)
    /// PencilKit's pens: the name, what it's like, the thinnest and thickest it's drawn here
    static let pens: [(name: String, about: String, type: PKInk.InkType, min: CGFloat, max: CGFloat)] = [
        ("簽字筆", "怎麼按都一樣粗", .monoline, 2, 14),
        ("原子筆", "按得越用力越粗", .pen, 2, 16),
        ("鋼筆", "粗細跟著筆壓和方向變最多", .fountainPen, 2, 16),
        ("鉛筆", "像鉛筆一樣有紋路，斜著寫會變寬", .pencil, 2, 14),
        ("麥克筆", "半透明的寬筆", .marker, 6, 30),
        ("蠟筆", "粗粗的蠟筆紋路", .crayon, 4, 26),
        ("水彩", "會暈開的水彩", .watercolor, 4, 26),
    ]
    static func pen(_ i: Int) -> Int { min(max(i, 0), pens.count - 1) }
    /// the width of a pen at a size (0–1)
    static func width(pen i: Int, size: Double) -> CGFloat {
        let p = pens[pen(i)]
        let w = p.min + (p.max - p.min) * CGFloat(min(max(size, 0), 1))
        let r = p.type.validWidthRange
        return min(max(w, r.lowerBound), r.upperBound)
    }
    /// the rainbow, in order: red, orange, yellow, green, teal, blue, purple, pink (the standard tone colours)
    static let rainbow: [UIColor] = [1, 2, 3, 4, 5, 6, 7, 0].map { col in
        let v = ToneColors.palette[col].shades[2]
        return UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    /// the pen for stroke number n (0 = the first)
    static func tool(stroke n: Int, rainbow on: Bool, pen i: Int, size: Double) -> PKInkingTool {
        let color = on ? rainbow[n % rainbow.count] : dark
        return PKInkingTool(pens[pen(i)].type, color: color, width: width(pen: i, size: size))
    }
}

/// 筆 and 粗細: in 設定 and behind the pen button at the top of 手寫練習
struct PenSettings: View {
    @AppStorage(HandInk.pressureKey) private var pen = 1
    @AppStorage(HandInk.sizeKey) private var size = HandInk.sizeDefault
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.delayKey) private var delay = 0.0
    /// in the pop-over (no Form around it)
    var compact = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                Text("筆").ffFont(.caption, .bold).foregroundStyle(T.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(HandInk.pens.indices, id: \.self) { i in
                        let on = HandInk.pen(pen) == i
                        Button { pen = i } label: {
                            Text(HandInk.pens[i].name).ffFont(.subheadline, on ? Font.Weight.bold : Font.Weight.regular)
                                .foregroundStyle(on ? T.greenInk : T.glyph)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(RoundedRectangle(cornerRadius: 10).fill(on ? T.green : T.fn))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? T.greenEdge : T.fnEdge, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Text(HandInk.pens[HandInk.pen(pen)].about).ffFont(.caption).foregroundStyle(T.muted)
                sizeRow
                preview
                delayRow
                Toggle("彩色筆跡（每一筆換一個顏色）", isOn: $rainbow).ffFont(.subheadline).tint(T.greenEdge)
            }
            .padding(18)
            .frame(width: 330)
        } else {
            Picker("筆", selection: $pen) {
                ForEach(HandInk.pens.indices, id: \.self) { Text(HandInk.pens[$0].name).tag($0) }
            }
            sizeRow
            preview
            delayRow
        }
    }

    /// 延遲: the writing shows up a moment after the pen
    private var delayRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("筆跡延遲").ffFont(.subheadline).foregroundStyle(T.glyph)
                Spacer()
                Text(delay < 0.025 ? "馬上出現" : String(format: "%.1f 秒", delay)).latFont(14).monospacedDigit().foregroundStyle(T.muted)
            }
            Slider(value: $delay, in: 0...1.5, step: 0.05).tint(T.greenEdge).accessibilityLabel("筆跡延遲")
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 10) {
            Text("粗細").ffFont(.subheadline).foregroundStyle(T.glyph)
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(T.muted)
            Slider(value: $size, in: 0...1).tint(T.greenEdge).accessibilityLabel("粗細")
            Image(systemName: "circle.fill").font(.system(size: 14)).foregroundStyle(T.muted)
        }
    }

    /// how a stroke of this pen looks, at this thickness
    private var preview: some View {
        let w = HandInk.width(pen: pen, size: size)
        let type = HandInk.pens[HandInk.pen(pen)].type
        return Canvas { ctx, sz in
            var p = Path()
            let n = 60
            for k in 0...n {
                let t = CGFloat(k) / CGFloat(n)
                let pt = CGPoint(x: 12 + t * (sz.width - 24), y: sz.height / 2 + sin(t * .pi * 2) * sz.height * 0.22)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            let ink = Color(rainbow ? HandInk.rainbow[0] : HandInk.dark)
            ctx.opacity = type == .marker ? 0.6 : (type == .watercolor ? 0.75 : 1)
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.96)))
        .accessibilityHidden(true)
    }
}

/// a PencilKit canvas: finger or Apple Pencil. The pen changes colour after each stroke in 彩色.
/// 延遲: the writing shows up a moment after the pen has been there (the canvas's own ink is then invisible, and
/// the ink is drawn a little later on top of it: first as a line following the pen, then PencilKit's own ink).
private struct WritingPad: UIViewRepresentable {
    let clearCount: Int
    let changed: (PKDrawing) -> Void
    @AppStorage(HandInk.pressureKey) private var level = 1
    @AppStorage(HandInk.sizeKey) private var size = HandInk.sizeDefault
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.delayKey) private var delay = 0.0

    func makeUIView(context: Context) -> PadHost {
        let host = PadHost()
        let v = host.canvas
        v.drawingPolicy = .anyInput
        v.backgroundColor = .clear
        v.isOpaque = false
        // (light, so PencilKit draws the colours as they are instead of turning them around for dark mode)
        v.overrideUserInterfaceStyle = .light
        v.isScrollEnabled = false
        let c = context.coordinator
        v.delegate = c
        c.host = host
        c.cleared = clearCount
        c.level = level; c.size = size; c.rainbow = rainbow; c.delay = delay
        host.later.delay = delay
        v.tool = c.tool(stroke: 0)
        // follows the pen (for 延遲), without getting in PencilKit's way
        let follow = PenFollower(target: nil, action: nil)
        follow.cancelsTouchesInView = false
        follow.delaysTouchesBegan = false
        follow.delaysTouchesEnded = false
        follow.delegate = c
        follow.began = { [weak c] p, t in c?.began(p, t) }
        follow.moved = { [weak c] p, t in c?.host?.later.add(p, t) }
        follow.ended = { [weak c] t in c?.host?.later.end(t) }
        v.addGestureRecognizer(follow)
        return host
    }

    func updateUIView(_ host: PadHost, context: Context) {
        let c = context.coordinator
        c.changed = changed
        let v = host.canvas
        if c.cleared != clearCount {
            c.cleared = clearCount
            v.drawing = PKDrawing()
            host.later.reset()
        }
        if c.level != level || c.rainbow != rainbow || c.size != size || c.delay != delay {
            let delayChanged = (c.delay > 0) != (delay > 0)
            c.level = level; c.rainbow = rainbow; c.size = size; c.delay = delay
            host.later.delay = delay
            v.tool = c.tool(stroke: v.drawing.strokes.count)
            // 延遲 on or off: the strokes already there in the right ink
            if delayChanged {
                v.drawing = delay > 0 ? c.hidden(v.drawing) : c.shown(v.drawing)
                host.later.reset()
                host.later.show(c.shown(v.drawing), upTo: v.drawing.strokes.count)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(changed) }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        weak var host: PadHost?
        var cleared = 0
        var changed: (PKDrawing) -> Void
        var level = 1
        var size = HandInk.sizeDefault
        var rainbow = false
        var delay = 0.0
        init(_ c: @escaping (PKDrawing) -> Void) { changed = c }

        func tool(stroke n: Int) -> PKInkingTool {
            let t = HandInk.tool(stroke: n, rainbow: rainbow, pen: level, size: size)
            // 延遲: the canvas's own ink can't be seen (the ink is drawn later, on top)
            return delay > 0 ? PKInkingTool(t.inkType, color: t.color.withAlphaComponent(0.02), width: t.width) : t
        }
        /// every stroke in its real colour
        func shown(_ d: PKDrawing) -> PKDrawing {
            PKDrawing(strokes: d.strokes.enumerated().map { i, s in
                var s = s
                s.ink = PKInk(s.ink.inkType, color: HandInk.tool(stroke: i, rainbow: rainbow, pen: level, size: size).color)
                return s
            })
        }
        func hidden(_ d: PKDrawing) -> PKDrawing {
            PKDrawing(strokes: d.strokes.map { s in
                var s = s
                s.ink = PKInk(s.ink.inkType, color: s.ink.color.withAlphaComponent(0.02))
                return s
            })
        }

        func began(_ p: CGPoint, _ t: TimeInterval) {
            guard delay > 0, let host else { return }
            let n = host.canvas.drawing.strokes.count + host.later.unfinished
            let tl = HandInk.tool(stroke: n, rainbow: rainbow, pen: level, size: size)
            host.later.begin(p, t, color: tl.color, width: tl.width, marker: tl.inkType == .marker)
        }

        func canvasViewDrawingDidChange(_ v: PKCanvasView) {
            let d = v.drawing
            // the next stroke's pen (彩色: the next colour; after 清掉 or undo: back to that stroke's colour)
            let want = tool(stroke: d.strokes.count)
            if let now = v.tool as? PKInkingTool, now.color != want.color || now.inkType != want.inkType || now.width != want.width { v.tool = want }
            let seen = delay > 0 ? shown(d) : d
            if delay > 0 { host?.later.strokes(seen) }
            DispatchQueue.main.async { self.changed(seen) }       // (not while SwiftUI is updating the view)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// the canvas with the late ink on top
final class PadHost: UIView {
    let canvas = PKCanvasView()
    let later = LateInk()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        addSubview(canvas)
        later.isUserInteractionEnabled = false
        later.backgroundColor = .clear
        later.isOpaque = false
        addSubview(later)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        later.frame = bounds
    }
}

/// watches the touches on the canvas (never takes them): where the pen is and when
final class PenFollower: UIGestureRecognizer {
    var began: ((CGPoint, TimeInterval) -> Void)?
    var moved: ((CGPoint, TimeInterval) -> Void)?
    var ended: ((TimeInterval) -> Void)?
    private weak var touch: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard touch == nil, let t = touches.first, let v = view else { return }
        touch = t
        began?(t.location(in: v), t.timestamp)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touch, touches.contains(t), let v = view else { return }
        for c in event.coalescedTouches(for: t) ?? [t] { moved?(c.location(in: v), c.timestamp) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touch, touches.contains(t) else { return }
        ended?(t.timestamp); touch = nil
        state = .failed
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let t = touch, touches.contains(t) else { return }
        ended?(t.timestamp); touch = nil
        state = .failed
    }
    override func reset() { touch = nil }
}

/// 延遲: draws the writing a moment late. A stroke being written (or just written) is a line that follows the pen
/// `delay` seconds behind; once it's all there it's swapped for PencilKit's own ink of that stroke.
final class LateInk: UIView {
    var delay = 0.0
    private struct Trail { var pts: [(CGPoint, TimeInterval)]; var color: UIColor; var width: CGFloat; var marker: Bool; var end: TimeInterval? }
    private var trails: [Trail] = []
    /// how many of the strokes are already drawn as ink (the image), and the strokes in their colours
    private var inked = 0
    private var all = PKDrawing()
    private var image: UIImage?
    private var link: CADisplayLink?

    var unfinished: Int { trails.count }

    func begin(_ p: CGPoint, _ t: TimeInterval, color: UIColor, width: CGFloat, marker: Bool) {
        trails.append(Trail(pts: [(p, t)], color: color, width: width, marker: marker, end: nil))
        run()
    }
    func add(_ p: CGPoint, _ t: TimeInterval) {
        guard !trails.isEmpty, trails[trails.count - 1].end == nil else { return }
        trails[trails.count - 1].pts.append((p, t))
    }
    func end(_ t: TimeInterval) {
        guard let i = trails.lastIndex(where: { $0.end == nil }) else { return }
        trails[i].end = t
    }
    /// the canvas's strokes changed (in their real colours)
    func strokes(_ d: PKDrawing) {
        // 清掉 or undo: start over from what's there
        if d.strokes.count < inked { inked = 0; trails.removeAll(); image = nil; all = d; show(d, upTo: d.strokes.count); return }
        all = d
        run()
    }
    func show(_ d: PKDrawing, upTo n: Int) {
        all = d
        inked = min(n, d.strokes.count)
        render()
        setNeedsDisplay()
    }
    func reset() {
        trails.removeAll(); inked = 0; all = PKDrawing(); image = nil
        setNeedsDisplay()
    }

    private func run() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
    }
    @objc private func tick() {
        let now = CACurrentMediaTime()
        // a stroke all there (and PencilKit has it): its real ink instead of the line
        while let f = trails.first, let e = f.end, e + delay <= now {
            if inked < all.strokes.count {
                trails.removeFirst()
                inked += 1
                render()
            } else if e + delay + 0.6 <= now {
                trails.removeFirst()        // a touch PencilKit didn't make a stroke of
            } else { break }
        }
        setNeedsDisplay()
        if trails.isEmpty && inked >= all.strokes.count { link?.invalidate(); link = nil }
    }
    private func render() {
        guard inked > 0, bounds.width > 0 else { image = nil; return }
        let d = PKDrawing(strokes: Array(all.strokes.prefix(inked)))
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = d.image(from: bounds, scale: window?.screen.scale ?? 2)
        }
        image = img
    }

    override func draw(_ rect: CGRect) {
        image?.draw(in: bounds)
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let shownUntil = CACurrentMediaTime() - delay
        for t in trails {
            let pts = t.pts.filter { $0.1 <= shownUntil }.map(\.0)
            guard let first = pts.first else { continue }
            ctx.setStrokeColor(t.color.withAlphaComponent(t.marker ? 0.6 : 1).cgColor)
            ctx.setLineWidth(t.width * (t.marker ? 1 : 0.8))
            ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.beginPath()
            ctx.move(to: first)
            if pts.count == 1 { ctx.addLine(to: CGPoint(x: first.x + 0.01, y: first.y)) }
            for p in pts.dropFirst() { ctx.addLine(to: p) }
            ctx.strokePath()
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        render(); setNeedsDisplay()
    }
}

/// 手寫練習: the words with a character, so it can be learned in context, each with 1–2 meanings
/// (in 華語 or English, as 設定 → 主要解釋 says).
/// 華語: the dictionary's words, the ones on the word lists (HSK / TOCFL) first, the easier levels first.
/// 台語: the cards' words, in the word list's order. Tap one to open it.
struct CharWordsList: View {
    let ch: String
    @EnvironmentObject var store: Store
    @State private var zhList: [Int]?
    @State private var openCard: Card?
    @State private var openZh: ZhKey?
    @State private var openChar: WordsRefID?
    struct WordsRefID: Identifiable { let id: String }

    private var dict: ZhDict? { store.isZh ? store.zh : nil }

    var body: some View {
        List {
            if let dict {
                if dict.charIndex[ch] != nil {
                    Section {
                        Button { openChar = WordsRefID(id: ch) } label: {
                            Label("「\(ch)」這個字", systemImage: "character.book.closed").foregroundStyle(T.glyph)
                        }
                    }
                    .listRowBackground(T.fn.opacity(0.7))
                }
                if let zhList {
                    Section(zhList.isEmpty ? "沒有找到有這個字的詞" : "有「\(ch)」的詞（\(zhList.count)）") {
                        ForEach(zhList, id: \.self) { i in
                            Button { openZh = ZhKey(k: dict.entries[i].k) } label: {
                                ZhWordRow(dict: dict, entry: dict.entries[i], meanings: 2).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(T.fn.opacity(0.7))
                } else {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            } else {
                let ws = store.cards.filter { Lang.charOf($0.k) == nil && $0.h.count > 1 && $0.h.contains(ch) }
                Section(ws.isEmpty ? "沒有找到有這個字的詞" : "有「\(ch)」的詞（\(ws.count)）") {
                    ForEach(ws, id: \.k) { c in
                        Button { openCard = c } label: { CharWordCardRow(card: c).contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                    }
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(item: $openCard) { CardSheet(card: $0).environmentObject(store) }
        .sheet(item: $openZh) { k in if let dict { ZhEntrySheet(dict: dict, key: k.k).environmentObject(store) } }
        .sheet(item: $openChar) { c in if let dict { ZhCharSheet(dict: dict, ch: c.id).environmentObject(store) } }
        .task(id: ch) {
            zhList = nil
            guard let d = dict else { return }
            let c = ch
            zhList = await Task.detached(priority: .userInitiated) { () -> [Int] in
                var listed: [(Int, Int)] = [], other: [Int] = []
                var seen = Set<String>()
                for (i, e) in d.entries.enumerated() where e.h.count > 1 && e.h.contains(c) {
                    guard seen.insert(e.h).inserted else { continue }
                    let lv = [e.hsk, e.tocfl].filter { $0 > 0 }.min() ?? 0
                    if lv > 0 { listed.append((lv, i)) } else if other.count < 150 { other.append(i) }
                }
                return listed.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.1) + other
            }.value
        }
    }
}

/// a 台語 word card with its reading and 1–2 meanings
struct CharWordCardRow: View {
    let card: Card
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.h).scaledFont(20, weight: .semibold).foregroundStyle(T.blueInk)
                Text(store.cardRom(card, rom, place)).latFont(16).toneGlow().foregroundStyle(T.greenInk).lineLimit(1)
                Spacer(minLength: 0)
            }
            let ds = Array(card.d.prefix(2))
            ForEach(Array(ds.enumerated()), id: \.offset) { i, d in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if ds.count > 1 { Text("\(i + 1).").ffFont(.caption, .bold).foregroundStyle(T.muted) }
                    Text(d.t).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
                }
            }
        }
    }
}

/// the words with a character, in a sheet (on a phone: tap the character at the top of 手寫練習)
struct CharWordsSheet: View {
    let ch: String
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            CharWordsList(ch: ch)
                .appBackground()
                .navigationTitle("有「\(ch)」的詞")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 6) {
                        if store.isZh { MeaningSwitch(vertical: false) }
                        RomButton()
                    }
                }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// 中 | 英: 華語's meanings in 華語 or English (the same switch as 設定 → 主要解釋); standing up (中 over 英) next
/// to the stacked spelling / 腔口 buttons
struct MeaningSwitch: View {
    var vertical = false
    @AppStorage(ZhMeaning.key) private var english = false
    var body: some View {
        Button { withAnimation(.snappy) { english.toggle() } } label: {
            let parts = ForEach([false, true], id: \.self) { en in
                let on = english == en
                Text(en ? "英" : "中").ffFont(.caption, on ? Font.Weight.bold : Font.Weight.regular)
                    .foregroundStyle(on ? T.greenInk : T.muted)
                    .frame(width: 24)
                    .frame(minHeight: 22, maxHeight: vertical ? .infinity : 22)
                    .background(Capsule().fill(on ? T.green : Color.clear))
            }
            Group {
                if vertical { VStack(spacing: 0) { parts } } else { HStack(spacing: 0) { parts } }
            }
            .padding(2)
            .background(Capsule().fill(T.fn))
            .overlay(Capsule().stroke(T.fnEdge, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(english ? "解釋：英文" : "解釋：華語")
    }
}

/// 手寫練習: 我會了. Tap: the character is known (its card 熟悉), yellow with little rainbow rays around it;
/// tap again: 不熟.
struct KnowCharButton: View {
    let ch: String
    @EnvironmentObject var store: Store
    @State private var pop = false
    private static let yellow = Color(hex: 0xF6C945)

    var body: some View {
        let known = store.card(for: Lang.charKey(ch)).flatMap { store.status($0) } == 1
        Button {
            let now = !known
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { _ = store.setCharKnown(ch, now); pop = now }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if now { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { withAnimation(.easeOut(duration: 0.2)) { pop = false } } }
        } label: {
            ZStack {
                // the rays: the rainbow, all the way round
                if known {
                    ForEach(0..<12, id: \.self) { i in
                        Capsule()
                            .fill(Color(HandInk.rainbow[i % HandInk.rainbow.count]))
                            .frame(width: 2.5, height: 6)
                            .offset(y: -(20 + 5 + (pop ? 3 : 0)))
                            .rotationEffect(.degrees(Double(i) * 30))
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                Circle()
                    .fill(known ? Self.yellow : T.fn)
                    .overlay(Circle().stroke(known ? Self.yellow.opacity(0.6) : T.fnEdge, lineWidth: 1.5))
                    .frame(width: 40, height: 40)
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(known ? Color(hex: 0x3a2a00) : T.muted)
            }
            .frame(width: 58, height: 58)
            .scaleEffect(pop ? 1.12 : 1)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(known ? "我會了（再點一下：不熟）" : "我會這個字")
        .accessibilityAddTraits(known ? .isSelected : [])
    }
}
