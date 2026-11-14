import SwiftUI

// In a dictionary entry: the word's card, 加到「不熟」 and 認識 side by side, and with a keyboard (iPad's Magic Keyboard)
// A = 認識 and S = 不熟 + 收藏, the same keys as in Safari 查詞. (Typing in a text field the keys stay letters.)

extension Store {
    /// 認識: the word to 熟悉, or tap again to take it back out to 新詞
    func toggleKnown(_ key: String) { setWord(key, status: wordStatus(key) == 1 ? 0 : 1) }
    /// 加到「不熟」: or tap again to take it back out to 新詞
    func toggleUnknownWord(_ key: String) { setWord(key, status: wordStatus(key) == 2 ? 0 : 2) }
    /// A: 熟悉 (as it is when it already is)
    func keyKnown(_ key: String) { if wordStatus(key) != 1 { setWord(key, status: 1) } }
    /// S: 不熟, and 收藏 too
    func keyUnknown(_ key: String) {
        if wordStatus(key) != 2 { setWord(key, status: 2) }
        if !isSaved(key) { toggleSaved(key) }
    }
}

/// 加到「不熟」 and 認識 for a word (or a character's own card), showing where it is now
struct CardMarkButtons: View {
    let key: String
    /// a character's card under a word (漢字卡…)
    var charCard = false
    /// A and S on a keyboard work here (only the entry's own word, not the cards under it)
    var keys = true
    @EnvironmentObject var store: Store

    var body: some View {
        let st = store.wordStatus(key)
        HStack(spacing: 8) {
            Group {
                // 不熟
                Button { withAnimation(.snappy) { store.toggleUnknownWord(key) } } label: {
                    Label(st == 2 ? (charCard ? trs("漢字卡在「不熟」") : trs("在「不熟」"))
                                  : (charCard ? trs("漢字卡加到「不熟」") : trs("加到「不熟」")),
                          systemImage: st == 2 ? "star.fill" : "star")
                        .modifier(MarkCapsule(on: st == 2, fill: T.rust, edge: T.rustEdge, ink: T.rustInk))
                }
                .buttonStyle(.plain)
                // 認識
                Button { withAnimation(.snappy) { store.toggleKnown(key) } } label: {
                    Label(st == 1 ? (charCard ? trs("漢字卡：熟悉") : trs("熟悉")) : trs("認識"),
                          systemImage: st == 1 ? "checkmark.circle.fill" : "checkmark.circle")
                        .modifier(MarkCapsule(on: st == 1, fill: T.green, edge: T.greenEdge, ink: T.greenInk))
                }
                .buttonStyle(.plain)
                .accessibilityHint(st == 1 ? tr("再按一下拿回新詞") : tr("把這個詞標成熟悉"))
            }
        }
        .background {
            if keys {
                // (the keys: buttons that can't be seen)
                ZStack {
                    Button { withAnimation(.snappy) { store.keyKnown(key) } } label: { Color.clear }
                        .keyboardShortcut(KeyEquivalent("a"), modifiers: [])
                    Button { withAnimation(.snappy) { store.keyUnknown(key) } } label: { Color.clear }
                        .keyboardShortcut(KeyEquivalent("s"), modifiers: [])
                }
                .frame(width: 0, height: 0)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct MarkCapsule: ViewModifier {
    let on: Bool
    let fill: Color, edge: Color, ink: Color
    func body(content: Content) -> some View {
        content
            .ffFont(.subheadline, .semibold)
            .foregroundStyle(on ? ink : T.glyph)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(on ? fill : T.fn.opacity(0.8)))
            .overlay(Capsule().stroke(on ? edge : T.fnEdge, lineWidth: 1.5))
    }
}
