import SwiftUI

enum QuizKind: CaseIterable {
    case meaningToWord   // 華語意思 → 選台語詞
    case wordToMeaning   // 台語詞 → 選意思
    case listen          // 聽發音 → 選詞
    case fillBlank       // 例句填空
    case romanization    // 漢字 → 選讀音
}

struct Question: Identifiable {
    let id = UUID()
    let card: Card
    let kind: QuizKind
    let options: [Card]
    let example: Example?
}

struct StudyView: View {
    /// true: only 例句填空 (fill in the blank in example sentences)
    var blanksOnly = false
    /// only these words (本週學習); nil = all of 不熟
    var words: [Card]? = nil
    /// 本週學習's final test: one question per word, nothing asked again, a score at the end
    var test = false
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("goal") private var goal = 3
    @AppStorage("sessionSize") private var sessionSize = 10

    @State private var queue: [Question] = []
    @State private var idx = 0
    @State private var chosen: Card?
    @State private var right = 0
    @State private var wrong = 0
    @State private var learned: [Card] = []
    @State private var retried: Set<String> = []
    /// the test: words answered wrong
    @State private var missed: [Card] = []
    @StateObject private var stars = StarField()
    @State private var resumed = false

    // MARK: a round left half way

    private struct SavedQ: Codable { let k: String; let kind: Int; let opts: [String]; let ex: String? }
    private struct Saved: Codable {
        let qs: [SavedQ]; let idx: Int; let right: Int; let wrong: Int
        let learned: [String]; let retried: [String]; let missed: [String]
    }
    private var saveName: String { test ? "test" : (blanksOnly ? "blanks" : (words != nil ? "week" : "study")) }
    private var saveScope: Int { words != nil ? -1 : store.practiceTopic }

    /// next: the question on show has been answered (it isn't asked again when the round is picked up)
    private func saveNow(next: Bool = false) {
        let at = idx + (next ? 1 : 0)
        guard at < queue.count else { PracticeSave.clear(saveName, zh: store.isZh); return }
        let qs = queue.map { q in
            SavedQ(k: q.card.k, kind: QuizKind.allCases.firstIndex(of: q.kind) ?? 0, opts: q.options.map(\.k), ex: q.example?.h)
        }
        PracticeSave.save(Saved(qs: qs, idx: at, right: right, wrong: wrong, learned: learned.map(\.k),
                                retried: Array(retried), missed: missed.map(\.k)),
                          saveName, zh: store.isZh, scope: saveScope)
    }

    private func restore() -> Bool {
        guard let s = PracticeSave.load(Saved.self, saveName, zh: store.isZh, scope: saveScope) else { return false }
        var qs: [Question] = []
        var at = 0
        for (i, sq) in s.qs.enumerated() {
            guard let c = store.card(for: sq.k), sq.kind < QuizKind.allCases.count else { continue }
            let kind = QuizKind.allCases[sq.kind]
            let opts = sq.opts.compactMap { store.card(for: $0) }
            guard opts.contains(c) else { continue }
            var ex: Example? = nil
            if let h = sq.ex {
                ex = (kind == .fillBlank ? c.blankExamples : c.d.flatMap { $0.x }).first { $0.h == h }
                if ex == nil && kind == .fillBlank { continue }
            }
            if i < s.idx { at += 1 }
            qs.append(Question(card: c, kind: kind, options: opts, example: ex))
        }
        guard at < qs.count else { return false }
        queue = qs; idx = at; chosen = nil; right = s.right; wrong = s.wrong
        learned = s.learned.compactMap { store.card(for: $0) }
        retried = Set(s.retried)
        missed = s.missed.compactMap { store.card(for: $0) }
        resumed = true
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // how far through the round: the potion fills up
                if !queue.isEmpty && idx < queue.count {
                    HStack(spacing: 10) {
                        PotionBar(value: Double(idx) / Double(max(queue.count, 1)), height: 22, showMarks: false, label: trs("練習進度"))
                        Text(tr("\(idx + 1)／\(queue.count)")).latFont(14).monospacedDigit().foregroundStyle(T.muted)
                    }
                    .padding(.horizontal).padding(.top, 2)
                    .frame(maxWidth: 700)
                }
                Group {
                    if queue.isEmpty {
                        Text(blanksOnly ? trs("不熟的詞裡沒有可以填空的例句。") : (words != nil ? trs("本週還沒有選詞。") : trs("沒有不熟的詞可以練習。"))).foregroundStyle(T.muted)
                    } else if idx >= queue.count {
                        summary
                    } else {
                        question(queue[idx])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) { ResumedNote(shown: $resumed).padding(.top, 4) }
            .starBursts(stars)
            .appBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("結束"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if idx > 0 && idx < queue.count { RestartPracticeButton { start() } }
                        RomButton()
                    }
                }
            }
        }
        .onAppear { if queue.isEmpty && !restore() { start() } }
        .onChange(of: idx) { saveNow() }
    }

    // MARK: building a session

    private func start() { begin(); saveNow() }

    private func begin() {
        if blanksOnly { startBlanks(); return }
        missed = []
        if test {
            // every word of the week once, in a random way
            queue = (words ?? []).shuffled().compactMap { c in kinds(for: c).randomElement().map { make(c, $0) } }
            idx = 0; chosen = nil; right = 0; wrong = 0; learned = []; retried = []
            return
        }
        let pool = words ?? store.practiceCards
        let picked = pool
            .shuffled()
            .sorted { store.streak($0) < store.streak($1) }
            .prefix(max(1, words != nil ? pool.count : sessionSize))
        var first: [Question] = [], second: [Question] = []
        for c in picked {
            let ks = kinds(for: c).shuffled()
            if let k = ks.first { first.append(make(c, k)) }
            if ks.count > 1 { second.append(make(c, ks[1])) }
        }
        queue = first.shuffled() + second.shuffled()
        idx = 0; chosen = nil; right = 0; wrong = 0; learned = []; retried = []
    }

    /// 例句填空 only: one sentence per word, a second (different) sentence later in the round when there is one
    private func startBlanks() {
        let words = store.practiceCards
            .filter { !$0.blankExamples.isEmpty }
            .shuffled()
            .sorted { store.streak($0) < store.streak($1) }
            .prefix(max(1, sessionSize))
        var first: [Question] = [], second: [Question] = []
        for c in words {
            let xs = c.blankExamples.shuffled()
            let opts = (store.distractors(for: c) + [c]).shuffled()
            first.append(Question(card: c, kind: .fillBlank, options: opts, example: xs[0]))
            if xs.count > 1 {
                second.append(Question(card: c, kind: .fillBlank, options: (store.distractors(for: c) + [c]).shuffled(), example: xs[1]))
            }
        }
        queue = first.shuffled() + second.shuffled()
        idx = 0; chosen = nil; right = 0; wrong = 0; learned = []; retried = []
    }

    private func kinds(for c: Card) -> [QuizKind] {
        QuizKind.allCases.filter {
            switch $0 {
            case .listen: return c.audio != nil
            case .fillBlank: return !c.blankExamples.isEmpty
            default: return !c.d.isEmpty
            }
        }
    }

    private func make(_ c: Card, _ k: QuizKind) -> Question {
        Question(card: c, kind: k,
                 options: (store.distractors(for: c) + [c]).shuffled(),
                 example: k == .fillBlank ? c.blankExamples.randomElement() : nil)
    }

    // MARK: one question

    @ViewBuilder
    private func question(_ q: Question) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                prompt(q)
                options(q)
                if let c = chosen { feedback(q, picked: c) }
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .task(id: q.id) {
            if q.kind == .listen, let a = q.card.audio { Player.shared.play(a) }
        }
    }

    @ViewBuilder
    private func prompt(_ q: Question) -> some View {
        let c = q.card
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                switch q.kind {
                case .meaningToWord:
                    label(store.isZh ? trs("這個意思是哪個詞？") : trs("這個意思的台語是？"))
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let p = c.d.first?.p, !p.isEmpty { Chip(text: p) }
                        Text(c.firstMeaning).ffFont(.title3).foregroundStyle(T.glyph)
                    }
                case .wordToMeaning:
                    label(trs("這個詞是什麼意思？"))
                    HStack {
                        Text(c.h).scaledFont(52, weight: .medium).foregroundStyle(T.blueInk)
                        Spacer()
                        if let a = c.audio { PlayButton(path: a, size: 44) }
                    }
                    Text(store.cardRom(c, rom, place)).latFont(24).foregroundStyle(T.greenInk)
                case .listen:
                    label(trs("聽發音，選出正確的詞"))
                    HStack {
                        Spacer()
                        if let a = c.audio { PlayButton(path: a, size: 84) }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                case .fillBlank:
                    label(trs("例句填空"))
                    if let x = q.example {
                        Text(x.bh ?? x.h).ffFont(.title3).foregroundStyle(T.blueInk)
                        if let br = store.blankRom(c, x, rom, place) { Text(br).latFont(17).foregroundStyle(T.greenInk) }
                        Text(x.z).ffFont(.subheadline).foregroundStyle(T.muted)
                        HStack(spacing: 8) {
                            PlayButton(path: Audio.examplePath(x.n), size: 28)
                            Text(tr("聽例句（提示）")).ffFont(.caption).foregroundStyle(T.muted)
                        }
                    }
                case .romanization:
                    label(trs("這個詞怎麼唸？"))
                    Text(c.h).scaledFont(60, weight: .medium).foregroundStyle(T.blueInk)
                    Text(c.firstMeaning).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
                }
            }
        }
    }

    private func label(_ s: String) -> some View {
        Text(s).ffFont(.subheadline, .bold).foregroundStyle(T.oliveInk)
    }

    @ViewBuilder
    private func options(_ q: Question) -> some View {
        let wide = q.kind == .wordToMeaning || q.kind == .romanization
        let cols = wide ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(q.options) { o in
                Button { pick(o, in: q) } label: { optionLabel(o, q) }
                    .buttonStyle(.plain)
                    .disabled(chosen != nil)
            }
        }
    }

    private func optionLabel(_ o: Card, _ q: Question) -> some View {
        let answered = chosen != nil
        let isRight = o == q.card
        let isPicked = chosen == o
        let fill: Color = answered && isRight ? T.green : (answered && isPicked ? T.rust : T.key)
        let edge: Color = answered && isRight ? T.greenEdge : (answered && isPicked ? T.rustEdge : T.keyEdge)
        return VStack(spacing: 4) {
            switch q.kind {
            case .wordToMeaning:
                Text(o.firstMeaning).foregroundStyle(T.glyph).lineLimit(3).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .romanization:
                Text(store.cardRom(o, rom, place)).latFont(22).foregroundStyle(T.greenInk)
            default:
                Text(o.h).scaledFont(30, weight: .medium).foregroundStyle(T.blueInk)
                    .lineLimit(1).minimumScaleFactor(0.5)
                if answered {
                    Text(store.cardRom(o, rom, place)).latFont(14).foregroundStyle(T.greenInk)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 64)
        .glassSurface(RoundedRectangle(cornerRadius: 18),
                      tint: answered && isRight ? T.greenEdge.opacity(0.75)
                          : (answered && isPicked ? T.rustEdge.opacity(0.75) : T.key.opacity(0.35)),
                      interactive: !answered,
                      fallback: fill, edge: edge)
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .animation(.smooth(duration: 0.25), value: answered)
    }

    private func pick(_ o: Card, in q: Question) {
        guard chosen == nil else { return }
        chosen = o
        let ok = o == q.card
        if ok { right += 1 } else { wrong += 1; if test { missed.append(q.card) } }
        if let a = q.card.audio, q.kind != .listen { Player.shared.play(a) }
        if test { _ = store.answer(q.card, correct: ok, goal: goal); saveNow(next: true); return }
        if store.answer(q.card, correct: ok, goal: goal) {
            learned.append(q.card)
            // learned: drop its remaining questions
            let rest = queue[(idx + 1)...].filter { $0.card != q.card }
            queue = Array(queue[...idx]) + rest
        } else if !ok && !retried.contains(q.card.k) {
            // ask once more later, in another way
            retried.insert(q.card.k)
            let other = kinds(for: q.card).filter { $0 != q.kind }.randomElement() ?? q.kind
            queue.append(make(q.card, other))
        }
        saveNow(next: true)
    }

    private func feedback(_ q: Question, picked: Card) -> some View {
        let ok = picked == q.card
        let c = q.card
        return VStack(alignment: .leading, spacing: 14) {
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ok ? (learned.contains(c) ? trs("答對了！學會了") : trs("答對了！")) : trs("答錯了"))
                        .ffFont(.headline).foregroundStyle(ok ? T.greenInk : T.rustInk)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(c.h).ffFont(.title, .medium).foregroundStyle(T.blueInk)
                        Text(store.cardRom(c, rom, place)).latFont(20).foregroundStyle(T.greenInk)
                        Text(store.cardZy(c, place)).foregroundStyle(T.purpleInk)
                        Spacer()
                        if let a = c.audio { PlayButton(path: a, size: 34) }
                    }
                    // 例句填空: the meaning the sentence is about; otherwise the word's first meaning
                    let sense = q.kind == .fillBlank ? q.example.flatMap { c.meaning(of: $0) } : nil
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if let p = sense?.p, !p.isEmpty { Chip(text: p) }
                        Text(sense?.t ?? c.firstMeaning).foregroundStyle(T.glyph)
                    }
                    if q.kind == .fillBlank, let x = q.example {
                        Text(store.exampleHan(c, x, place)).padding(.top, 4)
                        Text(store.exampleRom(c, x, rom, place)).latFont(15).foregroundStyle(T.greenInk)
                    }
                }
            }
            Button {
                chosen = nil
                idx += 1
            } label: {
                Text(idx + 1 >= queue.count ? trs("看結果") : trs("下一題")).ffFont(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .prominentButton(T.btnEdge)
        }
    }

    // MARK: end

    private var testSummary: some View {
        let total = max(right + wrong, 1)
        let score = Double(right) / Double(total)
        return ScrollView {
            VStack(spacing: 18) {
                Text(tr("期末測驗")).ffFont(.largeTitle, .bold).foregroundStyle(T.glyph)
                Text(tr("\(Int((score * 100).rounded())) 分")).ffFont(.title, .bold).foregroundStyle(score >= 0.8 ? T.greenInk : T.rustInk)
                PotionBar(value: score, height: 24, showMarks: false, label: trs("分數"))
                Text(tr("答對 \(right) 個，答錯 \(wrong) 個")).foregroundStyle(T.muted)
                if !missed.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("答錯的詞：")).ffFont(.headline).foregroundStyle(T.rustInk)
                            ForEach(missed) { WordRow(card: $0) }
                        }
                    }
                }
                VStack(spacing: 10) {
                    if !missed.isEmpty {
                        Button {
                            store.finishWeek(keep: missed.map(\.k)); dismiss()
                        } label: { Text(tr("開始新的一週（答錯的 \(missed.count) 個詞留下來）")).frame(maxWidth: .infinity, minHeight: 40) }
                            .prominentButton(T.btnEdge)
                    }
                    Button { store.finishWeek(); dismiss() } label: {
                        Text(tr("結束這一週（清空本週的詞）")).frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .softButton()
                    Button { dismiss() } label: { Text(tr("先不要，繼續這一週")).frame(maxWidth: .infinity, minHeight: 40) }
                        .softButton()
                }
                Text(tr("詞還是會留在「不熟」或「熟悉」，只是不在本週的清單裡。")).ffFont(.caption).foregroundStyle(T.muted)
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var summary: some View {
        if test { return AnyView(testSummary) }
        return AnyView(ScrollView {
            VStack(spacing: 18) {
                Text(tr("練習完了")).ffFont(.largeTitle, .bold).foregroundStyle(T.glyph)
                Text(tr("答對 \(right) 題，答錯 \(wrong) 題")).foregroundStyle(T.muted)
                if !learned.isEmpty {
                    Panel {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tr("學會了，移到「熟悉」：")).ffFont(.headline).foregroundStyle(T.greenInk)
                            ForEach(learned) { WordRow(card: $0) }
                        }
                    }
                }
                HStack(spacing: 12) {
                    Button { start() } label: { Text(tr("再練一次")).frame(maxWidth: .infinity, minHeight: 40) }
                        .softButton()
                        .disabled(words == nil ? store.practiceCards.isEmpty : (words ?? []).isEmpty)
                    Button { dismiss() } label: { Text(tr("完成")).frame(maxWidth: .infinity, minHeight: 40) }
                        .prominentButton(T.btnEdge)
                }
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        })
    }
}
