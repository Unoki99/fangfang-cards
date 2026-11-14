import SwiftUI

// MARK: - iPad / Mac: the dictionary's results on the left, the word picked on the right
//
// With room for both (an iPad or the Mac, not an iPhone held upright), 查詞 shows the list of results on the left
// and the entry of the word tapped on the right, instead of opening it as a page of its own. The links of the
// results (EntryLink) pick the word then; everywhere else they open the word's page as before.

/// what a result row does when tapped inside an EntrySplit
struct EntryPicker {
    let pick: (AnyHashable) -> Void
    let picked: AnyHashable?
}
private struct EntryPickerKey: EnvironmentKey { static let defaultValue: EntryPicker? = nil }
extension EnvironmentValues {
    var entryPicker: EntryPicker? {
        get { self[EntryPickerKey.self] }
        set { self[EntryPickerKey.self] = newValue }
    }
}

/// a link to a word: inside an EntrySplit it shows the word on the right; elsewhere it opens the word's page
struct EntryLink<V: Hashable, Label: View>: View {
    let value: V
    @ViewBuilder let label: () -> Label
    @Environment(\.entryPicker) private var picker
    var body: some View {
        if let picker {
            let on = picker.picked == AnyHashable(value)
            Button { picker.pick(AnyHashable(value)) } label: {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(on ? T.btn.opacity(0.55) : nil)
        } else {
            NavigationLink(value: value) { label() }
        }
    }
}

struct EntrySplit<ListPane: View, Detail: View>: View {
    @ViewBuilder let list: () -> ListPane
    @ViewBuilder let detail: (AnyHashable) -> Detail
    @Environment(\.horizontalSizeClass) private var hsc
    @State private var picked: AnyHashable?

    private var roomy: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return hsc == .regular && UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    var body: some View {
        if roomy {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    list()
                        .environment(\.entryPicker, EntryPicker(pick: { v in withAnimation(.snappy) { picked = v } }, picked: picked))
                        .frame(width: min(480, max(320, geo.size.width * 0.42)))
                    Rectangle().fill(T.fnEdge).frame(width: 1).ignoresSafeArea(edges: .bottom)
                    Group {
                        if let p = picked {
                            detail(p).id(p)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "character.book.closed").font(.system(size: 40)).foregroundStyle(T.muted.opacity(0.6))
                                Text(tr("點左邊的詞，在這裡看它的解釋。")).ffFont(.subheadline).foregroundStyle(T.muted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            list()
        }
    }
}
