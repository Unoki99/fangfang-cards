import SwiftUI

// 練習範圍 → 創作範圍: a name, then tick the 影片詞組 it's made of (e.g. every episode of one show). It shows up in
// 練習範圍 under 自己的範圍; choosing it practises all its groups' words. The same sheet changes one (編輯) or deletes it.

struct ScopeEditor: View {
    /// the 範圍 being changed (nil: a new one)
    var editing: String? = nil
    /// after 完成: the name it has now
    var done: ((String) -> Void)? = nil
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var picked: Set<String> = []
    @State private var ready = false
    @State private var deleting = false
    @FocusState private var nameFocused: Bool

    private var cleanName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(tr("名字（例如劇名）"), text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                } header: {
                    Text(tr("名字"))
                }
                Section {
                    let groups = store.groupIds
                    if groups.isEmpty {
                        Text(tr("還沒有影片詞組。在 Safari 查詞的影片字幕裡選的詞，傳到 App 的時候會照影片分組放在這裡。"))
                            .foregroundStyle(T.muted)
                    }
                    ForEach(groups, id: \.self) { g in row(g) }
                } header: {
                    HStack {
                        Text(tr("要放進去的影片詞組"))
                        Spacer()
                        if !store.groupIds.isEmpty {
                            Button(picked.count == store.groupIds.count ? tr("全部不選") : tr("全部選")) {
                                picked = picked.count == store.groupIds.count ? [] : Set(store.groupIds)
                            }
                            .ffFont(.caption, .semibold)
                            .textCase(nil)
                        }
                    }
                } footer: {
                    Text(tr("選了 \(picked.count) 組。一個詞組可以放在好幾個範圍裡。"))
                }
                if let editing {
                    Section {
                        Button(role: .destructive) { deleting = true } label: {
                            Label(tr("刪掉「\(editing)」（詞組留著）"), systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(editing == nil ? tr("創作範圍") : tr("編輯範圍"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("完成")) {
                        store.saveFolder(old: editing, name: cleanName, groups: picked)
                        done?(cleanName)
                        dismiss()
                    }
                    .disabled(cleanName.isEmpty || picked.isEmpty)
                }
            }
            .confirmationDialog(tr("刪掉這個範圍？"), isPresented: $deleting, titleVisibility: .visible) {
                Button(tr("刪掉範圍（詞組留著）"), role: .destructive) {
                    if let editing { store.deleteFolder(editing) }
                    dismiss()
                }
            }
            .onAppear {
                guard !ready else { return }
                ready = true
                if let editing {
                    name = editing
                    picked = Set(store.folderGroups(editing))
                } else {
                    nameFocused = true
                }
            }
        }
    }

    private func row(_ g: String) -> some View {
        let on = picked.contains(g)
        let n = store.groupKeys(g).filter { Lang.kind($0) == store.lang }.count
        return Button {
            if on { picked.remove(g) } else { picked.insert(g) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .ffFont(.title3)
                    .foregroundStyle(on ? T.greenInk : T.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.groupName(g)).ffFont(.body).foregroundStyle(T.glyph).lineLimit(2)
                    HStack(spacing: 8) {
                        Text(store.groupDate(g), style: .date)
                        Text(tr("\(n) 個詞"))
                        // (the other 範圍 it's in already)
                        let others = store.groupFolderList(g).filter { $0 != editing }
                        if !others.isEmpty { Text(others.joined(separator: "、")).lineLimit(1) }
                    }
                    .ffFont(.caption).foregroundStyle(T.muted)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(on ? T.green.opacity(0.35) : T.fn.opacity(0.7))
    }
}
