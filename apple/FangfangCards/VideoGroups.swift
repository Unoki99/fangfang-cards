import SwiftUI

// 影片詞組: the words chosen from one video / episode with Safari 查詞 (its subtitle panel), kept together as a group
// named after the video. In 不熟 → 練習範圍 a group can be chosen: then every way of practising uses its words.
// Here: all the groups of the language open now, each with its words, a link back to the video, renaming and deleting.

struct VideoGroupsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("goal") private var goal = 3
    @State private var detail: Card?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    /// 創作範圍 / 編輯範圍
    @State private var scopeSheet: PracticeScopeMenu.ScopeSheet?

    var body: some View {
        NavigationStack {
            List {
                let groups = store.groupIds
                if groups.isEmpty {
                    Text(tr("還沒有影片詞組。在 Safari 查詞的影片字幕裡選的詞，傳到 App 的時候會照影片分組放在這裡。"))
                        .foregroundStyle(T.muted)
                }
                // (a 範圍: its name, then each of its groups, still apart)
                ForEach(store.groupFolders, id: \.self) { f in
                    Section { } header: { folderHeader(f) }
                    ForEach(store.folderGroups(f), id: \.self) { g in groupSection(g, inFolder: true) }
                }
                ForEach(groups.filter { store.groupFolder($0).isEmpty }, id: \.self) { g in groupSection(g, inFolder: false) }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("影片詞組"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } }
                if !store.groupIds.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { scopeSheet = .init(name: nil) } label: { Label(tr("創作範圍"), systemImage: "plus") }
                    }
                }
            }
            .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
            .alert(tr("改名"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField(tr("名字"), text: $newName)
                Button(tr("取消"), role: .cancel) { renaming = nil }
                Button(tr("好")) {
                    if let g = renaming, !newName.trimmingCharacters(in: .whitespaces).isEmpty { store.renameGroup(g, newName) }
                    renaming = nil
                }
            }
            .sheet(item: $scopeSheet) { sh in ScopeEditor(editing: sh.name).environmentObject(store) }
            .confirmationDialog(tr("刪掉這個影片詞組？"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button(tr("刪掉詞組（詞留在不熟）"), role: .destructive) {
                    if let g = deleting { store.deleteGroup(g) }
                    deleting = nil
                }
            }
        }
    }

    private func groupSection(_ g: String, inFolder: Bool) -> some View {
        Section {
            ForEach(store.groupKeys(g).filter { Lang.kind($0) == store.lang }, id: \.self) { k in
                row(g, k)
            }
        } header: {
            header(g)
                .padding(.leading, inFolder ? 14 : 0)
                .overlay(alignment: .leading) {
                    if inFolder { RoundedRectangle(cornerRadius: 2).fill(T.btnInk.opacity(0.6)).frame(width: 3).padding(.vertical, 4) }
                }
        }
    }

    /// a 範圍: its name, how many groups and words, and 練習 / 編輯 / 刪掉
    private func folderHeader(_ f: String) -> some View {
        let gs = store.folderGroups(f)
        let n = gs.reduce(0) { $0 + store.groupKeys($1).filter { Lang.kind($0) == store.lang }.count }
        return HStack(alignment: .firstTextBaseline) {
            Image(systemName: "square.stack.fill").foregroundStyle(T.oliveInk)
            VStack(alignment: .leading, spacing: 2) {
                Text(f).ffFont(.title3, .bold).foregroundStyle(T.glyph)
                Text(tr("\(gs.count) 個影片詞組・\(n) 個詞")).ffFont(.caption).foregroundStyle(T.muted)
            }
            Spacer(minLength: 6)
            Menu {
                Button { store.practiceGroup = "folder:" + f; dismiss() } label: { Label(tr("練習這個範圍"), systemImage: "graduationcap") }
                Button { scopeSheet = .init(name: f) } label: { Label(tr("編輯（名字、詞組）"), systemImage: "pencil") }
                Button(role: .destructive) { store.deleteFolder(f) } label: { Label(tr("刪掉範圍（詞組留著）"), systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").ffFont(.title3).foregroundStyle(T.oliveInk)
            }
        }
        .textCase(nil)
        .padding(.top, 10)
    }

    private func header(_ g: String) -> some View {
        let keys = store.groupKeys(g).filter { Lang.kind($0) == store.lang }
        let unknown = keys.filter { store.wordStatus($0) == 2 }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "film").foregroundStyle(T.btnInk)
                Text(store.groupName(g)).ffFont(.headline).foregroundStyle(T.glyph).lineLimit(2)
                Spacer(minLength: 6)
                Menu {
                    Button { store.practiceGroup = g; dismiss() } label: { Label(tr("練習這一組"), systemImage: "graduationcap") }
                    if let u = store.groupURL(g) { Link(destination: u) { Label(tr("打開影片"), systemImage: "play.rectangle") } }
                    Button { newName = store.groupName(g); renaming = g } label: { Label(tr("改名"), systemImage: "pencil") }
                    Button(role: .destructive) { deleting = g } label: { Label(tr("刪掉詞組"), systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").ffFont(.title3).foregroundStyle(T.btnInk)
                }
            }
            HStack(spacing: 10) {
                Text(store.groupDate(g), style: .date)
                Text(tr("\(keys.count) 個詞・不熟 \(unknown)"))
                if store.practiceGroup == g { Text(tr("練習範圍")).foregroundStyle(T.greenInk) }
            }
            .ffFont(.caption).foregroundStyle(T.muted)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }

    @ViewBuilder private func row(_ g: String, _ k: String) -> some View {
        if let c = store.card(for: k) {
            Button { detail = c } label: {
                WordRow(card: c, streak: store.streak(c), goal: goal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { store.removeFromGroup(g, key: k) } label: { Label(tr("移出詞組"), systemImage: "minus.circle") }
            }
        } else {
            // (a word that isn't one of the cards: its characters)
            Text(String(k.split(separator: "\t").first ?? Substring(k))).ffFont(.body).foregroundStyle(T.glyph)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { store.removeFromGroup(g, key: k) } label: { Label(tr("移出詞組"), systemImage: "minus.circle") }
                }
        }
    }
}
