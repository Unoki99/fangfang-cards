import SwiftUI

// MARK: - 本週學習: pick words from 不熟 for the week, practise them, and take a test at the end

/// the panel at the top of 不熟
struct WeekPanel: View {
    @EnvironmentObject var store: Store
    @State private var picking = false
    @State private var practising = false
    @State private var testing = false
    @State private var writing = false

    var body: some View {
        let words = store.weekCards
        let left = store.weekDaysLeft
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(tr("本週學習"), systemImage: "calendar").ffFont(.headline).foregroundStyle(T.glyph)
                Spacer()
                if !words.isEmpty {
                    Text(left == 0 ? trs("該考試了！") : tr("還有 \(left) 天"))
                        .ffFont(.subheadline, .semibold).foregroundStyle(left == 0 ? T.rustInk : T.muted)
                }
            }
            if words.isEmpty {
                Text(tr("從「不熟」選這個星期要學的詞（例如 10–20 個），每天練習，一週後做期末測驗。"))
                    .ffFont(.footnote).foregroundStyle(T.muted)
            } else {
                let known = words.filter { store.status($0) == 1 }.count
                Text(tr("\(words.count) 個詞・已經學會 \(known) 個")).ffFont(.footnote).foregroundStyle(T.muted)
                // the week: how many of its 7 days have gone
                PotionBar(value: Double(7 - left) / 7, height: 16, showMarks: false, label: trs("這一週"), palette: .blue)
                FlowLayout(spacing: 6) {
                    ForEach(words.prefix(24)) { c in
                        Text(c.h).ffFont(.subheadline)
                            .foregroundStyle(store.status(c) == 1 ? T.greenInk : T.glyph)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(store.status(c) == 1 ? T.green.opacity(0.7) : T.fn.opacity(0.8)))
                    }
                    if words.count > 24 { Text("…").foregroundStyle(T.muted) }
                }
            }
            HStack(spacing: 10) {
                PracticeTile(title: words.isEmpty ? trs("選詞") : trs("改詞"), icon: "checklist", enabled: true) { picking = true }
                PracticeTile(title: tr("練習"), icon: "graduationcap.fill", enabled: !words.isEmpty) { practising = true }
                PracticeTile(title: tr("寫字"), icon: "pencil.line", enabled: words.contains { Store.canWrite($0.h) }) { writing = true }
                PracticeTile(title: tr("期末測驗"), icon: "rosette", enabled: !words.isEmpty) { testing = true }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(words.isEmpty || left > 0 ? T.fnEdge : T.rustEdge, lineWidth: 1.5))
        .sheet(isPresented: $picking) { WeekPicker().environmentObject(store) }
        .fullScreenCover(isPresented: $practising) { StudyView(words: store.weekCards).environmentObject(store) }
        .fullScreenCover(isPresented: $writing) { StudyView(words: store.weekCards, writeOnly: true).environmentObject(store) }
        .fullScreenCover(isPresented: $testing) { StudyView(words: store.weekCards, test: true).environmentObject(store) }
    }
}

/// choosing this week's words from 不熟
struct WeekPicker: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// the level / group to pick from (-1 = all of 不熟), so the week can follow the levels in order
    @AppStorage("weekPickTopic") private var topic = -1

    var body: some View {
        let topics = store.practiceTopics.filter { t in store.unknownCards.contains { store.inTopic($0, t.id) } }
        let unknown = topic < 0 || !topics.contains(where: { $0.id == topic }) ? store.unknownCards : store.unknownCards.filter { store.inTopic($0, topic) }
        // words already in the week that aren't in 不熟 any more (learned) are shown too
        let extra = store.weekCards.filter { store.status($0) != 2 }
        let list = (extra + unknown).filter { query.isEmpty || $0.h.contains(query) || $0.firstMeaning.contains(query) }
        let n = store.weekCards.count
        NavigationStack {
            List {
                if !topics.isEmpty {
                    Section {
                        Picker(tr("從哪裡選"), selection: $topic) {
                            Text(tr("全部不熟的詞")).tag(-1)
                            ForEach(topics) { t in Text(UILang.label(t.name)).tag(t.id) }
                        }
                    } footer: {
                        Text(tr("選一個等級或一組詞，照順序一級一級學。"))
                    }
                    .listRowBackground(T.fn.opacity(0.7))
                }
                Section {
                    HStack(spacing: 10) {
                        ForEach([10, 20], id: \.self) { k in
                            Button(tr("隨機選 \(k) 個")) {
                                let pick = unknown.filter { !store.isInWeek($0.k) }.shuffled().prefix(max(0, k - n)).map(\.k)
                                store.setWeek(pick, on: true)
                            }
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                        if n > 0 {
                            Button(tr("全部取消"), role: .destructive) { store.setWeek(store.weekCards.map(\.k), on: false) }
                                .buttonStyle(.bordered)
                        }
                    }
                } footer: {
                    Text(tr("已選 \(n) 個。建議一週 10–20 個詞。"))
                }
                .listRowBackground(Color.clear)
                Section(tr("不熟的詞（\(unknown.count)）")) {
                    ForEach(list) { c in
                        Button { withAnimation(.snappy) { store.toggleWeek(c.k) } } label: {
                            HStack {
                                Image(systemName: store.isInWeek(c.k) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(store.isInWeek(c.k) ? T.greenInk : T.muted)
                                    .ffFont(.title3)
                                WordRow(card: c)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .searchable(text: $query, prompt: trs("漢字或意思"))
            .navigationTitle(tr("本週要學的詞"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("完成")) { dismiss() } } }
        }
    }
}

// MARK: - a level of HSK / TOCFL: every word, and checking them off

struct LevelWordsView: View {
    let level: Int
    let name: String
    @EnvironmentObject var store: Store
    @State private var detail: Card?
    @State private var confirm: Int?          // 1 = all to 熟悉, 2 = the unseen ones to 熟悉, 3 = all back to 新詞
    @State private var filter = 0             // 0 all, 1 not seen, 2 熟悉, 3 不熟

    var body: some View {
        let all = store.levelCards(level)
        let shown = all.filter { c in
            switch filter {
            case 1: return (store.status(c) ?? 0) == 0
            case 2: return store.status(c) == 1
            case 3: return store.status(c) == 2
            default: return true
            }
        }
        List {
            Section {
                let p = store.hskProgress(level)
                SplitPotionBar(known: p.total > 0 ? Double(p.known) / Double(p.total) : 0,
                               unknown: p.total > 0 ? Double(p.unknown) / Double(p.total) : 0, label: name, tint: levelColor(level))
                Picker("", selection: $filter) {
                    Text(tr("全部")).tag(0)
                    Text(tr("沒看過")).tag(1)
                    Text(tr("熟悉")).tag(2)
                    Text(tr("不熟")).tag(3)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            Section(tr("\(shown.count) 個詞（往右滑 = 熟悉，往左滑 = 不熟）")) {
                ForEach(shown) { c in
                    Button { detail = c } label: {
                        HStack {
                            statusIcon(c)
                            WordRow(card: c)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button { store.mark(c, known: true, undoable: false) } label: { Label(tr("熟悉"), systemImage: "checkmark") }.tint(T.btnEdge)
                    }
                    .swipeActions(edge: .trailing) {
                        Button { store.mark(c, known: false, undoable: false) } label: { Label(tr("不熟"), systemImage: "xmark") }.tint(T.rustEdge)
                    }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { confirm = 1 } label: { Label(tr("全部標成熟悉"), systemImage: "checkmark.circle") }
                    Button { confirm = 2 } label: { Label(tr("沒看過的標成熟悉"), systemImage: "checkmark.circle.badge.questionmark") }
                    Button(role: .destructive) { confirm = 3 } label: { Label(tr("全部移回新詞"), systemImage: "arrow.uturn.backward") }
                } label: { Image(systemName: "checklist.checked") }
                .accessibilityLabel(tr("整個等級"))
            }
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button(confirm == 3 ? trs("移回新詞") : trs("標成熟悉"), role: confirm == 3 ? .destructive : nil) {
                switch confirm {
                case 1: store.markAll(all, known: true)
                case 2: store.markAll(all.filter { (store.status($0) ?? 0) == 0 }, known: true)
                case 3: store.markAll(all, known: false)
                default: break
                }
                confirm = nil
            }
            Button(tr("取消"), role: .cancel) { confirm = nil }
        }
        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
    }

    private var confirmTitle: String {
        switch confirm {
        case 1: return tr("把 \(name) 的詞全部標成熟悉？")
        case 2: return tr("把 \(name) 還沒看過的詞標成熟悉？")
        case 3: return tr("把 \(name) 的詞全部移回新詞？（熟悉和不熟的都會）")
        default: return ""
        }
    }

    @ViewBuilder private func statusIcon(_ c: Card) -> some View {
        switch store.status(c) {
        case 1?: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x6eaaff))
        case 2?: Image(systemName: "questionmark.circle.fill").foregroundStyle(Color(hex: 0xffa94d))
        default: Image(systemName: "circle").foregroundStyle(T.muted)
        }
    }
}
