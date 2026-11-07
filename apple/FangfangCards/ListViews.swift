import SwiftUI

private func matches(_ c: Card, _ q: String) -> Bool {
    if q.isEmpty { return true }
    let l = q.lowercased()
    return c.h.contains(q) || c.r.contains { $0.lowercased().contains(l) } || c.d.contains { $0.t.contains(q) }
}

/// 不熟: the words you swiped left. Study them here.
struct UnknownView: View {
    @EnvironmentObject var store: Store
    @AppStorage("goal") private var goal = 3
    @State private var studying = false
    @State private var toning = false
    @State private var scrambling = false
    @State private var readingOrder = false
    @State private var blanks = false
    @State private var memory = false
    @State private var writing = false
    @State private var helping = false
    @State private var detail: Card?
    @State private var query = ""

    var body: some View {
        // the words of the 練習範圍 (all of 不熟 when none is chosen)
        let list = store.practiceCards.filter { matches($0, query) }
        List {
            Section {
            } header: {
                // the ways to practise, two to a row, all in the same soft green.
                // In the header, not a row: a row's rounded corners would cut the tiles' corners off
                let pool = store.practiceCards
                VStack(spacing: 12) {
                WeekPanel()
                PracticeScopeMenu()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    PracticeTile(title: "開始練習", icon: "graduationcap.fill", enabled: !pool.isEmpty) { studying = true }
                    PracticeTile(title: "例句填空", icon: "text.badge.checkmark",
                                 enabled: pool.contains { !$0.blankExamples.isEmpty }) { blanks = true }
                    PracticeTile(title: "排句子", icon: "rectangle.3.group", enabled: !pool.isEmpty) { scrambling = true }
                    PracticeTile(title: "看字排讀音", icon: "character.book.closed", enabled: !pool.isEmpty) { readingOrder = true }
                    PracticeTile(title: "聲調練習", icon: "waveform", enabled: true) { toning = true }
                    PracticeTile(title: "翻牌配對", icon: "square.grid.2x2", enabled: pool.count > 1) { memory = true }
                    PracticeTile(title: "手寫練習", icon: "pencil.and.scribble", enabled: true) { writing = true }
                    // what each way of practising does
                    PracticeTile(title: "怎麼練習", icon: "questionmark.circle", enabled: true, quiet: true) { helping = true }
                }
                }
                .padding(.vertical, 6)
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section(store.practiceName == "全部不熟的詞" ? "不熟的詞（\(store.unknownCount)）"
                    : "\(store.practiceName)・不熟的詞（\(list.count)／\(store.unknownCount)）") {
                if list.isEmpty {
                    Text(query.isEmpty ? "在「新詞」往左滑的詞會出現在這裡。" : "找不到。")
                        .foregroundStyle(T.muted)
                }
                ForEach(list) { c in
                    Button { detail = c } label: {
                        HStack(spacing: 8) {
                            if store.isInWeek(c.k) { Image(systemName: "calendar").ffFont(.caption).foregroundStyle(T.blueInk) }
                            WordRow(card: c, streak: store.streak(c), goal: goal)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())          // the whole row, not only the word
                    }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button { store.mark(c, known: true, undoable: false) } label: { Label("熟悉", systemImage: "checkmark") }
                                .tint(T.btnEdge)
                            Button { store.toggleWeek(c.k) } label: {
                                Label(store.isInWeek(c.k) ? "移出本週" : "本週學習", systemImage: "calendar")
                            }
                                .tint(T.blueEdge)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.forget(c) } label: { Label("移回新詞", systemImage: "arrow.uturn.backward") }
                                .tint(T.oliveEdge)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .searchable(text: $query, prompt: "漢字、羅馬字或意思")

        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
        .fullScreenCover(isPresented: $studying) { StudyView().environmentObject(store) }
        .fullScreenCover(isPresented: $blanks) { StudyView(blanksOnly: true).environmentObject(store) }
        .fullScreenCover(isPresented: $toning) { ToneView().environmentObject(store) }
        .fullScreenCover(isPresented: $scrambling) { ScrambleView().environmentObject(store) }
        .fullScreenCover(isPresented: $memory) { MemoryView().environmentObject(store) }
        .fullScreenCover(isPresented: $writing) { HandwritingView().environmentObject(store) }
        .sheet(isPresented: $helping) { PracticeHelp(goal: goal).environmentObject(store) }
        .fullScreenCover(isPresented: $readingOrder) { ScrambleView(readingMode: true).environmentObject(store) }
    }
}

/// 熟悉: known words. Review them as cards; swiping left sends a word back to 不熟.
struct KnownView: View {
    @EnvironmentObject var store: Store
    @State private var mode = 0
    @State private var reviewKeys: [String] = []
    @State private var pos = 0
    @State private var detail: Card?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                Text("卡片複習").tag(0)
                Text("列表").tag(1)
                if store.isZh ? !store.topics.isEmpty : !store.freqTopics.isEmpty { Text("學習進度").tag(2) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 8)

            if mode == 2 { HSKProgressView() } else if mode == 0 { review } else { list }
        }
        .appBackground()

        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
        .onAppear { if reviewKeys.isEmpty { shuffle() } }
    }

    private var reviewCards: [Card] {
        guard pos < reviewKeys.count else { return [] }
        var out: [Card] = []
        for k in reviewKeys[pos...] {
            if let c = store.byKey[k], store.status(c) == 1 { out.append(c) }
            if out.count == 4 { break }
        }
        return out
    }

    private var review: some View {
        let cards = reviewCards
        return VStack(spacing: 14) {
            Text(store.knownCount == 0 ? "" : "\(min(pos, reviewKeys.count)) / \(reviewKeys.count)")
                .ffFont(.footnote).foregroundStyle(T.muted)
            if cards.isEmpty {
                Spacer()
                Text(store.knownCount == 0 ? "在「新詞」往右滑的詞會出現在這裡。" : "這一輪複習完了！")
                    .foregroundStyle(T.muted)
                if store.knownCount > 0 {
                    Button("再複習一輪") { shuffle() }.prominentButton(T.btnEdge)
                }
                Spacer()
            } else {
                DeckArea(cards: cards, leftLabel: "不熟", rightLabel: "記得") { card, right in
                    if !right { store.mark(card, known: false, undoable: false) }
                    advance(past: card)
                }
            }
        }
        .padding()
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        let cards = store.knownCards.filter { matches($0, query) }
        return List {
            // the search under 卡片複習 / 列表 (not above them, where .searchable puts it)
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.muted)
                    TextField("漢字、羅馬字或意思", text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .clearButton($query)
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section("熟悉的詞（\(store.knownCount)）") {
                ForEach(cards) { c in
                    Button { detail = c } label: {
                        WordRow(card: c).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button { store.mark(c, known: false, undoable: false) } label: { Label("不熟", systemImage: "xmark") }
                                .tint(T.rustEdge)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func shuffle() {
        reviewKeys = store.knownCards.map(\.k).shuffled()
        pos = 0
    }

    private func advance(past card: Card) {
        if let i = reviewKeys[pos...].firstIndex(of: card.k) { pos = i + 1 } else { pos += 1 }
    }
}


/// one practice button in 不熟 (half the width, the soft green)
struct PracticeTile: View {
    let title: String
    let icon: String
    var enabled = true
    /// not a way of practising (怎麼練習): the plain colour
    var quiet = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .ffFont(.subheadline, .semibold)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.horizontal, 8)
                .foregroundStyle(quiet ? T.glyph : (enabled ? T.btnInk : T.muted))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(quiet ? T.fn.opacity(0.8) : (enabled ? T.btn : T.fn.opacity(0.6))))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(quiet ? T.fnEdge : (enabled ? T.btnEdge : T.fnEdge), lineWidth: 1.5))
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 不熟 → 練習範圍: all of 不熟, or one level / group (華語: HSK / TOCFL words or characters; 台語: 常用詞 / 常用字)
struct PracticeScopeMenu: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let ts = store.practiceTopics
        let all = store.allTopicProgress()
        let words = ts.filter { store.isZh ? $0.id < Lang.charTopicBase : $0.id < Lang.freqCharBase }
        let chars = ts.filter { store.isZh ? $0.id > Lang.charTopicBase : $0.id >= Lang.freqCharBase }
        if !ts.isEmpty {
            Menu {
                Picker("練習範圍", selection: $store.practiceTopic) {
                    Text("全部不熟的詞（\(store.unknownCount)）").tag(-1)
                }
                .pickerStyle(.inline)
                Menu(store.isZh ? "詞（等級）" : "常用詞") {
                    Picker("詞", selection: $store.practiceTopic) {
                        ForEach(words) { t in Text("\(t.name)（不熟 \(all[t.id]?.unknown ?? 0)）").tag(t.id) }
                    }
                    .pickerStyle(.inline)
                }
                if !chars.isEmpty {
                    Menu(store.isZh ? "漢字（等級）" : "常用字") {
                        Picker("字", selection: $store.practiceTopic) {
                            ForEach(chars) { t in Text("\(t.name)（不熟 \(all[t.id]?.unknown ?? 0)）").tag(t.id) }
                        }
                        .pickerStyle(.inline)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope").foregroundStyle(T.btnInk)
                    Text("練習範圍").foregroundStyle(T.muted)
                    Text(store.practiceName).foregroundStyle(T.glyph).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(store.practiceCards.count)").ffFont(.footnote, mono: true).foregroundStyle(T.muted)
                    Image(systemName: "chevron.up.chevron.down").ffFont(.caption).foregroundStyle(T.muted)
                }
                .ffFont(.subheadline)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }
}

/// 不熟 → 怎麼練習: what each way of practising does, one box each
struct PracticeHelp: View {
    let goal: Int
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    private var items: [(icon: String, title: String, text: String)] {
        var a: [(String, String, String)] = [
            ("calendar", "本週學習", "從不熟的詞選這個星期要學的（或在列表往右滑 → 本週學習），一週後做期末測驗；答錯的詞可以留到下一週。"),
            ("graduationcap.fill", "開始練習", "各種題目混在一起練。連續答對 \(goal) 次，詞就會移到「熟悉」；在列表往右滑可以直接移過去。"),
            ("text.badge.checkmark", "例句填空", "只做例句填空題。"),
            ("rectangle.3.group", "排句子", "例句被打亂了，照華語的意思把詞排回去。"),
            ("character.book.closed", "看字排讀音", "只看漢字，把讀音照順序排。"),
            ("waveform", "聲調練習", "聽發音，選出聲調正確的拼法（先用不熟的詞，再用常用詞）。"),
            ("square.grid.2x2", "翻牌配對", "不熟的詞做成牌，一半是漢字，一半是讀音；一次翻兩張，把漢字和它的讀音配起來。"),
        ]
        do {
            a.append(("pencil.and.scribble", "手寫練習", store.isZh ? "選要寫的字（不熟的漢字、HSK／TOCFL 的漢字等級、認識的漢字或自己打的字），看字、讀音和意思，用手指或 Apple Pencil 在格子裡寫。「描字」會在格子裡放一個淡淡的字，藥水條顯示描得多像；點上面的字看有這個字的詞，打勾表示這個字會了。" : "選要寫的字（不熟的詞的字、熟悉的詞的字或自己打的字），看字、讀音和意思，用手指或 Apple Pencil 在格子裡寫。「描字」會在格子裡放一個淡淡的字，藥水條顯示描得多像；點上面的字看有這個字的詞，打勾表示這個字會了。"))
        }
        a.append(("scope", "練習範圍", "只練一個等級（或一組）的不熟的詞或字。"))
        return a
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(items, id: \.title) { it in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: it.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(T.btnInk)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(it.title).ffFont(.headline).foregroundStyle(T.glyph)
                                Text(it.text).ffFont(.subheadline).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.fnEdge, lineWidth: 1))
                    }
                }
                .padding()
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle("怎麼練習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
