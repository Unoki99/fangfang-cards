import SwiftUI

// 聲調色球: hear a word, and colour each of its syllables with its tone, one ball per syllable, in the tone colours
// (the ones picked in 設定, even when the colours on the words are off). Every syllable counts, not only the last
// one as in 聲調練習. 台語 (its tones as written, before sandhi), 華語, 粵語 and 客語 (only words with a recording:
// no voice reads 客語).

struct ToneGameView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @StateObject private var stars = StarField()

    private struct Q: Identifiable { let id = UUID(); let card: Card; let tones: [Int]; let audio: String }

    @State private var queue: [Q] = []
    @State private var idx = 0
    @State private var picked: [Int] = []
    @State private var done = false
    @State private var score = 0
    @State private var combo = 0
    @State private var best = 0
    @State private var allRight = 0
    @State private var ballsAt: CGPoint = .zero

    private let roundSize = 12

    var body: some View {
        NavigationStack {
            Group {
                if queue.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(tr("找可以聽的詞…")).ffFont(.footnote).foregroundStyle(T.muted)
                    }
                } else if idx >= queue.count {
                    summary
                } else {
                    question(queue[idx])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .starBursts(stars)
            .appBackground()
            .navigationTitle(tr("聲調色球"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("結束"))
                }
            }
        }
        .onAppear { if queue.isEmpty { start() } }
    }

    // MARK: the words

    /// the tones the game asks for in this language, and their colours
    private var toneSet: [Int] {
        switch store.lang {
        case 1: return [1, 2, 3, 4, 0]
        case 2: return [1, 2, 3, 4, 5, 6]
        case 3: return ToneColors.hakTones.filter { ToneColors.hakColor($0) != nil }
        default: return [1, 2, 3, 4, 5, 7, 8]
        }
    }
    private func color(_ t: Int) -> Color {
        let c: Color?
        switch store.lang {
        case 1: c = ToneColors.zhColor(t)
        case 2: c = ToneColors.yueColor(t)
        case 3: c = ToneColors.hakColor(t)
        default: c = ToneColors.twColor(t)
        }
        return c ?? T.muted
    }
    private func name(_ t: Int) -> String {
        switch store.lang {
        case 1: return ZH_TONE_NAMES[t] ?? ""
        case 2: return YUE_TONE_NAMES[t] ?? ""
        default: return TONE_NAMES[t] ?? ""
        }
    }

    /// a word's tones, one per syllable (nil: it can't be asked)
    private func tones(_ c: Card) -> [Int]? {
        let set = Set(toneSet)
        var out: [Int] = []
        if c.isZh {
            guard let s = c.zs else { return nil }
            for x in s where x != "-" && x != "_" && !x.isEmpty { out.append(Zhuyin.tone(x)) }
        } else {
            guard let cs = c.c else { return nil }
            for code in cs { if let d = code.last?.wholeNumberValue { out.append(d) } }
        }
        guard !out.isEmpty, out.count <= 4, out.allSatisfy({ set.contains($0) }) else { return nil }
        return out
    }

    // unknown words first, then common words
    private func start() {
        var words = store.practiceCards.shuffled()
        let seen = Set(words.map(\.k))
        words += store.cards.prefix(2000).filter { !seen.contains($0.k) }.shuffled()
        var qs: [Q] = []
        for c in words where Lang.charOf(c.k) == nil {
            guard let a = c.audio, let t = tones(c) else { continue }
            qs.append(Q(card: c, tones: t, audio: a))
            if qs.count == roundSize { break }
        }
        queue = qs
        idx = 0; picked = []; done = false; score = 0; combo = 0; best = 0; allRight = 0
    }

    // MARK: one word

    private func question(_ q: Q) -> some View {
        VStack(spacing: 18) {
            HStack {
                Text("\(idx + 1) / \(queue.count)").ffFont(.footnote).foregroundStyle(T.muted)
                Spacer()
                if combo >= 2 { Text(tr("連對 \(combo)")).ffFont(.footnote, .bold).foregroundStyle(T.oliveInk) }
                Text(tr("\(score) 分")).ffFont(.footnote, .bold).foregroundStyle(T.greenInk)
            }
            Panel {
                VStack(spacing: 14) {
                    Text(done ? trs("答案") : trs("聽聽看，每個字是第幾聲？")).ffFont(.subheadline, .bold).foregroundStyle(T.oliveInk)
                    PlayButton(path: q.audio, size: 72)
                    // one ball per syllable: empty until picked
                    HStack(spacing: 14) {
                        ForEach(q.tones.indices, id: \.self) { i in ball(q, i) }
                    }
                    .background(GeometryReader { g in Color.clear.onAppear { ballsAt = CGPoint(x: g.frame(in: .global).midX, y: g.frame(in: .global).midY) } })
                    if done {
                        Text(store.cardHan(q.card, place, base: T.blueInk)).scaledFont(40, weight: .medium).toneGlow()
                        Text(store.cardRom(q.card, rom, place)).latFont(18).toneGlow()
                        if let m = q.card.d.first?.t { Text(m).ffFont(.subheadline).foregroundStyle(T.muted).lineLimit(2) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if done {
                Button { next() } label: {
                    Text(idx + 1 < queue.count ? trs("下一個") : trs("看結果")).ffFont(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .softButton()
            } else {
                // the tones to pick from, in their colours
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 12)], spacing: 12) {
                    ForEach(toneSet, id: \.self) { t in
                        Button { pick(t, q) } label: {
                            VStack(spacing: 4) {
                                Circle().fill(color(t)).frame(width: 44, height: 44)
                                    .overlay(Text(t == 0 ? "˙" : "\(t)").font(.system(size: 18, weight: .bold)).foregroundStyle(.black.opacity(0.7)))
                                    .shadow(color: color(t).opacity(0.6), radius: 8)
                                Text(name(t)).ffFont(.caption2).foregroundStyle(T.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !picked.isEmpty {
                    Button { picked.removeLast() } label: { Label(tr("退一格"), systemImage: "delete.left") }
                        .ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: q.id) { Player.shared.play(q.audio) }
    }

    private func ball(_ q: Q, _ i: Int) -> some View {
        let has = i < picked.count
        let right = has && picked[i] == q.tones[i]
        return ZStack {
            Circle()
                .fill(has ? color(picked[i]) : Color.clear)
                .overlay(Circle().stroke(has ? Color.clear : T.muted.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
                .frame(width: 46, height: 46)
                .shadow(color: has ? color(picked[i]).opacity(0.7) : .clear, radius: 10)
            if done {
                Image(systemName: right ? "checkmark" : "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(.black.opacity(0.75))
            }
        }
        .overlay(alignment: .bottom) {
            // (wrong: the right colour under it)
            if done && !right {
                Circle().fill(color(q.tones[i])).frame(width: 16, height: 16).offset(y: 22)
            }
        }
        .padding(.bottom, done ? 14 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: picked.count)
    }

    private func pick(_ t: Int, _ q: Q) {
        guard !done, picked.count < q.tones.count else { return }
        picked.append(t)
        if picked.count == q.tones.count { check(q) }
    }

    private func check(_ q: Q) {
        done = true
        let n = zip(picked, q.tones).filter { $0 == $1 }.count
        score += n * 10
        if n == q.tones.count {
            combo += 1; allRight += 1
            best = max(best, combo)
            score += combo >= 2 ? combo * 5 : 0
            stars.burst(at: ballsAt)
        } else {
            combo = 0
            Player.shared.play(q.audio)            // (hear it again with the answer)
        }
    }

    private func next() {
        idx += 1; picked = []; done = false
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Text(tr("\(score) 分")).scaledFont(44, weight: .bold).foregroundStyle(T.greenInk)
            Text(tr("全對 \(allRight) / \(queue.count)・最多連對 \(best)")).ffFont(.subheadline).foregroundStyle(T.muted)
            Button { start() } label: { Text(tr("再玩一次")).ffFont(.headline).padding(.horizontal, 24).padding(.vertical, 6) }
                .softButton()
        }
    }
}
