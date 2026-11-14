import SwiftUI

// MARK: - 華語: 詞典 and 轉換

/// a 華語 word to open (its key)
struct ZhKey: Hashable, Identifiable {
    let k: String
    var id: String { k }
}

/// 單詞比較 (華語)
struct ZhCompareRef: Hashable {}
/// 四川話的詞 / 國語用詞 / 普通話用詞: the words of a `spec` (a value, like the others: a page pushed without one is
/// taken off again when a word in it is opened)
struct ZhSpecRef: Hashable { let spec: Int }
/// 依詞類列出 (華語): nil = every word class, or the words of one
struct ZhClassRef: Hashable { var cls: String? = nil }

/// shows its content once the 華語 dictionary is loaded
struct ZhGate<Content: View>: View {
    @EnvironmentObject var store: Store
    @ViewBuilder let content: (ZhDict) -> Content
    var body: some View {
        Group {
            if store.missingDict {
                // (its dictionary isn't installed: the page offers it; see the app's overlay)
                Color.clear
            } else if let d = store.zh {
                content(d)
                    // (a new dictionary (華語 ↔ 粵語): everything made again, nothing kept from the other one, such as
                    // search results pointing into it)
                    .id(ObjectIdentifier(d))
                    .navigationDestination(for: ZhKey.self) { ZhEntryView(dict: d, key: $0.k) }
                    .navigationDestination(for: ZhCompareRef.self) { _ in ZhComparePage(dict: d) }
                    .navigationDestination(for: ZhSpecRef.self) { r in ZhSpecWordsPage(dict: d, spec: r.spec) }
                    .navigationDestination(for: ZhClassRef.self) { r in
                        if let c = r.cls { ZhWordClassPage(dict: d, cls: c) } else { ZhWordClassListPage(dict: d) }
                    }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(tr("載入\(trs(Lang.names[max(Lang.current, 1)]))詞典…")).ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
    }
}

/// 詞典 in 華語 mode: 查詞 / 收藏
struct ZhDictTabs: View {
    let dict: ZhDict
    @AppStorage("zhDictTab") private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(tr("查詞")).tag(0)
                Text(tr("收藏")).tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
            Group {
                if tab == 1 { ZhSavedPane(dict: dict) } else {
                    // (iPad, Mac: the results on the left, the word on the right)
                    EntrySplit {
                        ZhLookupPane(dict: dict)
                    } detail: { p in
                        if let k = p.base as? ZhKey, let e = dict.entry(k.k) {
                            ScrollView {
                                ZhEntryBody(dict: dict, entry: e).dictFontArea().padding().frame(maxWidth: 760).frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .id(tab)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: 查詞

struct ZhLookupPane: View {
    let dict: ZhDict
    @EnvironmentObject var store: Store
    // (the same search text as the 台語 dictionary's: a word looked up stays when the language is switched)
    @AppStorage("lookupQuery") private var query = ""
    @State private var found = ZhDict.Found()
    /// what `found` was searched for ("找不到" only once the search for what's typed has finished)
    @State private var searched = ""
    @State private var task: Task<Void, Never>?

    var body: some View {
        List {
            Section {
                TextField(Lang.isSv ? tr("瑞典文、英文或中文，例如：läsa、bilarna、read、汽車") : Lang.isJa ? tr("漢字、假名、羅馬字或英文，例如：食べる、たべる、taberu、eat、食べなかった") : Lang.isHak ? tr("漢字、客語拼音、華語意思、英文或聲調，例如：食飯、*仔、siid fan、吃飯、eat、8-3") : Lang.isYue ? tr("漢字、粵拼、英文或聲調，例如：食飯、唔*、sikfaan、sik6 faan6、eat、6-6") : tr("漢字、拼音、注音、英文或聲調，例如：吃飯、人*、chifan、ㄔㄈㄢ、eat、1-4"), text: $query)
                    .scaledFont(18)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .clearButton($query)
            }
            .listRowBackground(T.fn.opacity(0.7))
            // 單詞比較, as in the 台語 dictionary (a header: a row's rounded corners would cut the tile off)
            Section {
            } header: {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        NavigationLink(value: ZhClassRef()) { TileLabel(icon: "list.bullet.indent", title: trs("依詞類列出")) }
                            .buttonStyle(.plain)
                        NavigationLink(value: ZhCompareRef()) { TileLabel(icon: "rectangle.split.2x1", title: trs("單詞比較")) }
                            .buttonStyle(.plain)
                    }
                    // 日語: 助詞 and 實驗室 (no 部首查字: the radicals are the 華語 data's)
                    if dict.isJa {
                        HStack(spacing: 10) {
                            NavigationLink { JaParticlesPage() } label: { TileLabel(icon: "point.3.connected.trianglepath.dotted", title: trs("助詞")) }
                                .buttonStyle(.plain)
                            NavigationLink { JaLabPage(dict: dict, start: nil) } label: { TileLabel(icon: "slider.horizontal.3", title: trs("實驗室")) }
                                .buttonStyle(.plain)
                        }
                    } else if !dict.isSv {
                    HStack(spacing: 10) {
                        NavigationLink {
                            RadicalPage(isChar: { dict.byHan[$0] != nil }) { query += $0 }
                        } label: { TileLabel(icon: "square.grid.3x3", title: trs("部首查字")) }
                            .buttonStyle(.plain)
                        // 華語: the words of the 讀音 chosen, like 日語借詞 in the 台語 dictionary: 國語用詞 (only 臺灣
                        // uses them), 普通話用詞 (only 大陸), 四川話的詞 (四川話's own)
                        let spec = [1, 2, ZhDict.sichuanSpec][min(max(store.zhPlace, 0), 2)]
                        if dict.lang == 1, !dict.specWords(spec).isEmpty {
                            NavigationLink(value: ZhSpecRef(spec: spec)) {
                                TileLabel(icon: spec == ZhDict.sichuanSpec ? "mountain.2" : "character.book.closed",
                                          title: spec == 1 ? trs("國語用詞") : spec == 2 ? trs("普通話用詞") : trs("四川話的詞"),
                                          count: dict.specWords(spec).count, cap: 1_000_000)
                            }
                                .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                    }
                }
                .padding(.vertical, 4)
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            if query.isEmpty {
                Text(Lang.isSv ? tr("可以查瑞典文（變化過的形也可以：bilarna → bil）、英文（read）或中文的意思（汽車）。\n每個詞分成詞素：詞根、前綴、後綴、連接音和詞尾各用一種顏色。點進一個詞，再點它的一個部分，看那個部分的意思和作用。\n* 代表一個以上的字母，? 代表剛好一個：*het → het 結尾\n往右滑一個詞加到「不熟」，往左滑收藏。")
                     : Lang.isJa ? tr("可以查漢字、假名、羅馬字（taberu）或英文（eat）。變化過的形也找得到：食べなかった、書かれた → 食べる、書く。英文的意思越接近（剛好是那個詞）排越前面。\n* 代表一個以上的字，? 代表剛好一個字：食* → 食開頭\n往右滑一個詞加到「不熟」，往左滑收藏。")
                     : Lang.isHak ? tr("可以查漢字、客語拼音（不用打聲調：siid fan）、華語的意思（吃飯）或英文（eat）。\n* 代表一個以上的字，? 代表剛好一個字：\n*仔 → 仔結尾　食* → 食開頭\n打聲調類別的數字找聲調組合：1 陰平、2 上聲、3 去聲、4 陰入、5 陽平、7 陽去、8 陽入，例如 8-3。\n讀音照選的腔顯示。\n往右滑一個詞加到「不熟」，往左滑收藏。")
                     : Lang.isYue ? tr("可以查漢字（正體或簡體）、粵拼（聲調可以不打，或用數字：sik6 faan6）或英文（eat、computer）。打華語的詞（聊天、沒有）會列出粵語的講法。\n* 代表一個以上的字，? 代表剛好一個字：\n唔* → 唔開頭的詞　*仔 → 仔結尾\n打聲調數字找聲調組合：1-4、6 6。\n往右滑一個詞加到「不熟」，往左滑收藏。")
                     : tr("可以查漢字（正體或簡體）、拼音（聲調可以不打，或用數字：chi1fan4）、注音或英文（eat、computer）。\n* 代表一個以上的字，? 代表剛好一個字：\n人* → 人開頭的詞　*子 → 子結尾　*水* → 水在中間　?子 → 兩個字、子結尾\n打聲調數字找聲調組合：1-4、3 3、2 0（0 或 5 = 輕聲）。\n讀音照上面選的「國語／普通話／四川話」和「拼音／注音」顯示（四川話拼音也可以查）。\n往右滑一個詞加到「不熟」，往左滑收藏。"))
                    .ffFont(.footnote).foregroundStyle(T.muted).listRowBackground(Color.clear)
            } else if found.empty && searched == query {
                Text(tr("找不到「\(query)」。")).foregroundStyle(T.muted).listRowBackground(Color.clear)
            }
            group(tr("聲調「\(found.toneLabel)」（\(found.tones.count >= 500 ? "500+" : String(found.tones.count))）"), found.tones)
            group(dict.isYue ? tr("華語「\(query)」的粵語講法") : (dict.isHak ? tr("華語「\(query)」的客語講法") : tr("「\(query)」的四川話講法")), found.mandarin)
            if found.englishFirst { group(tr("英文「\(query)」"), found.english, english: true) }
            group("「\(query)」", found.words)
            // 瑞典語: a compound the dictionary doesn't have, in its parts
            if let est = found.svEst {
                Section(tr("拆開來看")) { SvCompoundBlock(dict: dict, word: query, est: est).padding(.vertical, 4) }
                    .listRowBackground(T.fn.opacity(0.7))
            }
            ForEach(Array(found.parts.enumerated()), id: \.offset) { i, w in
                group("「\(w)」", found.partWords[i])
            }
            // 瑞典語: 華語 → English → 瑞典語, each marked as guessed
            if !found.svVia.isEmpty {
                Section {
                    ForEach(found.svVia.prefix(60).filter { $0 < dict.entries.count }, id: \.self) { i in
                        let e = dict.entries[i]
                        EntryLink(value: ZhKey(k: e.k)) {
                            HStack(spacing: 8) {
                                ZhWordRow(dict: dict, entry: e)
                                InfoChip.grey(tr("推測"))
                            }
                        }
                    }
                } header: {
                    Text(tr("經由英文推測：「\(query)」→ \(found.svViaEnglish)")).textCase(nil)
                } footer: {
                    Text(tr("這些詞是照「\(query)」在 CC-CEDICT 裡的英文意思，再用英文找瑞典文，不一定是同一個意思。"))
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
            group(tr("開頭是「\(query)」"), found.starts)
            if !found.englishFirst { group(tr("英文「\(query)」"), found.english, english: true) }
            group(tr("裡面有「\(query)」"), found.contains)
            group(tr("解釋裡有「\(query)」"), found.defs)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            search()
            // make the English search's text ahead of the first English search
            let d = dict
            Task.detached(priority: .utility) { d.warmEnglish() }
        }
        .onChange(of: query) { search() }
        .onChange(of: store.zhPlace) { search() }
    }

    @ViewBuilder private func group(_ title: String, _ list: [Int], english: Bool = false) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list.prefix(english ? 250 : 500).filter { $0 < dict.entries.count }, id: \.self) { i in
                    let e = dict.entries[i]
                    EntryLink(value: ZhKey(k: e.k)) { ZhWordRow(dict: dict, entry: e, english: english, query: english ? query : nil) }
                        .swipeActions(edge: .leading) {
                            Button { store.toggleUnknown(e.k) } label: { Label(tr("不熟"), systemImage: "star") }.tint(T.rustEdge)
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleSaved(e.k) } label: {
                                Label(store.isSaved(e.k) ? trs("取消收藏") : trSaveVerb(), systemImage: "bookmark")
                            }.tint(T.oliveEdge)
                        }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
    }

    private func search() {
        task?.cancel()
        let q = query, d = dict, pl = store.zhPlace
        task = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { d.search(q, place: pl) }.value
            guard !Task.isCancelled else { return }
            found = r
            searched = q
        }
    }
}

/// a word in a list: 漢字, reading, first meaning
struct ZhWordRow: View {
    let dict: ZhDict
    let entry: ZhEntry
    /// found by its English meaning: show that instead of the 華語 one
    var english = false
    /// how many meanings to show (more than 1: one a line)
    var meanings = 1
    /// found by this English word: the meanings with it first, and the 中文 meaning under them
    var query: String? = nil
    @EnvironmentObject var store: Store
    @AppStorage(ZhMeaning.key) private var zhMainEnglish = false
    @AppStorage(ZhMeaning.hakKey) private var hakMainEnglish = false
    /// 設定 → 主要解釋 for this dictionary's language
    private var mainEnglish: Bool { dict.isHak ? hakMainEnglish : zhMainEnglish }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dict.hanText(entry.h, entry.syl(store.zhPlace), base: T.glyph)).scaledFont(20, weight: .semibold).toneGlow()
                Text(dict.reading(entry.syl(store.zhPlace), store.zhRom)).latFont(16).toneGlow().foregroundStyle(T.greenInk)
                if entry.spec != 0 { ZhSpecChip(spec: entry.spec) }
                // 四川話: where the reading is from (no box: Wiktionary)
                if dict.lang == 1, store.zhPlace == 2, let k = SichuanChip.kind(entry.sc == nil ? nil : entry.scKind) {
                    SichuanChip(kind: k, small: true)
                }
                if entry.level(store.zhList) > 0 {
                    Text(UILang.label(Lang.levelName(store.zhList, entry.level(store.zhList)))).ffFont(.caption2, .bold).foregroundStyle(T.blueInk)
                }
                Spacer(minLength: 0)
                if store.isSaved(entry.k) { Image(systemName: "bookmark.fill").ffFont(.caption).foregroundStyle(T.oliveInk) }
                if store.cardStatus(entry.k) == 2 { Image(systemName: "star.fill").ffFont(.caption).foregroundStyle(T.rustInk) }
            }
            // found by its English meaning, or 設定 → 主要解釋: English
            if meanings > 1 {
                // 1–2 meanings, one a line (手寫練習's words)
                let en = ((english || mainEnglish) && entry.en != nil) || entry.senses.isEmpty
                let ms = en ? Array(entry.enList.prefix(meanings)) : entry.senses.prefix(meanings).map(\.text)
                ForEach(Array(ms.enumerated()), id: \.offset) { i, m in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if ms.count > 1 { Text("\(i + 1).").ffFont(.caption, .bold).foregroundStyle(T.muted) }
                        Text(m).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
                    }
                }
            } else if let q = query, english {
                // found by its English: the English (the meanings with the word first), then the 中文 meaning
                // (粵語: Wiktionary's meanings are English already)
                let ens = EnglishMatch.first(dict.isYue ? EnglishMatch.unique(entry.senses.map(\.text) + entry.enList) : entry.enList, q)
                Text(ens.prefix(3).joined(separator: "; ")).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.85)).lineLimit(2)
                if !dict.isYue, !mainEnglish, let s = entry.senses.first {
                    Text(s.text).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1)
                }
            } else if english || mainEnglish, entry.en != nil {
                Text(entry.enList.prefix(3).joined(separator: "; ")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
            } else if let s = entry.senses.first {
                Text(s.text).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
            } else if entry.en != nil {
                Text(entry.enList.prefix(3).joined(separator: "; ")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
            }
        }
    }
}

struct ZhSpecChip: View {
    let spec: Int
    var body: some View {
        if spec == ZhDict.sichuanSpec {
            Chip(text: trs("四川話"), fill: Color(hex: 0x1d4a44), edge: ToneColors.teal, ink: Color(hex: 0xb4f2e8))
        } else {
            Chip(text: spec == 1 ? trs("臺灣用語") : trs("大陸用語"), fill: T.twFill, edge: T.twEdge, ink: T.twInk)
        }
    }
}

// MARK: one entry

struct ZhEntryView: View {
    let dict: ZhDict
    let key: String
    var body: some View {
        ScrollView {
            if let e = dict.entry(key) {
                ZhEntryBody(dict: dict, entry: e).dictFontArea()
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            } else {
                Text(tr("找不到這個詞。")).foregroundStyle(T.muted).padding()
            }
        }
        .appBackground()
        .navigationTitle(dict.entry(key)?.h ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

/// a 華語 entry in a sheet from the bottom (from the cards)
struct ZhEntrySheet: View {
    let dict: ZhDict
    let key: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZhEntryView(dict: dict, key: key)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
                .navigationDestination(for: ZhKey.self) { ZhEntryView(dict: dict, key: $0.k) }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }
}

struct ZhEntryBody: View {
    let dict: ZhDict
    let entry: ZhEntry
    @EnvironmentObject var store: Store
    @State private var tapped: ZhKey?

    /// for each character of the headword: the single-character entry read the way this word reads it
    private func charKeys(_ syl: [String]) -> [String?] {
        var out: [String?] = [], n = 0
        for u in entry.h.unicodeScalars {
            guard Zhuyin.isHan(u) else { out.append(nil); continue }
            defer { n += 1 }
            let ch = String(u)
            guard n < syl.count, syl[n] != "-" else { out.append(nil); continue }
            let s = syl[n]
            let hit = (dict.byHan[ch] ?? []).map { dict.entries[$0] }
                .first { $0.h == ch && $0.k != entry.k && ($0.tw.first == s || $0.lu?.first == s || (n < entry.tw.count && $0.tw.first == entry.tw[n])) }
            out.append(hit?.k)
        }
        return out
    }

    /// the readings of the other 讀音 (國語 0, 普通話 1, 四川話 2) that differ from the one shown
    private func otherPlaces(_ shown: [String]) -> [(Int, [String])] {
        var out: [(Int, [String])] = []
        for (i, s) in [entry.tw, entry.lu ?? entry.tw, entry.sc].enumerated() where i != store.zhPlace {
            guard let s, s != shown, !out.contains(where: { $0.1 == s }) else { continue }
            out.append((i, s))
        }
        return out
    }

    var body: some View {
        let syl = dict.isSv ? dict.svSyl(entry) : entry.syl(store.zhPlace)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if dict.isSv {
                    // 瑞典語: the word, and its morphemes right under it (long words don't fit side by side)
                    HStack(alignment: .center, spacing: 12) {
                        Text(dict.hanText(entry.h, syl, base: T.glyph)).toneGlow().latFont(34).fontWeight(.semibold)
                            .textSelection(.enabled)
                        PlayButton(path: entry.audio ?? "tts:" + entry.h)
                        Spacer()
                        FrequencyBadge(key: entry.k)
                    }
                    let r = dict.reading(syl, store.zhRom)
                    if !r.characters.isEmpty {
                        Text(r).toneGlow().latFont(22).foregroundStyle(T.greenInk).textSelection(.enabled)
                    }
                    // (found through the English of a 華語 word: a guess)
                    if let v = SvVia.found[entry.k] {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            InfoChip.grey(tr("推測"))
                            Text(tr("由「\(v.zh)」經英文（\(v.en)）推測的詞，不一定是同一個意思。")).ffFont(.caption).foregroundStyle(T.muted)
                        }
                    }
                } else {
                HStack(alignment: .center, spacing: 12) {
                    // tap a character to see it on its own (the entry with the same reading)
                    TappableHeadword(text: dict.hanText(entry.h, syl, base: T.glyph), targets: charKeys(syl)) { tapped = ZhKey(k: $0) }
                        .toneGlow()
                    // the reading chosen (讀音 and spelling), right next to the word
                    Text(dict.reading(syl, store.zhRom)).toneGlow().latFont(22).foregroundStyle(T.greenInk).textSelection(.enabled)
                    PlayButton(path: entry.audio ?? "tts:" + entry.h)
                    Spacer()
                    FrequencyBadge(key: entry.k)
                }
                }
                HStack(spacing: 8) {
                    saveButton
                    star
                }
                // a single character: its character card too
                if entry.h.count == 1 && !dict.isSv { ZhCharCardRow(dict: dict, ch: entry.h) }
                // the other reading system, small (四川話 too: 四川話拼音 and 注音)
                if !dict.isSv {
                    Text(dict.reading(syl, store.zhRom == 0 ? 1 : 0)).ffFont(.subheadline).foregroundStyle(T.purpleInk).textSelection(.enabled)
                }
                // 客語: how the other accents say it
                if dict.isHak { HakAccentRows(dict: dict, entry: entry) }
                // 四川話: no 四川話 reading (orange), or a guessed one (pink)
                if dict.lang == 1, store.zhPlace == 2 {
                    if let k = SichuanChip.kind(entry.sc == nil ? nil : entry.scKind) { SichuanNote(kind: k) }
                }
                // 國語, 普通話 and 四川話: every one, the one chosen in colour (like 客語's accents)
                if dict.lang == 1 { ZhPlaceRows(dict: dict, entry: entry) }
                if !dict.isJa && !dict.isSv { InputCodesRow(han: entry.h) }
                // the English meanings, one per line
                let ens = dict.isJa ? [] : entry.enList
                if !ens.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Chip(text: tr("英"), fill: T.fn, edge: T.fnEdge, ink: T.muted)
                        ZhEnglishList(items: ens)
                    }
                }
                // 粵語: the 華語 word(s) with the same meaning
                if !entry.eq.isEmpty && !dict.isSv {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Chip(text: dict.isJa ? tr("也寫") : tr("華"), fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
                        Text(entry.eq.joined(separator: "、")).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                    }
                }
                // the boxes, always in the same order of colours: blue (levels), green (where it's said), yellow
                // (詞類: tap one for the words of that class), grey (簡化字)
                FlowLayout(spacing: 6) {
                    if dict.lang != 1 {
                        if entry.hsk > 0 { InfoChip.blue(UILang.label(Lang.levelName(0, entry.hsk))) }
                    } else if entry.hsk > 0 { InfoChip.blue(Lang.hskName(entry.hsk)) }
                    if entry.tocfl > 0 && dict.lang == 1 { InfoChip.blue(UILang.label(Lang.levelName(1, entry.tocfl))) }
                    if entry.spec != 0 { ZhSpecChip(spec: entry.spec) }
                    ForEach(entry.pos, id: \.self) { p in
                        NavigationLink(value: ZhClassRef(cls: p)) { InfoChip.yellow(p) }
                            .buttonStyle(.plain)
                    }
                    if entry.h.count == 1, let l = Shuowen.liushu(entry.h) { InfoChip.yellow(tr("六書：") + l) }
                    if let a = entry.alt, a != entry.h {
                        InfoChip.grey(tr("簡") + "　" + a)
                    }
                }
            }
            // the same 漢字 read another way
            let others = dict.others(entry)
            if !others.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Chip(text: tr("又讀"), fill: T.fn, edge: T.fnEdge, ink: T.muted)
                    FlowLayout(spacing: 6) {
                        ForEach(others, id: \.k) { o in
                            NavigationLink(value: ZhKey(k: o.k)) {
                                Text(dict.reading(o.syl(store.zhPlace), store.zhRom)).latFont(15).foregroundStyle(T.greenInk)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(T.fn.opacity(0.8)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            // 日語: the meanings small and numbered (like the English ones), not as boxes
            if dict.isJa {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(entry.senses, id: \.n) { s in jaSense(s) }
                }
            } else {
                ForEach(entry.senses, id: \.n) { s in sense(s) }
            }
            // 近義詞 / 反義詞 (《重編國語辭典修訂本》), the ones this dictionary has
            let syn = entry.syn.compactMap { dict.usual($0).map { dict.entries[$0] } }
            let ant = entry.ant.compactMap { dict.usual($0).map { dict.entries[$0] } }
            if !syn.isEmpty || !ant.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    links("近", syn, T.blue, T.blueEdge, T.blueInk)
                    links("反", ant, T.rust, T.rustEdge, T.rustInk)
                }
            }
            // 日語: the kanji of the word, and its 活用
            if dict.isJa { JaWordExtras(dict: dict, entry: entry) }
            // 瑞典語: the word's parts (tap one), its Chinese meanings, its forms
            if dict.isSv { SvWordExtras(dict: dict, entry: entry) }
            FoundSentences(key: entry.k)
            // a single character: 說文解字 (when installed)
            if entry.h.count == 1 && !dict.isJa && !dict.isSv { ShuowenBlock(ch: entry.h) }
            if entry.extra {
                Text(tr("這個詞表裡的詞《兩岸常用詞典》裡沒有：讀音用 CC-CEDICT 的（有臺灣讀音的話用臺灣的），沒有的話照組成它的詞推算；意思用 CC-CEDICT 的英文解釋。"))
                    .ffFont(.caption).foregroundStyle(T.muted)
            }
            Text(dict.isSv
                 ? tr("資料：Folkets lexikon（KTH，CC BY-SA 2.5）；中文意思：維基詞典（CC BY-SA）；常用詞：FrequencyWords（CC BY-SA 4.0）。詞的組成依規則推算，可能有誤。")
                 : dict.isJa
                 ? tr("資料：JMdict（EDRDG，CC BY-SA 4.0）。活用表依規則產生。")
                 : dict.isHak
                 ? tr("資料：教育部《臺灣客語辭典》（CC BY-ND 3.0 TW）；英文解釋：CC-CEDICT（華語寫法相同的詞）。注音依拼音照規則轉寫；例句的讀音依詞典的詞推算，可能有誤。")
                 : dict.isYue
                 ? tr("資料：CC-Canto、CC-CEDICT（CC BY-SA）、維基詞典（CC BY-SA）、rime-cantonese（CC BY）、開放粵語字典（CC BY）。耶魯拼音依粵拼照規則轉寫；例句的讀音依維基詞典。")
                 : tr("資料：中華文化總會《兩岸常用詞典》（CC BY-NC-ND）。拼音依注音照規則轉寫；例句的讀音依詞典的詞推算，可能有誤。"))
                .ffFont(.caption2).foregroundStyle(T.muted)
            // 《重編國語辭典修訂本》 always at the very bottom
            moeChar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $tapped) { k in ZhEntrySheet(dict: dict, key: k.k).environmentObject(store) }
    }

    /// a single character: its meanings in 教育部《重編國語辭典修訂本》 too (the reading this entry has)
    @ViewBuilder private var moeChar: some View {
        if entry.h.count == 1, !dict.isHak, !dict.isJa, let i = dict.charIndex[entry.h],
           let r = dict.chars[i].readings.first(where: { $0.zy == entry.tw.first }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(dict.isYue ? tr("開放粵語字典") : tr("《重編國語辭典修訂本》")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                ForEach(Array(r.defs.enumerated()), id: \.offset) { n, d in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(n + 1).").ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                        if !d.pos.isEmpty { Chip(text: d.pos, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                        Text(d.text).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.4)))
            Text(dict.isYue ? tr("資料：開放詞典《開放粵語字典》（CC BY 3.0）。") : tr("資料：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW），g0v 萌典整理。只收字的解釋和用例，引用的古書省略。"))
                .ffFont(.caption2).foregroundStyle(T.muted)
        }
    }

    private func sense(_ s: ZhSense) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(s.n).").ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                Text(s.text).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                Spacer(minLength: 4)
                ZhSenseCopyButton(dict: dict, key: entry.k, sense: s.n - 1)
                SenseSaveButton(item: SavedSense(key: entry.k, sense: s.n - 1), store: store)
            }
            ForEach(Array(s.ex.enumerated()), id: \.offset) { _, x in
                ZhExampleBlock(dict: dict, ex: x)
                    .padding(.leading, 18)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    /// 日語: one meaning, a small number in front of it, its examples under it
    private func jaSense(_ s: ZhSense) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            EnNum(n: s.n)
            VStack(alignment: .leading, spacing: 4) {
                Text(s.text).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                ForEach(Array(s.ex.enumerated()), id: \.offset) { _, x in
                    ZhExampleBlock(dict: dict, ex: x)
                }
            }
            Spacer(minLength: 4)
            SenseSaveButton(item: SavedSense(key: entry.k, sense: s.n - 1), store: store)
        }
    }

    @ViewBuilder private func links(_ name: String, _ es: [ZhEntry], _ fill: Color, _ edge: Color, _ ink: Color) -> some View {
        if !es.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Chip(text: name, fill: fill, edge: edge, ink: ink)
                FlowLayout(spacing: 6) {
                    ForEach(es, id: \.k) { e in
                        NavigationLink(value: ZhKey(k: e.k)) {
                            HStack(spacing: 4) {
                                Text(Simp.show(e.h)).foregroundStyle(T.glyph)
                                Text(dict.reading(e.syl(store.zhPlace), store.zhRom)).latFont(13).foregroundStyle(ink)
                            }
                            .ffFont(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(fill.opacity(0.5)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var saveButton: some View {
        let on = store.isSaved(entry.k)
        return Button { withAnimation(.snappy) { store.toggleSaved(entry.k) } } label: {
            Label(on ? trs("已收藏") : trSaveVerb(), systemImage: on ? "bookmark.fill" : "bookmark")
                .ffFont(.subheadline, .semibold)
                .foregroundStyle(on ? T.oliveInk : T.glyph)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? T.olive : T.fn.opacity(0.8)))
                .overlay(Capsule().stroke(on ? T.oliveEdge : T.fnEdge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var star: some View { CardMarkButtons(key: entry.k) }
}

/// an example sentence: 漢字 (tap a word to see it in the dictionary; the whole word is the button), reading, where it's from; ▶ reads it aloud
struct ZhExampleBlock: View {
    let dict: ZhDict
    let ex: ZhEx
    @EnvironmentObject var store: Store
    @State private var tapped: ZhKey?
    /// 設定 → 例句的詞分開一點
    @AppStorage("wordGap") private var gap = true
    var body: some View {
        if dict.isJa { jaBody } else if dict.isSv { SvExampleBody(dict: dict, ex: ex) } else { zhBody }
    }

    /// 日語: the sentence (kanji, hiragana, katakana in their colours) and its English (Tatoeba's, through JMdict)
    private var jaBody: some View {
        HStack(alignment: .top, spacing: 10) {
            PlayButton(path: "tts:" + ex.h, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(JaInk.word(ex.h)).ffFont(.body).toneGlow().textSelection(.enabled)
                if !ex.src.isEmpty { Text(ex.src).ffFont(.subheadline).foregroundStyle(T.muted).textSelection(.enabled) }
            }
        }
    }

    @ViewBuilder private var zhBody: some View {
        // (客語: no reading word by word in the sentence: the dictionary's words, as in 轉換)
        let ps = ex.code.isEmpty ? dict.convertPieces(ex.h) : ZhDict.pieces(ex)
        HStack(alignment: .top, spacing: 10) {
            PlayButton(path: "tts:" + ex.h, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                // the same as the 台語 sentences: each word its own taller box (a bigger place to tap), a little apart
                // swells when pressed or under the pointer; hold and slide to swell the word under the finger
                let keys = ps.map { p in p.tw != nil ? dict.entry(for: p)?.k : nil }
                SwellWords(pieces: ps.indices.map { i in (dict.sentenceHan([ps[i]], store.zhPlace, base: T.blueInk), keys[i] != nil, false, 0) },
                           lineSpacing: -4, vPad: 7, hPad: gap ? 2 : 0) { i in
                    if let k = keys[i] { tapped = ZhKey(k: k) }
                }
                .ffFont(.body)
                Text(dict.sentence(ps, store.zhRom, store.zhPlace)).latFont(15).toneGlow().foregroundStyle(T.greenInk).textSelection(.enabled)
                if !ex.src.isEmpty { Text(ex.src).ffFont(.caption).foregroundStyle(T.muted) }
            }
        }
        .sheet(item: $tapped) { k in ZhEntrySheet(dict: dict, key: k.k).environmentObject(store) }
    }
}

// MARK: 收藏

struct ZhSavedPane: View {
    let dict: ZhDict
    @EnvironmentObject var store: Store
    @State private var shareItem: ShareItem?
    var body: some View {
        let keys = store.savedKeys
        let senses = store.savedSenses
        List {
            if keys.isEmpty && senses.isEmpty {
                Text(tr("在詞典裡按「收藏」或意思旁邊的書籤，詞和意思會出現在這裡。"))
                    .ffFont(.footnote).foregroundStyle(T.muted).listRowBackground(Color.clear)
            } else {
                Button {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("方方-華語收藏.csv")
                    if (try? Data(csv(keys, senses).utf8).write(to: url, options: .atomic)) != nil { shareItem = ShareItem(url: url) }
                } label: {
                    Label(tr("匯出 CSV"), systemImage: "square.and.arrow.up").foregroundStyle(T.oliveInk)
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
            if !keys.isEmpty {
                Section(tr("\(keys.count) 個詞（往左滑刪除）")) {
                    ForEach(keys, id: \.self) { k in
                        if let e = dict.entry(k) {
                            NavigationLink(value: ZhKey(k: k)) { ZhWordRow(dict: dict, entry: e) }
                                .swipeActions { Button(role: .destructive) { store.toggleSaved(k) } label: { Label(tr("刪除"), systemImage: "trash") } }
                        }
                    }
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
            if !senses.isEmpty {
                Section(tr("\(senses.count) 個意思（往左滑刪除）")) {
                    ForEach(senses, id: \.id) { s in
                        if let e = dict.entry(s.key), s.sense < e.senses.count {
                            NavigationLink(value: ZhKey(k: s.key)) { senseRow(e, e.senses[s.sense]) }
                                .swipeActions { Button(role: .destructive) { store.unsave(s) } label: { Label(tr("刪除"), systemImage: "trash") } }
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = SenseCopy.zhText(dict, key: s.key, sense: s.sense, rom: store.zhRom, place: store.zhPlace)
                                    } label: { Label(tr("複製這個意思"), systemImage: "doc.on.doc") }
                                }
                        }
                    }
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
    }

    /// word, 拼音 with tone numbers (a space between syllables), meaning (English first), sentences (a blank line
    /// between them); saved words first, then saved meanings
    private func csv(_ keys: [String], _ senses: [SavedSense]) -> String {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        func numbered(_ e: ZhEntry) -> String {
            e.syl(store.zhPlace).filter { $0 != "-" && $0 != "_" }.map { s -> String in
                let t = Zhuyin.tone(s)
                return Zhuyin.plainSyllable(s).replacingOccurrences(of: "v", with: "ü") + String(t == 0 ? 5 : t)
            }.joined(separator: " ")
        }
        func sentences(_ xs: [ZhEx]) -> String { xs.map(\.h).joined(separator: "\n\n") }
        var rows = ["word,pronunciation,meaning,sentences"]
        for k in keys {
            guard let e = dict.entry(k) else { continue }
            let meaning = e.en ?? e.senses.map(\.text).joined(separator: "；")
            rows.append([e.h, numbered(e), meaning, sentences(e.senses.flatMap(\.ex))].map(q).joined(separator: ","))
        }
        for s in senses {
            guard let e = dict.entry(s.key), s.sense < e.senses.count else { continue }
            let m = e.senses[s.sense]
            // the English meaning is for the whole word: with it, which meaning this is
            let meaning = e.en.map { $0 + "（\(m.text)）" } ?? m.text
            rows.append([e.h, numbered(e), meaning, sentences(m.ex)].map(q).joined(separator: ","))
        }
        return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
    }

    private func senseRow(_ e: ZhEntry, _ m: ZhSense) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dict.hanText(e.h, e.syl(store.zhPlace), base: T.glyph)).scaledFont(20, weight: .semibold).toneGlow()
                Text(dict.reading(e.syl(store.zhPlace), store.zhRom)).latFont(16).toneGlow().foregroundStyle(T.greenInk)
                Spacer(minLength: 0)
                Image(systemName: "bookmark.fill").ffFont(.caption).foregroundStyle(T.blueInk)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(m.n).").ffFont(.footnote, .bold).foregroundStyle(T.muted)
                Text(m.text).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.9))
            }
            ForEach(Array(m.ex.prefix(3).enumerated()), id: \.offset) { _, x in
                let ps = ZhDict.pieces(x)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dict.sentenceHan(ps, store.zhPlace, base: T.blueInk)).ffFont(.subheadline).toneGlow()
                    Text(dict.sentence(ps, store.zhRom, store.zhPlace)).latFont(14).toneGlow().foregroundStyle(T.greenInk)
                }
                .padding(.leading, 18)
            }
        }
    }
}

// MARK: - 轉換 (華語)

/// 華語 text → 拼音 / 注音, in tone colours; the readings are the dictionary's (most common reading of each word)
struct ZhConvertPane: View {
    let dict: ZhDict
    /// the 歌詞 window: no typing, only the 漢字 (left) and the chosen reading (right)
    let lyrics: Bool
    @EnvironmentObject var store: Store
    @AppStorage private var text: String
    @State private var pieces: [ZhPiece] = []
    @State private var copied: Int?
    @State private var copySheet = false
    @State private var task: Task<Void, Never>?
    @State private var tapped: ZhKey?
    @FocusState private var focused: Bool

    init(dict: ZhDict, textKey: String = "zhConvText", lyrics: Bool = false) {
        self.dict = dict
        self.lyrics = lyrics
        _text = AppStorage(wrappedValue: "", textKey)
    }

    /// the reading chosen (拼音 / 注音, 粵拼 / 耶魯, rōmaji / かな…)
    private var romIndex: Int { min(max(store.zhRom, 0), 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if lyrics {
                    if !pieces.isEmpty {
                        // how much of the song you know: 認識 of the words the dictionary has
                        let ks = words.compactMap(\.key).compactMap { store.cardStatus($0) }
                        if !ks.isEmpty {
                            let n = Int((100 * Double(ks.filter { $0 == 1 }.count) / Double(ks.count)).rounded())
                            Text(tr("懂 \(n)%（虛線：還沒學的詞，黃線：不熟）")).ffFont(.footnote).foregroundStyle(T.muted)
                        }
                        LyricsColumns {
                            panel(0, trs("漢字"), dict.sentenceHan(pieces, store.zhPlace, base: T.glyph))
                            panel(romIndex + 1, trs(Lang.romNames[romIndex]), dict.sentence(pieces, romIndex, store.zhPlace))
                        }
                    }
                } else {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(Lang.isHak ? tr("輸入或貼上客語…") : Lang.isYue ? tr("輸入或貼上粵語（正體或簡體都可以）…") : tr("輸入或貼上華語（正體或簡體都可以）…")).foregroundStyle(T.muted).padding(.horizontal, 5).padding(.vertical, 8)
                    }
                    TextEditor(text: $text)
                        .scaledFont(18)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
                .overlay(alignment: .bottomTrailing) {
                    // the same as the 台語 轉換: paste, and empty it
                    HStack(spacing: 6) {
                        Button {
                            if let s = UIPasteboard.general.string { text = s }
                        } label: { Image(systemName: "doc.on.clipboard") }
                        if !text.isEmpty {
                            Button { text = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel(tr("清除"))
                        }
                    }
                    .scaledFont(18)
                    .foregroundStyle(T.muted)
                    .padding(10)
                }
                if !pieces.isEmpty {
                    panel(0, trs("漢字"), dict.sentenceHan(pieces, store.zhPlace, base: T.glyph))
                    panel(1, trs(Lang.romNames[0]), dict.sentence(pieces, 0, store.zhPlace))
                    panel(2, trs(Lang.romNames[1]), dict.sentence(pieces, 1, store.zhPlace))
                    HStack(spacing: 10) {
                        Button { copy(all: true) } label: {
                            Label(copied == 9 ? trs("已複製") : trs("全部複製"), systemImage: copied == 9 ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                        }
                        .softButton()
                        Button { copySheet = true } label: {
                            Label(tr("選擇複製…"), systemImage: "slider.horizontal.3").frame(maxWidth: .infinity)
                        }
                        .softButton()
                    }
                    Text(tr("讀音照詞典裡最常見的唸法，一字多音的地方可能會錯。上面可以切換國語／普通話／四川話的讀音。"))
                        .ffFont(.caption).foregroundStyle(T.muted)
                }
                }
            }
            .padding()
            .frame(maxWidth: lyrics ? 1100 : 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { run() }
        .onChange(of: text) { run() }
        .sheet(item: $tapped) { k in ZhEntrySheet(dict: dict, key: k.k).environmentObject(store) }
        .sheet(isPresented: $copySheet) {
            CopyOptionsSheet(texts: [plain(0), plain(1), plain(2)], names: [trs("漢字"), trs(Lang.romNames[0]), trs(Lang.romNames[1])])
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(tr("完成")) { focused = false }
            }
        }
    }

    private func panel(_ i: Int, _ title: String, _ a: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).ffFont(.caption, .bold).foregroundStyle(T.muted)
                Spacer()
                if i == 0 { PlayButton(path: "tts:" + text, size: 28) }
                Button { copy(i) } label: {
                    Image(systemName: copied == i ? "checkmark" : "doc.on.doc").foregroundStyle(T.muted)
                }
                .buttonStyle(.plain)
            }
            if i == 0 {
                // the 漢字: each word can be tapped to see it (it swells when pressed or under the pointer;
                // hold and slide to swell the word under the finger, let go to open it)
                let w = words
                SwellWords(pieces: w.map { x in
                    var a = dict.sentenceHan([x.piece], store.zhPlace, base: T.glyph)
                    // (the 歌詞 page: a word you don't know yet underlined; 不熟 in yellow)
                    if lyrics, let k = x.key, let st = store.cardStatus(k), st != 1 {
                        let line: Text.LineStyle = st == 2 ? Text.LineStyle(pattern: .solid, color: T.oliveInk)
                            : Text.LineStyle(pattern: .dot, color: Color.white.opacity(0.5))
                        a.underlineStyle = line
                    }
                    return (a, x.key != nil, x.newLine, 0)
                }, vPad: 3) { j in
                    if let k = w[j].key { focused = false; remember(k, j, w); tapped = ZhKey(k: k) }
                }
                .ffFont(.title3)
            } else if lyrics {
                // (the 歌詞 window: the reading's words swell and open too, like the 漢字)
                let w = words
                SwellWords(pieces: romPieces(w, i - 1), vPad: 3) { j in
                    if let k = w[j].key { remember(k, j, w); tapped = ZhKey(k: k) }
                }
                .environment(\.noToneGlow, true)      // (letters: no glow here, it got slow)
                .ffFont(.body)
                .foregroundStyle(i == 1 ? T.greenInk : T.purpleInk)
            } else {
                Text(a).ffFont(.body).toneGlow().textSelection(.enabled)
                    .foregroundStyle(i == 1 ? T.greenInk : T.purpleInk)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    /// the reading word by word (a space before each word that follows another; only a line's first word with a
    /// capital letter in 拼音)
    private func romPieces(_ w: [(piece: ZhPiece, key: String?, newLine: Bool)], _ mode: Int)
        -> [(text: AttributedString, tap: Bool, newLine: Bool, mark: Int)] {
        var out: [(text: AttributedString, tap: Bool, newLine: Bool, mark: Int)] = []
        var prevWord = false
        for (j, x) in w.enumerated() {
            let lineStart = j == 0 || x.newLine
            if lineStart { prevWord = false }
            var a = dict.sentence([x.piece], mode, store.zhPlace)
            let isWord = dict.pieceSyl(x.piece, store.zhPlace) != nil
            if isWord, mode == 0, dict.lang == 1, !lineStart, let f = a.characters.firstIndex(where: { $0.isLetter }) {
                let ch = a.characters[f]
                a.characters.replaceSubrange(f...f, with: String(ch).lowercased())
            }
            if isWord && prevWord { a = AttributedString(" ") + a }
            prevWord = isWord
            out.append((a, x.key != nil, x.newLine, 0))
        }
        return out
    }

    /// (the 歌詞 page: the line the word is in, kept with it if it's saved or added to 不熟 from here)
    private func remember(_ k: String, _ j: Int, _ w: [(piece: ZhPiece, key: String?, newLine: Bool)]) {
        guard lyrics else { return }
        var a = j
        while a > 0 && !w[a].newLine { a -= 1 }
        var b = j + 1
        while b < w.count && !w[b].newLine { b += 1 }
        let line = w[a..<b].map { $0.piece.text.joined() }.joined().trimmingCharacters(in: .whitespaces)
        store.lyricContext = (k, line)
    }

    /// the converted text's words (line breaks start a new line), with the entry each one opens
    private var words: [(piece: ZhPiece, key: String?, newLine: Bool)] {
        var out: [(piece: ZhPiece, key: String?, newLine: Bool)] = []
        var newLine = false
        for p in pieces {
            if p.text == ["\n"] { newLine = true; continue }
            out.append((p, p.tw != nil ? dict.entry(for: p)?.k : nil, newLine))
            newLine = false
        }
        return out
    }

    private func plain(_ i: Int) -> String {
        switch i {
        case 0: return text
        case 1: return String(dict.sentence(pieces, 0, store.zhPlace, colours: 0).characters)
        default: return String(dict.sentence(pieces, 1, store.zhPlace, colours: 0).characters)
        }
    }

    private func copy(_ i: Int) { UIPasteboard.general.string = plain(i); flash(i) }
    private func copy(all: Bool) { UIPasteboard.general.string = [plain(0), plain(1), plain(2)].joined(separator: "\n"); flash(9) }
    private func flash(_ m: Int) {
        copied = m
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); if copied == m { copied = nil } }
    }

    private func run() {
        task?.cancel()
        let t = text, d = dict
        task = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            // line by line, so line breaks stay
            let r = await Task.detached(priority: .userInitiated) { () -> [ZhPiece] in
                var out: [ZhPiece] = []
                for (i, line) in t.components(separatedBy: "\n").enumerated() {
                    if i > 0 { out.append(ZhPiece(text: ["\n"], tw: nil, lu: nil)) }
                    out += d.convertPieces(line)
                }
                return out
            }.value
            guard !Task.isCancelled else { return }
            pieces = r
        }
    }
}


// MARK: - 單詞比較 (華語)

/// two 華語 words one above the other (side by side on a wide screen)
struct ZhComparePage: View {
    let dict: ZhDict
    @Environment(\.horizontalSizeClass) private var size
    var body: some View {
        Group {
            if size == .regular {
                HStack(spacing: 0) {
                    ZhComparePane(dict: dict, slot: "A")
                    Rectangle().fill(T.fnEdge).frame(width: 1)
                    ZhComparePane(dict: dict, slot: "B")
                }
            } else {
                VStack(spacing: 0) {
                    ZhComparePane(dict: dict, slot: "A")
                    Rectangle().fill(T.fnEdge).frame(height: 1)
                    ZhComparePane(dict: dict, slot: "B")
                }
            }
        }
        .appBackground()
        .navigationTitle(tr("單詞比較"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

/// one side: search, pick a word, read its entry (remembered for next time)
struct ZhComparePane: View {
    let dict: ZhDict
    let slot: String
    @EnvironmentObject var store: Store
    @AppStorage private var key: String
    @State private var query = ""
    @State private var found: [Int] = []
    @State private var task: Task<Void, Never>?

    init(dict: ZhDict, slot: String) {
        self.dict = dict; self.slot = slot
        _key = AppStorage(wrappedValue: "", "zhCompare" + slot)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(T.muted)
                TextField(slot == "A" ? trs("第一個詞") : trs("第二個詞"), text: $query)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: query) { search() }
                    .clearButton($query)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.8)))
            .padding(10)
            if !query.isEmpty {
                List(found, id: \.self) { i in
                    Button { key = dict.entries[i].k; query = "" } label: { ZhWordRow(dict: dict, entry: dict.entries[i]) }
                        .listRowBackground(T.fn.opacity(0.7))
                }
                .scrollContentBackground(.hidden)
            } else if !key.isEmpty, let e = dict.entry(key) {
                ScrollView { ZhEntryBody(dict: dict, entry: e).dictFontArea().padding(.horizontal).padding(.bottom) }
            } else {
                Text(tr("查一個詞，選它。")).foregroundStyle(T.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search() {
        task?.cancel()
        let q = query, d = dict, pl = store.zhPlace
        guard !q.isEmpty else { found = []; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { d.search(q, place: pl) }.value
            guard !Task.isCancelled else { return }
            var out: [Int] = []
            for i in r.tones + r.words + r.starts + r.english + r.contains + r.defs where !out.contains(i) {
                out.append(i)
                if out.count >= 40 { break }
            }
            found = out
        }
    }
}

/// 客語: the word in each of the six accents (the one chosen marked); an accent that says it with another word
/// shows that word
struct HakAccentRows: View {
    let dict: ZhDict
    let entry: ZhEntry
    @EnvironmentObject var store: Store
    var body: some View {
        // every accent side by side (the name, its reading under it), wrapping onto more lines when needed
        if let acc = entry.acc {
            FlowLayout(spacing: 10) {
                ForEach(0..<Lang.hakAccents.count, id: \.self) { a in
                    let mine = a == dict.accent
                    VStack(alignment: .center, spacing: 2) {
                        Chip(text: trs(Lang.hakAccents[a]), fill: mine ? T.hakFill : T.fn, edge: mine ? T.hakEdge : T.fnEdge, ink: mine ? T.hakInk : T.muted)
                        if a < acc.count, let syl = acc[a] {
                            Text(dict.reading(syl, store.zhRom)).latFont(15).foregroundStyle(T.greenInk)
                        } else if mine && entry.hakGuess {
                            // (put together from how this accent reads each character)
                            Text(dict.reading(entry.tw, store.zhRom)).latFont(15).foregroundStyle(T.greenInk)
                            Text(tr("推測")).ffFont(.caption2).foregroundStyle(T.muted)
                        } else if let w = entry.otherWords[a] {
                            Text(tr("說「\(w)」")).ffFont(.caption).foregroundStyle(T.glyph)
                        } else {
                            Text(tr("（沒有收）")).ffFont(.caption).foregroundStyle(T.muted)
                        }
                    }
                }
            }
        }
    }
}

/// English meanings found by a search: the ones with the searched word(s) first ("to park": "to park (a car)" before
/// "to anchor (a vessel)"); the rest keep their order
enum EnglishMatch {
    static func first(_ list: [String], _ q0: String) -> [String] {
        var q = q0.enFold.trimmingCharacters(in: .whitespaces)
        if q.hasPrefix("to ") { q = String(q.dropFirst(3)) }
        guard !q.isEmpty else { return list }
        let pat = #"(^|[^a-z])"# + NSRegularExpression.escapedPattern(for: q) + #"($|[^a-z])"#
        let hit = list.filter { $0.enFold.range(of: pat, options: .regularExpression) != nil }
        return hit + list.filter { !hit.contains($0) }
    }

    static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for x in list where !x.isEmpty && seen.insert(x.lowercased()).inserted { out.append(x) }
        return out
    }
}

extension String {
    /// English for searching: small letters, and the curly apostrophe the keyboard types ("one’s") the same as the
    /// straight one in the dictionaries ("one's")
    var enFold: String {
        lowercased().replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{02BC}", with: "'")
    }
}

/// the words of a `spec`: 國語用詞 (1, only 臺灣 uses them), 普通話用詞 (2, only 大陸), 四川話的詞 (3, 四川話's own
/// words from Wiktionary, the ones with a reading from Wiktionary first)
struct ZhSpecWordsPage: View {
    let dict: ZhDict
    let spec: Int
    @EnvironmentObject var store: Store
    @State private var query = ""
    private var title: String { spec == 1 ? tr("國語用詞") : spec == 2 ? tr("普通話用詞") : tr("四川話的詞") }
    var body: some View {
        let all = dict.specWords(spec)
        let list = query.isEmpty ? all : all.filter { i in
            let e = dict.entries[i]
            return e.h.contains(query) || (e.alt?.contains(query) ?? false) || e.eq.contains { $0.contains(query) }
                || e.senses.contains { $0.text.contains(query) } || (e.en?.localizedCaseInsensitiveContains(query) ?? false)
        }
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.muted)
                    TextField(spec == ZhDict.sichuanSpec ? tr("漢字、華語的詞或英文") : tr("漢字、意思或英文"), text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .clearButton($query)
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section(tr("\(list.count) 個詞")) {
                ForEach(list, id: \.self) { i in
                    NavigationLink(value: ZhKey(k: dict.entries[i].k)) { ZhWordRow(dict: dict, entry: dict.entries[i]) }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}


/// 國語, 普通話 and 四川話, each with its reading; the 讀音 chosen in blue, the others grey (the way 客語's accents are
/// shown). 四川話: where the reading is from when it's not Wiktionary's (pink: put together; yellow: predicted;
/// orange: no 四川話 reading, so 普通話's)
struct ZhPlaceRows: View {
    let dict: ZhDict
    let entry: ZhEntry
    @EnvironmentObject var store: Store
    var body: some View {
        // side by side (the name, its reading under it)
        FlowLayout(spacing: 10) {
            ForEach(0..<Lang.zhPlaceNames.count, id: \.self) { i in
                let mine = i == store.zhPlace
                let s: [String] = i == 0 ? entry.tw : (i == 1 ? (entry.lu ?? entry.tw) : (entry.sc ?? entry.lu ?? entry.tw))
                VStack(alignment: .center, spacing: 2) {
                    HStack(spacing: 3) {
                        Chip(text: trs(Lang.zhPlaceNames[i]), fill: mine ? T.blue : T.fn, edge: mine ? T.blueEdge : T.fnEdge, ink: mine ? T.blueInk : T.muted)
                        if i == 2, let k = SichuanChip.kind(entry.sc == nil ? nil : entry.scKind) { SichuanChip(kind: k, small: true) }
                    }
                    Text(dict.reading(s, store.zhRom)).latFont(15).foregroundStyle(T.greenInk)
                }
            }
        }
    }
}

/// the small boxes of an entry, by colour: blue = levels (HSK, TOCFL, 常用詞), green = where it's said, yellow = 詞類
/// and 六書, pink = 分類, grey = the rest
enum InfoChip {
    static func blue(_ t: String) -> Chip { Chip(text: t, fill: T.blue, edge: T.blueEdge, ink: T.blueInk) }
    static func green(_ t: String) -> Chip { Chip(text: t, fill: T.green, edge: T.greenEdge, ink: T.greenInk) }
    static func yellow(_ t: String) -> Chip { Chip(text: t, fill: T.olive, edge: T.oliveEdge, ink: T.oliveInk) }
    static func pink(_ t: String) -> Chip { Chip(text: t, fill: T.pink, edge: T.pinkEdge, ink: T.pinkInk) }
    static func grey(_ t: String) -> Chip { Chip(text: t, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
}
