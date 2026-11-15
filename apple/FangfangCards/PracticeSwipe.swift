import SwiftUI

// 滑卡練習: the 新詞 cards, but for practising the 練習範圍's words (and the ones due to be reviewed).
// A swipe doesn't put a word in 熟悉 straight away: right (會) counts as a right answer, left (不會) as a wrong one,
// the same as in the other ways of practising. So a word goes to 熟悉 after enough right answers in a row
// (設定 → 答對幾次算學會), and comes back to be reviewed a few days later.

struct PracticeSwipeView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("goal") private var goal = 3
    /// the words of this round still to swipe (the top one first)
    @State private var queue: [Card] = []
    @State private var total = 0
    @State private var right = 0
    @State private var wrong = 0
    @State private var learned = 0
    /// words got wrong once this round: they come back once at the end
    @State private var again: Set<String> = []
    @State private var started = false

    var body: some View {
        NavigationStack {
            Group {
                if !started {
                    Color.clear
                } else if total == 0 {
                    Text(tr("練習範圍裡沒有要練習的詞。")).foregroundStyle(T.muted).padding()
                } else if queue.isEmpty {
                    summary
                } else {
                    VStack(spacing: 12) {
                        Text(tr("\(store.practiceName)・還有 \(queue.count) 個"))
                            .ffFont(.footnote).foregroundStyle(T.muted)
                        DeckArea(cards: Array(queue.prefix(4)), leftLabel: trs("不會"), rightLabel: trs("會"),
                                 onSwipe: { c, r in swiped(c, r) })
                            .frame(maxWidth: 560)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle(tr("滑卡練習"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel(tr("結束"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if started && total > 0 {
                        Text(tr("會 \(right)・不會 \(wrong)")).ffFont(.caption, mono: true).foregroundStyle(T.muted)
                    }
                }
            }
        }
        .onAppear { if !started { build() } }
    }

    /// the round: the words due to be reviewed first, then the 練習範圍's 不熟 words
    private func build() {
        var seen = Set<String>()
        queue = store.studyCards.filter { seen.insert($0.k).inserted }
        total = queue.count
        right = 0; wrong = 0; learned = 0; again = []
        started = true
    }

    private func swiped(_ c: Card, _ ok: Bool) {
        if store.answer(c, correct: ok, goal: goal) && ok { learned += 1 }
        if ok { right += 1 } else { wrong += 1 }
        if let i = queue.firstIndex(where: { $0.id == c.id }) { queue.remove(at: i) }
        // (wrong: once more at the end of the round)
        if !ok && !again.contains(c.k) {
            again.insert(c.k)
            if let fresh = store.card(for: c.k) { queue.append(fresh) }
        }
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(T.greenInk)
            Text(tr("這一輪練完了")).ffFont(.title2, .bold).foregroundStyle(T.glyph)
            Text(tr("會 \(right)・不會 \(wrong)")).ffFont(.body).foregroundStyle(T.muted)
            if learned > 0 {
                Text(tr("\(learned) 個詞學會了，放到「熟悉」，過幾天會再出來複習。")).ffFont(.subheadline).foregroundStyle(T.greenInk)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button { build() } label: {
                    Label(tr("再來一輪"), systemImage: "arrow.clockwise").frame(minWidth: 120, minHeight: 44)
                }
                .softButton()
                Button { dismiss() } label: {
                    Text(tr("結束")).frame(minWidth: 120, minHeight: 44)
                }
                .softButton()
            }
        }
        .padding()
    }
}
