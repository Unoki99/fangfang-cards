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
    @State private var toneGame = false
    @State private var particles = false
    @State private var scrambling = false
    @State private var readingOrder = false
    @State private var blanks = false
    @State private var memory = false
    @State private var writing = false
    @State private var freeWriting = false
    @State private var gaming = false
    @State private var helping = false
    @State private var statsOpen = false
    /// 要複習 → practise just the words due
    @State private var reviewWords: [Card] = []
    @State private var reviewing = false
    @State private var reviewWriting = false
    @State private var detail: Card?
    @State private var query = ""

    var body: some View {
        // the words of the 練習範圍 (all of 不熟 when none is chosen)
        let list = store.practiceCards.filter { matches($0, query) }
        let due = store.dueCards
        List {
            Section {
            } header: {
                // the ways to practise, two to a row, all in the same soft green.
                // In the header, not a row: a row's rounded corners would cut the tiles' corners off
                let pool = store.practiceCards
                VStack(spacing: 12) {
                WeekPanel()
                PracticeScopeMenu()
                ReviewBar(due: store.allDueCards.count, stats: { statsOpen = true }) { hand in
                    reviewWords = store.allDueCards
                    if hand { reviewWriting = true } else { reviewing = true }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    PracticeTile(title: tr("開始練習"), icon: "graduationcap.fill", enabled: !pool.isEmpty || !due.isEmpty) { studying = true }
                    PracticeTile(title: tr("例句填空"), icon: "text.badge.checkmark",
                                 enabled: (pool + due).contains { !store.blanks($0).isEmpty }) { blanks = true }
                    PracticeTile(title: tr("排句子"), icon: "rectangle.3.group", enabled: !pool.isEmpty) { scrambling = true }
                    PracticeTile(title: tr("看字排讀音"), icon: "character.book.closed", enabled: !pool.isEmpty && !store.isSv) { readingOrder = true }
                    // (客語: no voice to listen to)
                    // (日語: no tones; its particles instead)
                    if store.isJa {
                        PracticeTile(title: tr("助詞練習"), icon: "puzzlepiece", enabled: true) { particles = true }
                    } else {
                        PracticeTile(title: tr("聲調練習"), icon: "waveform", enabled: !store.isHak && !store.isSv) { toning = true }
                        // (every syllable's tone, in its colour: a game)
                        PracticeTile(title: tr("聲調色球"), icon: "circle.hexagongrid.fill", enabled: !store.isSv) { toneGame = true }
                    }
                    PracticeTile(title: tr("翻牌配對"), icon: "square.grid.2x2", enabled: pool.count > 1) { memory = true }
                    PracticeTile(title: tr("手寫練習"), icon: "pencil.and.scribble", enabled: !store.isSv) { writing = true }
                    PracticeTile(title: tr("自由寫字"), icon: "square.grid.3x3", enabled: !store.isSv) { freeWriting = true }
                    PracticeTile(title: tr("遊戲"), icon: "gamecontroller", enabled: pool.count > 3) { gaming = true }
                    // what each way of practising does
                    PracticeTile(title: tr("怎麼練習"), icon: "questionmark.circle", enabled: true, quiet: true) { helping = true }
                }
                }
                .padding(.vertical, 6)
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            Section(store.practiceName == trs("全部不熟的詞") ? tr("不熟的詞（\(store.unknownCount)）")
                    : tr("\(store.practiceName)・不熟的詞（\(list.count)／\(store.unknownCount)）")) {
                if list.isEmpty {
                    Text(query.isEmpty ? trs("在「新詞」往左滑的詞會出現在這裡。") : trs("找不到。"))
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
                            Button { store.mark(c, known: true, undoable: false) } label: { Label(tr("熟悉"), systemImage: "checkmark") }
                                .tint(T.btnEdge)
                            Button { store.toggleWeek(c.k) } label: {
                                Label(store.isInWeek(c.k) ? trs("移出本週") : trs("本週學習"), systemImage: "calendar")
                            }
                                .tint(T.blueEdge)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.forget(c) } label: { Label(tr("移回新詞"), systemImage: "arrow.uturn.backward") }
                                .tint(T.oliveEdge)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        // (under the top bar, not in it: on an iPad it would push the reading and settings buttons out)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: trs("漢字、羅馬字或意思"))

        .sheet(item: $detail) { CardSheet(card: $0).environmentObject(store) }
        .fullScreenCover(isPresented: $studying) { StudyView().environmentObject(store) }
        .fullScreenCover(isPresented: $reviewing) { StudyView(words: reviewWords, saveAs: "review").environmentObject(store) }
        .fullScreenCover(isPresented: $reviewWriting) { StudyView(words: reviewWords, writeOnly: true, saveAs: "reviewWrite").environmentObject(store) }
        .fullScreenCover(isPresented: $blanks) { StudyView(blanksOnly: true).environmentObject(store) }
        .fullScreenCover(isPresented: $toning) { ToneView().environmentObject(store) }
        .fullScreenCover(isPresented: $toneGame) { ToneGameView().environmentObject(store) }
        .fullScreenCover(isPresented: $particles) { JaParticleQuiz().environmentObject(store) }
        .fullScreenCover(isPresented: $scrambling) { ScrambleView().environmentObject(store) }
        .fullScreenCover(isPresented: $memory) { MemoryView().environmentObject(store) }
        .fullScreenCover(isPresented: $writing) { HandwritingView().environmentObject(store) }
        .fullScreenCover(isPresented: $freeWriting) { FreeWritingView().environmentObject(store) }
        .fullScreenCover(isPresented: $gaming) { FallingGameView().environmentObject(store) }
        .sheet(isPresented: $helping) { PracticeHelp(goal: goal).environmentObject(store) }
        .sheet(isPresented: $statsOpen) { NavigationStack { ReviewStatsView() }.environmentObject(store).macTextSize() }
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
                Text(tr("卡片複習")).tag(0)
                Text(tr("列表")).tag(1)
                if store.isZh ? !store.topics.isEmpty : !store.freqTopics.isEmpty { Text(tr("學習進度")).tag(2) }
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
                Text(store.knownCount == 0 ? trs("在「新詞」往右滑的詞會出現在這裡。") : trs("這一輪複習完了！"))
                    .foregroundStyle(T.muted)
                if store.knownCount > 0 {
                    Button(tr("再複習一輪")) { shuffle() }.prominentButton(T.btnEdge)
                }
                Spacer()
            } else {
                DeckArea(cards: cards, leftLabel: trs("不熟"), rightLabel: trs("記得")) { card, right in
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
                    TextField(tr("漢字、羅馬字或意思"), text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                        .clearButton($query)
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section(tr("熟悉的詞（\(store.knownCount)）")) {
                ForEach(cards) { c in
                    Button { detail = c } label: {
                        WordRow(card: c).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button { store.mark(c, known: false, undoable: false) } label: { Label(tr("不熟"), systemImage: "xmark") }
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
                Picker(tr("練習範圍"), selection: $store.practiceTopic) {
                    Text(tr("全部不熟的詞（\(store.unknownCount)）")).tag(-1)
                }
                .pickerStyle(.inline)
                Menu(store.isZh ? trs("詞（等級）") : trs("常用詞")) {
                    Picker(tr("詞"), selection: $store.practiceTopic) {
                        ForEach(words) { t in Text(tr("\(t.name)（不熟 \(all[t.id]?.unknown ?? 0)）")).tag(t.id) }
                    }
                    .pickerStyle(.inline)
                }
                if !chars.isEmpty {
                    Menu(store.isZh ? trs("漢字（等級）") : trs("常用字")) {
                        Picker(tr("字"), selection: $store.practiceTopic) {
                            ForEach(chars) { t in Text(tr("\(t.name)（不熟 \(all[t.id]?.unknown ?? 0)）")).tag(t.id) }
                        }
                        .pickerStyle(.inline)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "scope").foregroundStyle(T.btnInk)
                    Text(tr("練習範圍")).foregroundStyle(T.muted)
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
            ("calendar", trs("本週學習"), trs("從不熟的詞選這個星期要學的（或在列表往右滑 → 本週學習），一週後做期末測驗；答錯的詞可以留到下一週。")),
            ("graduationcap.fill", trs("開始練習"), tr("各種題目混在一起練。連續答對 \(goal) 次，詞就會移到「熟悉」；在列表往右滑可以直接移過去。")),
            ("text.badge.checkmark", trs("例句填空"), trs("只做例句填空題。")),
            ("pencil.line", trs("寫字題"), trs("開始練習和本週學習裡也有寫字題：看意思和讀音，一個字一個字把整個詞寫出來，按「對答案」以後自己說寫對了沒有。可以在「設定 → 卡片與練習」關掉。")),
            ("rectangle.3.group", trs("排句子"), trs("例句被打亂了，照華語的意思把詞排回去。")),
            ("character.book.closed", trs("看字排讀音"), trs("只看漢字，把讀音照順序排。")),
            ("waveform", trs("聲調練習"), trs("聽發音，選出聲調正確的拼法（先用不熟的詞，再用常用詞）。")),
            ("circle.hexagongrid.fill", trs("聲調色球"), trs("聽一個詞，照每個字的聲調點顏色球（顏色是設定裡選的聲調顏色）。每個字都算，全對有連對加分。")),
            ("square.grid.2x2", trs("翻牌配對"), trs("不熟的詞做成牌，一半是漢字，一半是讀音；一次翻兩張，把漢字和它的讀音配起來。")),
        ]
        do {
            a.append(("pencil.and.scribble", trs("手寫練習"), store.isZh ? trs("選要寫的字（不熟的漢字、HSK／TOCFL 的漢字等級、認識的漢字或自己打的字），看字、讀音和意思，用手指或 Apple Pencil 在格子裡寫。「描字」會在格子裡放一個淡淡的字，藥水條顯示描得多像；點上面的字看有這個字的詞，打勾表示這個字會了。") : trs("選要寫的字（不熟的詞的字、熟悉的詞的字或自己打的字），看字、讀音和意思，用手指或 Apple Pencil 在格子裡寫。「描字」會在格子裡放一個淡淡的字，藥水條顯示描得多像；點上面的字看有這個字的詞，打勾表示這個字會了。")))
        }
        a.append(("scope", trs("練習範圍"), trs("只練一個等級（或一組）的不熟的詞或字。")))
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
            .navigationTitle(tr("怎麼練習"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
