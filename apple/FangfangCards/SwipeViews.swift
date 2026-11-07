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
                        .offset(i == 0 ? offset : .zero)
                        .rotationEffect(.degrees(i == 0 ? Double(offset.width / 18) : 0))
                        .allowsHitTesting(i == 0)
                        .gesture(drag(card, size: g.size))
                        .zIndex(Double(10 - i))
                        .transition(.identity)          // (it turns into the squares instead)
                }
                // (much bigger than the stack, so the squares can fly off over the whole screen)
                CardDust(bursts: bursts, pad: CardDust.pad)
                    .padding(-CardDust.pad)
                    .allowsHitTesting(false).zIndex(20)
            }
            .onChange(of: fling) { _, f in
                if let f, let top = cards.first { fly(top, right: f.right, size: g.size) }
            }
        }
    }

    private var stamp: some View {
        let right = offset.width > 0
        let amount = min(abs(offset.width) / 110, 1)
        return Text(right ? "認識" : "不熟")
            .ffFont(.title, .heavy)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(right ? T.greenInk : T.rustInk)
            .background(RoundedRectangle(cornerRadius: 12).fill((right ? T.green : T.rust).opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(right ? T.greenEdge : T.rustEdge, lineWidth: 3))
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
        let b = CardBurst(card: card, right: right, size: size, offset: offset,
                          angle: Double(offset.width / 18) * .pi / 180, store: store)
        bursts.append(b)
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { offset = .zero; touch = nil }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { onSwipe(card, right) }
        let id = b.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(CardBurst.life * 1_000_000_000) + 100_000_000)
            bursts.removeAll { $0.id == id }
        }
    }
}

/// a card falling apart: its picture cut into little squares, each with its own way to go
struct CardBurst: Identifiable {
    let id = UUID()
    let start = Date()
    let right: Bool
    let size: CGSize
    let offset: CGSize
    let angle: Double
    let cell: CGFloat
    let cols: Int, rows: Int
    /// each square's colour (from the card's picture) and its own little differences
    let colors: [SIMD4<Float>]
    let rnd: [SIMD4<Float>]
    /// 聲調顏色: the colour of each character of the word (left to right); empty = blue / red
    let tones: [SIMD3<Float>]
    static let life: Double = 1.1

    @MainActor init(card: Card, right: Bool, size: CGSize, offset: CGSize, angle: Double, store: Store) {
        self.right = right; self.size = size; self.offset = offset; self.angle = angle
        let cell: CGFloat = max(7, min(12, size.width / 46))
        self.cell = cell
        let cols = max(1, Int(size.width / cell)), rows = max(1, Int(size.height / cell))
        self.cols = cols; self.rows = rows
        // the card's picture, made as small as the grid: one pixel = one square's colour
        var px = [UInt8](repeating: 0, count: cols * rows * 4)
        let r = ImageRenderer(content: WordCard(card: card, isTop: true).environmentObject(store)
            .frame(width: size.width, height: size.height))
        r.scale = 1
        if let img = r.cgImage {
            px.withUnsafeMutableBytes { buf in
                if let ctx = CGContext(data: buf.baseAddress, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: cols * 4,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    ctx.interpolationQuality = .medium
                    ctx.draw(img, in: CGRect(x: 0, y: 0, width: cols, height: rows))
                }
            }
        }
        // (the card's own colour where the picture has nothing)
        let base = UIColor(T.fn).cgColor.components ?? [0.17, 0.17, 0.18, 1]
        let bb = SIMD3<Float>(Float(base[0]), Float(base.count > 2 ? base[1] : base[0]), Float(base.count > 2 ? base[2] : base[0]))
        var cs: [SIMD4<Float>] = [], rs: [SIMD4<Float>] = []
        cs.reserveCapacity(cols * rows); rs.reserveCapacity(cols * rows)
        let radius = 28 / cell
        for y in 0..<rows {
            for x in 0..<cols {
                // outside the rounded corners: nothing
                let fx = Float(x) + 0.5, fy = Float(y) + 0.5
                let rx = min(fx, Float(cols) - fx), ry = min(fy, Float(rows) - fy)
                let rr = Float(radius)
                var inside = true
                if rx < rr && ry < rr { let dx = rr - rx, dy = rr - ry; inside = dx * dx + dy * dy <= rr * rr }
                // (CoreGraphics' rows start at the bottom)
                let o = ((rows - 1 - y) * cols + x) * 4
                let a = Float(px[o + 3]) / 255
                let c = SIMD3<Float>(Float(px[o]), Float(px[o + 1]), Float(px[o + 2])) / 255 + bb * (1 - a)
                cs.append(SIMD4<Float>(c.x, c.y, c.z, inside ? 1 : 0))
                rs.append(SIMD4<Float>(Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1), Float.random(in: 0...1)))
            }
        }
        colors = cs; rnd = rs
        // the word's characters in their tone colours (only when 聲調顏色 is on)
        var ts: [SIMD3<Float>] = []
        if ToneColors.system != 0 {
            let han = store.cardHan(card, UserDefaults.standard.object(forKey: "place") as? Int ?? -1, base: T.blueInk)
            for run in han.runs {
                guard let fg = run.swiftUI.foregroundColor else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, al: CGFloat = 0
                UIColor(fg).getRed(&r, green: &g, blue: &bl, alpha: &al)
                let n = han[run.range].characters.filter { !$0.isWhitespace }.count
                for _ in 0..<n { ts.append(SIMD3<Float>(Float(r), Float(g), Float(bl))) }
            }
        }
        tones = ts
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
        TimelineView(.animation(paused: bursts.isEmpty)) { tl in
            Canvas { ctx, size in
                let now = tl.date
                for b in bursts { draw(b, now.timeIntervalSince(b.start), in: &ctx, size) }
            }
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
        let tones = b.tones
        let c = Double(b.cell)
        for y in 0..<b.rows {
            for x in 0..<b.cols {
                let i = y * b.cols + x
                let col = b.colors[i]
                if col.w == 0 { continue }
                let r = b.rnd[i]
                let u = (Double(x) + 0.5) / Double(b.cols)          // 0 = left, 1 = right
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
                // 聲調顏色 on: each character's part of the card turns that character's tone colour
                let to = tones.isEmpty ? tint : tones[min(Int(u * Double(tones.count)), tones.count - 1)]
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

    var body: some View {
        let queue = store.newQueue(4, topic: topic)
        VStack(spacing: 18) {
            Text("已看 \(store.seenCount) / \(store.cards.count)　熟悉 \(store.knownCount)　不熟 \(store.unknownCount)")
                .ffFont(.footnote).foregroundStyle(T.muted)
            if queue.isEmpty {
                Spacer()
                Text(topic < 0 ? "全部的詞都看過了！" : "這個主題的詞都看過了！").ffFont(.title3).foregroundStyle(T.muted)
                Spacer()
            } else {
                DeckArea(cards: queue) { card, right in
                    store.mark(card, known: right)
                } undo: {
                    store.undo()
                }
            }
        }
        .padding()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
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
    @EnvironmentObject var store: Store

    @State private var fling: SwipeStack.Fling?

    var body: some View {
        VStack(spacing: 18) {
            SwipeStack(cards: cards, onSwipe: onSwipe, fling: fling).frame(maxHeight: 680).frame(maxHeight: .infinity)
            if !cards.isEmpty {
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
