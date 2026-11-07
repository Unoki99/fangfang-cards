import SwiftUI

/// A stack of cards: drag right = 認識 (known), drag left = 不熟 (unknown). A card swiped away falls apart into
/// little squares: blue ones floating up on the right (認識), red ones dropping down on the left (不熟).
struct SwipeStack: View {
    let cards: [Card]                       // top card first
    let onSwipe: (Card, Bool) -> Void       // true = right (known)
    /// the ✕ / ✓ buttons (and ← →): swipe the top card that way
    var fling: Fling? = nil
    struct Fling: Equatable { let right: Bool; let id = UUID() }
    @EnvironmentObject var store: Store
    @State private var offset: CGSize = .zero
    @State private var touch: CGPoint?
    @State private var bursts: [CardBurst] = []
    /// the top card's picture, made a moment after it comes up (see CardPicture)
    @State private var picture: (key: String, pic: CardPicture)?

    var body: some View {
        GeometryReader { g in
            ZStack {
                ForEach(Array(cards.prefix(3).enumerated()).reversed(), id: \.element.id) { i, card in
                    WordCard(card: card, isTop: i == 0)
                        .overlay {
                            if i == 0 { CardLight(swipe: max(-1, min(1, offset.width / 140)), touch: touch) }
                        }
                        .overlay(alignment: .top) { if i == 0 { stamp } }
                        .scaleEffect(i == 0 ? 1 : 1 - CGFloat(i) * 0.04)
                        .offset(y: CGFloat(i) * 14)
                        // (only the stack moves up; the rest of the screen changes without animating)
                        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: i)
                        .offset(i == 0 ? offset : .zero)
                        .rotationEffect(.degrees(i == 0 ? Double(offset.width / 18) : 0))
                        .allowsHitTesting(i == 0)
                        .gesture(drag(card, size: g.size))
                        .zIndex(Double(10 - i))
                        .transition(.identity)          // (it turns into the squares instead)
                }
                // (much bigger than the stack, so the squares can fly off over the whole screen)
                // (only while something is falling apart: it's a big picture to keep around)
                if !bursts.isEmpty {
                    CardDust(bursts: bursts, pad: CardDust.pad)
                        .padding(-CardDust.pad)
                        .allowsHitTesting(false).zIndex(20)
                }
            }
            .onChange(of: fling) { _, f in
                if let f, let top = cards.first { fly(top, right: f.right, size: g.size) }
            }
            // the top card's picture, once the last one has finished falling apart (so nothing stutters)
            .task(id: cards.first.map { "\($0.k)|\(Int(g.size.width))x\(Int(g.size.height))|\(ToneColors.system)" }) {
                guard let top = cards.first, g.size.width > 0 else { return }
                let key = "\(top.k)|\(Int(g.size.width))x\(Int(g.size.height))|\(ToneColors.system)"
                if picture?.key == key { return }
                try? await Task.sleep(nanoseconds: 700_000_000)
                while !bursts.isEmpty || touch != nil {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if Task.isCancelled { return }
                }
                guard !Task.isCancelled else { return }
                picture = (key, CardPicture.make(top, g.size, store))
            }
        }
    }

    private var stamp: some View {
        let right = offset.width > 0
        let amount = min(abs(offset.width) / 110, 1)
        return Text(right ? "認識" : "不熟")
            .ffFont(.title, .heavy)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(right ? T.blueInk : T.rustInk)
            .background(RoundedRectangle(cornerRadius: 12).fill((right ? T.blue : T.rust).opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(right ? T.blueEdge : T.rustEdge, lineWidth: 3))
            .rotationEffect(.degrees(right ? -10 : 10))
            .padding(.top, 24)
            .opacity(amount)
            .allowsHitTesting(false)
    }

    private func drag(_ card: Card, size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in offset = v.translation; touch = v.location }
            .onEnded { v in
                touch = nil
                let w = v.translation.width + v.predictedEndTranslation.width * 0.25
                if abs(w) > 120 { fly(card, right: w > 0, size: size) }
                else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero } }
            }
    }

    /// the card falls apart where it is, and the next one comes up right away
    private func fly(_ card: Card, right: Bool, size: CGSize) {
        let key = "\(card.k)|\(Int(size.width))x\(Int(size.height))|\(ToneColors.system)"
        let pic = picture?.key == key ? picture!.pic : CardPicture.plain(card, size, store)
        let b = CardBurst(pic, right: right, offset: offset, angle: Double(offset.width / 18) * .pi / 180)
        bursts.append(b)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { offset = .zero; touch = nil }
        onSwipe(card, right)
        let id = b.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(CardBurst.life * 1_000_000_000) + 100_000_000)
            bursts.removeAll { $0.id == id }
        }
    }
}

/// a card's picture as a grid of little squares (one colour each), made ahead of time: drawing the card into a
/// picture takes a moment, so it's done while nothing moves, not when the card is swiped
struct CardPicture {
    let size: CGSize
    let cell: CGFloat
    let cols: Int, rows: Int
    let colors: [SIMD4<Float>]
    /// 聲調顏色: the word's tone colours; empty = blue / red
    let tones: [SIMD3<Float>]

    private static func grid(_ size: CGSize) -> (CGFloat, Int, Int) {
        let cell: CGFloat = max(8, min(13, size.width / 42))
        return (cell, max(1, Int(size.width / cell)), max(1, Int(size.height / cell)))
    }
    private static var base: SIMD3<Float> {
        let c = UIColor(T.fn).cgColor.components ?? [0.17, 0.17, 0.18, 1]
        return SIMD3<Float>(Float(c[0]), Float(c.count > 2 ? c[1] : c[0]), Float(c.count > 2 ? c[2] : c[0]))
    }

    /// the card drawn into a picture, made as small as the grid (one pixel = one square)
    @MainActor static func make(_ card: Card, _ size: CGSize, _ store: Store) -> CardPicture {
        make(card, size, store, WordCard(card: card, isTop: true).environmentObject(store))
    }
    /// any card's look drawn into a picture (the side cards of the characters)
    @MainActor static func make<V: View>(_ card: Card, _ size: CGSize, _ store: Store, _ view: V) -> CardPicture {
        let (cell, cols, rows) = grid(size)
        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        let r = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        r.scale = 0.5
        if let img = r.cgImage {
            px.withUnsafeMutableBytes { buf in
                if let ctx = CGContext(data: buf.baseAddress, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.interpolationQuality = .medium
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: cols, height: rows))
                }
            }
        }
        return build(size, cell, cols, rows, px, tones(card, store))
    }

    /// no picture yet (swiped very quickly): the card's own colour
    @MainActor static func plain(_ card: Card, _ size: CGSize, _ store: Store) -> CardPicture {
        let (cell, cols, rows) = grid(size)
        return build(size, cell, cols, rows, nil, tones(card, store))
    }

    private static func build(_ size: CGSize, _ cell: CGFloat, _ cols: Int, _ rows: Int, _ px: [UInt8]?, _ tones: [SIMD3<Float>]) -> CardPicture {
        let bb = base
        var cs: [SIMD4<Float>] = []
        cs.reserveCapacity(cols * rows)
        let rr = Float(28 / cell)
        for y in 0..<rows {
            for x in 0..<cols {
                // outside the rounded corners: nothing
                let fx = Float(x) + 0.5, fy = Float(y) + 0.5
                let rx = min(fx, Float(cols) - fx), ry = min(fy, Float(rows) - fy)
                var inside = true
                if rx < rr && ry < rr { let dx = rr - rx, dy = rr - ry; inside = dx * dx + dy * dy <= rr * rr }
                var c = bb
                if let px {
                    // (CoreGraphics' rows start at the bottom)
                    let o = ((rows - 1 - y) * cols + x) * 4
                    let a = Float(px[o + 3]) / 255
                    c = SIMD3<Float>(Float(px[o]), Float(px[o + 1]), Float(px[o + 2])) / 255 + bb * (1 - a)
                }
                cs.append(SIMD4<Float>(c.x, c.y, c.z, inside ? 1 : 0))
            }
        }
        return CardPicture(size: size, cell: cell, cols: cols, rows: rows, colors: cs, tones: tones)
    }

    /// the word's characters in their tone colours (only when 聲調顏色 is on)
    @MainActor private static func tones(_ card: Card, _ store: Store) -> [SIMD3<Float>] {
        guard ToneColors.system != 0 else { return [] }
        var ts: [SIMD3<Float>] = []
        let han = store.cardHan(card, UserDefaults.standard.object(forKey: "place") as? Int ?? -1, base: T.blueInk)
        for run in han.runs {
            guard let fg = run.swiftUI.foregroundColor else { continue }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(fg).getRed(&r, green: &g, blue: &b, alpha: &a)
            let n = han[run.range].characters.filter { !$0.isWhitespace }.count
            for _ in 0..<n { ts.append(SIMD3<Float>(Float(r), Float(g), Float(b))) }
        }
        return ts
    }
}

/// a card falling apart: its picture's squares, each with its own way to go
struct CardBurst: Identifiable {
    let id = UUID()
    let start = Date()
    let right: Bool
    let offset: CGSize
    let angle: Double
    let pic: CardPicture
    let rnd: [SIMD4<Float>]
    static let life: Double = 1.1
    var size: CGSize { pic.size }

    init(_ pic: CardPicture, right: Bool, offset: CGSize, angle: Double) {
        self.pic = pic; self.right = right; self.offset = offset; self.angle = angle
        rnd = (0..<(pic.cols * pic.rows)).map { _ in
            SIMD4<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1))
        }
    }
}

/// draws the falling-apart cards
struct CardDust: View {
    let bursts: [CardBurst]
    /// how far past the stack it draws
    var pad: CGFloat = 0
    static let pad: CGFloat = 700
    // 認識: blue; 不熟: red
    private static let blue = SIMD3<Float>(0.43, 0.66, 1.0)
    private static let red = SIMD3<Float>(1.0, 0.42, 0.40)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: bursts.isEmpty)) { tl in
            Canvas(rendersAsynchronously: true) { ctx, size in
                let now = tl.date
                for b in bursts { draw(b, now.timeIntervalSince(b.start), in: &ctx, size) }
            }
            // drawn on the graphics chip (Metal), not by the processor: the drawing covers the whole screen, and the
            // moving backgrounds underneath are busy too
            .drawingGroup()
        }
    }

    private func draw(_ b: CardBurst, _ t: Double, in ctx: inout GraphicsContext, _ size: CGSize) {
        guard t >= 0, t < CardBurst.life else { return }
        // (the card was moved, then turned about the middle of the stack)
        let cx = Double(size.width) / 2, cy = Double(size.height) / 2      // (the padding is the same all round)
        let ox = Double(b.offset.width), oy = Double(b.offset.height)
        let bw = Double(b.size.width), bh = Double(b.size.height)
        let ca = cos(b.angle), sa = sin(b.angle)
        let tint = b.right ? Self.blue : Self.red
        let tones = b.pic.tones
        let c = Double(b.pic.cell)
        let cols = b.pic.cols, rows = b.pic.rows
        for y in 0..<rows {
            for x in 0..<cols {
                let i = y * cols + x
                let col = b.pic.colors[i]
                if col.w == 0 { continue }
                let r = b.rnd[i]
                let u = (Double(x) + 0.5) / Double(cols)          // 0 = left, 1 = right
                // the side it's going to goes first, like a wind blowing it away
                let delay = (b.right ? (1 - u) : u) * 0.28 + Double(r.x) * 0.12
                let s = t - delay
                // the square's place on the card (turned and moved like the card)
                let lx = (Double(x) + 0.5) * c - bw / 2 + ox, ly = (Double(y) + 0.5) * c - bh / 2 + oy
                var px = cx + lx * ca - ly * sa, py = cy + lx * sa + ly * ca
                var alpha = 1.0, k: Float = 0, sc = 1.0
                if s > 0 {
                    k = Float(min(s / 0.22, 1))                         // the colour turns blue / red
                    let left = CardBurst.life - delay
                    alpha = max(0, 1 - s / max(left, 0.3))
                    sc = 1 - 0.45 * s / max(left, 0.3)
                    if b.right {
                        // up and away to the right, faster and faster, swaying a little
                        px += (40 + Double(r.y) * 110) * s + sin(s * 7 + Double(r.z) * 6) * 6
                        py -= (60 + Double(r.w) * 120) * s + 260 * s * s
                    } else {
                        // out to the left, then falling
                        px -= (50 + Double(r.y) * 120) * s
                        py += (-40 + Double(r.w) * 60) * s + 620 * s * s
                    }
                }
                // 聲調顏色 on: the word's tone colours, mixed all over the card (each square takes one of them)
                let to = tones.isEmpty ? tint : tones[min(Int(r.z * Float(tones.count)), tones.count - 1)]
                let rgb = SIMD3<Float>(col.x, col.y, col.z) * (1 - k) + to * k
                let w = c * sc
                ctx.fill(Path(CGRect(x: px - w / 2, y: py - w / 2, width: w, height: w)),
                         with: .color(Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z)).opacity(alpha)))
            }
        }
    }
}

/// ✕ / ↺ / ✓ buttons under a stack
struct SwipeButtons: View {
    var leftLabel = "不熟"
    var rightLabel = "認識"
    var canUndo = false
    var onLeft: () -> Void
    var onRight: () -> Void
    var onUndo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 22) {
            round("xmark", leftLabel, T.rust, T.rustEdge, T.rustInk, onLeft)
                .keyboardShortcut(.leftArrow, modifiers: [])
            if let onUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .scaledFont(18, weight: .bold)
                        .frame(width: 46, height: 46)
                        .foregroundStyle(canUndo ? T.oliveInk : T.fnEdge)
                        .glassSurface(Circle(), tint: T.fn.opacity(0.4), interactive: true)
                }
                .disabled(!canUndo)
                .keyboardShortcut("z", modifiers: .command)
                .accessibilityLabel("復原")
            }
            round("checkmark", rightLabel, T.blue, T.blueEdge, T.blueInk, onRight)
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        // one piece of Liquid Glass across the three
        .padding(.horizontal, 14).padding(.vertical, 8)
        .modifier(GlassBar())
    }

    private func round(_ icon: String, _ label: String, _ fill: Color, _ edge: Color, _ ink: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon).scaledFont(22, weight: .heavy)
                Text(label).ffFont(.caption2, .bold)
            }
            .frame(width: 68, height: 68)
            .foregroundStyle(ink)
            .glassSurface(Circle(), tint: edge.opacity(0.55), interactive: true, fallback: fill, edge: edge)
        }
        .accessibilityLabel(label)
    }
}

/// 新詞: go through the dictionary, most common words first.
struct NewDeckView: View {
    @EnvironmentObject var store: Store
    @AppStorage("autoPlay") private var autoPlay = false
    @AppStorage("topic") private var taigiTopic = -1
    /// 華語: an HSK level (-1 = all of them, level by level)
    @AppStorage("zhTopic") private var zhTopic = -1
    private var topicBinding: Binding<Int> { store.isZh ? $zhTopic : $taigiTopic }
    private var topic: Int { store.isZh ? zhTopic : taigiTopic }
    @State private var size: CGSize = .zero
    /// room for the characters' cards on both sides of the big card: an iPad, or a phone on its side
    private var wideSides: Bool { size.width >= 1150 || (size.width > size.height && size.width >= 560) }
    private var sideWidth: CGFloat { size.width >= 1150 ? 290 : max(150, (size.width - 80) * 0.27) }
    /// a phone on its side: smaller side cards
    private var smallSides: Bool { size.height < 520 }
    /// a phone on its side (short and wide)
    private var sideways: Bool { size.width > size.height && size.height < 520 && size.height > 0 }

    var body: some View {
        let queue = store.newQueue(4, topic: topic)
        VStack(spacing: sideways ? 0 : 18) {
            // (a phone on its side: no counts, no buttons, no tab bar; just the cards)
            if !sideways {
                Text("已看 \(store.seenCount) / \(store.cards.count)　熟悉 \(store.knownCount)　不熟 \(store.unknownCount)")
                    .ffFont(.footnote).foregroundStyle(T.muted)
            }
            if queue.isEmpty {
                Spacer()
                Text(topic < 0 ? "全部的詞都看過了！" : "這個主題的詞都看過了！").ffFont(.title3).foregroundStyle(T.muted)
                Spacer()
            } else {
                HStack(alignment: .top, spacing: smallSides ? 14 : 24) {
                    // iPad (wide enough), 華語: the word's characters beside the card
                    if wideSides, let top = queue.first { CharSideColumn(word: top, side: 0, small: smallSides).frame(width: sideWidth) }
                    DeckArea(cards: queue, onSwipe: { card, right in
                        store.mark(card, known: right)
                    }, undo: {
                        store.undo()
                    }, buttons: !sideways)
                    .frame(maxWidth: 560)
                    .environment(\.compactCard, sideways)
                    if wideSides, let top = queue.first { CharSideColumn(word: top, side: 1, small: smallSides).frame(width: sideWidth) }
                }
            }
        }
        .padding()
        .frame(maxWidth: wideSides ? 1260 : 560)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .toolbar(sideways ? .hidden : .automatic, for: .tabBar)
        .animation(.snappy, value: sideways)
        .appBackground()
        .rootPage("新詞") {
            if !store.topics.isEmpty {
            Menu {
                if store.isZh {
                    Picker("詞表", selection: $store.zhList) {
                        ForEach(0..<Lang.listNames.count, id: \.self) { Text(Lang.listNames[$0]).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Picker(store.isZh ? "等級" : "主題", selection: topicBinding) {
                    Text(store.isZh ? "全部（從第一級開始）" : "全部（最常用的先）").tag(-1)
                    ForEach(store.topics.filter { !store.isZh || $0.id < Lang.charTopicBase }) { t in Text("\(t.name)（\(t.count)）").tag(t.id) }
                }
                // 華語: the character cards, one level at a time
                let charTopics = store.isZh ? store.topics.filter { $0.id > Lang.charTopicBase } : []
                if !charTopics.isEmpty {
                    Picker("漢字", selection: topicBinding) {
                        ForEach(charTopics) { t in Text("\(t.name)（\(t.count)）").tag(t.id) }
                    }
                    .pickerStyle(.inline)
                }
                // 台語: the most common words / characters, 500 at a time
                if !store.isZh && !store.freqTopics.isEmpty {
                    Menu("常用詞（每組 \(Lang.freqSize) 個）") {
                        Picker("常用詞", selection: topicBinding) {
                            ForEach(store.freqTopics.filter { $0.id < Lang.freqCharBase }) { t in Text(t.name).tag(t.id) }
                        }
                        .pickerStyle(.inline)
                    }
                    Menu("常用字（每組 \(Lang.freqSize) 個）") {
                        Picker("常用字", selection: topicBinding) {
                            ForEach(store.freqTopics.filter { $0.id >= Lang.freqCharBase }) { t in Text(t.name).tag(t.id) }
                        }
                        .pickerStyle(.inline)
                    }
                }
            } label: {
                Label(topicName, systemImage: "square.stack.3d.up").labelStyle(.titleAndIcon)
                    .ffFont(.subheadline, .semibold)
            }
            }
        }
        .onChange(of: queue.first?.k) { _, _ in
            if autoPlay, let a = queue.first?.audio { Player.shared.play(a) }
        }
    }
}

extension NewDeckView {
    var topicName: String {
        (store.topics + store.freqTopics).first(where: { $0.id == topic })?.name ?? (store.isZh ? Lang.listNames[min(max(store.zhList, 0), 1)] + "・全部" : "全部")
    }
}

/// a stack plus its buttons
struct DeckArea: View {
    let cards: [Card]
    var leftLabel = "不熟"
    var rightLabel = "認識"
    let onSwipe: (Card, Bool) -> Void
    var undo: (() -> Void)? = nil
    /// the ✕ ↺ ✓ buttons (not on a phone on its side: there's no room)
    var buttons = true
    @EnvironmentObject var store: Store

    @State private var fling: SwipeStack.Fling?

    var body: some View {
        VStack(spacing: 18) {
            SwipeStack(cards: cards, onSwipe: onSwipe, fling: fling).frame(maxHeight: 680).frame(maxHeight: .infinity)
            if !cards.isEmpty && buttons {
                // the buttons swipe the card too (so it falls apart the same way)
                SwipeButtons(leftLabel: leftLabel, rightLabel: rightLabel, canUndo: store.canUndo,
                             onLeft: { fling = .init(right: false) },
                             onRight: { fling = .init(right: true) },
                             onUndo: undo)
            }
        }
    }
}

/// a capsule of Liquid Glass behind a row of buttons (iOS 26; frosted glass before)
struct GlassBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { content.glassEffect(.regular, in: Capsule()) }
        } else {
            content
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
    }
}

// MARK: - iPad, 新詞: the characters of the word beside the card

/// a character of the word on the card, as a small card of its own: the character, its reading and meanings.
/// Swipe it to mark the character card 認識 / 不熟; it falls apart like the big card and comes back (it's part of
/// the word on the big card, which stays until that one is swiped).
struct CharSideCard: View {
    let card: Card
    /// a phone on its side: smaller
    var small = false
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage(ZhMeaning.key) private var zhEnglish = false

    private var ch: String { Lang.charOf(card.k) ?? card.h }
    private var english: [String]? {
        guard card.isZh, zhEnglish, let d = store.zh, let e = ZhCharSheet.entry(d, ch) else { return nil }
        return e.enList.isEmpty ? nil : e.enList
    }

    var body: some View {
        HStack(alignment: .top, spacing: small ? 8 : 14) {
            VStack(spacing: 4) {
                Text(store.cardHan(card, place, base: T.blueInk)).toneGlow()
                    .scaledFont(small ? 38 : 56, weight: .medium)
                Text(store.cardRom(card, rom, place)).latFont(small ? 15 : 20).toneGlow().foregroundStyle(T.greenInk)
                    .lineLimit(1).minimumScaleFactor(0.5)
                // the character card's place now
                switch store.status(card) {
                case 1?: Chip(text: "熟悉", fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
                case 2?: Chip(text: "不熟", fill: T.rust, edge: T.rustEdge, ink: T.rustInk)
                default: EmptyView()
                }
            }
            .frame(minWidth: small ? 48 : 70)
            VStack(alignment: .leading, spacing: small ? 3 : 6) {
                if let en = english {
                    ForEach(Array(en.prefix(small ? 3 : 4).enumerated()), id: \.offset) { i, t in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            EnNum(n: i + 1)
                            Text(t).ffFont(small ? .footnote : .subheadline).foregroundStyle(T.glyph).lineLimit(2)
                        }
                    }
                } else {
                    ForEach(Array(card.d.prefix(small ? 3 : 4).enumerated()), id: \.offset) { i, d in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            NumBadge(n: i + 1)
                            Text(d.t).ffFont(small ? .footnote : .subheadline).foregroundStyle(T.glyph).lineLimit(2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(small ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(CardSurface(frosted: true))
        .contentShape(RoundedRectangle(cornerRadius: 28))
    }
}

/// a side card you can swipe: right = 認識, left = 不熟 (the character card); then it comes back
struct CharSideSwipe: View {
    let card: Card
    var small = false
    @EnvironmentObject var store: Store
    @State private var offset: CGSize = .zero
    @State private var bursts: [CardBurst] = []
    @State private var gone = false
    @State private var picture: (key: String, pic: CardPicture)?
    @State private var writing = false

    var body: some View {
        GeometryReader { g in
            ZStack {
                if !gone {
                    CharSideCard(card: card, small: small)
                        .overlay { CardLight(swipe: max(-1, min(1, offset.width / 110)), touch: nil) }
                        // write this character (手寫練習), then back to the cards
                        .overlay(alignment: .bottomTrailing) {
                            Button { writing = true } label: {
                                Image(systemName: "pencil.and.scribble")
                                    .font(.system(size: small ? 14 : 17, weight: .semibold))
                                    .foregroundStyle(T.muted)
                                    .frame(width: small ? 32 : 38, height: small ? 32 : 38)
                                    // (quiet: see-through, in the theme's own colours)
                                    .background(Circle().fill(.ultraThinMaterial))
                                    .background(Circle().fill(T.fn.opacity(0.35)))
                                    .overlay(Circle().stroke(T.fnEdge.opacity(0.6), lineWidth: 1))
                            }
                            .buttonStyle(SwellButtonStyle())
                            .padding(small ? 8 : 12)
                            .accessibilityLabel("寫這個字")
                        }
                        .offset(offset)
                        .rotationEffect(.degrees(Double(offset.width / 22)))
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { offset = $0.translation }
                                .onEnded { v in
                                    let w = v.translation.width + v.predictedEndTranslation.width * 0.25
                                    if abs(w) > 90 { fly(right: w > 0, size: g.size) }
                                    else { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { offset = .zero } }
                                })
                        .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .identity))
                }
                if !bursts.isEmpty {
                    CardDust(bursts: bursts, pad: CardDust.pad).padding(-CardDust.pad).allowsHitTesting(false)
                }
            }
            .fullScreenCover(isPresented: $writing) {
                HandwritingView(only: [Lang.charOf(card.k) ?? card.h],
                                given: card.isZh ? [:] : [card.h: card]).environmentObject(store)
            }
            // its picture, made ahead of time (see CardPicture)
            .task(id: "\(card.k)|\(Int(g.size.width))x\(Int(g.size.height))|\(ToneColors.system)|\(store.status(card) ?? 0)") {
                let key = "\(card.k)|\(Int(g.size.width))x\(Int(g.size.height))|\(ToneColors.system)|\(store.status(card) ?? 0)"
                guard g.size.width > 0, picture?.key != key else { return }
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                picture = (key, CardPicture.make(card, g.size, store, CharSideCard(card: card, small: small).environmentObject(store)))
            }
        }
    }

    private func fly(right: Bool, size: CGSize) {
        let pic = picture?.pic.size == size ? picture!.pic : CardPicture.plain(card, size, store)
        let b = CardBurst(pic, right: right, offset: offset, angle: Double(offset.width / 22) * .pi / 180)
        bursts.append(b)
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) { gone = true; offset = .zero }
        // 華語: the character card; 台語: the character's own dictionary word (read as in the big card's word)
        if Lang.charOf(card.k) != nil { store.setCharKnown(Lang.charOf(card.k) ?? card.h, right) }
        else { store.mark(card, known: right, undoable: false) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let id = b.id
        Task { @MainActor in
            // back again once the squares are mostly gone
            try? await Task.sleep(nanoseconds: 750_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { gone = false }
            try? await Task.sleep(nanoseconds: UInt64(CardBurst.life * 1_000_000_000) - 650_000_000)
            bursts.removeAll { $0.id == id }
        }
    }
}

/// the side cards of a word's characters: the 1st, 3rd, 5th… on the left (side 0), the 2nd, 4th, 6th… on the right
struct CharSideColumn: View {
    let word: Card
    let side: Int
    var small = false
    @EnvironmentObject var store: Store
    var body: some View {
        let cards = store.sideCards(word)
        VStack(spacing: small ? 10 : 16) {
            ForEach(Array(cards.enumerated()).filter { $0.offset % 2 == side }, id: \.offset) { _, c in
                CharSideSwipe(card: c, small: small).frame(height: small ? 140 : 210).id(word.k + "|" + c.k)
            }
            Spacer(minLength: 0)
        }
    }
}

/// 台語: each character's most common reading (its first word in the word list, which is in order of use)
nonisolated(unsafe) private var twCharCache: (count: Int, map: [String: Card]) = (0, [:])

extension Store {
    /// 台語: a character as its own dictionary word, read the most common way
    func twCharCard(_ ch: String) -> Card? {
        guard !isZh else { return nil }
        if twCharCache.count != cards.count {
            var m: [String: Card] = [:]
            for c in cards where c.h.count == 1 && m[c.h] == nil { m[c.h] = c }
            twCharCache = (cards.count, m)
        }
        return twCharCache.map[ch]
    }

    /// 台語 手寫練習: the characters of your 不熟 and 熟悉 words (that have a word of their own), in the order learned
    func twCharSets() -> (unknown: [String], known: [String]) {
        var unknown: [String] = [], known: [String] = []
        var su = Set<String>(), sk = Set<String>()
        let keys = progress.status.filter { !Lang.isZhKey($0.key) && Lang.charOf($0.key) == nil }
            .sorted { (progress.added[$0.key] ?? 0) > (progress.added[$1.key] ?? 0) }
        for (k, v) in keys {
            for ch in Dict.hanOf(k).map(String.init) where Zhuyin.isHan(ch.unicodeScalars.first!) && twCharCard(ch) != nil {
                if v == 2, su.insert(ch).inserted { unknown.append(ch) }
                if v == 1, sk.insert(ch).inserted { known.append(ch) }
            }
        }
        return (unknown.filter { !sk.contains($0) }, known.filter { !su.contains($0) })
    }

    /// the side cards of a word (2 characters or more): 華語, each character's card; 台語, each character's own
    /// word in the dictionary with the reading it has in this word (a character is often read several ways)
    func sideCards(_ word: Card) -> [Card] {
        if word.isZh {
            let chars = word.h.unicodeScalars.filter { Zhuyin.isHan($0) }.map(String.init)
            return chars.count > 1 ? chars.compactMap { card(for: Lang.charKey($0)) } : []
        }
        let han = Dict.hanOf(word.k).map(String.init)
        let codes = Dict.codesOf(word.k).split(separator: " ").map(String.init)
        guard han.count > 1, han.count == codes.count else { return [] }
        return zip(han, codes).compactMap { h, c in
            let k = h + "\t" + c
            if let x = card(for: k) { return x }
            // the same character and reading under another written form
            if let p = dict?.altParent[k], Dict.hanOf(p).count == 1 { return card(for: p) }
            return nil
        }
    }
}

/// a phone on its side: the big card is drawn smaller (there's little height)
private struct CompactCardKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var compactCard: Bool {
        get { self[CompactCardKey.self] }
        set { self[CompactCardKey.self] = newValue }
    }
}
