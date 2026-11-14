import SwiftUI

// MARK: - 遊戲: words falling down the screen
//
// 看讀音找字: the reading of one of the falling words is at the bottom; tap that word before it reaches the bottom.
// 看字找讀音: the word is at the bottom and readings fall; tap its reading.
// The further you get, the faster they fall. Three hearts: the right one reaching the bottom costs a heart, a wrong
// tap half a heart (its pixels fly to the hearts). A right tap bursts into pixels flying up.

@MainActor
final class FallingGame: ObservableObject {
    struct Drop: Identifiable {
        let id = UUID()
        let card: Card
        var x: CGFloat
        var y: CGFloat
    }
    /// pixels flying from a wrong tap to the hearts
    struct Flyer: Identifiable {
        let id = UUID()
        let from: CGPoint
        let born: Date
        let color: Color
        let dx: CGFloat, dy: CGFloat
    }

    @Published var drops: [Drop] = []
    @Published var target: Card?
    /// half hearts left (3 hearts = 6)
    @Published var halves = 6
    @Published var score = 0
    @Published var over = false
    @Published var flyers: [Flyer] = []

    private var pool: [Card] = []
    var size: CGSize = .zero
    /// points per second
    private(set) var speed: CGFloat = 55
    private var sinceSpawn: Double = 10
    let bottomBand: CGFloat = 96

    func start(_ cards: [Card]) {
        pool = cards
        drops = []; target = nil; halves = 6; score = 0; over = false; speed = 55; sinceSpawn = 10; flyers = []
    }

    private func spawn(_ c: Card) {
        guard size.width > 0 else { return }
        // (not on top of a word near the top already)
        var x = CGFloat.random(in: 70...max(71, size.width - 70))
        for _ in 0..<6 where drops.contains(where: { abs($0.x - x) < 110 && $0.y < 120 }) {
            x = CGFloat.random(in: 70...max(71, size.width - 70))
        }
        drops.append(Drop(card: c, x: x, y: -30))
    }

    private func newTarget() {
        // one that's falling and still high enough to be reached, else a new one
        let open = drops.filter { $0.y < size.height * 0.45 }
        if let d = open.randomElement() { target = d.card; return }
        guard let c = pool.randomElement() else { return }
        target = c
        spawn(c)
    }

    func tick(_ dt: Double) {
        guard !over, size.height > 0, !pool.isEmpty else { return }
        let floor = size.height - bottomBand
        for i in drops.indices { drops[i].y += speed * CGFloat(dt) }
        // the right one reached the bottom: a heart lost
        if let t = target, drops.contains(where: { $0.card.k == t.k && $0.y > floor }) {
            drops.removeAll { $0.card.k == t.k }
            lose(2)
            target = nil
        }
        drops.removeAll { $0.y > floor + 40 }
        sinceSpawn += dt
        let every = max(0.7, 1.9 - Double(score) * 0.04)
        if sinceSpawn >= every && drops.count < 7 {
            sinceSpawn = 0
            // (another word than the ones already falling)
            let falling = Set(drops.map { $0.card.k })
            if let c = pool.filter({ !falling.contains($0.k) }).randomElement() ?? pool.randomElement() { spawn(c) }
        }
        if target == nil || !drops.contains(where: { $0.card.k == target?.k }) { newTarget() }
        speed += CGFloat(dt) * 1.4
        let now = Date()
        flyers.removeAll { now.timeIntervalSince($0.born) > 0.7 }
    }

    /// a tap on a falling word: true when it's the right one
    func tap(_ d: Drop) -> Bool {
        guard !over else { return false }
        if d.card.k == target?.k {
            drops.removeAll { $0.id == d.id }
            score += 1
            speed += 4
            target = nil
            newTarget()
            return true
        }
        lose(1)
        return false
    }

    private func lose(_ n: Int) {
        halves = max(0, halves - n)
        if halves == 0 { over = true }
    }

    func flyToHearts(from p: CGPoint, to heart: CGPoint) {
        let now = Date()
        for i in 0..<10 {
            flyers.append(Flyer(from: CGPoint(x: p.x + CGFloat.random(in: -14...14), y: p.y + CGFloat.random(in: -10...10)),
                                born: now.addingTimeInterval(Double(i) * 0.015),
                                color: StarField.colors[i % StarField.colors.count],
                                dx: heart.x - p.x, dy: heart.y - p.y))
        }
    }
}

struct FallingGameView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("fallingBest") private var best = 0
    @StateObject private var game = FallingGame()
    @StateObject private var stars = StarField()
    /// nil: choosing; 0 看讀音找字; 1 看字找讀音
    @State private var mode: Int?
    private let timer = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()

    private var cards: [Card] {
        let p = store.practiceCards + store.knownCards.prefix(200)
        // (words of 1–4 characters, so they fit as they fall)
        return Array(p.filter { (1...4).contains($0.h.count) }.prefix(400))
    }

    private func reading(_ c: Card) -> String { String(store.cardRom(c, rom, place).characters) }

    var body: some View {
        NavigationStack {
            Group {
                if let m = mode { play(m) } else { menu }
            }
            .appBackground()
            .navigationTitle(tr("遊戲"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if mode != nil && !game.over { mode = nil } else { dismiss() } } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(tr("結束"))
                }
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 18) {
            Spacer()
            Text(tr("字從上面掉下來，在它掉到底以前點對的那一個。越玩越快。")).ffFont(.subheadline).foregroundStyle(T.muted)
                .multilineTextAlignment(.center).padding(.horizontal)
            ForEach(0..<2, id: \.self) { m in
                Button {
                    game.start(cards.shuffled())
                    mode = m
                } label: {
                    VStack(spacing: 6) {
                        Text(m == 0 ? trs("看讀音找字") : trs("看字找讀音")).ffFont(.title3, .bold)
                        Text(m == 0 ? trs("下面是讀音，點掉下來的字") : trs("下面是字，點掉下來的讀音")).ffFont(.caption).foregroundStyle(T.muted)
                    }
                    .frame(maxWidth: 360, minHeight: 70)
                }
                .prominentButton(T.btnEdge)
                .disabled(cards.count < 4)
            }
            if cards.count < 4 {
                Text(tr("先在「新詞」往左滑幾個詞（不熟），才有字可以玩。")).ffFont(.footnote).foregroundStyle(T.muted)
            }
            if best > 0 { Text(tr("最高分：\(best)")).ffFont(.footnote).foregroundStyle(T.muted) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func play(_ m: Int) -> some View {
        GeometryReader { g in
            let heart = CGPoint(x: g.size.width - 70, y: 22)
            ZStack(alignment: .top) {
                // the falling words
                ForEach(game.drops) { d in
                    Button {
                        let p = CGPoint(x: d.x, y: d.y)
                        if game.tap(d) {
                            stars.burst(at: p)
                        } else {
                            game.flyToHearts(from: p, to: heart)
                        }
                    } label: {
                        Group {
                            if m == 0 {
                                KaitiText(text: d.card.h, size: 34, color: T.glyph)
                            } else {
                                Text(reading(d.card)).latFont(20).foregroundStyle(T.greenInk)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.85)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .position(x: d.x, y: d.y)
                }
                // pixels flying to the hearts (a wrong tap)
                TimelineView(.animation(paused: game.flyers.isEmpty)) { tl in
                    Canvas { ctx, _ in
                        for f in game.flyers {
                            let t = min(max(tl.date.timeIntervalSince(f.born) / 0.55, 0), 1)
                            let e = t * t * (3 - 2 * t)
                            let p = CGPoint(x: f.from.x + f.dx * e, y: f.from.y + f.dy * e)
                            ctx.fill(Path(CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(f.color.opacity(1 - t * 0.6)))
                        }
                    }
                }
                .allowsHitTesting(false)
                StarLayer(field: stars).allowsHitTesting(false)
                // hearts and score
                HStack {
                    Text(tr("分數 \(game.score)")).latFont(16).foregroundStyle(T.glyph)
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            let left = game.halves - i * 2
                            Image(systemName: left >= 2 ? "heart.fill" : (left == 1 ? "heart.lefthalf.filled" : "heart"))
                                .foregroundStyle(ToneColors.red)
                        }
                    }
                    .font(.title3)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                // what to find, at the bottom
                VStack {
                    Spacer()
                    Group {
                        if let t = game.target {
                            if m == 0 {
                                Text(reading(t)).latFont(26).foregroundStyle(T.greenInk)
                            } else {
                                KaitiText(text: t.h, size: 40, color: T.glyph)
                            }
                        } else {
                            Text(" ").latFont(26)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: game.bottomBand - 16)
                    .background(Rectangle().fill(T.btn.opacity(0.5)))
                    .overlay(Rectangle().fill(T.btnEdge).frame(height: 2), alignment: .top)
                }
                if game.over { gameOver(m) }
            }
            .onAppear { game.size = g.size }
            .onChange(of: g.size) { game.size = g.size }
            .onReceive(timer) { _ in
                game.tick(1.0 / 30)
                stars.sweep(height: g.size.height, now: Date())
            }
        }
        .clipped()
    }

    private func gameOver(_ m: Int) -> some View {
        VStack(spacing: 14) {
            Text(tr("遊戲結束")).ffFont(.title, .bold).foregroundStyle(T.glyph)
            Text(tr("分數 \(game.score)")).ffFont(.title2).foregroundStyle(T.btnInk)
            if game.score >= best && game.score > 0 { Text(tr("新的最高分！")).foregroundStyle(T.oliveInk) }
            Button { game.start(cards.shuffled()) } label: { Text(tr("再玩一次")).frame(minWidth: 180, minHeight: 36) }
                .prominentButton(T.btnEdge)
            Button(tr("換一種玩法")) { mode = nil }.foregroundStyle(T.muted)
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(T.fn.opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(T.fnEdge, lineWidth: 1.5))
        .frame(maxHeight: .infinity)
        .onAppear { if game.score > best { best = game.score } }
    }
}
