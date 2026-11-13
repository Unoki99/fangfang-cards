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
    static func font(_ size: CGFloat) -> UIFont { font(size, style: style) }

    /// a font of `styles` for SwiftUI's Text, made from the UIFont itself (by its name SwiftUI doesn't always find a
    /// font the app registered or downloaded, which is why 手寫練習 draws its characters itself)
    static func text(_ size: CGFloat, style s: Int) -> Font { Font(font(size, style: s) as CTFont) }

    /// the font `s` of `styles` at a size, with the same fallbacks
    static func font(_ size: CGFloat, style s: Int) -> UIFont {
        register()
        let chosen = styles[min(max(s, 0), styles.count - 1)].ps
        var names = [chosen]
        for n in ["LXGWWenKaiTC-Regular", tc, sc] where n != chosen { names.append(n) }
        let have = names.filter { UIFont(name: $0, size: size) != nil }
        guard let first = have.first, let main = UIFont(name: first, size: size) else { return .systemFont(ofSize: size) }
        let cascade = have.dropFirst().map { UIFontDescriptor(name: $0, size: size) }
        return UIFont(descriptor: main.fontDescriptor.addingAttributes([.cascadeList: Array(cascade)]), size: size)
    }

    /// a character drawn in 楷體, filling a square (centred on the character's own shape)
    static func image(_ ch: String, side: CGFloat, scale: CGFloat, color: UIColor) -> UIImage {
        let key = "\(ch)|\(Int(side * 4))|\(scale)|\(color.description)|\(style)|\(ready)" as NSString
        if let hit = imageCache.object(forKey: key) { return hit }
        let made = draw(ch, side: side, scale: scale, color: color)
        imageCache.setObject(made, forKey: key)
        return made
    }
    /// (drawn characters, kept: a page that's drawn again often, like the falling words, doesn't draw them again)
    private static let imageCache: NSCache<NSString, UIImage> = { let c = NSCache<NSString, UIImage>(); c.countLimit = 600; return c }()

    private static func draw(_ ch: String, side: CGFloat, scale: CGFloat, color: UIColor) -> UIImage {
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

/// text in the handwriting font chosen, drawn by the app itself (the same way as 手寫練習's character: SwiftUI's Text
/// doesn't always get a font the app registered)
struct KaitiText: View {
    let text: String
    let size: CGFloat
    var color: Color = T.glyph
    @AppStorage(Kaiti.styleKey) private var fontStyle = 0
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                Image(uiImage: Kaiti.image(String(ch), side: size * 1.1, scale: 3, color: UIColor(color)))
                    .resizable()
                    .frame(width: size * 1.1, height: size * 1.1)
            }
        }
        .id("\(text)\(fontStyle)\(Kaiti.ready)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
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
    /// from a side card (新詞): just these characters (not saved, no 選字), then back to the cards
    var only: [String]? = nil
    /// 台語, from a side card: the character's word, read as in the big card's word
    var given: [String: Card] = [:]
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
                    HandwritingPad(chars: list, idx: $idx, given: given) { dismiss() }
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
            .navigationTitle(tr("手寫練習"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("結束"))
                }
                if list != nil && only == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { PracticeSave.clear("handwriting", zh: store.isZh); list = nil } label: {
                            Label(tr("選字"), systemImage: "square.grid.3x3")
                        }
                    }
                }
            }
        }
        .onAppear {
            if let only, list == nil { list = only; idx = 0; return }
            guard list == nil, let s = PracticeSave.load(Saved.self, "handwriting", zh: store.isZh, scope: 0),
                  !s.chars.isEmpty, s.idx < s.chars.count else { return }
            list = s.chars; idx = s.idx; resumed = true
        }
        .onChange(of: idx) { save() }
    }

    private func save() {
        guard only == nil else { return }
        guard let list, idx < list.count else { PracticeSave.clear("handwriting", zh: store.isZh); return }
        PracticeSave.save(Saved(chars: list, idx: idx), "handwriting", zh: store.isZh, scope: 0)
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
        // 台語: the characters of your 不熟 / 熟悉 words
        if !store.isZh {
            let sets = store.twCharSets()
            var out = [Source(id: "unknown", name: trs("不熟的詞的字"), chars: sets.unknown),
                       Source(id: "known", name: trs("熟悉的詞的字"), chars: sets.known)]
            var seen = Set<String>()
            let mine = own.unicodeScalars.filter { Zhuyin.isHan($0) }.map { String($0) }.filter { seen.insert($0).inserted }
            out.append(Source(id: "own", name: trs("自己選的字"), chars: mine))
            return out
        }
        let sets = store.zhCharSets()
        var out = [Source(id: "unknown", name: trs("不熟的漢字"), chars: sets.all.filter { sets.unknown.contains($0) })]
        for t in store.topics where t.id > Lang.charTopicBase {
            out.append(Source(id: "level\(t.id)", name: t.name, chars: store.levelCards(t.id).compactMap { Lang.charOf($0.k) }))
        }
        out.append(Source(id: "known", name: trs("認識的漢字"), chars: sets.all.filter { sets.known.contains($0) }))
        var seen = Set<String>()
        let mine = own.unicodeScalars.filter { Zhuyin.isHan($0) }.map { String($0) }.filter { seen.insert($0).inserted }
        out.append(Source(id: "own", name: trs("自己選的字"), chars: mine))
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
                    Label(tr("開始寫（\(picked.count) 個字）"), systemImage: "pencil.and.scribble").frame(maxWidth: .infinity, minHeight: 44)
                }
                .prominentButton(T.btnEdge)
                .disabled(picked.isEmpty)
                Toggle(tr("打亂順序"), isOn: $shuffle)
                Picker(tr("要寫的字"), selection: $listID) {
                    ForEach(all) { s in Text(s.id == "own" ? s.name : "\(s.name)（\(s.chars.count)）").tag(s.id) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                .onChange(of: listID) { off = [] }
                if src.id == "own" {
                    TextField(tr("打你要寫的字，例如：龍鳳書寫"), text: $own)
                        .scaledFont(20)
                        .autocorrectionDisabled()
                        .clearButton($own)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                }
                if src.chars.isEmpty {
                    Text(src.id == "unknown" ? trs("還沒有不熟的漢字。") : (src.id == "own" ? trs("在上面打字。") : trs("這裡沒有字。")))
                        .ffFont(.footnote).foregroundStyle(T.muted)
                } else {
                    HStack(spacing: 10) {
                        Text(tr("點字可以不選它。選了 \(picked.count)／\(src.chars.count) 個")).ffFont(.footnote).foregroundStyle(T.muted)
                        Spacer()
                        Button(tr("全選")) { off = [] }.ffFont(.footnote, .semibold)
                        Button(tr("全不選")) { off = Set(src.chars) }.ffFont(.footnote, .semibold)
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
    var given: [String: Card] = [:]
    let finished: () -> Void
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    /// the character's card: 華語, its character card; 台語, its own word in the dictionary (the one given, or the
    /// most common reading)
    private func charCard(_ ch: String) -> Card? {
        store.isZh ? store.card(for: Lang.charKey(ch)) : (given[ch] ?? store.twCharCard(ch))
    }
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
    @State private var colorOpen = false
    /// the biggest the square can be on this screen (set from the space there is)
    @State private var maxPad: CGFloat = 520
    /// the character whose words are shown (tapping it at the top)
    @State private var wordsFor: WordsRef?
    @Environment(\.horizontalSizeClass) private var hSize
    static let sideWidth: CGFloat = 330
    /// room for the words beside the square (iPad, not in a narrow split view)
    private func isWide(_ size: CGSize) -> Bool { hSize == .regular && size.width >= 800 && !isShort(size) }
    struct WordsRef: Identifiable { let ch: String; var id: String { ch } }

    var body: some View {
        let ch = chars[min(idx, chars.count - 1)]
        GeometryReader { g in
            let w = isWide(g.size)
            HStack(alignment: .top, spacing: 0) {
                // iPad: the words with the character beside the square, to learn it in context
                if w { sideWords(ch).frame(width: Self.sideWidth).padding([.leading, .vertical]) }
                pad(ch, wide: w, short: isShort(g.size))
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
        if isShort(size) { return max(180, min(size.height - 24, size.width - 400 - 60)) }
        let side = isWide(size) ? Self.sideWidth + 16 : 0
        return max(200, min(size.width - 32 - side, size.height - (trace ? 360 : 320)))
    }
    /// a phone on its side
    private func isShort(_ size: CGSize) -> Bool { size.width > size.height && size.height < 520 }

    private func sideWords(_ ch: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(tr("有「\(ch)」的詞")).ffFont(.headline).foregroundStyle(T.glyph)
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

    private func progressRow() -> some View {
        HStack(spacing: 10) {
            PotionBar(value: Double(idx + 1) / Double(chars.count), height: 20, showMarks: false, label: trs("手寫進度"))
            Text(tr("\(idx + 1)／\(chars.count)")).latFont(14).monospacedDigit().foregroundStyle(T.muted)
        }
    }
    @ViewBuilder private func scoreAndNotes() -> some View {
        if trace {
            HStack(spacing: 10) {
                Text(tr("描得像")).ffFont(.footnote, .semibold).foregroundStyle(T.muted)
                PotionBar(value: score, height: 22, showMarks: false, label: trs("描得像"))
                Text(drawn ? "\(Int((score * 100).rounded()))%" : "—").latFont(15).monospacedDigit().foregroundStyle(T.glyph)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        if downloading && Kaiti.styles[Kaiti.style].file == nil {
            Text(tr("下載楷體中…（第一次要網路）")).ffFont(.caption).foregroundStyle(T.muted)
        } else if !kaiti && trace && Kaiti.styles[Kaiti.style].file == nil {
            Text(tr("楷體下載不了，先用系統的字。")).ffFont(.caption).foregroundStyle(T.muted)
        }
    }
    /// 格子大小: the writing square, bigger or smaller (the shadow follows)
    private func sizeRow() -> some View {
        HStack(spacing: 10) {
            Image(systemName: "square.resize.down").foregroundStyle(T.muted)
            Slider(value: Binding(get: { Double(padSide) }, set: { padSize = $0 }), in: 180...Double(max(181, maxPad)))
                .tint(T.btnEdge)
                .accessibilityLabel(tr("格子大小"))
            Image(systemName: "square.resize.up").foregroundStyle(T.muted)
        }
    }

    private func pad(_ ch: String, wide: Bool, short: Bool = false) -> some View {
        Group {
            if short {
                // a phone on its side: everything else on the left, the square on the right
                HStack(alignment: .top, spacing: 20) {
                    ScrollView {
                        VStack(spacing: 10) {
                            progressRow()
                            header(ch, wide: wide)
                            scoreAndNotes()
                            controls
                            sizeRow()
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxWidth: 400)
                    canvas(ch)
                }
                .padding(.horizontal).padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 14) {
                    progressRow()
                    header(ch, wide: wide)
                    canvas(ch)
                    scoreAndNotes()
                    controls
                    sizeRow()
                    Spacer(minLength: 0)
                }
                .padding()
                .frame(maxWidth: max(640, padSide + 32))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    PenTools()
                    // 描字: on = the icon glows (no filled background), off = plain
                    Button { withAnimation(.easeInOut(duration: 0.25)) { trace.toggle() } } label: {
                        Label(tr("描字"), systemImage: "character.cursor.ibeam")
                            .foregroundStyle(trace ? T.btnInk : T.muted)
                            .shadow(color: trace ? T.btnEdge.opacity(0.95) : .clear, radius: 3)
                            .shadow(color: trace ? T.btnEdge.opacity(0.7) : .clear, radius: 9)
                    }
                    .accessibilityLabel(tr("描字"))
                    .accessibilityValue(trace ? trs("開") : trs("關"))
                    .accessibilityAddTraits(trace ? .isSelected : [])
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
        if !store.isZh, let c = charCard(ch) {
            return (store.cardRom(c, rom, place), c.d.prefix(2).map { ($0.p, $0.t) }, c.audio)
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
                KaitiText(text: ch, size: 64, color: T.blueInk).id("\(kaiti)\(fontStyle)")
            } else {
                Button { wordsFor = WordsRef(ch: ch) } label: {
                    VStack(spacing: 0) {
                        KaitiText(text: ch, size: 64, color: T.blueInk).id("\(kaiti)\(fontStyle)")
                        Label(tr("看詞"), systemImage: "text.magnifyingglass").ffFont(.caption2, .semibold).foregroundStyle(T.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SwellButtonStyle())
                .accessibilityLabel(tr("看有「\(ch)」的詞"))
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
                if let c = charCard(ch) { KnowCharButton(card: c) }
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
            StrokeNumbers(drawing: lastDrawing)
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .frame(width: padSide, height: padSide)
        .accessibilityLabel(tr("寫字的地方"))
    }

    private func makeTarget(_ ch: String) {
        guard side > 0 else { return }
        target = TraceScore.cells(Kaiti.image(ch, side: CGFloat(TraceScore.n), scale: 1, color: .white))
        if trace && drawn { score = TraceScore.score(target: target, drawing: lastDrawing, side: side) }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { go(-1) } label: { Label(tr("上一個"), systemImage: "chevron.left").frame(maxWidth: .infinity, minHeight: 40) }
                .softButton()
                .disabled(idx == 0)
            Button { clearCount += 1; score = 0; drawn = false } label: {
                Label(tr("清掉"), systemImage: "eraser").frame(maxWidth: .infinity, minHeight: 40)
            }
            .softButton()
            Button { go(1) } label: {
                Label(idx + 1 >= chars.count ? trs("完成") : trs("下一個"), systemImage: "chevron.right").frame(maxWidth: .infinity, minHeight: 40)
            }
            .prominentButton(T.btnEdge)
        }
    }

    private func go(_ d: Int) {
        if d > 0 && idx + 1 >= chars.count {
            PracticeSave.clear("handwriting", zh: store.isZh)
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
    /// the ink's own colour (a colour of the tone colours' grid, as 0xRRGGBB); 0 = the dark ink
    static let colorKey = "handwritingInkColor"
    /// 延遲: how many seconds after the pen the writing shows up (0 = right away)
    static let delayKey = "handwritingInkDelay"
    /// 筆畫編號: a small circled number at the start of each stroke
    static let numbersKey = "handwritingStrokeNumbers"
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
    /// the ink when it isn't the rainbow: the colour picked, or the dark ink
    static var solid: UIColor {
        let v = UserDefaults.standard.integer(forKey: colorKey)
        guard v > 0 else { return dark }
        return UIColor(red: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255, blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }
    static func tool(stroke n: Int, rainbow on: Bool, pen i: Int, size: Double) -> PKInkingTool {
        let color = on ? rainbow[n % rainbow.count] : solid
        return PKInkingTool(pens[pen(i)].type, color: color, width: width(pen: i, size: size))
    }
}

/// 筆 and 粗細: in 設定 and behind the pen button at the top of 手寫練習
struct PenSettings: View {
    @AppStorage(HandInk.pressureKey) private var pen = 1
    @AppStorage(HandInk.sizeKey) private var size = HandInk.sizeDefault
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.delayKey) private var delay = 0.0
    @AppStorage(HandInk.colorKey) private var inkColor = 0
    @AppStorage(HandInk.numbersKey) private var numbers = false
    /// in the pop-over (no Form around it)
    var compact = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("筆")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                GlassGroup {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(HandInk.pens.indices, id: \.self) { i in
                            let on = HandInk.pen(pen) == i
                            Button { withAnimation(.snappy) { pen = i } } label: {
                                Text(trs(HandInk.pens[i].name)).ffFont(.subheadline, on ? Font.Weight.bold : Font.Weight.regular)
                                    .foregroundStyle(T.glyph)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .glassChip(selected: on)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                Text(trs(HandInk.pens[HandInk.pen(pen)].about)).ffFont(.caption).foregroundStyle(T.muted)
                sizeRow
                preview
                delayRow
                Toggle(tr("筆畫編號"), isOn: $numbers).ffFont(.subheadline)
            }
            .padding(18)
            .frame(width: 330)
        } else {
            Picker(tr("筆"), selection: $pen) {
                ForEach(HandInk.pens.indices, id: \.self) { Text(trs(HandInk.pens[$0].name)).tag($0) }
            }
            sizeRow
            preview
            delayRow
            Toggle(tr("筆畫編號"), isOn: $numbers)
        }
    }

    /// 延遲: the writing shows up a moment after the pen
    private var delayRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(tr("筆跡延遲")).ffFont(.subheadline).foregroundStyle(T.glyph)
                Spacer()
                Text(delay < 0.025 ? trs("馬上出現") : String(format: trs("%.1f 秒"), delay)).latFont(14).monospacedDigit().foregroundStyle(T.muted)
            }
            Slider(value: $delay, in: 0...1.5, step: 0.05).tint(T.btnEdge).accessibilityLabel(tr("筆跡延遲"))
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 10) {
            Text(tr("粗細")).ffFont(.subheadline).foregroundStyle(T.glyph)
            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(T.muted)
            Slider(value: $size, in: 0...1).tint(T.btnEdge).accessibilityLabel(tr("粗細"))
            Image(systemName: "circle.fill").font(.system(size: 14)).foregroundStyle(T.muted)
        }
    }

    /// how a stroke of this pen looks, at this thickness
    private var preview: some View {
        let w = HandInk.width(pen: pen, size: size)
        let _ = inkColor
        let type = HandInk.pens[HandInk.pen(pen)].type
        return Canvas { ctx, sz in
            var p = Path()
            let n = 60
            for k in 0...n {
                let t = CGFloat(k) / CGFloat(n)
                let pt = CGPoint(x: 12 + t * (sz.width - 24), y: sz.height / 2 + sin(t * .pi * 2) * sz.height * 0.22)
                if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            let ink = Color(rainbow ? HandInk.rainbow[0] : HandInk.solid)
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
    /// what's on the pad when it's cleared (寫字題: going back to a character already written)
    var initial: PKDrawing? = nil
    let changed: (PKDrawing) -> Void
    @AppStorage(HandInk.pressureKey) private var level = 1
    @AppStorage(HandInk.sizeKey) private var size = HandInk.sizeDefault
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.delayKey) private var delay = 0.0
    @AppStorage(HandInk.colorKey) private var inkColor = 0

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
        c.level = level; c.size = size; c.rainbow = rainbow; c.delay = delay; c.ink = inkColor
        host.later.delay = delay
        if let d = initial, !d.strokes.isEmpty { v.drawing = delay > 0 ? c.hidden(d) : d }
        v.tool = c.tool(stroke: v.drawing.strokes.count)
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
            let d = initial ?? PKDrawing()
            v.drawing = c.delay > 0 ? c.hidden(d) : d
            host.later.reset()
            if c.delay > 0 && !d.strokes.isEmpty { host.later.show(c.shown(d), upTo: d.strokes.count) }
            v.tool = c.tool(stroke: d.strokes.count)
        }
        if c.level != level || c.rainbow != rainbow || c.size != size || c.delay != delay || c.ink != inkColor {
            let delayChanged = (c.delay > 0) != (delay > 0)
            c.level = level; c.rainbow = rainbow; c.size = size; c.delay = delay; c.ink = inkColor
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
        var ink = 0
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
                            Label(tr("「\(ch)」這個字"), systemImage: "character.book.closed").foregroundStyle(T.glyph)
                        }
                    }
                    .listRowBackground(T.fn.opacity(0.7))
                }
                if let zhList {
                    Section(zhList.isEmpty ? trs("沒有找到有這個字的詞") : tr("有「\(ch)」的詞（\(zhList.count)）")) {
                        ForEach(zhList, id: \.self) { i in
                            Button { openZh = ZhKey(k: dict.entries[i].k) } label: {
                                ZhWordRow(dict: dict, entry: dict.entries[i], meanings: 2).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
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
                Section(ws.isEmpty ? trs("沒有找到有這個字的詞") : tr("有「\(ch)」的詞（\(ws.count)）")) {
                    ForEach(ws, id: \.k) { c in
                        Button { openCard = c } label: { CharWordCardRow(card: c).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()) }
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
                .navigationTitle(tr("有「\(ch)」的詞"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } }
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
                Text(en ? trs("英") : trs("中")).ffFont(.caption, on ? Font.Weight.bold : Font.Weight.regular)
                    .foregroundStyle(on ? T.btnInk : T.muted)
                    .frame(width: 24)
                    .frame(minHeight: 22, maxHeight: vertical ? .infinity : 22)
                    .background(Capsule().fill(on ? T.btn : Color.clear))
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
        .accessibilityLabel(english ? trs("解釋：英文") : trs("解釋：華語"))
    }
}

/// 手寫練習: 我會了. Tap: the character is known (its card 熟悉), yellow with little rainbow rays around it;
/// tap again: 不熟.
struct KnowCharButton: View {
    /// 華語: the character card; 台語: the character's own word
    let card: Card
    @EnvironmentObject var store: Store
    @State private var pop = false
    private static let yellow = Color(hex: 0xF6C945)

    var body: some View {
        let known = store.status(card) == 1
        Button {
            let now = !known
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                if let ch = Lang.charOf(card.k) { _ = store.setCharKnown(ch, now) } else { store.mark(card, known: now, undoable: false) }
                pop = now
            }
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
        .accessibilityLabel(known ? trs("我會了（再點一下：不熟）") : trs("我會這個字"))
        .accessibilityAddTraits(known ? .isSelected : [])
    }
}

// MARK: - the ink's colour

/// the ink's colour as a little ball: the colour, or the rainbow
struct InkSwatch: View {
    var size: CGFloat = 20
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.colorKey) private var inkColor = 0
    var body: some View {
        let _ = inkColor
        Group {
            if rainbow {
                Circle().fill(AngularGradient(colors: (HandInk.rainbow + [HandInk.rainbow[0]]).map { Color($0) }, center: .center))
            } else {
                Circle().fill(Color(HandInk.solid))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
    }
}

/// 筆的顏色: the dark ink, 彩虹 (a new colour for every stroke) or one colour from the grid of balls (the same
/// colours as 選聲調顏色: one column per colour in rainbow order, light at the top and dark at the bottom)
struct InkColorPicker: View {
    /// in the pop-over (no Form around it)
    var compact = false
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.colorKey) private var inkColor = 0

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("筆的顏色")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                modes
                grid
                Text(tr("中間那一排是原本的顏色，往上越淺，往下越深。")).ffFont(.caption).foregroundStyle(T.muted)
            }
            .padding(18)
            .frame(width: 330)
        } else {
            Form {
                Section { modes }.listRowBackground(T.fn.opacity(0.7))
                Section {
                    grid.frame(maxWidth: .infinity).padding(.vertical, 6)
                } header: {
                    Text(tr("自己選一個顏色"))
                } footer: {
                    Text(tr("中間那一排是原本的顏色，往上越淺，往下越深。"))
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("筆的顏色"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 墨色 or 彩虹
    private var modes: some View {
        GlassGroup {
            HStack(spacing: 8) {
                mode(trs("墨色"), on: !rainbow && inkColor == 0) { rainbow = false; inkColor = 0 } swatch: {
                    Circle().fill(Color(HandInk.dark)).overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1))
                }
                mode(trs("彩虹"), on: rainbow) { rainbow = true } swatch: {
                    Circle().fill(AngularGradient(colors: (HandInk.rainbow + [HandInk.rainbow[0]]).map { Color($0) }, center: .center))
                }
            }
        }
    }

    private func mode<S: View>(_ name: String, on: Bool, _ act: @escaping () -> Void, @ViewBuilder swatch: () -> S) -> some View {
        Button { withAnimation(.snappy) { act() } } label: {
            HStack(spacing: 8) {
                swatch().frame(width: 18, height: 18)
                Text(name).ffFont(.subheadline, on ? Font.Weight.bold : Font.Weight.regular).foregroundStyle(T.glyph)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassChip(selected: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var grid: some View {
        let cols = ToneColors.palette
        return Grid(horizontalSpacing: 4, verticalSpacing: 8) {
            ForEach(0..<5, id: \.self) { row in
                GridRow {
                    ForEach(cols.indices, id: \.self) { c in ball(cols[c].shades[row], label: cols[c].name) }
                }
            }
        }
    }

    private func ball(_ hex: UInt32, label: String) -> some View {
        let picked = !rainbow && inkColor == Int(hex)
        return Button {
            withAnimation(.snappy) { inkColor = Int(hex); rainbow = false }
        } label: {
            Circle().fill(Color(hex: hex))
                .frame(width: 27, height: 27)
                .shadow(color: Color(hex: hex).opacity(0.55), radius: picked ? 6 : 0)
                .overlay(Circle().stroke(picked ? T.glyph : Color.clear, lineWidth: 2.5).padding(-3))
                .frame(width: 31, height: 31)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

// MARK: - Liquid Glass chips (the pen and colour pop-overs)

/// Liquid Glass's container (iOS 26), so the chips melt together; nothing before iOS 26
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(iOS 26.0, *) { GlassEffectContainer(spacing: 8) { content } } else { content }
    }
}

extension View {
    /// a capsule of Liquid Glass (iOS 26: the real one; before: frosted); the one picked is brighter and rimmed
    @ViewBuilder func glassChip(selected: Bool) -> some View {
        if #available(iOS 26.0, *) {
            self.padding(.horizontal, 10)
                .glassEffect(selected ? .regular.tint(.white.opacity(0.22)).interactive() : .regular.interactive(), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.7 : 0), lineWidth: 1.5))
        } else {
            self.padding(.horizontal, 10)
                .background(Capsule().fill(.ultraThinMaterial))
                .background(Capsule().fill(.white.opacity(selected ? 0.18 : 0)))
                .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.7 : 0.15), lineWidth: selected ? 1.5 : 1))
        }
    }
}

// MARK: - 寫字題: writing a whole word in practice (開始練習, 本週學習)

enum WordWrite {
    /// 設定 → 卡片與練習 → 寫字題
    static let key = "practiceWrite"
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// the word's characters in squares to write in: on an iPad all of them side by side; on a phone one at a time in a
/// big square, each written one kept in a small square above (tap one to write it again). 對答案 shows the right
/// characters faintly over the writing, and you say whether you got it
struct WordWriteArea: View {
    let chars: [String]
    /// the question has been graded (only the small squares stay, with the answer in them)
    let answered: Bool
    let grade: (Bool) -> Void
    /// just practising (a card's 寫整個詞): after 對答案, 再寫一次 (grade(false)) or 完成 (grade(true))
    var practiceOnly = false
    /// 不會寫: shows the answer, and the word is written again a little later (only then)
    var dontKnow: (() -> Void)? = nil
    @State private var drawings: [PKDrawing]
    /// 格子大小: the squares stay this size (only the slider changes it; smaller only when they don't fit)
    @AppStorage("handwritingTestPadSize") private var fixedSize = 300.0
    @State private var avail: CGFloat = 0
    /// changes when a square is cleared (清掉)
    @State private var clears: [Int]
    @State private var cur = 0
    @State private var checked = false
    @State private var side: CGFloat = 0
    @State private var kaiti = Kaiti.ready
    @AppStorage(Kaiti.styleKey) private var fontStyle = 0
    @Environment(\.horizontalSizeClass) private var hSize

    init(chars: [String], answered: Bool, practiceOnly: Bool = false, dontKnow: (() -> Void)? = nil, grade: @escaping (Bool) -> Void) {
        self.chars = chars; self.answered = answered; self.practiceOnly = practiceOnly; self.dontKnow = dontKnow; self.grade = grade
        _drawings = State(initialValue: Array(repeating: PKDrawing(), count: chars.count))
        _clears = State(initialValue: Array(repeating: 0, count: chars.count))
    }

    private var showAnswer: Bool { checked || answered }
    /// a square's side: the size chosen, smaller only when n of them don't fit side by side
    private func side(_ n: Int) -> CGFloat {
        let want = CGFloat(min(max(fixedSize, 140), 640))
        guard avail > 0 else { return want }
        let gap: CGFloat = 16
        return max(110, min(want, (avail - gap * CGFloat(max(n, 1) - 1)) / CGFloat(max(n, 1))))
    }
    /// an iPad (not a narrow split view): every character gets a big square at once
    private var wide: Bool { hSize == .regular }

    var body: some View {
        VStack(spacing: 12) {
            // after 對答案: what you wrote next to the character, to compare
            // (on a tablet the big squares already show the answer: the small ones would be the same thing twice)
            if showAnswer && !wide { slots }
            if wide {
                allPads
                HStack(spacing: 12) {
                    Button { for i in chars.indices { clear(i) } } label: {
                        Label(chars.count > 1 ? trs("全部清掉") : trs("清掉"), systemImage: "eraser").frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .softButton()
                    if !showAnswer, let dontKnow { dontKnowButton(dontKnow) }
                    if !showAnswer { checkButton }
                }
                .frame(maxWidth: 560)
            } else {
                if !showAnswer { slots }
                pad(cur).id(cur)
                    .frame(width: side(1), height: side(1))
                    .frame(maxWidth: .infinity)
                HStack(spacing: 12) {
                    Button { clear(cur) } label: {
                        Label(tr("清掉"), systemImage: "eraser").frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .softButton()
                    if !showAnswer, cur + 1 >= chars.count || chars.count == 1, let dontKnow { dontKnowButton(dontKnow) }
                    if cur + 1 < chars.count {
                        Button { cur += 1 } label: {
                            Label(tr("下一個字"), systemImage: "chevron.right").frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .prominentButton(T.btnEdge)
                    } else if !showAnswer {
                        checkButton
                    } else if chars.count > 1 {
                        Button { cur = 0 } label: {
                            Label(tr("第一個字"), systemImage: "arrow.uturn.left").frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .softButton()
                    }
                }
                sizeSlider
            }
            if showAnswer && !answered {
                // (the squares stay: write the character a few more times, over the faint one, before going on)
                Text(tr("淡淡的字是正確的寫法，和你寫的比一比；也可以在格子裡照著多寫幾次。")).ffFont(.footnote).foregroundStyle(T.muted)
                    .frame(maxWidth: .infinity, alignment: wide ? .center : .leading)
                HStack(spacing: 12) {
                    Button { grade(false) } label: {
                        Label(practiceOnly ? trs("再寫一次") : trs("寫錯了"), systemImage: practiceOnly ? "arrow.counterclockwise" : "xmark")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .softButton()
                    Button { grade(true) } label: {
                        Label(practiceOnly ? trs("完成") : trs("寫對了"), systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .prominentButton(T.btnEdge)
                }
                .frame(maxWidth: wide ? 560 : .infinity)
            }
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { avail = g.size.width }
                .onChange(of: g.size.width) { avail = g.size.width }
        })
        .onAppear {
            if !Kaiti.ready { Kaiti.prepare { ok in kaiti = ok } }
        }
    }

    /// 格子大小 (the squares change size only with this)
    private var sizeSlider: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.resize.down").foregroundStyle(T.muted)
            Slider(value: $fixedSize, in: 140...640).tint(T.btnEdge).accessibilityLabel(tr("格子大小"))
            Image(systemName: "square.resize.up").foregroundStyle(T.muted)
        }
        .frame(maxWidth: 420)
    }

    /// 不會寫: the answer shows, and (in practice and tests) the word comes back to be written again
    private func dontKnowButton(_ action: @escaping () -> Void) -> some View {
        Button { withAnimation(.snappy) { checked = true }; action() } label: {
            Label(tr("不會寫"), systemImage: "questionmark").frame(maxWidth: .infinity, minHeight: 40)
        }
        .softButton()
    }

    /// the character, faint (the same picture as 手寫練習's: the font chosen, drawn by the app itself)
    private func ghost(_ ch: String, _ s: CGFloat, _ opacity: Double) -> some View {
        Image(uiImage: Kaiti.image(ch, side: max(s, 1), scale: 2, color: UIColor(T.btnInk)))
            .resizable()
            .frame(width: s, height: s)
            .opacity(opacity)
            .allowsHitTesting(false)
            .id("\(ch)\(kaiti)\(fontStyle)\(Int(s))")
    }

    private var checkButton: some View {
        Button { withAnimation(.snappy) { checked = true } } label: {
            Label(tr("對答案"), systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 40)
        }
        .prominentButton(T.btnEdge)
    }

    /// iPad: a big square for each character, side by side (as big as the space lets them be)
    private var allPads: some View {
        let s = side(chars.count), gap: CGFloat = 16
        return VStack(spacing: 10) {
            HStack(spacing: gap) {
                ForEach(chars.indices, id: \.self) { i in
                    VStack(spacing: 6) {
                        pad(i).frame(width: s, height: s)
                        HStack(spacing: 8) {
                            Text(tr("第 \(i + 1) 個字")).ffFont(.caption).foregroundStyle(T.muted)
                            if !drawings[i].strokes.isEmpty {
                                Button { clear(i) } label: { Image(systemName: "eraser").ffFont(.caption) }
                                    .buttonStyle(.plain).foregroundStyle(T.btnInk)
                                    .accessibilityLabel(tr("清掉"))
                            }
                        }
                        .frame(height: 18)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            sizeSlider
        }
    }

    /// the small squares: what's been written of each character (and, after 對答案, the character)
    private var slots: some View {
        let s: CGFloat = showAnswer ? (wide ? 130 : 86) : 58
        return HStack(spacing: 10) {
            ForEach(chars.indices, id: \.self) { i in
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.75))
                    if showAnswer { ghost(chars[i], s, 0.4) }
                    if side > 0 && !drawings[i].strokes.isEmpty {
                        Image(uiImage: picture(drawings[i])).resizable().scaledToFit()
                    }
                }
                .frame(width: s, height: s)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(!showAnswer && i == cur ? T.btnEdge : T.fnEdge, lineWidth: !showAnswer && i == cur ? 2.5 : 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { if i != cur { cur = i } }
                .accessibilityLabel(tr("第 \(i + 1) 個字"))
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: showAnswer)
    }

    /// a square (米字格) to write character i in
    private func pad(_ i: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(T.fn.opacity(0.75))
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
                // after 對答案: the character, faint, to write over
                if showAnswer { ghost(chars[i], w, 0.22) }
            }
            WritingPad(clearCount: clears[i], initial: drawings[i]) { d in
                if i < drawings.count { drawings[i] = d }
            }
            StrokeNumbers(drawing: drawings[i])
        }
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(T.fnEdge, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .noStarBursts()
        .accessibilityLabel(tr("寫字的地方"))
    }

    private func clear(_ i: Int) {
        drawings[i] = PKDrawing()
        clears[i] += 1
    }

    /// the writing as a picture (in the colours as written, like the pad shows them)
    private func picture(_ d: PKDrawing) -> UIImage {
        var img = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = d.image(from: CGRect(x: 0, y: 0, width: side, height: side), scale: 2)
        }
        return img
    }
}

/// 新詞 on an iPad: write the whole word on the card (the word, its reading and meaning above the squares)
struct WordWriteSheet: View {
    let card: Card
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage(ZhMeaning.key) private var zhEnglish = false
    @AppStorage(Kaiti.styleKey) private var fontStyle = 0
    /// the word hidden: write it from the reading and meaning
    @State private var hidden = false
    @State private var round = 0
    @State private var kaiti = Kaiti.ready

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Panel {
                    HStack(alignment: .center, spacing: 16) {
                        KaitiText(text: hidden ? String(repeating: "？", count: card.h.count) : card.h, size: 56, color: T.blueInk)
                            .id("\(kaiti)\(fontStyle)")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.cardRom(card, rom, place)).latFont(22).toneGlow().foregroundStyle(T.greenInk)
                            let m = store.practiceMeaning(card)
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                if !m.p.isEmpty { Chip(text: m.p) }
                                Text(m.t).ffFont(.subheadline).foregroundStyle(T.glyph).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        if let a = card.audio { PlayButton(path: a, size: 40) }
                    }
                }
                WordWriteArea(chars: card.h.map(String.init), answered: false, practiceOnly: true) { done in
                    if done { dismiss() } else { round += 1 }
                }
                .id(round)
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .appBackground()
            .navigationTitle(tr("寫整個詞"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("結束"))
                }
                ToolbarItem(placement: .topBarTrailing) { PenTools() }
                ToolbarItem(placement: .topBarTrailing) {
                    // 藏字: write it from memory
                    Button { withAnimation(.snappy) { hidden.toggle() } } label: {
                        Label(hidden ? trs("顯示字") : trs("藏字"), systemImage: hidden ? "eye" : "eye.slash").labelStyle(.titleAndIcon)
                    }
                }
            }
            .onAppear { if !Kaiti.ready { Kaiti.prepare { ok in kaiti = ok } } }
        }
    }
}


/// the writing tools of the top bar: 字體 (楷體, 文楷 or 芫荽), 筆 (which pen, how thick, 筆畫編號) and 顏色 (the dark
/// ink, the rainbow or a colour of its own); the same in every place that's written in
struct PenTools: View {
    @AppStorage(Kaiti.styleKey) private var fontStyle = 0
    @State private var penOpen = false
    @State private var colorOpen = false
    var body: some View {
        HStack {
            Menu {
                Picker(tr("字體"), selection: $fontStyle) {
                    ForEach(Kaiti.styles.indices, id: \.self) { Text(trs(Kaiti.styles[$0].name)).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(tr("字體"), systemImage: "textformat")
            }
            .accessibilityLabel(tr("字體：") + trs(Kaiti.styles[Kaiti.style].name))
            Button { penOpen = true } label: { Label(tr("筆"), systemImage: "pencil.tip") }
                .popover(isPresented: $penOpen) {
                    PenSettings(compact: true).presentationCompactAdaptation(.popover)
                }
            Button { colorOpen = true } label: {
                Label { Text(tr("顏色")) } icon: { InkSwatch(size: 20) }
            }
            .popover(isPresented: $colorOpen) {
                InkColorPicker(compact: true).presentationCompactAdaptation(.popover)
            }
            .accessibilityLabel(tr("筆的顏色"))
        }
    }
}


/// 筆畫編號 (設定 or the pen's pop-over): a small circled number by the start of each stroke, in the stroke's own
/// colour, just above where it starts (or beside it), never on top of a line
struct StrokeNumbers: View {
    let drawing: PKDrawing
    @AppStorage(HandInk.numbersKey) private var on = false
    @AppStorage(HandInk.pressureKey) private var level = 1
    @AppStorage(HandInk.sizeKey) private var size = HandInk.sizeDefault
    @AppStorage(HandInk.rainbowKey) private var rainbow = false
    @AppStorage(HandInk.colorKey) private var inkColor = 0

    static func circled(_ n: Int) -> String {
        switch n {
        case 1...20: return String(UnicodeScalar(0x2460 + n - 1)!)
        case 21...35: return String(UnicodeScalar(0x3251 + n - 21)!)
        case 36...50: return String(UnicodeScalar(0x32B1 + n - 36)!)
        default: return "\(n)"
        }
    }

    /// where each number goes: the first place around the stroke's start (above first) with no line near it
    static func places(_ d: PKDrawing, size: CGSize) -> [CGPoint] {
        let pts: [CGPoint] = d.strokes.flatMap { s in
            s.path.interpolatedPoints(by: .distance(3)).map { $0.location.applying(s.transform) }
        }
        let r: CGFloat = 8, gap: CGFloat = 13
        let dirs: [CGVector] = [CGVector(dx: 0, dy: -1), CGVector(dx: -0.7, dy: -0.7), CGVector(dx: 0.7, dy: -0.7),
                                CGVector(dx: -1, dy: 0), CGVector(dx: 1, dy: 0), CGVector(dx: -0.7, dy: 0.7),
                                CGVector(dx: 0.7, dy: 0.7), CGVector(dx: 0, dy: 1)]
        var taken: [CGPoint] = []
        return d.strokes.map { s in
            guard let first = s.path.first?.location.applying(s.transform) else { return .zero }
            var best = CGPoint(x: first.x, y: first.y - gap), bestRoom: CGFloat = -1
            for dist in [gap, gap * 1.6, gap * 2.3] {
                for v in dirs {
                    let c = CGPoint(x: first.x + v.dx * dist, y: first.y + v.dy * dist)
                    guard c.x > r, c.y > r, c.x < size.width - r, c.y < size.height - r else { continue }
                    let room = min(pts.map { hypot($0.x - c.x, $0.y - c.y) }.min() ?? 99,
                                   taken.map { hypot($0.x - c.x, $0.y - c.y) - r }.min() ?? 99)
                    if room > r + 2 { taken.append(c); return c }
                    if room > bestRoom { best = c; bestRoom = room }
                }
            }
            taken.append(best)
            return best
        }
    }

    var body: some View {
        if on && !drawing.strokes.isEmpty {
            GeometryReader { g in
                let at = Self.places(drawing, size: g.size)
                ForEach(at.indices, id: \.self) { i in
                    Text(Self.circled(i + 1))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(uiColor: HandInk.tool(stroke: i, rainbow: rainbow, pen: level, size: size).color))
                        .position(at[i])
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - 自由寫字: a whole sheet of squares

/// a sheet of writing squares with no space between them (the size chosen with the slider, also very small); type a
/// sentence and its characters fill the squares, faint, to write over (calligraphy practice). The pen, its colour and
/// the 字體 are the same as everywhere; only here there's 上一筆 (take back the last stroke).
struct FreeWritingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("freeWritingCell") private var cell = 90.0
    @AppStorage("freeWritingText") private var text = ""
    @AppStorage("handwritingTrace") private var trace = true
    @AppStorage(Kaiti.styleKey) private var fontStyle = 0
    @State private var drawing = PKDrawing()
    @State private var clearCount = 0
    @State private var page = 0
    @State private var kaiti = Kaiti.ready
    @State private var editing = false

    private var chars: [String] { text.filter { !$0.isWhitespace && !$0.isNewline }.map(String.init) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "square.grid.3x3").foregroundStyle(T.muted)
                    Slider(value: $cell, in: 28...200, step: 2)
                    Text("\(Int(cell))").latFont(13).monospacedDigit().foregroundStyle(T.muted).frame(width: 34)
                }
                .padding(.horizontal)
                HStack(spacing: 8) {
                    TextField(tr("打一句話，字會出現在格子裡（可以照著寫）"), text: $text)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: text) { page = 0 }
                    if !text.isEmpty {
                        Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(T.muted) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                GeometryReader { g in
                    let s = CGFloat(cell)
                    let cols = max(1, Int(g.size.width / s)), rows = max(1, Int(g.size.height / s))
                    let w = CGFloat(cols) * s, h = CGFloat(rows) * s
                    let perPage = cols * rows
                    let pages = max(1, (chars.count + perPage - 1) / max(perPage, 1))
                    ZStack(alignment: .topLeading) {
                        // the squares (米字格), no space between them
                        Path { p in
                            for c in 0...cols { p.move(to: CGPoint(x: CGFloat(c) * s, y: 0)); p.addLine(to: CGPoint(x: CGFloat(c) * s, y: h)) }
                            for r in 0...rows { p.move(to: CGPoint(x: 0, y: CGFloat(r) * s)); p.addLine(to: CGPoint(x: w, y: CGFloat(r) * s)) }
                        }
                        .stroke(T.fnEdge, lineWidth: 1.2)
                        Path { p in
                            for r in 0..<rows {
                                for c in 0..<cols {
                                    let x = CGFloat(c) * s, y = CGFloat(r) * s
                                    p.move(to: CGPoint(x: x + s / 2, y: y)); p.addLine(to: CGPoint(x: x + s / 2, y: y + s))
                                    p.move(to: CGPoint(x: x, y: y + s / 2)); p.addLine(to: CGPoint(x: x + s, y: y + s / 2))
                                    if s >= 60 {
                                        p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + s, y: y + s))
                                        p.move(to: CGPoint(x: x + s, y: y)); p.addLine(to: CGPoint(x: x, y: y + s))
                                    }
                                }
                            }
                        }
                        .stroke(T.fnEdge.opacity(0.6), style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
                        // the sentence's characters, faint, one per square
                        if trace {
                            ForEach(0..<min(perPage, max(0, chars.count - page * perPage)), id: \.self) { i in
                                // (drawn by the app in the font chosen, like 手寫練習's character)
                                Image(uiImage: Kaiti.image(chars[page * perPage + i], side: max(s, 1), scale: 2, color: UIColor(T.btnInk)))
                                    .resizable()
                                    .opacity(0.25)
                                    .frame(width: s, height: s)
                                    .position(x: CGFloat(i % cols) * s + s / 2, y: CGFloat(i / cols) * s + s / 2)
                            }
                            .id("\(kaiti)\(fontStyle)")
                        }
                        WritingPad(clearCount: clearCount, initial: drawing) { d in drawing = d }
                            .frame(width: w, height: h)
                        StrokeNumbers(drawing: drawing).frame(width: w, height: h)
                    }
                    .frame(width: w, height: h)
                    .background(RoundedRectangle(cornerRadius: 4).fill(T.fn.opacity(0.75)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        if pages > 1 {
                            HStack(spacing: 14) {
                                Button { page = max(0, page - 1); clearPage() } label: { Image(systemName: "chevron.left") }
                                    .disabled(page == 0)
                                Text("\(page + 1)／\(pages)").latFont(14).monospacedDigit()
                                Button { page = min(pages - 1, page + 1); clearPage() } label: { Image(systemName: "chevron.right") }
                                    .disabled(page >= pages - 1)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(T.fn.opacity(0.95)))
                            .offset(y: 18)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .noStarBursts()
            }
            .appBackground()
            .navigationTitle(tr("自由寫字"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("結束"))
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 上一筆: only in 自由寫字
                    Button { undo() } label: { Label(tr("上一筆"), systemImage: "arrow.uturn.backward") }
                        .disabled(drawing.strokes.isEmpty)
                    Button { clearPage() } label: { Label(tr("清掉"), systemImage: "eraser") }
                        .disabled(drawing.strokes.isEmpty)
                    PenTools()
                    Button { withAnimation(.easeInOut(duration: 0.25)) { trace.toggle() } } label: {
                        Label(tr("描字"), systemImage: "character.cursor.ibeam").foregroundStyle(trace ? T.btnInk : T.muted)
                    }
                    .accessibilityValue(trace ? trs("開") : trs("關"))
                }
            }
            .onAppear { if !Kaiti.ready { Kaiti.prepare { ok in kaiti = ok } } }
        }
    }

    private func undo() {
        guard !drawing.strokes.isEmpty else { return }
        drawing = PKDrawing(strokes: Array(drawing.strokes.dropLast()))
        clearCount += 1
    }

    private func clearPage() {
        drawing = PKDrawing()
        clearCount += 1
    }
}
