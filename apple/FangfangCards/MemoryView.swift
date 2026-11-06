import SwiftUI

/// 翻牌配對: memory with 不熟 words. Half the cards are 漢字, half their readings; turn two over,
/// and keep them if they belong together.
struct MemoryView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("memoryPairs") private var pairCount = 6
    @StateObject private var stars = StarField()

    struct Tile: Identifiable {
        let id: Int
        let pair: Int           // which word
        let isHan: Bool
        let text: AttributedString
    }

    @State private var cards: [Card] = []
    @State private var tiles: [Tile] = []
    @State private var up: [Int] = []           // tile ids turned over, not matched yet
    @State private var matched: Set<Int> = []   // pair numbers found
    @State private var wrong: Set<Int> = []     // tile ids shown red for a moment
    @State private var moves = 0
    @State private var busy = false
    @State private var resumed = false

    /// a board left half way: the words, where each card lies, the pairs found, how many turns
    private struct Saved: Codable { let keys: [String]; let order: [Int]; let matched: [Int]; let moves: Int }
    private func saveNow() {
        guard !tiles.isEmpty, !done else { PracticeSave.clear("memory", zh: store.isZh); return }
        PracticeSave.save(Saved(keys: cards.map(\.k), order: tiles.map(\.id), matched: Array(matched), moves: moves),
                          "memory", zh: store.isZh, scope: store.practiceTopic)
    }
    private func restore() -> Bool {
        guard let s = PracticeSave.load(Saved.self, "memory", zh: store.isZh, scope: store.practiceTopic) else { return false }
        let cs = s.keys.compactMap { store.card(for: $0) }
        guard cs.count == s.keys.count, cs.count >= 2, s.order.count == cs.count * 2 else { return false }
        var byID: [Int: Tile] = [:]
        for (i, c) in cs.enumerated() {
            for t in makeTiles(i, c) { byID[t.id] = t }
        }
        let t = s.order.compactMap { byID[$0] }
        guard t.count == s.order.count else { return false }
        cards = cs; tiles = t; matched = Set(s.matched); moves = s.moves
        up = []; wrong = []; busy = false
        resumed = true
        return true
    }
    private func makeTiles(_ i: Int, _ c: Card) -> [Tile] {
        var h = AttributedString(c.h)
        h.foregroundColor = T.glyph
        return [Tile(id: i * 2, pair: i, isHan: true, text: h),
                Tile(id: i * 2 + 1, pair: i, isHan: false, text: store.cardRom(c, rom, place))]
    }

    private var done: Bool { !tiles.isEmpty && matched.count == cards.count }

    var body: some View {
        NavigationStack {
            Group {
                if tiles.isEmpty {
                    Text("「不熟」裡至少要有兩個詞才能玩。").foregroundStyle(T.muted)
                } else if done {
                    summary
                } else {
                    board
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { ResumedNote(shown: $resumed).padding(.top, 4) }
            .starBursts(stars)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("結束")
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !tiles.isEmpty && !done && (moves > 0 || !matched.isEmpty) { RestartPracticeButton { build() } }
                }
                ToolbarItem(placement: .principal) {
                    if !tiles.isEmpty && !done {
                        Text("翻牌配對　\(matched.count)／\(cards.count)　翻了 \(moves) 次")
                            .ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("幾對", selection: $pairCount) {
                            ForEach([4, 6, 8, 10], id: \.self) { Text("\($0) 對").tag($0) }
                        }
                    } label: { Image(systemName: "square.grid.3x3") }
                    .accessibilityLabel("幾對")
                }
            }
        }
        .onAppear {
            if store.dict == nil { store.loadDict() }
            if tiles.isEmpty && !restore() { build() }
        }
        .onChange(of: pairCount) { build() }
        .onChange(of: rom) { build() }
        .onChange(of: moves) { saveNow() }
        .onChange(of: matched) { saveNow() }
    }

    // MARK: the game

    private func build() {
        var picked: [Card] = []
        var hans = Set<String>(), roms = Set<String>()
        for c in store.practiceCards.shuffled() {
            let r = c.rom(min(max(rom, 0), 2), place)
            if hans.contains(c.h) || roms.contains(r) { continue }
            hans.insert(c.h); roms.insert(r)
            picked.append(c)
            if picked.count >= pairCount { break }
        }
        if picked.count < 2 { cards = []; tiles = []; return }
        cards = picked
        var t: [Tile] = []
        for (i, c) in picked.enumerated() { t += makeTiles(i, c) }
        tiles = t.shuffled()
        up = []; matched = []; wrong = []; moves = 0; busy = false
        saveNow()
    }

    private func tap(_ t: Tile) {
        guard !busy, !matched.contains(t.pair), !up.contains(t.id) else { return }
        withAnimation(.spring(duration: 0.35)) { up.append(t.id) }
        guard up.count == 2 else { return }
        moves += 1
        let a = tiles.first { $0.id == up[0] }!, b = tiles.first { $0.id == up[1] }!
        if a.pair == b.pair {
            let c = cards[a.pair]
            if let au = c.audio { Player.shared.play(au) }
            withAnimation(.snappy) { matched.insert(a.pair); up = [] }
            stars.burst(at: CGPoint(x: CGFloat.random(in: 80...320), y: CGFloat.random(in: 200...380)))
        } else {
            busy = true
            withAnimation(.snappy) { wrong = Set(up) }
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.spring(duration: 0.35)) { up = []; wrong = [] }
                busy = false
            }
        }
    }

    // MARK: views

    private var board: some View {
        GeometryReader { geo in
            let cols = geo.size.width > 600 ? 4 : 3
            let rows = Int(ceil(Double(tiles.count) / Double(cols)))
            let spacing: CGFloat = 10
            let h = max(64, min(130, (geo.size.height - 32 - CGFloat(rows - 1) * spacing) / CGFloat(rows)))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: cols), spacing: spacing) {
                    ForEach(tiles) { t in
                        tileView(t).frame(height: h)
                            .onTapGesture { tap(t) }
                    }
                }
                .padding(16)
            }
        }
    }

    private func tileView(_ t: Tile) -> some View {
        let open = up.contains(t.id) || matched.contains(t.pair)
        let isMatched = matched.contains(t.pair)
        let isWrong = wrong.contains(t.id)
        let fill = isMatched ? T.green : (isWrong ? T.rust : (open ? T.fn : T.blue.opacity(0.55)))
        let edge = isMatched ? T.greenEdge : (isWrong ? T.rustEdge : (open ? T.fnEdge : T.blueEdge))
        return ZStack {
            RoundedRectangle(cornerRadius: 14).fill(fill)
            RoundedRectangle(cornerRadius: 14).stroke(edge, lineWidth: 1.5)
            if open {
                Group {
                    if t.isHan {
                        Text(t.text).scaledFont(26, weight: .semibold)
                    } else {
                        Text(t.text).latFont(17)
                    }
                }
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
                .padding(6)
                .opacity(isMatched ? 0.75 : 1)
            } else {
                Image(systemName: t.isHan ? "character" : "textformat.abc")
                    .ffFont(.title3).foregroundStyle(T.blueInk.opacity(0.7))
                    .scaleEffect(x: -1)      // the card is turned around: turn the picture back
            }
        }
        .rotation3DEffect(.degrees(open ? 0 : 180), axis: (x: 0, y: 1, z: 0))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel(open ? String(t.text.characters) : (t.isHan ? "漢字牌" : "讀音牌"))
        .accessibilityAddTraits(.isButton)
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles").font(.system(size: 44)).foregroundStyle(T.greenInk)
            Text("全部配對了！").ffFont(.title2, .bold).foregroundStyle(T.glyph)
            Text("\(cards.count) 對，翻了 \(moves) 次").foregroundStyle(T.muted)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(cards, id: \.k) { c in
                    HStack(spacing: 10) {
                        Text(c.h).scaledFont(18, weight: .semibold).foregroundStyle(T.glyph)
                        Text(store.cardRom(c, rom, place)).latFont(15).foregroundStyle(T.greenInk)
                        Text(c.d.first?.t ?? "").ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
            HStack(spacing: 12) {
                Button { build() } label: { Label("再玩一次", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                    .softButton()
                Button { dismiss() } label: { Label("結束", systemImage: "checkmark").frame(maxWidth: .infinity) }
                    .softButton()
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
    }
}
