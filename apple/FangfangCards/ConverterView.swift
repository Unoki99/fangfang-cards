import SwiftUI
import UIKit

/// a dictionary word to open (key = "漢字\tcodes")
struct DictKey: Hashable, Identifiable {
    let k: String
    var id: String { k }
}

/// a category (分類) to list
struct CatRef: Hashable { let i: Int }

/// 查詞 → 更多: one of the result pages. Opened the same way as a word (a value), so going on to a word
/// from it and back again keeps the pages in the right order.
enum MoreRoute: Hashable {
    case keys(title: String, keys: [String])
    case sentences(title: String, hits: [Dict.SentenceHit])
    case places(groups: [PlaceGroup])
    case wordClass(String)
    case compare
    case classes
    case japanese
    case placeWords(Int)
}
struct PlaceRow: Hashable { let han: String; let codes: String; let places: [Int] }
struct PlaceGroup: Hashable { let zh: String; let rows: [PlaceRow] }

extension View {
    /// where dictionary words and categories open
    func dictDestinations(_ d: Dict) -> some View {
        navigationDestination(for: DictKey.self) { DictEntryView(dict: d, key: $0.k) }
            .navigationDestination(for: MoreRoute.self) { MorePage(dict: d, route: $0) }
            .navigationDestination(for: CatRef.self) { CategoryWordsView(dict: d, cat: $0.i) }
    }
}

extension View {
    /// a word tapped in an example sentence: on iPhone/iPad a sheet from the bottom (like in 轉換),
    /// on the Mac a page (sheets there have a fixed size)
    @ViewBuilder func wordOpener(_ d: Dict, _ item: Binding<DictKey?>) -> some View {
        #if targetEnvironment(macCatalyst)
        navigationDestination(item: item) { DictEntryView(dict: d, key: $0.k) }
        #else
        sheet(item: item) { WordEntrySheet(dict: d, key: $0.k).environmentObject(Store.shared) }
        #endif
    }
}

/// a dictionary entry in a sheet from the bottom (half height, pull up for more)
struct WordEntrySheet: View {
    let dict: Dict
    let key: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DictEntryView(dict: dict, key: key)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
                .dictDestinations(dict)
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }
}

/// shows its content once the dictionary is loaded
struct DictGate<Content: View>: View {
    @EnvironmentObject var store: Store
    @ViewBuilder let content: (Dict) -> Content
    var body: some View {
        Group {
            if let d = store.dict {
                content(d).dictDestinations(d)
            } else if let e = store.dictError {
                Text(e).foregroundStyle(T.muted).padding()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(tr("載入字典…")).ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .onAppear { store.loadDict() }
    }
}

// MARK: - 轉換 tab

/// 轉換: 漢字 ⇄ 皓羅 ⇄ 方音, all native and offline (only audio uses the network).
struct ConverterView: View {
    @EnvironmentObject var store: Store
    /// 0 轉換, 1 讀音 (a word in 台語, 華語 and 粵語 side by side), 2 歌詞 (the radio's song)
    @AppStorage("convertTab") private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(tr("轉換")).tag(0)
                Text(tr("讀音")).tag(1)
                Text(tr("歌詞")).tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
            Group {
                if tab == 1 {
                    ReadingsPane()
                } else if tab == 2 {
                    LyricsWindow(inConvert: true)
                } else if store.isSv {
                    ZhGate { z in SvConvertPane(dict: z) }
                } else if store.isZh {
                    ZhGate { z in ZhConvertPane(dict: z) }
                } else {
                    DictGate { d in ConvertPane(dict: d) }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .appBackground()
    }
}

// MARK: - 詞典 tab

/// 詞典: look up 華語 / 台語 words, browse categories, saved words.
struct DictionaryView: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if store.isZh {
            ZhGate { z in ZhDictTabs(dict: z) }
        } else {
            DictGate { d in DictTabs(dict: d) }
        }
    }
}

/// 查詞 / 分類 / 收藏 (its own view, so switching always redraws the page below)
struct DictTabs: View {
    let dict: Dict
    @AppStorage("dictTab") private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text(tr("查詞")).tag(0)
                Text(tr("各地讀音")).tag(3)
                Text(tr("分類")).tag(1)
                Text(tr("收藏")).tag(2)
                Text(tr("自訂")).tag(4)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
            Group {
                switch tab {
                case 1: CategoryPane(dict: dict)
                case 2: SavedPane(dict: dict)
                case 3: PronunciationPane(dict: dict)
                case 4: OwnPane(dict: dict)
                default:
                    // (iPad, Mac: the results on the left, the word on the right)
                    EntrySplit {
                        LookupPane(dict: dict)
                    } detail: { p in
                        if let k = p.base as? DictKey {
                            ScrollView { DictEntryBody(dict: dict, key: k.k).dictFontArea().padding().frame(maxWidth: 760).frame(maxWidth: .infinity) }
                        }
                    }
                }
            }
            .id(tab)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - conversion

@MainActor
final class ConvModel: ObservableObject {
    @Published var text: String { didSet { schedule() } }
    @Published private(set) var result = ConvResult()
    @Published var latinMode: LatinMode {
        didSet {
            engine?.latinMode = latinMode
            UserDefaults.standard.set(latinMode.rawValue, forKey: "ff-latin")
            run()
        }
    }
    private(set) var engine: ConvertEngine?
    private var task: Task<Void, Never>?
    /// where the text is kept (轉換's own, or the 歌詞 window's)
    let key: String

    init(key: String = "ff-text") {
        self.key = key
        text = UserDefaults.standard.string(forKey: key) ?? ""
        latinMode = LatinMode(rawValue: UserDefaults.standard.string(forKey: "ff-latin") ?? "") ?? .auto
    }

    func attach(_ d: Dict) {
        guard engine == nil else { return }
        let e = ConvertEngine(dict: d)
        e.latinMode = latinMode
        engine = e
        run()
    }

    private func schedule() {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.run()
        }
    }

    func run() {
        guard let engine else { return }
        result = engine.convert(text)
        UserDefaults.standard.set(text, forKey: key)
    }

    func choose(_ item: Int, _ opt: Int) {
        guard result.items.indices.contains(item) else { return }
        result.items[item].sel = opt
        result.items[item].likely = nil          // your choice: no longer a guess
        engine?.remember(result.items, item)
    }
}

struct ConvertPane: View {
    let dict: Dict
    /// the 歌詞 window: no typing, only the 漢字 (left) and the chosen spelling (right)
    let lyrics: Bool
    @EnvironmentObject var store: Store
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    @StateObject private var model: ConvModel

    init(dict: Dict, textKey: String = "ff-text", lyrics: Bool = false) {
        self.dict = dict
        self.lyrics = lyrics
        _model = StateObject(wrappedValue: ConvModel(key: textKey))
    }
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @FocusState private var focused: Bool
    @State private var openItem: ConvSelection?
    @State private var copied: Int?
    @State private var copySheet = false

    private var hasOutput: Bool { model.result.items.contains(where: { $0.isWord }) }

    var body: some View {
        GeometryReader { geo in
            if lyrics {
                ScrollView {
                    if hasOutput {
                        LyricsColumns {
                            panel(0, trs("漢字"))
                            // (letters: no glow here, it got slow)
                            panel(1, trs(ROM_NAMES[min(max(rom, 0), 2)])).environment(\.noToneGlow, true)
                        }
                        .padding()
                        .frame(maxWidth: 1100)
                        .frame(maxWidth: .infinity)
                    }
                }
            } else if geo.size.width >= 820 {
                // wide (iPad landscape, Mac): text on the left, the three scripts on the right
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            input
                            if model.result.anyLatin { latinPicker }
                            if hasOutput { actions } else { help }
                        }
                        .padding()
                    }
                    .frame(width: min(440, geo.size.width * 0.42))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if hasOutput { panels } else {
                                Text(tr("轉換的結果會出現在這裡。")).foregroundStyle(T.muted).padding(.top, 40)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .frame(maxWidth: 820)
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        input
                        if model.result.anyLatin { latinPicker }
                        if hasOutput { panels; actions } else { help }
                    }
                    .padding()
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { model.attach(dict) }
        // (the 歌詞 window: a new song's lyrics)
        .onReceive(NotificationCenter.default.publisher(for: LyricsBridge.changed)) { _ in
            let t = UserDefaults.standard.string(forKey: model.key) ?? ""
            if t != model.text { model.text = t }
        }
        #if targetEnvironment(macCatalyst)
        .navigationDestination(item: $openItem) { sel in
            WordSheet(dict: dict, model: model, index: sel.index, inSheet: false)
        }
        #else
        .sheet(item: $openItem) { sel in
            WordSheet(dict: dict, model: model, index: sel.index)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(tr("完成")) { focused = false }
            }
        }
    }

    @ViewBuilder private var panels: some View {
        panel(0, trs("漢字"))
        panel(1, trs(ROM_NAMES[min(max(rom, 0), 2)]))
        panel(2, trs("方音"))
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 10) {
            Button { copy(all: true) } label: {
                Label(copied == 9 ? trs("已複製") : trs("全部複製"), systemImage: copied == 9 ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .softButton()
            Button { copySheet = true } label: {
                Label(tr("選擇複製…"), systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .softButton()
        }
        .sheet(isPresented: $copySheet) {
            CopyOptionsSheet(texts: [plain(0), plain(1), plain(2)],
                             names: [trs("漢字"), trs(ROM_NAMES[min(max(rom, 0), 2)]), trs("方音")])
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        let keys = textKeys
        if !keys.isEmpty {
            let newOnes = keys.filter { store.cardStatus($0) == 0 }
            Button { withAnimation(.snappy) { store.addUnknown(keys) } } label: {
                Label(newOnes.isEmpty ? trs("這段的新詞都在卡片裡了") : tr("這段的新詞加到「不熟」（\(newOnes.count)）"),
                      systemImage: newOnes.isEmpty ? "star.fill" : "star")
                    .frame(maxWidth: .infinity)
            }
            .softButton()
            .disabled(newOnes.isEmpty)
            let all = keys.allSatisfy { store.isSaved($0) }
            Button { withAnimation(.snappy) { store.saveAll(keys) } } label: {
                Label(all ? trs("這段的詞都收藏了") : tr("收藏這段所有的詞（\(keys.filter { !store.isSaved($0) }.count)）"),
                      systemImage: all ? "bookmark.fill" : "bookmark")
                    .frame(maxWidth: .infinity)
            }
            .softButton()
            .disabled(all)
        }
        Text(tr("點詞可以看意思、換讀音、收藏、加到「不熟」。詞下面有彩色小星星 = 已收藏或在「不熟」，藍色星星 = 收藏了這個詞的某個意思。橘色 = 字典裡找不到，或讀音不太確定（猜對的機會約 80% 以下），點一下可以確認。"))
            .ffFont(.caption).foregroundStyle(T.muted)
    }

    private var input: some View {
        ZStack(alignment: .topLeading) {
            if model.text.isEmpty {
                Text(tr("輸入或貼上漢字、皓羅、方音、台羅、白話字…"))
                    .foregroundStyle(T.muted)
                    .padding(.horizontal, 5).padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $model.text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .scaledFont(18)
                .frame(minHeight: 110, maxHeight: 220)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(8)
        .glassSurface(RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Button {
                    if let s = UIPasteboard.general.string { model.text = s }
                } label: { Image(systemName: "doc.on.clipboard") }
                if !model.text.isEmpty {
                    Button { model.text = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                }
            }
            .scaledFont(18)
            .foregroundStyle(T.muted)
            .padding(10)
        }
    }

    private var latinPicker: some View {
        let autoName = ["lat": "皓羅", "tl": "台羅", "poj": "白話字"][model.result.autoLatin] ?? "皓羅"
        return VStack(alignment: .leading, spacing: 4) {
            Text(tr("羅馬字當作")).ffFont(.caption).foregroundStyle(T.muted)
            Picker(tr("羅馬字"), selection: $model.latinMode) {
                Text(tr("自動（\(autoName)）")).tag(LatinMode.auto)
                Text(tr("皓羅")).tag(LatinMode.lat)
                Text(tr("台羅")).tag(LatinMode.tl)
                Text(tr("白話字")).tag(LatinMode.poj)
            }
            .pickerStyle(.segmented)
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("例：")).ffFont(.footnote, .bold).foregroundStyle(T.muted)
            ForEach(["我欲去學校讀冊。", "Guá beh khì ha̍k-hāu tha̍k-tsheh.", "ㆣㄨㄚˋ ㄅㆤㆷ ㄎㄧˋ"], id: \.self) { s in
                Button { model.text = s } label: {
                    Group { if s.first.map({ $0.isASCII }) == true { Text(s).latFont(16) } else { Text(s).ffFont(.body) } }
                        .foregroundStyle(T.glyph)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .softButton()
            }
        }
    }

    // MARK: output

    private func panel(_ mode: Int, _ title: String) -> some View {
        let pieces = model.engine?.pieces(model.result.items, mode: mode, rom: min(max(rom, 0), 2), place: place) ?? []
        let ink = [T.glyph, T.greenInk, T.purpleInk][mode]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).ffFont(.caption, .bold).foregroundStyle(T.muted)
                Spacer()
                TaigiSpeakButton(text: speechText)
                Button { copy(mode) } label: {
                    Image(systemName: copied == mode ? "checkmark" : "doc.on.doc").ffFont(.footnote)
                }
                .foregroundStyle(T.muted)
            }
            let sp = swellPieces(pieces, ink: ink, mode: mode)
            SwellWords(pieces: sp.pieces, lineSpacing: 4, vPad: 3) { n in
                if let i = sp.items[n], i >= 0 {
                    focused = false
                    openItem = ConvSelection(index: i)
                }
            }
            .foregroundStyle(ink)
            .scaledFont(mode == 0 ? 22 : 20, on: mode != 1)
            .latFont(19)   // 羅馬字 box (the other boxes set their own size just above)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .glassSurface(RoundedRectangle(cornerRadius: 18))
    }

    /// 聲調顏色 in 轉換: the tone of every syllable of every word, working through the whole text
    /// (punctuation and line ends close a tone group). item index -> (tokens, tones)
    private func itemTones() -> [Int: (tokens: [String], tones: [Int])] {
        let items = model.result.items
        var units: [ToneUnit] = []
        var ranges: [Int: (tokens: [String], from: Int, to: Int)] = [:]
        var prevKey: String? = nil
        func endPhrase() { if !units.isEmpty { units[units.count - 1].phraseEnd = true } }
        // the word right after each word (not across punctuation or a line end): to tell a 量詞 (這款種)
        var nextKeyOf: [Int: String] = [:]
        var upcoming: String? = nil
        for i in items.indices.reversed() {
            let it = items[i]
            if it.space { continue }
            if it.newline || it.raw != nil || it.current.codes == nil { upcoming = nil; continue }
            if let up = upcoming { nextKeyOf[i] = up }
            upcoming = dict.keyOf(it.current)
        }
        for (i, it) in items.enumerated() {
            if it.newline { endPhrase(); prevKey = nil; continue }
            if it.space { continue }
            if let raw = it.raw {
                if ConvertEngine.isPunct(raw) && !ConvertEngine.openers.contains(raw) { endPhrase() }
                prevKey = nil
                continue
            }
            guard let codes = it.current.codes else { endPhrase(); prevKey = nil; continue }
            let key = dict.keyOf(it.current)
            let tokens: [String]
            if let key, dict.baseKeys.contains(key), it.current.parent == nil { tokens = dict.tokensFor(key, place) }
            else { tokens = (it.current.tokens ?? codes.joined(separator: " ")).split(separator: " ").map(String.init) }
            let u = dict.toneUnits(tokens: tokens, key: key, after: prevKey, before: nextKeyOf[i])
            prevKey = key
            // a word that starts with "--" (--ah): the syllable before it keeps its tone
            if tokens.first == "--", !units.isEmpty { units[units.count - 1].beforeLight = true }
            // a word that starts with 仔: 仔-sandhi on the syllable before it
            if it.current.han?.first == "仔", !units.isEmpty { units[units.count - 1].beforeA = true }
            ranges[i] = (tokens, units.count, units.count + u.count)
            units += u
        }
        endPhrase()
        let tones = dict.realizedTones(units, place)
        return ranges.mapValues { (tokens: $0.tokens, tones: Array(tones[$0.from..<$0.to])) }
    }

    /// the output piece by piece (a piece's leading space included), ready to show; tappable words carry a link
    private func attributedPieces(_ pieces: [(text: String, item: Int?)], ink: Color, mode: Int) -> [AttributedString] {
        if toneSys != 0 { return toneAttributed(pieces, ink: ink, mode: mode) }
        var all: [AttributedString] = []
        for p in pieces {
            var out = AttributedString()
            defer { all.append(out) }
            var t = p.text
            if t.hasPrefix(" ") { out += AttributedString(" "); t.removeFirst() }
            var a = AttributedString(t)
            if let i = p.item {
                if i < 0 {
                    a.swiftUI.foregroundColor = .orange
                } else {
                    let it = model.result.items[i]
                    if it.current.codes == nil {
                        a.swiftUI.foregroundColor = .orange
                    } else {
                        var colored = false
                        if it.unsure { colored = true }                     // shaky guess: the whole word orange
                        else if mode != 0, let e = model.engine {
                            let ps = e.wordPieces(it.current, mode: mode, rom: min(max(rom, 0), 2), place: place)
                            if ps.contains(where: { $0.guessed }) { a = guessColored(ps, ink: ink); colored = true }
                        }
                        // your own word (自訂): purple
                        if !it.unsure, let k = dict.keyOf(it.current), dict.isUser(k) {
                            a.swiftUI.foregroundColor = T.ownInk; colored = true
                        }
                        a.link = URL(string: "ff://w/\(i)")
                        if it.unsure { a.swiftUI.foregroundColor = .orange }
                        else if !colored { a.swiftUI.foregroundColor = ink }
                        if it.opts.count > 1 { a.swiftUI.underlineStyle = Text.LineStyle(pattern: .dot, color: (it.unsure ? Color.orange : ink).opacity(0.6)) }
                    }
                }
            }
            out += a
        }
        return all
    }

    /// the output in tone colours (words still tappable, choices underlined, saved words shaded)
    private func toneAttributed(_ pieces: [(text: String, item: Int?)], ink: Color, mode: Int) -> [AttributedString] {
        let tones = itemTones()
        var all: [AttributedString] = []
        for p in pieces {
            var out = AttributedString()
            defer { all.append(out) }
            var t = p.text
            if t.hasPrefix(" ") { out += AttributedString(" "); t.removeFirst() }
            guard let i = p.item, i >= 0, let tt = tones[i] else {
                var a = AttributedString(t)
                if p.item != nil { a.swiftUI.foregroundColor = .orange }      // not in the dictionary
                out += a; continue
            }
            let it = model.result.items[i]
            var a: AttributedString
            if mode == 0 { a = dict.hanToneText(t, tones: tt.tones, system: toneSys, base: ink) }
            else { a = dict.toneText(tt.tokens, mode == 2 ? 3 : rom, place, tones: tt.tones, system: toneSys) }
            a.link = URL(string: "ff://w/\(i)")
            if it.opts.count > 1 { a.swiftUI.underlineStyle = Text.LineStyle(pattern: .dot, color: (it.unsure ? Color.orange : ink).opacity(0.6)) }
            out += a
        }
        return all
    }

    /// the pieces for SwellWords: a word's link becomes its button (the link itself is taken off, so the
    /// word keeps its colours); a space in front of a word moves to the end of the piece before it, so a
    /// line never starts with a space; "\n" starts a new line
    private func swellPieces(_ pieces: [(text: String, item: Int?)], ink: Color, mode: Int)
        -> (pieces: [(text: AttributedString, tap: Bool, newLine: Bool, mark: Int)], items: [Int?]) {
        let texts = attributedPieces(pieces, ink: ink, mode: mode)
        let savedSenseKeys = store.savedSenseKeys
        var out: [(text: AttributedString, tap: Bool, newLine: Bool, mark: Int)] = [], items: [Int?] = []
        var newLine = false
        for (p, a0) in zip(pieces, texts) {
            if p.text == "\n" { if newLine { out.append((AttributedString(" "), false, true, 0)); items.append(nil) }; newLine = true; continue }
            var a = a0
            var tap = false
            for r in a.runs where r.link != nil { tap = true; a[r.range].link = nil }
            if a.characters.first == " " {
                a.removeSubrange(a.startIndex..<a.index(afterCharacter: a.startIndex))
                if !newLine, !out.isEmpty { out[out.count - 1].text += AttributedString(" ") }
            }
            // a little star under the word: in the tone colours when the word is saved or in 不熟,
            // blue when only some of its meanings are saved
            var mark = 0
            if let i = p.item, i >= 0, model.result.items.indices.contains(i), let k = dict.keyOf(model.result.items[i].current) {
                mark = store.isSaved(k) || store.cardStatus(k) == 2 ? 1 : (savedSenseKeys.contains(k) ? 2 : 0)
            }
            out.append((a, tap, newLine, mark)); items.append(p.item)
            newLine = false
        }
        return (out, items)
    }

    /// dictionary words in the converted text, in order, once each
    private var textKeys: [String] {
        var seen = Set<String>(), out: [String] = []
        for it in model.result.items where it.isWord && it.current.codes != nil {
            if let k = dict.keyOf(it.current), dict.raw.defs.m[k] != nil || dict.baseKeys.contains(k), seen.insert(k).inserted { out.append(k) }
        }
        return out
    }

    /// the text in 台羅 (通行 readings), for reading aloud, whichever box the button is on.
    /// Never any 漢字: a word the dictionary doesn't know (still in 漢字) is left out.
    private var speechText: String {
        let t = (model.engine?.pieces(model.result.items, mode: 1, rom: 1, place: -1) ?? []).map { $0.text }.joined()
        let noHan = String(String.UnicodeScalarView(t.unicodeScalars.filter { !ConvertEngine.isHan($0.value) }))
        return noHan.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func plain(_ mode: Int) -> String {
        (model.engine?.pieces(model.result.items, mode: mode, rom: min(max(rom, 0), 2), place: place) ?? []).map { $0.text }.joined()
    }

    private func copy(_ mode: Int) {
        UIPasteboard.general.string = plain(mode)
        flash(mode)
    }
    private func copy(all: Bool) {
        UIPasteboard.general.string = [plain(0), plain(1), plain(2)].joined(separator: "\n")
        flash(9)
    }
    private func flash(_ m: Int) {
        copied = m
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); if copied == m { copied = nil } }
    }
}

struct ConvSelection: Identifiable, Hashable {
    let index: Int
    var id: Int { index }
}

/// a word in the converted text: pick the reading, see its dictionary entry
struct WordSheet: View {
    let dict: Dict
    @ObservedObject var model: ConvModel
    let index: Int
    /// false on the Mac: shown as a page in the 轉換 tab instead of a sheet (sheets there have a fixed size)
    var inSheet = true
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Store.shared
    @State private var addingOwn = false

    var body: some View {
        if inSheet {
            NavigationStack {
                page
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button(tr("完成")) { dismiss() } }
                        ToolbarItem(placement: .topBarLeading) { RomButton() }
                    }
                    .dictDestinations(dict)
            }
        } else {
            page
                .navigationTitle(model.result.items.indices.contains(index) ? (model.result.items[index].current.han ?? "") : "")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        }
    }

    private var page: some View {
            Group {
                if model.result.items.indices.contains(index) {
                    let it = model.result.items[index]
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 14) {
                            if it.opts.count > 1 { options(it) }
                            if let k = dict.keyOf(it.current), dict.baseKeys.contains(k) || dict.raw.defs.m[k] != nil {
                                DictEntryBody(dict: dict, key: k).dictFontArea()
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(model.engine?.wordText(it.current, mode: 0, rom: min(max(rom, 0), 2), place: place) ?? "")
                                        .scaledFont(30, weight: .semibold)
                                    if it.current.codes != nil {
                                        Text(optText(it.current, 1))
                                            .latFont(20).foregroundStyle(T.greenInk)
                                        Text(optText(it.current, 2))
                                            .foregroundStyle(T.purpleInk)
                                    }
                                    if let k = dict.keyOf(it.current), dict.isUser(k) {
                                        HStack(spacing: 8) {
                                            OwnChip()
                                            Text(tr("你自己加的詞（不是教育部辭典的內容）。")).ffFont(.footnote).foregroundStyle(T.muted)
                                        }
                                    } else {
                                        Text(tr("字典裡沒有這個詞。")).ffFont(.footnote).foregroundStyle(T.muted)
                                        if let h = it.current.han, !h.isEmpty {
                                            Button { addingOwn = true } label: {
                                                Label(tr("加到「自訂」"), systemImage: "plus.circle")
                                                    .ffFont(.subheadline, .semibold)
                                                    .foregroundStyle(T.ownInk)
                                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                                    .background(Capsule().fill(T.own))
                                                    .overlay(Capsule().stroke(T.ownEdge, lineWidth: 1.5))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.top, 4)
                                            .sheet(isPresented: $addingOwn) {
                                                AddOwnWordSheet(dict: dict, han0: h,
                                                                reading0: it.current.codes.map { dict.codes($0.joined(separator: " "), 1, -1) } ?? "")
                                                    .environmentObject(store)
                                                    .onDisappear { model.run() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationBarTitleDisplayMode(.inline)
    }

    private func optText(_ o: Opt, _ mode: Int) -> AttributedString {
        guessColored(model.engine?.wordPieces(o, mode: mode, rom: min(max(rom, 0), 2), place: place) ?? [])
    }

    /// a short meaning for a reading choice: its 華語 words, or the start of its definition
    private func gloss(_ o: Opt) -> String? {
        guard let k = dict.keyOf(o) else { return nil }
        let pos = (dict.raw.pos[k] ?? "").split(separator: "|").first.map(String.init) ?? ""
        let text: String?
        if let g = dict.gl[k], !g.isEmpty { text = g.prefix(5).map { $0.t }.joined(separator: "、") }
        else if let t = dict.defText(k) {
            text = t.replacingOccurrences(of: #"\d+\.\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "\n", with: "／")
        } else { text = nil }
        guard let t = text else { return nil }
        return pos.isEmpty ? t : "〔\(pos)〕" + t
    }

    private func options(_ it: ConvItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("選讀音／漢字")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                if let p = it.likely {
                    Text(tr("目前的讀音：猜對的機會約 \(Int((p * 100).rounded()))%"))
                        .ffFont(.caption).foregroundStyle(it.unsure ? Color.orange : T.muted)
                }
            }
            ForEach(Array(it.opts.enumerated()), id: \.offset) { i, o in
                Button {
                    withAnimation(.snappy) { model.choose(index, i) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: i == it.sel ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(i == it.sel ? T.greenInk : T.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(o.han ?? "—").scaledFont(20, weight: .semibold).foregroundStyle(T.glyph)
                                if o.codes != nil {
                                    Text(optText(o, 1))
                                        .latFont(17).foregroundStyle(T.greenInk)
                                    Text(optText(o, 2))
                                        .ffFont(.footnote).foregroundStyle(T.purpleInk)
                                }
                                if let l = o.label { Chip(text: l) }
                                if let k = dict.keyOf(o), let r = dict.raw.reg[k] { RegChip(reg: r) }
                            }
                            if let g = gloss(o) {
                                Text(g).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.75))
                                    .lineLimit(2).multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(RoundedRectangle(cornerRadius: 12).fill(i == it.sel ? T.btn.opacity(0.6) : T.fn.opacity(0.6)))
            }
        }
    }
}

// MARK: - dictionary entry

struct DictEntryView: View {
    let dict: Dict
    let key: String
    var body: some View {
        ScrollView { DictEntryBody(dict: dict, key: key).dictFontArea().padding().frame(maxWidth: 760).frame(maxWidth: .infinity) }
            .appBackground()
            .navigationTitle(Dict.hanOf(key))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

struct DictEntryBody: View {
    let dict: Dict
    let key: String
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    private var han: String { Dict.hanOf(key) }
    @State private var tapped: DictKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            let oth = dict.others(key, place)
            if !oth.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(oth.enumerated()), id: \.offset) { _, o in
                        OtherRow(label: o.label,
                                 rom: dict.codes(o.codes, rom, -1, tokens: o.tokens),
                                 zy: dict.codes(o.codes, 3, o.label == "通行" ? -1 : place, tokens: o.tokens))
                    }
                }
            }
            namesRow
            variantsRow
            otherWordsRow
            if let g = dict.gl[key], !g.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Chip(text: tr("華語"), fill: T.fn, edge: T.fnEdge, ink: T.muted)
                    Text(g.map { $0.t }.joined(separator: "、")).ffFont(.subheadline).foregroundStyle(T.glyph.opacity(0.9))
                }
            }
            // English from Wiktionary (a file of its own: the dictionary's own meanings below stay as they are)
            let en = TwEnglish.meanings(key)
            if !en.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Chip(text: tr("英"), fill: T.fn, edge: T.fnEdge, ink: T.muted)
                    VStack(alignment: .leading, spacing: 3) {
                        ZhEnglishList(items: en, max: 6)
                        Text(tr("英文解釋：維基詞典（CC BY-SA）")).ffFont(.caption2).foregroundStyle(T.muted)
                    }
                }
            }
            ForEach(dict.senses(key), id: \.n) { s in sense(s) }
            FoundSentences(key: key)
            // a single character: 說文解字 (when installed)
            if han.count == 1 { ShuowenBlock(ch: han) }
            if place >= 0, dict.senses(key).contains(where: { s in s.ex.contains { $0.count > 1 && dict.hasGuess($0[1], han: $0[0], place: place) } }) {
                GuessNote()
            }
            let wl = dict.wordLinks(key)
            if !wl.syn.isEmpty || !wl.ant.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    links("近", wl.syn, T.blue, T.blueEdge, T.blueInk)
                    links("反", wl.ant, T.rust, T.rustEdge, T.rustInk)
                }
            }
            if dict.raw.typ[key] == 1 {
                Text(tr("臺華共同詞：台語和華語寫法、意思一樣的詞。")).ffFont(.caption).foregroundStyle(T.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wordOpener(dict, $tapped)
    }

    // MARK: parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                // tap a character to see it on its own (the entry with the same reading)
                TappableHeadword(text: dict.hanText(key, place, base: dict.isUser(key) ? T.ownInk : T.glyph),
                                 targets: charKeys) { tapped = DictKey(k: $0) }
                    .toneGlow()
                // the reading of the 腔口 chosen, in the spelling chosen, right next to the word
                Text(dict.wordText(key, rom, place)).toneGlow().latFont(22).foregroundStyle(T.greenInk).textSelection(.enabled)
                if let au = dict.raw.au[key] { PlayButton(path: Audio.wordPath(au)) }
                Spacer()
                FrequencyBadge(key: key)
            }
            HStack(spacing: 8) {
                saveButton
                star
            }
            Text(dict.wordText(key, 3, place)).toneGlow().scaledFont(19).foregroundStyle(T.purpleInk).textSelection(.enabled).hongimLine()
            // every 腔口's reading, the one chosen in colour (guessed ones marked 推測)
            TwPlaceRows(dict: dict, key: key)
            InputCodesRow(han: han)
            // the boxes, always in the same order of colours: green (白／文／俗, where it's said), yellow (詞類),
            // pink (分類: tap for its words), grey (the rest)
            FlowLayout(spacing: 6) {
                if let r = dict.raw.reg[key] { RegChip(reg: r) }
                ForEach(wordClasses, id: \.self) { p in InfoChip.yellow(p) }
                if han.count == 1, let l = Shuowen.liushu(han) { InfoChip.yellow(tr("六書：") + l) }
                ForEach(categories, id: \.self) { i in
                    NavigationLink(value: CatRef(i: i)) { InfoChip.pink(tr("分類：") + (dict.raw.cats?[i] ?? "")) }
                        .buttonStyle(.plain)
                }
                if dict.subst.contains(key) { Chip(text: tr("替"), fill: T.rust, edge: T.rustEdge, ink: T.rustInk) }
                if let t = dict.raw.typ[key], t > 0, let types = dict.raw.types, t < types.count, t != 1 {
                    InfoChip.grey(types[t])
                }
                if dict.own.contains(key) { InfoChip.grey(tr("方方補")) }
                if dict.isUser(key) { OwnChip() }
            }
        }
    }

    /// the word's 詞類 (each once, in the order of its meanings)
    private var wordClasses: [String] {
        var out: [String] = []
        for s in dict.senses(key) where !s.pos.isEmpty && !out.contains(s.pos) { out.append(s.pos) }
        return out
    }
    /// its 分類 (topics)
    private var categories: [Int] {
        let n = dict.raw.cats?.count ?? 0
        return (dict.raw.cat?[key] ?? []).filter { $0 < n }
    }

    /// for each character of the headword: the single-character entry read the way this word reads it
    private var charKeys: [String?] {
        let codes = Dict.codesOf(key).split(separator: " ").map(String.init)
        var out: [String?] = [], n = 0
        for ch in han {
            let isHan = ch.unicodeScalars.first.map { ConvertEngine.isHan($0.value) } ?? false
            guard isHan else { out.append(nil); continue }
            defer { n += 1 }
            let c = String(ch)
            guard n < codes.count, dict.hanMap[c]?.contains(codes[n]) == true,
                  let k = dict.keyOf(Opt(han: c, codes: [codes[n]])), dict.raw.defs.m[k] != nil, k != key else { out.append(nil); continue }
            out.append(k)
        }
        return out
    }

    private var saveButton: some View {
        let on = store.isSaved(key)
        return Button { withAnimation(.snappy) { store.toggleSaved(key) } } label: {
            Label(on ? trs("已收藏") : trSaveVerb(), systemImage: on ? "bookmark.fill" : "bookmark")
                .ffFont(.subheadline, .semibold)
                .foregroundStyle(on ? T.oliveInk : T.glyph)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(on ? T.olive : T.fn.opacity(0.8)))
                .overlay(Capsule().stroke(on ? T.oliveEdge : T.fnEdge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var star: some View { CardMarkButtons(key: key) }

    @ViewBuilder private var namesRow: some View {
        if han.count == 1 {
            let part: (String, [[String]]?) -> String? = { lab, list in
                guard let list, !list.isEmpty else { return nil }
                return lab + "：" + list.prefix(4).map { dict.codes($0[0], rom, -1) }.joined(separator: "、")
            }
            let s = [part("人名", dict.raw.names[han]), part("姓", dict.raw.sur[han])].compactMap { $0 }.joined(separator: "　")
            if !s.isEmpty { Text(s).latFont(14).foregroundStyle(T.muted) }
        }
    }

    private var placesTable: some View { PlacesTable(dict: dict, key: key) }

    /// 各地講法: with a place chosen, the other words that place uses for the same meaning (做伙 → 鹿港 also 鬥陣)
    @ViewBuilder private var otherWordsRow: some View {
        if place >= 0 {
            let words: [(han: String, codes: String)] = {
                var out: [(han: String, codes: String)] = []
                for e in dict.raw.cmp where e.rows.contains(where: { $0.han == han }) {
                    for r in e.rows where r.place == place && r.han != han && !out.contains(where: { $0.han == r.han }) {
                        out.append((r.han, r.codes))
                    }
                }
                return out
            }()
            if !words.isEmpty, place < dict.raw.places.count {
                HStack(alignment: .top, spacing: 6) {
                    Chip(text: String(dict.raw.places[place].prefix(2)) + "也講", fill: T.twFill, edge: T.twEdge, ink: T.twInk)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                            let k = dict.keyOf(Opt(han: w.han, codes: w.codes.split(separator: " ").map(String.init)))
                            let label = HStack(spacing: 4) {
                                Text(w.han).foregroundStyle(T.glyph)
                                Text(dict.codes(w.codes, rom, place)).latFont(13).foregroundStyle(T.purpleInk)
                            }
                            .ffFont(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(T.twFill.opacity(0.6)))
                            if let k, dict.raw.defs.m[k] != nil {
                                NavigationLink(value: DictKey(k: k)) { label }.buttonStyle(.plain)
                            } else {
                                label
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var categoriesRow: some View {
        let cs = dict.raw.cat?[key] ?? []
        if !cs.isEmpty, let names = dict.raw.cats {
            HStack(alignment: .top, spacing: 6) {
                Chip(text: tr("分類"), fill: T.pink, edge: T.pinkEdge, ink: T.pinkInk)
                FlowLayout(spacing: 6) {
                    ForEach(cs.filter { $0 < names.count }, id: \.self) { i in
                        NavigationLink(value: CatRef(i: i)) {
                            Text(names[i]).ffFont(.subheadline).foregroundStyle(T.pinkInk)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(T.pink.opacity(0.6)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private var variantsRow: some View {
        let vs = dict.raw.variants.filter { $0.value.contains(key) }.map(\.key).sorted()
        if !vs.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Chip(text: tr("異用字"), fill: T.fn, edge: T.fnEdge, ink: T.muted)
                Text(vs.joined(separator: "、")).ffFont(.subheadline).foregroundStyle(T.glyph.opacity(0.9))
            }
        }
    }

    private func sense(_ s: DictSense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(s.n).").ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                if !s.pos.isEmpty { Chip(text: s.pos, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                Text(s.text).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                Spacer(minLength: 4)
                SenseCopyButton(dict: dict, key: key, sense: s.n - 1)
                SenseSaveButton(item: SavedSense(key: key, sense: s.n - 1), store: store)
            }
            senseReadings(s)
            ForEach(Array(s.ex.enumerated()), id: \.offset) { _, e in
                ExampleBlock(dict: dict, ex: e, own: key, onWord: { tapped = DictKey(k: $0) })
                    .padding(.leading, 18)
            }
            if !s.syn.isEmpty || !s.ant.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    links("近", s.syn, T.blue, T.blueEdge, T.blueInk)
                    links("反", s.ant, T.rust, T.rustEdge, T.rustInk)
                }
                .padding(.leading, 18)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    /// places that read this meaning differently from the word (足「非常、很」: 臺南、高雄、金門 tsok)
    @ViewBuilder private func senseReadings(_ s: DictSense) -> some View {
        if let m = dict.raw.sdia?[key]?[String(s.n - 1)], !m.isEmpty {
            // with a place chosen: only that place; otherwise every place, those that say it the same way together
            let shown = place >= 0 ? m.filter { $0.key == String(place) } : m
            let groups = Dictionary(grouping: shown.keys.compactMap { Int($0) }.sorted(), by: { shown[String($0)] ?? "" })
            ForEach(groups.keys.sorted(), id: \.self) { codes in
                let ps = groups[codes] ?? []
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // yellow like 又: another reading, for this meaning
                    Chip(text: ps.map { $0 < dict.raw.places.count ? String(dict.raw.places[$0].prefix(2)) : "" }.joined(separator: "、"))
                    Text(dict.codes(codes, rom, ps.first ?? -1)).latFont(15).foregroundStyle(T.greenInk)
                    Text(dict.codes(codes, 3, ps.first ?? -1)).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                    Text(tr("這個意思")).ffFont(.caption2).foregroundStyle(T.muted)
                }
                .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder private func links(_ name: String, _ keys: [String], _ fill: Color, _ edge: Color, _ ink: Color) -> some View {
        if !keys.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Chip(text: name, fill: fill, edge: edge, ink: ink)
                FlowLayout(spacing: 6) {
                    ForEach(keys, id: \.self) { k in
                        NavigationLink(value: DictKey(k: k)) {
                            HStack(spacing: 4) {
                                Text(Dict.hanOf(k)).foregroundStyle(T.glyph)
                                Text(dict.wordText(k, rom, place)).latFont(13).foregroundStyle(ink)
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
}

/// lays its children out in rows, wrapping like text
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat? = nil          // between rows (default: same as spacing)
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if (x > 0 && x + sz.width > w + 0.5) || (s[FlowBreak.self] && (x > 0 || y > 0 || row > 0)) {
                x = 0; y += row + (lineSpacing ?? spacing); row = 0
            }
            x += sz.width + spacing; row = max(row, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(maxX, w), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // wrap at the same width as when measuring (the bounds can be the narrower measured width), with a
        // little room for rounding: otherwise a row could wrap here but not when measured, and the last
        // line would hang over whatever comes below
        let maxX = bounds.minX + max(bounds.width, proposal.width ?? 0) + 0.5
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if (x > bounds.minX && x + sz.width > maxX) || (s[FlowBreak.self] && (x > bounds.minX || y > bounds.minY || row > 0)) {
                x = bounds.minX; y += row + (lineSpacing ?? spacing); row = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; row = max(row, sz.height)
        }
    }
}

/// in a FlowLayout: this piece starts a new line
struct FlowBreak: LayoutValueKey { static let defaultValue = false }

/// words in a row that wrap like text; the tappable ones swell when pressed or under the pointer, and
/// (iPhone / iPad) holding a finger on them and sliding swells the word under it, letting go opens it
struct SwellWords: View {
    /// each piece: its text, whether it's tappable, whether it starts a new line
    let pieces: [(text: AttributedString, tap: Bool, newLine: Bool, mark: Int)]
    var lineSpacing: CGFloat = 0
    var vPad: CGFloat = 4
    /// room on each side of a word (例句的詞分開一點)
    var hPad: CGFloat = 0
    let onTap: (Int) -> Void
    @State private var frames: [Int: CGRect] = [:]
    /// which word is swollen: kept in its own object, so only the words notice when it changes
    /// (with @State here, every pointer move onto another word redrew the whole sentence)
    @StateObject private var sw = SwellState()
    @State private var space = UUID()

    var body: some View {
        let flow = FlowLayout(spacing: 0, lineSpacing: lineSpacing) {
            ForEach(pieces.indices, id: \.self) { i in
                let p = pieces[i]
                Group {
                    if p.tap {
                        Button { if !sw.scrubbing { onTap(i) } } label: {
                            Text(p.text).toneGlow().padding(.vertical, vPad).padding(.horizontal, hPad).contentShape(Rectangle())
                                .overlay(alignment: .bottom) {
                                    if p.mark == 1 { ToneStar().offset(y: 5) } else if p.mark == 2 { ToneStar(blue: true).offset(y: 5) }
                                }
                        }
                        .buttonStyle(SwellButtonStyle())
                        .swellHot(sw, i)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: WordFramesKey.self, value: [i: g.frame(in: .named(space))])
                        })
                    } else {
                        Text(p.text).toneGlow().padding(.vertical, vPad).padding(.horizontal, hPad)
                    }
                }
                .layoutValue(key: FlowBreak.self, value: p.newLine)
            }
        }
        let tracked = flow
            .coordinateSpace(name: space)
            .onPreferenceChange(WordFramesKey.self) { frames = $0 }
            // one pointer tracker for the whole text, instead of one per word: with one per word, the Mac
            // checked every word on every mouse move (slow, and late to react)
            .onContinuousHover(coordinateSpace: .named(space)) { phase in
                var hit: Int? = nil
                if case .active(let p) = phase { hit = frames.first { $0.value.contains(p) }?.key }
                if hit != sw.hover { sw.hover = hit }
            }
        #if targetEnvironment(macCatalyst)
        return tracked
        #else
        return tracked
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
                    .onChanged { v in
                        guard case .second(true, let drag) = v else { return }
                        if !sw.scrubbing { sw.scrubbing = true; Haptics.start() }
                        guard let drag else { return }
                        let hit = frames.first { $0.value.insetBy(dx: -4, dy: -2).contains(drag.location) }?.key
                        if hit != sw.scrub { sw.scrub = hit; if hit != nil { Haptics.tick() } }
                    }
                    .onEnded { _ in
                        let open = sw.scrub
                        sw.scrub = nil
                        if let open { onTap(open) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [sw] in sw.scrubbing = false }
                    }
            )
        #endif
    }
}

// MARK: - 華語 → 台語

struct LookupResult: Sendable {
    var exact: [String] = []
    var taigi: [String] = []         // words for a 台語 spelling (羅馬字 / 方音)
    var contains: [String] = []      // 台語 words that contain the 漢字
    var pattern: [String] = []       // 台語 words matching a * / ? pattern
    var patternZh: [String] = []     // 台語 words for 華語 words matching it
    var isPattern = false
    var gloss: [String] = []
    var defs: [String] = []
    var places: [(zh: String, rows: [(han: String, codes: String, places: [Int])])] = []
    var tones: [String] = []                  // words with a tone pattern (4-5)
    var toneNote: String? = nil               // why a tone search found nothing (tone 6 in 通行)
    var sentences: [Dict.SentenceHit] = []    // example sentences that use the 台語 word(s) found
    var sentenceWords: [String] = []          // …those words (漢字), for the title
    /// several words searched at once (陰謀論 → 陰謀, 論; or 陰謀 論): each word and what it finds
    var parts: [String] = []
    var partResults: [LookupResult] = []
    /// words whose English (Wiktionary) has the word: added after the rest, which stay as they are
    var english: [String] = []
    var empty: Bool { english.isEmpty && parts.isEmpty && tones.isEmpty && taigi.isEmpty && contains.isEmpty && pattern.isEmpty && patternZh.isEmpty && exact.isEmpty && gloss.isEmpty && defs.isEmpty && places.isEmpty }
}

enum Lookup {
    /// * = one or more characters, ? = exactly one: 人* (starts with 人), *人 (ends with 人), *人* (人 in the middle), 一?一? …
    static func wildcard(_ d: Dict, _ q: String) -> LookupResult {
        var r = LookupResult()
        r.isPattern = true
        var pat = "^"
        for ch in q {
            switch ch {
            case "*", "＊": pat += ".+"
            case "?", "？": pat += "."
            default: pat += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        pat += "$"
        guard let re = try? NSRegularExpression(pattern: pat) else { return r }
        func hit(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        func rank(_ k: String) -> (Int, Double) { (Dict.hanOf(k).count, -d.score(Dict.hanOf(k), Dict.codesOf(k))) }
        // 台語 words
        var keys: [String] = []
        for (h, cs) in d.hanMap where hit(h) {
            for c in cs {
                let k = h + "\t" + c
                if d.baseKeys.contains(k) || d.isUser(k) { keys.append(k) }
            }
        }
        r.pattern = Array(keys.sorted { rank($0) < rank($1) }.prefix(300))
        // 華語 words that match → their 台語 words
        let seen = Set(r.pattern)
        var zh: [String] = []
        for (t, ks) in d.termIndex where hit(t) { zh += ks.filter { !seen.contains($0) } }
        r.patternZh = Array(Set(zh).sorted { rank($0) < rank($1) }.prefix(100))
        return r
    }

    /// words for a 台語 spelling: 皓羅, 台羅, 白話字 (with or without tones; syllables split by space or -) or 方音
    static func taigi(_ d: Dict, _ q: String) -> [String] {
        var keys: [String] = [], seen = Set<String>()
        func add(_ h: String, _ codes: [String]) {
            guard let k = d.keyOf(Opt(han: h, codes: codes)), d.raw.defs.m[k] != nil || d.baseKeys.contains(k) || d.isUser(k) else { return }
            if seen.insert(k).inserted { keys.append(k) }
        }
        if q.unicodeScalars.contains(where: { ConvertEngine.isZy($0.value) }) {
            // 方音: read it like the converter does
            let res = ConvertEngine(dict: d).convert(q)
            for it in res.items where it.isWord { for o in it.opts { if let h = o.han, let c = o.codes { add(h, c) } } }
        } else {
            let toks = q.precomposedStringWithCanonicalMapping
                .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "‑" || $0 == "　" }).map(String.init)
            var lists: [[String]] = []
            for t in toks {
                var c = Set<String>()
                let low = t.lowercased()
                c.formUnion(d.latRev[low] ?? [])
                if let rk = ConvertEngine.romKey(t) {
                    c.formUnion(d.tlRev[rk] ?? []); c.formUnion(d.pojRev[rk] ?? [])
                }
                let toned = t.decomposedStringWithCanonicalMapping.unicodeScalars.contains {
                    ((0x300...0x36F).contains($0.value) && $0.value != 0x358) || ("1"..."9").contains(Character($0))
                }
                if !toned { c.formUnion(d.plainRev[Dict.plainKey(t)] ?? []) }
                if c.isEmpty { return [] }
                lists.append(Array(c))
            }
            func combos(_ ls: ArraySlice<[String]>) -> [[String]] {
                var acc: [[String]] = [[]]
                for l in ls {
                    var next: [[String]] = []
                    outer: for a in acc { for x in l { next.append(a + [x]); if next.count >= 400 { break outer } } }
                    acc = next
                }
                return acc
            }
            for cs in combos(lists[...]) { for h in d.codeMap[cs.joined(separator: " ")] ?? [] { add(h, cs) } }
            // not one word: the words it's made of, longest first from the left
            if keys.isEmpty && lists.count > 1 {
                var i = 0
                while i < lists.count {
                    var step = 1
                    for L in stride(from: lists.count - i, through: 1, by: -1) {
                        var hit = false
                        for cs in combos(lists[i..<i + L]) {
                            for h in d.codeMap[cs.joined(separator: " ")] ?? [] { add(h, cs); hit = true }
                        }
                        if hit { step = L; break }
                    }
                    i += step
                }
                return keys
            }
        }
        return Array(keys.sorted { d.score(Dict.hanOf($0), Dict.codesOf($0)) > d.score(Dict.hanOf($1), Dict.codesOf($1)) }.prefix(120))
    }

    static func run(_ d: Dict, _ q0: String, place: Int = -1, split: Bool = true) -> LookupResult {
        let q = q0.trimmingCharacters(in: .whitespacesAndNewlines)
        var r = LookupResult()
        guard !q.isEmpty else { return r }
        if q.contains(where: { "*＊?？".contains($0) }) { return wildcard(d, q) }
        // a tone pattern: 4-5, 45, 4 5 (1–8 syllables)
        if q.range(of: #"^[1-9](?:[-\s]?[1-9]){0,7}$"#, options: .regularExpression) != nil {
            let ts = q.filter { $0.isNumber }.compactMap { $0.wholeNumberValue }
            r.tones = toneSearch(d, ts, place: place)
            if r.tones.isEmpty && ts.contains(6) {
                r.toneNote = place < 0
                    ? trs("通行讀音沒有第 6 聲。先在上方選一個有第 6 聲的腔口（例如鹿港），再查一次。")
                    : trs("這個腔口找不到這個聲調組合的詞。第 6 聲只有部分腔口有（例如鹿港）。")
            }
            return r
        }
        if q.unicodeScalars.contains(where: { ConvertEngine.isZy($0.value) || ConvertEngine.isLatinLetter($0.value) }) {
            r.taigi = taigi(d, q)
            addSentences(d, &r, r.taigi)
            // (letters: maybe English too; a section of its own, after the 台語 results)
            if !q.unicodeScalars.contains(where: { ConvertEngine.isZy($0.value) }) {
                let seen = Set(r.taigi)
                r.english = TwEnglish.search(q).filter { !seen.contains($0) }
            }
            return r
        }
        var seen = Set<String>()
        func add(_ k: String, _ list: inout [String]) { if seen.insert(k).inserted { list.append(k) } }
        // the 華語 word itself, then words written the same in 台語
        for k in d.termIndex[q] ?? [] { add(k, &r.exact) }
        for c in d.hanMap[q] ?? [] {
            let k = q + "\t" + c
            add(d.baseKeys.contains(k) ? k : (d.keyOf(Opt(han: q, codes: c.split(separator: " ").map(String.init))) ?? k), &r.exact)
        }
        // 台語 words written with it
        if q.unicodeScalars.allSatisfy({ ConvertEngine.isHan($0.value) }) {
            var c: [String] = []
            for (h, cs) in d.hanMap where h != q && h.contains(q) {
                for code in cs { let k = h + "\t" + code; if (d.baseKeys.contains(k) || d.isUser(k)) && !seen.contains(k) { c.append(k) } }
            }
            func crank(_ k: String) -> (Int, Double) { (Dict.hanOf(k).count, -d.score(Dict.hanOf(k), Dict.codesOf(k))) }
            r.contains = Array(c.sorted { crank($0) < crank($1) }.prefix(80))
            seen.formUnion(r.contains)
        }
        // 華語 glosses that contain it
        var g: [String] = []
        for (k, arr) in d.gl where !seen.contains(k) && arr.contains(where: { $0.t != q && $0.t.contains(q) }) { g.append(k) }
        func rank(_ k: String) -> Double { d.score(Dict.hanOf(k), Dict.codesOf(k)) - 0.15 * Double(Dict.hanOf(k).count) }
        r.gloss = Array(g.sorted { rank($0) > rank($1) }.prefix(60))
        seen.formUnion(r.gloss)
        // meanings that mention it
        var m: [String] = []
        for (k, i) in d.raw.defs.m where !seen.contains(k) && d.raw.defs.t[i].contains(q) { m.append(k) }
        r.defs = Array(m.sorted { rank($0) > rank($1) }.prefix(60))
        // 各地講法
        var hits = d.raw.cmp.filter { $0.zh == q }
        if hits.count < 6 { hits += d.raw.cmp.filter { $0.zh != q && $0.zh.contains(q) }.prefix(6 - hits.count) }
        for e in hits.prefix(6) {
            var order: [String] = []
            var by: [String: [Int]] = [:]
            for row in e.rows {
                let k = row.han + "\t" + row.codes
                if by[k] == nil { order.append(k) }
                by[k, default: []].append(row.place)
            }
            r.places.append((zh: e.zh, rows: order.map { (han: Dict.hanOf($0), codes: Dict.codesOf($0), places: by[$0]!) }))
        }
        addSentences(d, &r, r.exact)
        // not one word: the words it's made of, each searched on its own
        if split, r.exact.isEmpty, let ps = Segmenter.parts(q, isWord: { d.termIndex[$0] != nil || d.hanMap[$0] != nil }) {
            r.parts = ps
            r.partResults = ps.map { run(d, $0, place: place, split: false) }
        }
        return r
    }

    /// words whose syllables have exactly these tones (as written in the dictionary), most common first
    /// words whose syllables have these tones, in the chosen place's readings (so tone 6 is found
    /// where the place has it, e.g. 鹿港)
    static func toneSearch(_ d: Dict, _ tones: [Int], place: Int = -1) -> [String] {
        var out: [(k: String, s: Double)] = []
        for w in d.raw.words where w.count == 2 {
            let cs = (place >= 0 ? d.codesFor(w[0] + "\t" + w[1], place) : w[1]).split(separator: " ")
            guard cs.count == tones.count, w[0].count == tones.count else { continue }
            if zip(cs, tones).allSatisfy({ $0.0.last?.wholeNumberValue == $0.1 }) {
                out.append((w[0] + "\t" + w[1], d.score(w[0], w[1])))
            }
        }
        return out.sorted { $0.s > $1.s }.prefix(1000).map { $0.k }
    }

    /// 台語句子裡有「…」: example sentences using the 台語 word(s) found (the first few)
    static func addSentences(_ d: Dict, _ r: inout LookupResult, _ keys: [String]) {
        var ks: [String] = []
        for k in keys where !ks.contains(k) { ks.append(k) }
        ks = Array(ks.prefix(6))
        r.sentences = d.sentences(with: ks)
        var hs: [String] = []
        for k in ks where r.sentences.contains(where: { $0.word == k }) {
            let h = Dict.hanOf(k)
            if !hs.contains(h) { hs.append(h) }
        }
        r.sentenceWords = hs
    }
}

struct LookupPane: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @AppStorage("lookupQuery") private var query = ""
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var result = LookupResult()
    /// what `result` was searched for ("找不到" only once the search for what's typed has finished)
    @State private var searched = ""
    @State private var task: Task<Void, Never>?
    /// several words searched: the one whose 更多 is shown (nil = the whole search)
    @State private var picked: Int?

    var body: some View {
        List {
            Section {
                TextField(tr("華語、台語漢字、羅馬字或方音，例如：醫院、食飯、tsiah png"), text: $query)
                    .scaledFont(18)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .clearButton($query)
            }
            .listRowBackground(T.fn.opacity(0.7))
            // 依詞類列出 and 單詞比較 side by side (as a header: a row's rounded corners would cut the tiles off)
            Section {
            } header: {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        NavigationLink(value: MoreRoute.classes) { TileLabel(icon: "list.bullet.indent", title: trs("依詞類列出")) }
                            .buttonStyle(.plain)
                        NavigationLink(value: MoreRoute.compare) { TileLabel(icon: "rectangle.split.2x1", title: trs("單詞比較")) }
                            .buttonStyle(.plain)
                    }
                    HStack(spacing: 10) {
                        NavigationLink {
                            RadicalPage(isChar: { dict.hanMap[$0] != nil }) { query += $0 }
                        } label: { TileLabel(icon: "square.grid.3x3", title: trs("部首查字")) }
                            .buttonStyle(.plain)
                        NavigationLink(value: MoreRoute.japanese) { TileLabel(icon: "globe.asia.australia", title: trs("日語借詞")) }
                            .buttonStyle(.plain)
                    }
                    // with a 腔口 chosen: the words that place uses and (almost) no other does (鹿港偏好用詞)
                    if place >= 0, place < dict.raw.places.count {
                        HStack(spacing: 10) {
                            NavigationLink(value: MoreRoute.placeWords(place)) {
                                TileLabel(icon: "mappin.and.ellipse", title: PlaceWordsPage.title(dict, place),
                                          count: PlaceWordsPage.words(dict, place).count, cap: 1_000_000)
                            }
                                .buttonStyle(.plain)
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
                .padding(.vertical, 4)
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            if !query.isEmpty && result.empty && searched == query {
                Text(tr("找不到「\(query)」。")).foregroundStyle(T.muted).listRowBackground(Color.clear)
            }
            if result.isPattern {
                group(tr("台語詞「\(query)」（\(result.pattern.count == 300 ? "300+" : String(result.pattern.count))）"), result.pattern)
                group(tr("華語「\(query)」的台語講法"), result.patternZh)
            } else if query.isEmpty {
                Text(tr("可以查華語、台語漢字、皓羅／台羅／白話字（聲調可以不打，例如 tsiah png）、方音或英文（eat）。\n往右滑一個詞加到「不熟」，往左滑收藏。\n* 代表一個以上的字，? 代表剛好一個字：\n人* → 人開頭的詞　*仔 → 仔結尾　*水* → 水在中間　?仔 → 兩個字、仔結尾\n打聲調數字找聲調組合：4-5、2 2、817…"))
                    .ffFont(.footnote).foregroundStyle(T.muted).listRowBackground(Color.clear)
            }
            if !result.tones.isEmpty {
                group(tr("聲調「\(query.filter { $0.isNumber }.map(String.init).joined(separator: "-"))」（\(result.tones.count >= 1000 ? "1000+" : String(result.tones.count))）"), result.tones)
            }
            if let note = result.toneNote {
                Text(note).ffFont(.footnote).foregroundStyle(T.muted).listRowBackground(Color.clear)
            }
            group(tr("台語「\(query)」"), result.taigi)
            group(trs("台語講法"), result.exact)
            KeyListSection(dict: dict, title: tr("英文「\(query)」（維基詞典）"), keys: result.english, englishQuery: query)
            if !result.parts.isEmpty {
                ForEach(Array(result.parts.enumerated()), id: \.offset) { i, w in
                    let pr = result.partResults[i]
                    group("「\(w)」", pr.exact + pr.taigi.filter { !pr.exact.contains($0) })
                }
                // which word 更多 is for
                Section {
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("點一個詞，看那個詞的更多")).ffFont(.footnote).foregroundStyle(T.muted).padding(.leading, 16)
                        WordPickRow(words: result.parts, picked: $picked)
                    }
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                }
            }
            if let i = picked, i < result.partResults.count {
                more(result.partResults[i], result.parts[i])
            } else {
                more(result, query)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            search()
            // build the sentence index ahead of the first search (台語句子裡有「…」)
            let d = dict
            Task.detached(priority: .utility) { _ = d.sentences(with: ["\t"]) }
        }
        .onChange(of: query) { picked = nil; search() }
        .onChange(of: place) { search() }
    }

    /// everything else, as a short list of pages right under 台語講法 (less to scroll)
    @ViewBuilder private func more(_ r: LookupResult, _ query: String) -> some View {
        let words = r.sentenceWords.prefix(3).joined(separator: "、")
        if !r.sentences.isEmpty || !r.contains.isEmpty || !r.places.isEmpty || !r.gloss.isEmpty || !r.defs.isEmpty {
            Section {
            } header: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("更多")).ffFont(.footnote).foregroundStyle(T.muted).padding(.leading, 16)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        if !r.sentences.isEmpty {
                            NavigationLink(value: MoreRoute.sentences(title: tr("台語句子裡有「\(words)」"), hits: r.sentences)) {
                                TileLabel(icon: "text.quote", title: tr("句子裡有「\(words)」"), count: r.sentences.count, cap: 300)
                            }
                            .buttonStyle(.plain)
                        }
                        if !r.contains.isEmpty {
                            NavigationLink(value: MoreRoute.keys(title: tr("台語詞裡有「\(query)」"), keys: r.contains)) {
                                TileLabel(icon: "character.textbox", title: tr("詞裡有「\(query)」"), count: r.contains.count, cap: 80)
                            }
                            .buttonStyle(.plain)
                        }
                        if !r.places.isEmpty {
                            NavigationLink(value: MoreRoute.places(groups: r.places.map { e in
                                PlaceGroup(zh: e.zh, rows: e.rows.map { PlaceRow(han: $0.han, codes: $0.codes, places: $0.places) })
                            })) {
                                TileLabel(icon: "map", title: trs("各地講法"), count: r.places.count, cap: 6)
                            }
                            .buttonStyle(.plain)
                        }
                        if !r.gloss.isEmpty {
                            NavigationLink(value: MoreRoute.keys(title: tr("華語意思有「\(query)」"), keys: r.gloss)) {
                                TileLabel(icon: "text.magnifyingglass", title: tr("華語意思有「\(query)」"), count: r.gloss.count, cap: 60)
                            }
                            .buttonStyle(.plain)
                        }
                        if !r.defs.isEmpty {
                            NavigationLink(value: MoreRoute.keys(title: tr("解釋裡有「\(query)」"), keys: r.defs)) {
                                TileLabel(icon: "book", title: tr("解釋裡有「\(query)」"), count: r.defs.count, cap: 60)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
                .textCase(nil)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }

    private func search() {
        task?.cancel()
        let q = query, d = dict, pl = place
        task = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { Lookup.run(d, q, place: pl) }.value
            guard !Task.isCancelled else { return }
            result = r
            searched = q
        }
    }

    private func group(_ title: String, _ keys: [String]) -> some View {
        KeyListSection(dict: dict, title: title, keys: keys)
    }

    private func row(_ k: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Dict.hanOf(k)).scaledFont(20, weight: .semibold).foregroundStyle(T.glyph)
                Text(dict.wordText(k, rom, place)).latFont(16).foregroundStyle(T.greenInk)
                Text(dict.wordText(k, 3, place)).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                if let r = dict.raw.reg[k] { RegChip(reg: r) }
            }
            if let g = dict.gl[k], !g.isEmpty {
                Text(g.map { $0.t }.joined(separator: "、")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1)
            } else if let t = dict.defText(k) {
                Text(t.replacingOccurrences(of: "\n", with: " ")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
            }
        }
    }
}

/// 查詞 → 更多 → a page of words, sentences or 各地講法
struct MorePage: View {
    let dict: Dict
    let route: MoreRoute
    var body: some View {
        switch route {
        case .sentences(let title, let hits):
            SentencesPage(dict: dict, title: title, hits: hits)
        case .keys(let title, let keys):
            List { KeyListSection(dict: dict, title: "", keys: keys) }
                .scrollContentBackground(.hidden)
                .appBackground()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        case .wordClass(let c):
            WordClassPage(dict: dict, cls: c)
        case .compare:
            ComparePage(dict: dict)
        case .classes:
            WordClassListPage(dict: dict)
        case .japanese:
            JapaneseWordsPage(dict: dict)
        case .placeWords(let p):
            PlaceWordsPage(dict: dict, place: p)
        case .places(let groups):
            List {
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in PlacesBlockView(dict: dict, e: g) }
                    .listRowBackground(T.fn.opacity(0.7))
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("各地講法"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        }
    }
}

/// a list of words (swipe right = 加到不熟, left = 收藏)
struct KeyListSection: View {
    let dict: Dict
    let title: String
    let keys: [String]
    /// found by their English (Wiktionary): the English shown too
    var englishQuery: String? = nil
    @EnvironmentObject var store: Store
    var body: some View {
        if !keys.isEmpty {
            Section(title) {
                ForEach(keys, id: \.self) { k in
                    EntryLink(value: DictKey(k: k)) { DictRow(dict: dict, key: k, englishQuery: englishQuery) }
                        .swipeActions(edge: .leading) {
                            if store.cardStatus(k) == 0 {
                                Button { store.toggleUnknown(k) } label: { Label(tr("加到不熟"), systemImage: "star") }
                                    .tint(T.rustEdge)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleSaved(k) } label: {
                                Label(store.isSaved(k) ? trs("取消收藏") : trSaveVerb(), systemImage: "bookmark")
                            }
                            .tint(T.oliveEdge)
                        }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
    }
}

/// one 各地講法 meaning: the words each place uses for it
struct PlacesBlockView: View {
    let dict: Dict
    let e: PlaceGroup
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(e.zh).ffFont(.headline).foregroundStyle(T.pinkInk)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(T.pink))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.pinkEdge, lineWidth: 1.5))
            ForEach(Array(e.rows.enumerated()), id: \.offset) { _, row in
                let key = dict.keyOf(Opt(han: row.han, codes: row.codes.split(separator: " ").map(String.init)))
                let content = VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.han).scaledFont(18, weight: .semibold).foregroundStyle(T.glyph)
                        Text(dict.codes(row.codes, rom, -1)).latFont(15).foregroundStyle(T.greenInk)
                        Text(dict.codes(row.codes, 3, row.places.first ?? -1)).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                    }
                    Text(row.places.compactMap { $0 < dict.raw.places.count ? dict.raw.places[$0] : nil }.joined(separator: "、"))
                        .ffFont(.caption).foregroundStyle(row.places.contains(place) ? T.oliveInk : T.muted)
                }
                if let key, dict.raw.defs.m[key] != nil {
                    NavigationLink(value: DictKey(k: key)) { content }
                } else {
                    content
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// one example sentence: 漢字 word by word (tap a word to open it; with a 腔口, the place's own words in pink),
/// 羅馬字 in the place's readings, 華語, and on the right the 在地詞 switch / 選詞 and ▶.
/// Used in dictionary entries and in 台語句子裡有「…」.
struct ExampleBlock: View {
    let dict: Dict
    let ex: [String]                 // 漢字, template, 華語, audio
    /// the word the sentence is about: shown in yellow (boxed in 台語句子裡有「…」)
    var own: String? = nil
    var boxedOwn = false
    let onWord: (String) -> Void
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var swapWord: String?                  // the word picker for a place's own words
    @State private var swapZh: String?                    // …and the 華語 translation of its sentence
    // hold a finger on the sentence and slide over the words: the word under the finger swells,
    // letting go opens it (iPhone / iPad)
    @State private var wordFrames: [Int: CGRect] = [:]
    /// which word is swollen: kept in its own object, so only the words notice when it changes
    /// (with @State here, every pointer move onto another word redrew the whole sentence)
    @StateObject private var sw = SwellState()
    @State private var scrubSpace = UUID()
    @AppStorage("ff-swaps") private var swapsJSON = ""     // your choices (redraws when they change)
    @AppStorage("ff-swap-off") private var swapOffJSON = "" // sentences with the 在地詞 switch off
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    /// 設定 → 例句的詞分開一點
    @AppStorage("wordGap") private var gap = true

    var body: some View {
        let e = ex
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if e.count > 1 {
                    exampleWordsView(e[0], e[1], zh: e.count > 2 ? e[2] : nil)
                } else {
                    Text(e[0]).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                }
                if e.count > 1 { Text(dict.sentenceText(e[1], rom, place: place, han: e[0], zh: e.count > 2 ? e[2] : nil)).toneGlow().latFont(15).foregroundStyle(T.greenInk).textSelection(.enabled) }
                if e.count > 2, !e[2].isEmpty { Text(e[2]).ffFont(.footnote).foregroundStyle(T.muted).textSelection(.enabled) }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 8) {
                if e.count > 1 { swapControl(e[0], e[1], zh: e.count > 2 ? e[2] : nil) }
                if e.count > 3, !e[3].isEmpty { PlayButton(path: Audio.examplePath(e[3]), size: 28) }
            }
        }
        .confirmationDialog(swapTitle, isPresented: Binding(get: { swapWord != nil }, set: { if !$0 { swapWord = nil } }),
                            titleVisibility: .visible) {
            if let w = swapWord {
                ForEach(Array(dict.vocabOptions(w, place, zh: swapZh).enumerated()), id: \.offset) { _, o in
                    Button(o.han + "　" + dict.codes(o.codes.joined(separator: " "), min(max(rom, 0), 2), place)) { choose(w, o.han) }
                }
                Button(tr("原本的詞：") + w + "　" + dict.word(dict.hanMap[w]?.first.map { w + "\t" + $0 } ?? w, min(max(rom, 0), 2), -1)) { choose(w, w) }
            }
            Button(tr("取消"), role: .cancel) { swapWord = nil }
        }
    }

    private var swapTitle: String {
        place >= 0 && place < dict.raw.places.count ? dict.raw.places[place] + "怎麼講？" : "怎麼講？"
    }

    /// remember which word to show for this place (the original word = keep it)
    private func choose(_ word: String, _ pick: String) {
        var m = (try? JSONDecoder().decode([String: String].self, from: Data(swapsJSON.utf8))) ?? [:]
        m["\(place)|\(word)"] = pick
        swapsJSON = (try? String(data: JSONEncoder().encode(m), encoding: .utf8)) ?? swapsJSON
        swapWord = nil
    }

    /// 在地詞: a switch for the place's own words in this sentence, and a menu to pick which word to use
    @ViewBuilder private func swapControl(_ han0: String, _ tpl0: String, zh: String?) -> some View {
        let _ = swapsJSON + swapOffJSON          // redraw when a choice or the switch changes
        let words: [String] = {
            guard place >= 0 else { return [] }
            let loc = dict.localizedExample(han0, tpl0, place, zh: zh)
            var out: [String] = []
            for k in loc.words.keys.sorted() { if let w = loc.words[k], !w.isEmpty, !out.contains(w) { out.append(w) } }
            return out
        }()
        if !words.isEmpty {
            let k = Dict.swapOffKey(han0, place)
            let on = !dict.swapsOff().contains(k)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    Text(tr("在地詞")).ffFont(.caption, .bold).foregroundStyle(on ? T.pinkInk : T.muted)
                    Toggle(tr("在地詞"), isOn: Binding(get: { on }, set: { setSwapOn(k, $0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(T.swapInk)
                        .controlSize(.mini)
                }
                if on {
                    Menu {
                        ForEach(words, id: \.self) { w in
                            let cur = dict.vocabSwap(w, place, zh: zh)?.han ?? w
                            Section(w + " →") {
                                ForEach(Array(dict.vocabOptions(w, place, zh: zh).enumerated()), id: \.offset) { _, o in
                                    Button { choose(w, o.han) } label: {
                                        let t = o.han + "　" + dict.codes(o.codes.joined(separator: " "), min(max(rom, 0), 2), place)
                                        if cur == o.han { Label(t, systemImage: "checkmark") } else { Text(t) }
                                    }
                                }
                                Button { choose(w, w) } label: {
                                    let t = w + "（原本的詞）"
                                    if cur == w { Label(t, systemImage: "checkmark") } else { Text(t) }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(tr("選詞"))
                            Image(systemName: "chevron.down").ffFont(.caption2, .bold)
                        }
                        .ffFont(.caption, .semibold)
                        .foregroundStyle(T.pinkInk)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(T.pink))
                        .overlay(Capsule().stroke(T.pinkEdge, lineWidth: 1.5))
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                }
            }
        }
    }

    private func setSwapOn(_ k: String, _ on: Bool) {
        var s = dict.swapsOff()
        if on { s.remove(k) } else { s.insert(k) }
        withAnimation(.snappy) {
            swapOffJSON = (try? String(data: JSONEncoder().encode(Array(s).sorted()), encoding: .utf8)) ?? swapOffJSON
        }
    }

    /// one piece of an example's 漢字: a dictionary word (tap opens it), a word the place may say differently
    /// (tap = choose), or plain text
    private struct ExPiece { let text: String; let key: String?; let swapOf: String?; let swapped: Bool }

    private func examplePiecesHan(_ han0: String, _ tpl0: String, zh: String?) -> [ExPiece] {
        let loc = place >= 0 ? dict.localizedExample(han0, tpl0, place, zh: zh) : (han: han0, tpl: tpl0, swapped: Set<Int>(), words: [Int: String]())
        var out: [ExPiece] = []
        var at = 0
        for p in dict.exampleWords(loc.han, loc.tpl) {
            defer { at += p.text.count }
            if (0..<p.text.count).contains(where: { loc.words[at + $0] != nil }) {
                // group the characters by the original word they stand for
                var cur = "", curOrig: String? = nil, curSw = false
                func flush() { if !cur.isEmpty { out.append(ExPiece(text: cur, key: nil, swapOf: curOrig, swapped: curSw)) }; cur = "" }
                for (j, ch) in p.text.enumerated() {
                    let o = loc.words[at + j], sw = loc.swapped.contains(at + j)
                    if o != curOrig || sw != curSw { flush(); curOrig = o; curSw = sw }
                    cur.append(ch)
                }
                flush()
                continue
            }
            // plain text (punctuation, words not in the dictionary): one piece per character so lines can wrap anywhere
            if p.key == nil, p.text.count > 1 {
                for ch in p.text { out.append(ExPiece(text: String(ch), key: nil, swapOf: nil, swapped: false)) }
            } else {
                out.append(ExPiece(text: p.text, key: p.key, swapOf: nil, swapped: false))
            }
        }
        return out
    }

    /// the example's 漢字, word by word: the whole word (with a little room around it) is the button
    private func exampleWordsView(_ han0: String, _ tpl0: String, zh: String?) -> some View {
        let _ = swapsJSON + swapOffJSON + "\(toneSys)\(toneMarks)"   // redraw when a choice or a switch changes
        // 聲調顏色: the tone of every syllable, and where each piece starts
        let tones: [Int]? = toneSys != 0 ? dict.exampleTones(han0, tpl0, place: place, zh: zh).tones : nil
        let pieces = examplePiecesHan(han0, tpl0, zh: zh)
        var starts: [Int] = [], n = 0
        for p in pieces { starts.append(n); n += p.text.unicodeScalars.filter { ConvertEngine.isHan($0.value) }.count }
        func colored(_ i: Int, _ ink: Color) -> AttributedString {
            guard let tones else { var a = AttributedString(pieces[i].text); a.swiftUI.foregroundColor = ink; return a }
            return dict.hanToneText(pieces[i].text, tones: Array(tones.dropFirst(starts[i])), system: toneSys, base: ink)
        }
        // what tapping word i does (nil = not a button)
        func action(_ i: Int) -> (() -> Void)? {
            let p = pieces[i]
            if let orig = p.swapOf { return { swapWord = orig; swapZh = zh } }
            if let k = p.key, k != own { return { onWord(k) } }
            return nil
        }
        let layout = FlowLayout(spacing: 0, lineSpacing: -4) {     // taller boxes, lines as close as before
            ForEach(Array(pieces.enumerated()), id: \.offset) { i, p in
                if let orig = p.swapOf {
                    Button { if !sw.scrubbing { swapWord = orig; swapZh = zh } } label: {
                        wordLabel(colored(i, p.swapped ? T.swapInk : T.glyph), line: T.swapInk.opacity(0.8))
                    }
                    .buttonStyle(SwellButtonStyle())
                    .swellHot(sw, i)
                    .background(frameReader(i))
                } else if let k = p.key, k != own {
                    Button { if !sw.scrubbing { onWord(k) } } label: {
                        wordLabel(colored(i, T.blueInk), line: T.blueInk.opacity(0.45))
                    }
                    .buttonStyle(SwellButtonStyle())
                    .swellHot(sw, i)
                    .background(frameReader(i))
                } else {
                    Text(colored(i, p.key != nil && p.key == own ? T.oliveInk : T.glyph)).toneGlow().ffFont(.body)
                        .padding(.vertical, 7).padding(.horizontal, gap ? 2 : 0)
                        .background(RoundedRectangle(cornerRadius: 4).fill(boxedOwn && p.key != nil && p.key == own ? T.olive.opacity(0.6) : .clear))
                }
            }
        }
        let tracked = layout
            .coordinateSpace(name: scrubSpace)
            .onPreferenceChange(WordFramesKey.self) { wordFrames = $0 }
            // one pointer tracker for the whole sentence (see SwellWords)
            .onContinuousHover(coordinateSpace: .named(scrubSpace)) { phase in
                var hit: Int? = nil
                if case .active(let p) = phase { hit = wordFrames.first { $0.value.contains(p) }?.key }
                if hit != sw.hover { sw.hover = hit }
            }
        #if targetEnvironment(macCatalyst)
        return tracked
        #else
        return tracked
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(scrubSpace)))
                    .onChanged { v in
                        guard case .second(true, let drag) = v else { return }
                        if !sw.scrubbing { sw.scrubbing = true; Haptics.start() }
                        guard let drag else { return }
                        let hit = wordFrames.first { $0.value.insetBy(dx: -4, dy: -2).contains(drag.location) }?.key
                        if hit != sw.scrub { sw.scrub = hit; if hit != nil { Haptics.tick() } }
                    }
                    .onEnded { _ in
                        let open = sw.scrub.flatMap(action)
                        sw.scrub = nil
                        open?()
                        // the word's own button may fire too when the finger lifts: ignore it for a moment
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [sw] in sw.scrubbing = false }
                    }
            )
        #endif
    }

    /// where word i is (for sliding over the words)
    private func frameReader(_ i: Int) -> some View {
        GeometryReader { g in
            Color.clear.preference(key: WordFramesKey.self, value: [i: g.frame(in: .named(scrubSpace))])
        }
    }

    /// a tappable word: no underline (it swells under the pointer instead); the whole padded box reacts
    private func wordLabel(_ t: AttributedString, line: Color) -> some View {
        Text(t).ffFont(.body).toneGlow()
            .padding(.vertical, 7).padding(.horizontal, gap ? 2 : 0)
            .contentShape(Rectangle())
    }

}

/// 台語句子裡有「…」: example sentences that use the word, the word highlighted; tap 出自 to open the entry
struct SentencesPage: View {
    let dict: Dict
    let title: String
    let hits: [Dict.SentenceHit]
    @State private var tapped: DictKey?
    @State private var openEntry: DictKey?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                Text(tr("\(hits.count) 句，短的在前面")).ffFont(.caption).foregroundStyle(T.muted)
                ForEach(Array(hits.enumerated()), id: \.offset) { _, h in card(h) }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        .wordOpener(dict, $tapped)
        .navigationDestination(item: $openEntry) { DictEntryView(dict: dict, key: $0.k) }
    }

    private func card(_ h: Dict.SentenceHit) -> some View {
        let e = h.ex
        return VStack(alignment: .leading, spacing: 4) {
            ExampleBlock(dict: dict, ex: e, own: h.word, boxedOwn: true, onWord: { tapped = DictKey(k: $0) })
            NavigationLink(value: DictKey(k: h.entry)) {
                HStack(spacing: 4) {
                    Text(tr("出自")).foregroundStyle(T.muted)
                    Text(Dict.hanOf(h.entry)).foregroundStyle(T.blueInk)
                    Image(systemName: "chevron.right").ffFont(.caption2, .bold).foregroundStyle(T.muted)
                }
                .ffFont(.caption)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
        // anywhere on the card (except its own buttons) opens the entry the sentence comes from
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { openEntry = DictKey(k: h.entry) }
    }
}

// MARK: - 收藏

struct SavedPane: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var shareItem: ShareItem?

    var body: some View {
        let keys = store.savedKeys
        let senses = store.savedSenses.filter { dict.raw.defs.m[$0.key] != nil }
        List {
            if keys.isEmpty && senses.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label(tr("還沒有收藏"), systemImage: "bookmark").ffFont(.headline).foregroundStyle(T.glyph)
                    Text(tr("在「轉換」點一個詞，或在「查詞」打開一個詞，按「收藏」就會存在這裡。詞的每個意思旁邊也有書籤，可以只收藏那個意思（連同它的讀音、例句、音檔）。"))
                        .ffFont(.footnote).foregroundStyle(T.muted)
                }
                .listRowBackground(Color.clear)
            } else {
                // export (here rather than in the top bar, so the top bar is the same on every page)
                Menu {
                    Button { share(Data(store.savedCSV(dict).utf8), "方方-收藏.csv") } label: {
                        Label(tr("匯出 CSV（Anki）"), systemImage: "tablecells")
                    }
                    Button { share(Data(textExport(keys, senses).utf8), "方方-收藏.txt") } label: {
                        Label(tr("匯出文字"), systemImage: "doc.plaintext")
                    }
                } label: {
                    Label(tr("匯出收藏"), systemImage: "square.and.arrow.up").foregroundStyle(T.oliveInk)
                }
                .listRowBackground(T.fn.opacity(0.7))
                if !keys.isEmpty {
                Section {
                    ForEach(keys, id: \.self) { k in
                        NavigationLink(value: DictKey(k: k)) { row(k) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { withAnimation { store.unsave([k]) } } label: {
                                    Label(tr("刪除"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if let st = store.cardStatus(k), st != 2 {
                                    Button { store.toggleUnknown(k) } label: { Label(tr("加到不熟"), systemImage: "star") }
                                        .tint(T.rustEdge)
                                }
                            }
                    }
                } header: {
                    Text(tr("\(keys.count) 個詞（往左滑刪除，往右滑加到「不熟」）"))
                }
                .listRowBackground(T.fn.opacity(0.7))
                }
                if !senses.isEmpty {
                    Section {
                        ForEach(senses, id: \.id) { s in
                            NavigationLink(value: DictKey(k: s.key)) { senseRow(s) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { withAnimation { store.unsave(s) } } label: {
                                        Label(tr("刪除"), systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        Text(tr("\(senses.count) 個意思（往左滑刪除）"))
                    }
                    .listRowBackground(T.fn.opacity(0.7))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
    }

    private func row(_ k: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Dict.hanOf(k)).scaledFont(20, weight: .semibold).foregroundStyle(T.glyph)
                Text(dict.wordText(k, rom, place)).latFont(16).foregroundStyle(T.greenInk)
                Text(dict.wordText(k, 3, place)).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                Spacer(minLength: 0)
                if store.cardStatus(k) == 2 { Image(systemName: "star.fill").ffFont(.caption).foregroundStyle(T.rustInk) }
            }
            if let g = dict.gl[k], !g.isEmpty {
                Text(g.map { $0.t }.joined(separator: "、")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1)
            } else if let t = dict.defText(k) {
                Text(t.replacingOccurrences(of: "\n", with: " ")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
            }
        }
    }

    /// 匯出文字: the words, then the meanings (with their sentences)
    private func textExport(_ keys: [String], _ senses: [SavedSense]) -> String {
        var lines = keys.map { Dict.hanOf($0) + "\t" + dict.word($0, rom, -1) }
        for s in senses {
            let all = dict.senses(s.key)
            guard s.sense < all.count else { continue }
            let m = all[s.sense]
            lines.append(Dict.hanOf(s.key) + "\t" + dict.word(s.key, rom, -1) + "\t" + (m.pos.isEmpty ? "" : "〔\(m.pos)〕") + m.text)
            for x in m.ex {
                lines.append("\t" + x[0] + (x.count > 1 ? "\t" + dict.sentence(x[1], rom) : "") + (x.count > 2 ? "\t" + x[2] : ""))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// a saved meaning: the word, its reading, the meaning and all its sentences
    private func senseRow(_ s: SavedSense) -> some View {
        let all = dict.senses(s.key)
        let m = s.sense < all.count ? all[s.sense] : nil
        return senseRowBody(s, m)
            .contextMenu {
                Button { UIPasteboard.general.string = SenseCopy.text(dict, key: s.key, sense: s.sense, rom: rom, place: place) } label: {
                    Label(tr("複製這個意思"), systemImage: "doc.on.doc")
                }
            }
    }

    private func senseRowBody(_ s: SavedSense, _ m: DictSense?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Dict.hanOf(s.key)).scaledFont(20, weight: .semibold).foregroundStyle(T.glyph)
                Text(dict.wordText(s.key, rom, place)).latFont(16).foregroundStyle(T.greenInk)
                Text(dict.wordText(s.key, 3, place)).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                Spacer(minLength: 0)
                Image(systemName: "bookmark.fill").ffFont(.caption).foregroundStyle(T.blueInk)
            }
            if let m {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(m.n).").ffFont(.footnote, .bold).foregroundStyle(T.muted)
                    if !m.pos.isEmpty { Chip(text: m.pos, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                    Text(m.text).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.9))
                }
                ForEach(Array(m.ex.enumerated()), id: \.offset) { _, x in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dict.exampleHanText(x[0], x.count > 1 ? x[1] : "", place: place, zh: x.count > 2 ? x[2] : nil, base: T.blueInk))
                            .ffFont(.subheadline)
                        if x.count > 1 {
                            Text(dict.sentenceText(x[1], rom, place: place, han: x[0], zh: x.count > 2 ? x[2] : nil))
                                .latFont(14).foregroundStyle(T.greenInk)
                        }
                        if x.count > 2, !x[2].isEmpty { Text(x[2]).ffFont(.caption).foregroundStyle(T.muted) }
                    }
                    .padding(.leading, 18)
                }
            }
        }
    }

    private func share(_ data: Data, _ name: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if (try? data.write(to: url, options: .atomic)) != nil { shareItem = ShareItem(url: url) }
    }
}

// MARK: - 分類

struct CategoryPane: View {
    let dict: Dict
    @State private var filter = ""
    var body: some View {
        let names = dict.raw.cats ?? []
        let counts = dict.catCounts
        let shown = names.indices.filter { filter.isEmpty || names[$0].contains(filter) }
        List {
            Section {
                TextField(tr("找分類，例如：食物、稱謂、時間"), text: $filter).autocorrectionDisabled().clearButton($filter)
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section(tr("\(shown.count) 個分類（教育部辭典）")) {
                ForEach(shown, id: \.self) { i in
                    NavigationLink(value: CatRef(i: i)) {
                        HStack {
                            Text(names[i]).foregroundStyle(T.glyph)
                            Spacer()
                            Text("\(counts[i, default: 0])").ffFont(.footnote).foregroundStyle(T.muted)
                        }
                    }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }
}

struct CategoryWordsView: View {
    let dict: Dict
    let cat: Int
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    var body: some View {
        let keys = dict.catWords[cat, default: []].sorted { store.rankOf($0) < store.rankOf($1) }
        let newOnes = keys.filter { store.cardStatus($0) == 0 }
        List {
            Section {
                Button { withAnimation(.snappy) { store.addUnknown(keys) } } label: {
                    Label(newOnes.isEmpty ? trs("這個分類的新詞都在卡片裡了") : tr("新詞全部加到「不熟」（\(newOnes.count)）"),
                          systemImage: newOnes.isEmpty ? "star.fill" : "star")
                }
                .disabled(newOnes.isEmpty)
            } footer: {
                Text(tr("最常用的在前面。往右滑一個詞加到「不熟」，往左滑收藏。"))
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section(tr("\(keys.count) 個詞")) {
                ForEach(keys, id: \.self) { k in
                    NavigationLink(value: DictKey(k: k)) { DictRow(dict: dict, key: k) }
                        .swipeActions(edge: .leading) {
                            if store.cardStatus(k) == 0 {
                                Button { store.toggleUnknown(k) } label: { Label(tr("加到不熟"), systemImage: "star") }
                                    .tint(T.rustEdge)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleSaved(k) } label: {
                                Label(store.isSaved(k) ? trs("取消收藏") : trSaveVerb(), systemImage: "bookmark")
                            }
                            .tint(T.oliveEdge)
                        }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(dict.raw.cats.map { cat < $0.count ? $0[cat] : "" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

/// one word in a list: 漢字, readings, a short meaning, and whether it's in 不熟 / 熟悉 / 收藏
struct DictRow: View {
    let dict: Dict
    let key: String
    /// found by its English (Wiktionary): that English (the meanings with the word first) above the 華語 meaning
    var englishQuery: String? = nil
    @AppStorage(ZhMeaning.twKey) private var twEnglish = false
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    @EnvironmentObject var store: Store
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dict.hanText(key, place, base: dict.isUser(key) ? T.ownInk : T.glyph)).scaledFont(20, weight: .semibold).toneGlow()
                Text(dict.wordText(key, rom, place)).toneGlow().latFont(16).foregroundStyle(T.greenInk)
                Text(dict.wordText(key, 3, place)).toneGlow().ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                Spacer(minLength: 0)
                if dict.isUser(key) { OwnChip() }
                if store.isSaved(key) { Image(systemName: "bookmark.fill").ffFont(.caption).foregroundStyle(T.oliveInk) }
                switch store.cardStatus(key) {
                case 2: Image(systemName: "star.fill").ffFont(.caption).foregroundStyle(T.rustInk)
                case 1: Image(systemName: "checkmark.circle.fill").ffFont(.caption).foregroundStyle(T.greenInk)
                default: EmptyView()
                }
            }
            if let q = englishQuery {
                let en = EnglishMatch.first(TwEnglish.meanings(key), q)
                if !en.isEmpty {
                    Text(en.prefix(3).joined(separator: "; ")).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.85)).lineLimit(2)
                }
            } else if twEnglish, case let en = TwEnglish.meanings(key), !en.isEmpty {
                // 設定 → 主要解釋 → 台語: 英文
                Text(en.prefix(3).joined(separator: "; ")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(2)
            }
            if twEnglish && englishQuery == nil && !TwEnglish.meanings(key).isEmpty {
                EmptyView()
            } else if let g = dict.gl[key], !g.isEmpty {
                Text(g.map { $0.t }.joined(separator: "、")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(1)
            } else if let t = dict.defText(key) {
                Text(t.replacingOccurrences(of: "\n", with: " ")).ffFont(.footnote).foregroundStyle(T.muted).lineLimit(englishQuery == nil ? 2 : 1)
            }
        }
    }
}

// MARK: - example sentences with guessed readings marked

extension Dict {
    /// 羅馬字 of an example; readings guessed by rule (not stated by the dictionary) are red
    func sentenceText(_ tpl: String, _ sys: Int, place: Int, han: String, zh: String? = nil, ink: Color = T.greenInk) -> AttributedString {
        let ts = ToneColors.system
        if ts != 0 { return sentenceToneText(han, tpl, sys, place: place, zh: zh, system: ts) }   // 聲調顏色
        var out = AttributedString()
        for p in examplePieces(tpl, sys, place: place, han: han, zh: zh) {
            var a = AttributedString(p.text)
            if p.mark == 1 { a.swiftUI.foregroundColor = T.guessInk }        // guessed reading: red
            if p.mark == 2 { a.swiftUI.foregroundColor = T.swapInk }         // the place's own word: pink
            out += a
        }
        return out
    }

    /// an example's 漢字 for a place: words the place says differently swapped in, in pink
    func exampleHanText(_ han: String, _ tpl: String, place: Int, zh: String?, base: Color) -> AttributedString {
        let ts = ToneColors.system
        if ts != 0 { return sentenceHanToneText(han, tpl, place: place, zh: zh, system: ts, base: base) }
        guard place >= 0 else { var a = AttributedString(han); a.swiftUI.foregroundColor = base; return a }
        let loc = localizedExample(han, tpl, place, zh: zh)
        var out = AttributedString()
        for (i, ch) in loc.han.enumerated() {
            var a = AttributedString(String(ch))
            a.swiftUI.foregroundColor = loc.swapped.contains(i) ? T.swapInk : base
            out += a
        }
        return out
    }
}

/// shown under examples when some readings in them are guessed
struct GuessNote: View {
    var body: some View {
        Text(tr("紅色 = 推測的讀音（辭典沒有寫這個地方怎麼唸這個詞，照規則推出來的）"))
            .ffFont(.caption2).foregroundStyle(T.muted)
    }
}

/// guessed parts in red, the rest left to the view's colour
func guessColored(_ pieces: [(text: String, guessed: Bool)], ink: Color? = nil, guess: Color = T.guessInk) -> AttributedString {
    var out = AttributedString()
    for p in pieces {
        var a = AttributedString(p.text)
        if p.guessed { a.swiftUI.foregroundColor = guess } else if let ink { a.swiftUI.foregroundColor = ink }
        out += a
    }
    return out
}

extension Dict {
    /// a word spelled as in `place`, with its tones changed as in `tonesIn` (各地讀音: the 通行 box for 泉 places)
    func wordText(_ key: String, _ sys: Int, _ place: Int, tonesIn: Int) -> AttributedString {
        let ts = ToneColors.system
        guard ts != 0, tonesIn != place else { return wordText(key, sys, place) }
        let tok = tokensFor(key, place)
        let tones = wordTones(key, tonesIn)
        // the place's reading has a different number of syllables: keep the place's own tones
        let n = tok.filter { isCode($0.hasPrefix("^") ? String($0.dropFirst()) : $0) }.count
        guard n == tones.count else { return wordText(key, sys, place) }
        return toneText(tok, sys, place, tones: tones, system: ts)
    }

    /// a word's reading with guessed place readings in red
    func wordText(_ key: String, _ sys: Int, _ place: Int) -> AttributedString {
        let ts = ToneColors.system
        if ts != 0 { return wordToneText(key, sys, place, system: ts) }       // 聲調顏色
        return guessColored(wordPieces(key, sys, place))
    }
    /// a word's 漢字: in tone colours when 聲調顏色 is on, else in `base`
    func hanText(_ key: String, _ place: Int, base: Color) -> AttributedString {
        let ts = ToneColors.system
        if ts != 0 { return wordHanToneText(key, place, system: ts, base: base) }
        var a = AttributedString(Dict.hanOf(key)); a.swiftUI.foregroundColor = base
        return a
    }
}

/// 各地讀音: how a word is said in each of the 10 places (places that say it the same way share a box).
/// Readings MOE gives are in the usual colours; guessed ones are red with 推測.
struct PlacesTable: View {
    let dict: Dict
    let key: String
    /// show even when every place says it like 通行
    var always = false
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    var body: some View {
        let main = Dict.codesOf(key)
        let colours = ToneColors.system != 0
        let groups: [(codes: String, guessed: Bool, tones: [Int], places: [Int])] = {
            var out: [(codes: String, guessed: Bool, tones: [Int], places: [Int])] = []
            for p in dict.raw.places.indices {
                // a place that says it like 通行 (臺南/高雄 o → or included) shares the 通行 box
                let c = dict.differsFromCommon(key, p) ? dict.codesFor(key, p) : main
                let g = !dict.guessedSyllables(key, p).isEmpty
                // with tone colours on, places whose tones change differently (泉: 2→5, 5→3, 8→3;
                // 漳: 2→1, 5→7, 8→4) get boxes of their own, even when the reading is the same
                let t = colours ? dict.wordTones(key, p) : []
                if let i = out.firstIndex(where: { $0.codes == c && $0.guessed == g && $0.tones == t }) { out[i].places.append(p) }
                else { out.append((c, g, t, [p])) }
            }
            return out
        }()
        // more than one box with the 通行 reading: they differ only in how the tones change
        let commonBoxes = groups.filter { $0.codes == main }.count
        if always || groups.contains(where: { $0.codes != main }) || dict.raw.dia2?[key] != nil {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("各地讀音")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(g.places.map { String(dict.raw.places[$0].prefix(2)) }.joined(separator: "、")
                             + (g.codes == main ? (commonBoxes > 1 ? (g.places.contains(where: { dict.quanSandhi($0) }) ? trs("（同通行，泉腔變調）") : trs("（同通行，漳腔變調）")) : trs("（同通行）")) : ""))
                            .ffFont(.caption).foregroundStyle(g.places.contains(place) ? T.oliveInk : T.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            // the 通行 box is written the 通行 way, whichever places share it
                            // (spelled the 通行 way, but with the tones as these places change them)
                            let shownIn = g.codes == main ? -1 : g.places[0]
                            Text(dict.wordText(key, rom, shownIn, tonesIn: g.places[0])).latFont(17).foregroundStyle(T.greenInk)
                            Text(dict.wordText(key, 3, shownIn, tonesIn: g.places[0])).ffFont(.subheadline).foregroundStyle(T.purpleInk).hongimLine()
                            if g.guessed { Chip(text: tr("推測"), fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                        }
                        // the place also says it another way
                        let also = Array(Set(g.places.flatMap { dict.alsoSaid(key, $0) })).sorted()
                        ForEach(also, id: \.self) { x in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Chip(text: tr("也講"), fill: T.twFill, edge: T.twEdge, ink: T.twInk)
                                Text(dict.codes(x, rom, g.places[0])).latFont(15).foregroundStyle(T.greenInk)
                                Text(dict.codes(x, 3, g.places[0])).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                                let who = g.places.filter { dict.alsoSaid(key, $0).contains(x) }
                                if who.count < g.places.count {
                                    Text(who.map { String(dict.raw.places[$0].prefix(2)) }.joined(separator: "、"))
                                        .ffFont(.caption2).foregroundStyle(T.muted)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.55)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(g.places.contains(place) ? T.twEdge : .clear, lineWidth: 1.5))
                }
                Text(colours ? trs("推測 = 辭典沒有寫這個地方的讀音，是照規則推出來的。顏色是在詞尾以外的字照各地的變調（泉腔：2→5、5→3、8→3；漳腔：2→1、5→7、8→4）。")
                             : trs("紅色／推測 = 辭典沒有寫這個地方的讀音，是照規則推出來的。")).ffFont(.caption2).foregroundStyle(T.muted)
            }
        }
    }
}

// MARK: - 各地讀音 (search a word, see it in every place)

struct PronunciationPane: View {
    let dict: Dict
    @AppStorage("pronQuery") private var query = ""
    @AppStorage("rom") private var rom = 0
    @State private var keys: [String] = []
    @State private var task: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(tr("台語漢字、羅馬字或方音，例如：做伙、四界、tsiah"), text: $query)
                    .scaledFont(18)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .clearButton($query)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
                if query.isEmpty {
                    Text(tr("查一個詞，看它在鹿港、三峽、臺北、宜蘭、臺南、高雄、金門、馬公、新竹、臺中各地的讀音。紅色／推測 = 辭典沒有寫，照規則推出來的。"))
                        .ffFont(.footnote).foregroundStyle(T.muted)
                } else if keys.isEmpty {
                    Text(tr("找不到「\(query)」。")).foregroundStyle(T.muted)
                }
                ForEach(keys, id: \.self) { k in
                    // the whole block opens the word's dictionary entry
                    NavigationLink(value: DictKey(k: k)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Dict.hanOf(k)).scaledFont(24, weight: .semibold).foregroundStyle(T.glyph)
                                Text(tr("通行")).ffFont(.caption).foregroundStyle(T.muted)
                                Text(dict.word(k, TwRom.lat(rom), -1)).latFont(16).foregroundStyle(T.greenInk)
                                Text(dict.word(k, 3, -1)).ffFont(.footnote).foregroundStyle(T.purpleInk).hongimLine()
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").ffFont(.caption).foregroundStyle(T.muted)
                            }
                            PlacesTable(dict: dict, key: k, always: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.35)))
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { search() }
        .onChange(of: query) { search() }
    }

    /// only words that are exactly what was typed: the same 漢字 (all its readings), or the same 台語 spelling
    /// (romanization or 方音, whole word). 華語 meanings and longer words containing it are not included.
    nonisolated static func exact(_ d: Dict, _ q0: String) -> [String] {
        let q = q0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var out: [String] = []
        func add(_ k: String?) {
            if let k, !out.contains(k), d.raw.defs.m[k] != nil || d.baseKeys.contains(k) { out.append(k) }
        }
        if q.unicodeScalars.allSatisfy({ ConvertEngine.isHan($0.value) }) {
            for c in d.hanMap[q] ?? [] { add(d.keyOf(Opt(han: q, codes: c.split(separator: " ").map(String.init)))) }
            return out
        }
        // 台語 spelling: whole-word matches only (same number of syllables as typed)
        let typed = q.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "‑" || $0 == "　" }).count
        let zy = q.unicodeScalars.contains { ConvertEngine.isZy($0.value) }
        for k in Lookup.taigi(d, q) where zy || Dict.codesOf(k).split(separator: " ").count == typed { add(k) }
        if zy {   // 方音 has no separators: keep only words that are the whole input
            let res = ConvertEngine(dict: d).convert(q)
            let words = res.items.filter { $0.isWord }
            if words.count != 1 { return [] }
        }
        return out
    }

    private func search() {
        task?.cancel()
        let q = query, d = dict
        task = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let found: [String] = await Task.detached(priority: .userInitiated) { PronunciationPane.exact(d, q) }.value
            guard !Task.isCancelled else { return }
            keys = found
        }
    }
}


/// a word under the pointer (iPad trackpad / mouse, Mac) swells a little, like app icons on the iPad
/// a word in an example sentence grows a little while it's pressed, under the pointer (Mac, iPad with a
/// trackpad), or under the finger while sliding over the words (`hot`)
struct SwellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwellBody(label: configuration.label, pressed: configuration.isPressed)
    }
}

/// which word of a sentence is swollen (under the pointer, or under the finger while sliding)
final class SwellState: ObservableObject {
    @Published var hover: Int?
    @Published var scrub: Int?
    var scrubbing = false
}

private struct SwellHotKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var swellHot: Bool {
        get { self[SwellHotKey.self] }
        set { self[SwellHotKey.self] = newValue }
    }
}

/// word i watches the sentence's SwellState; only this small view is redrawn when the swollen word changes
private struct SwellHot<Content: View>: View {
    @ObservedObject var state: SwellState
    let i: Int
    let content: Content
    var body: some View { content.environment(\.swellHot, state.hover == i || state.scrub == i) }
}
extension View {
    func swellHot(_ state: SwellState, _ i: Int) -> some View { SwellHot(state: state, i: i, content: self) }
}

private struct SwellBody<L: View>: View {
    let label: L
    let pressed: Bool
    @Environment(\.swellHot) private var hot
    /// 設定 → 畫成圖再放大
    @AppStorage(SwellTest.key) private var on = SwellTest.standard
    var body: some View {
        let big = on && (pressed || hot)
        // the word (with its glow) is drawn once into a picture, and only the picture grows
        label
            .padding(8)
            .drawingGroup()
            .padding(-8)
            .scaleEffect(big ? 1.16 : 1)
            .zIndex(big ? 1 : 0)
            .animation(.easeOut(duration: 0.14), value: big)
    }
}

enum SwellTest {
    /// 設定 → 畫成圖再放大: words swell (drawn once as a picture, and the picture grows); off = they don't swell
    static let key = "swellOn"
    static let standard = true
}

struct WordFramesKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

enum Haptics {
    @MainActor static func start() {
        #if !targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
    @MainActor static func tick() {
        #if !targetEnvironment(macCatalyst)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}


// MARK: - 依詞類列出

/// all the words of one word class (any of their meanings), most common first: 300, then all
struct WordClassPage: View {
    let dict: Dict
    let cls: String
    @EnvironmentObject var store: Store
    @State private var all = false
    /// the word classes in the dictionary, plus 離合詞 (verbs that end in a noun: 洗身軀, 食飯)
    static let classes = ["名詞", "動詞", "離合詞", "形容詞", "副詞", "量詞", "時間詞", "代詞", "數詞", "方位詞",
                          "介詞", "連詞", "助詞", "疑問詞", "嘆詞", "擬聲詞", "擬態詞", "熟語"]

    var body: some View {
        let keys = dict.wordsOfClass(cls).sorted { store.rankOf($0) < store.rankOf($1) }
        List {
            KeyListSection(dict: dict, title: cls == "離合詞" ? "動詞裡面有名詞（\(keys.count)）" : "\(keys.count) 個詞",
                           keys: all ? keys : Array(keys.prefix(300)))
            if !all && keys.count > 300 {
                Button { all = true } label: {
                    Label(tr("顯示全部（\(keys.count)）"), systemImage: "list.bullet").foregroundStyle(T.oliveInk)
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(cls)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

extension Dict {
    /// a verb (main meaning) whose last part is a noun in the dictionary: 洗身軀 (身軀), 食飯 (飯)
    /// words that look like 離合詞 but are normal verbs (picked by hand): their last syllable changes tone
    static let notVerbWithNoun: Set<String> = [
        "不服\tpuD4 hoG8",
        "交流\tkU1 diu5",
        "代理\ttI7 di2",
        "佩服\tpue7 hoG8",
        "保領\tpø2 dNia2",
        "信任\tsiD3 ziB7",
        "修理\tsiu1 di2",
        "克服\tKiøG4 hoG8",
        "再會\tcI3 hue7",
        "包領\tpU1 dNia2",
        "委任\tui2 ziB7",
        "安眠\taD1 biD5",
        "對指\ttui3 ci2",
        "對相\ttui3 sioG3",
        "對頭誤\ttui3 TU5 go7",
        "徛黃\tKia7 G5",
        "必叉\tpiD4 Ce1",
        "拑牢牢\tKNi5 tiU5 tiU5",
        "指教\tci2 kU3",
        "掩崁\taB1 KaB3",
        "掰會\tpue2 hue7",
        "搬運\tpNua1 uD7",
        "撙節\tcuD2 caD4",
        "擔任\ttaB1 ziB7",
        "支理\tci1 di2",
        "敗露\tpI7 do7",
        "整理\tciøG2 di2",
        "料理\tdiU7 di2",
        "明品\tbiøG5 PiD2",
        "暗崁\taB3 KaB3",
        "暴露\tpoG8 do7",
        "檢點\tkiaB2 tiaB2",
        "毋知影\tB7 cI1 Nia2",
        "發表\thuaD4 piU2",
        "相干\tsioG1 kaD1",
        "相會\tsioG1 hue7",
        "知影\tcI1 Nia2",
        "管理\tkuaD2 di2",
        "纘袂牢\tcaD3 be7 tiU5",
        "處理\tCu2 di2",
        "請教\tCiøG2 kU3",
        "貓貓相\tdNiU1 dNiU1 sioG3",
        "負擔\thu7 taB1",
        "辦理\tpaD7 di2",
        "違背\tui5 pue7",
        "金金相\tkiB1 kiB1 sioG3",
        "體會\tTe2 hue7",
    ]

    func isVerbWithNoun(_ key: String) -> Bool {
        if Dict.notVerbWithNoun.contains(key) { return false }
        guard let pos = raw.pos[key], (pos.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? "").contains("動詞") else { return false }
        let hs = Array(Dict.hanOf(key)), cs = Dict.codesOf(key).split(separator: " ").map(String.init)
        guard hs.count == cs.count, hs.count > 1 else { return false }
        for L in 1..<hs.count {
            let k = String(hs.suffix(L)) + "\t" + cs.suffix(L).joined(separator: " ")
            if baseKeys.contains(k), let p = raw.pos[k],
               (p.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? "").contains("名詞") { return true }
        }
        return false
    }

    func wordsOfClass(_ c: String) -> [String] {
        WordClassCache.lock.lock(); defer { WordClassCache.lock.unlock() }
        if let hit = WordClassCache.map[c] { return hit }
        let list: [String]
        if c == "離合詞" { list = raw.pos.keys.filter { isVerbWithNoun($0) } }
        else { list = raw.pos.compactMap { k, v in v.split(separator: "|").contains { $0.contains(c) } ? k : nil } }
        WordClassCache.map[c] = list
        return list
    }
    func wordClassCount(_ c: String) -> Int { wordsOfClass(c).count }
}

// MARK: - 單詞比較

/// two words next to each other (iPad / Mac: left and right; iPhone: top and bottom)
struct ComparePage: View {
    let dict: Dict
    @Environment(\.horizontalSizeClass) private var size
    var body: some View {
        Group {
            if size == .regular {
                HStack(spacing: 0) {
                    ComparePane(dict: dict, slot: "A")
                    Rectangle().fill(T.fnEdge).frame(width: 1)
                    ComparePane(dict: dict, slot: "B")
                }
            } else {
                VStack(spacing: 0) {
                    ComparePane(dict: dict, slot: "A")
                    Rectangle().fill(T.fnEdge).frame(height: 1)
                    ComparePane(dict: dict, slot: "B")
                }
            }
        }
        .appBackground()
        .navigationTitle(tr("單詞比較"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

/// one side of 比較: search, pick a word, read its entry (remembered for next time)
struct ComparePane: View {
    let dict: Dict
    let slot: String
    @AppStorage private var key: String
    @State private var query = ""
    @State private var found: [String] = []
    @State private var task: Task<Void, Never>?

    init(dict: Dict, slot: String) {
        self.dict = dict; self.slot = slot
        _key = AppStorage(wrappedValue: "", "compare" + slot)
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
                List(found, id: \.self) { k in
                    Button { key = k; query = "" } label: { DictRow(dict: dict, key: k) }
                        .listRowBackground(T.fn.opacity(0.7))
                }
                .scrollContentBackground(.hidden)
            } else if !key.isEmpty, dict.raw.defs.m[key] != nil || dict.baseKeys.contains(key) || dict.isUser(key) {
                ScrollView { DictEntryBody(dict: dict, key: key).dictFontArea().padding(.horizontal).padding(.bottom) }
            } else {
                Text(tr("查一個詞，選它。")).foregroundStyle(T.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func search() {
        task?.cancel()
        let q = query, d = dict
        guard !q.isEmpty else { found = []; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { Lookup.run(d, q) }.value
            guard !Task.isCancelled else { return }
            var out: [String] = []
            for k in r.tones + r.taigi + r.exact + r.contains + r.gloss where !out.contains(k) { out.append(k) }
            found = Array(out.prefix(40))
        }
    }
}

/// word class lists are worked out once
enum WordClassCache {
    nonisolated(unsafe) static var map: [String: [String]] = [:]
    static let lock = NSLock()
}


/// 收藏 one meaning of a word (with everything that belongs to it: reading, meaning, sentences, recordings)
struct SenseSaveButton: View {
    let item: SavedSense
    @ObservedObject var store: Store
    var body: some View {
        let on = store.isSaved(item)
        Button { withAnimation(.snappy) { store.toggleSaved(item) } } label: {
            Image(systemName: on ? "bookmark.fill" : "bookmark")
                .ffFont(.subheadline, .semibold)
                .foregroundStyle(on ? T.blueInk : T.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(on ? T.blue : T.fn.opacity(0.8)))
                .overlay(Circle().stroke(on ? T.blueEdge : T.fnEdge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? trs("取消收藏這個意思") : trs("收藏這個意思"))
    }
}

/// a little star in all the tone colours: under a word in 轉換 that's saved or in 不熟
struct ToneStar: View {
    var size: CGFloat = 8
    /// blue: only some meanings of the word are saved
    var blue = false
    var body: some View {
        Image(systemName: "star.fill")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(blue ? AnyShapeStyle(ToneColors.blue)
                             : AnyShapeStyle(AngularGradient(colors: [ToneColors.red, ToneColors.orange, ToneColors.yellow, ToneColors.green,
                                                                      ToneColors.teal, ToneColors.blue, ToneColors.purple, ToneColors.pink, ToneColors.red],
                                                             center: .center)))
            .shadow(color: .black.opacity(0.4), radius: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}


/// a half-width button in 查詞 (two to a row)
struct TileLabel: View {
    let icon: String
    let title: String
    var count: Int? = nil
    var cap = 0
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(T.oliveInk)
            Text(title).foregroundStyle(T.glyph).lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 2)
            if let count { Text(count >= cap ? "\(cap)+" : "\(count)").ffFont(.footnote, mono: true).foregroundStyle(T.muted) }
        }
        .ffFont(.subheadline)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// 依詞類列出: every word class, with how many words it has
struct WordClassListPage: View {
    let dict: Dict
    var body: some View {
        List {
            ForEach(WordClassPage.classes, id: \.self) { c in
                NavigationLink(value: MoreRoute.wordClass(c)) {
                    HStack {
                        Text(c).foregroundStyle(c == "離合詞" ? T.pinkInk : T.glyph)
                        Spacer()
                        Text("\(dict.wordClassCount(c))").ffFont(.footnote, mono: true).foregroundStyle(T.muted)
                    }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("依詞類列出"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}


/// 選擇複製: pick which versions to copy, and a Discord style for each one (the text itself is wrapped in it)
struct CopyOptionsSheet: View {
    let texts: [String]
    let names: [String]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("copyHan") private var useHan = true
    @AppStorage("copyRom") private var useRom = true
    @AppStorage("copyZy") private var useZy = true
    @AppStorage("copyStyleHan") private var styleHan = 0
    @AppStorage("copyStyleRom") private var styleRom = 0
    @AppStorage("copyStyleZy") private var styleZy = 0
    @AppStorage("copyPreHan") private var preHan = ""
    @AppStorage("copyPreRom") private var preRom = ""
    @AppStorage("copyPreZy") private var preZy = ""
    @AppStorage("copyGap") private var gap = true
    @State private var done = false

    /// name, and how a line is wrapped: (before, after); block = the whole text at once
    struct Style { let name: String; let before: String; let after: String; var block = false; var lineStart = false }
    static let styles: [Style] = [
        Style(name: "不加", before: "", after: ""),
        Style(name: "**粗體**", before: "**", after: "**"),
        Style(name: "*斜體*", before: "*", after: "*"),
        Style(name: "***粗斜體***", before: "***", after: "***"),
        Style(name: "__底線__", before: "__", after: "__"),
        Style(name: "~~刪除線~~", before: "~~", after: "~~"),
        Style(name: "||暗藏||", before: "||", after: "||"),
        Style(name: "`程式碼`", before: "`", after: "`"),
        Style(name: "```程式區塊```", before: "```\n", after: "\n```", block: true),
        Style(name: "> 引用", before: "> ", after: "", lineStart: true),
        Style(name: "# 大標題", before: "# ", after: "", lineStart: true),
        Style(name: "## 標題", before: "## ", after: "", lineStart: true),
        Style(name: "### 小標題", before: "### ", after: "", lineStart: true),
        Style(name: "-# 小字", before: "-# ", after: "", lineStart: true),
    ]

    static func wrap(_ text: String, _ i: Int) -> String {
        let st = styles[min(max(i, 0), styles.count - 1)]
        if st.block { return st.before + text + st.after }
        // every line on its own, so the marks never run across a line break
        return text.components(separatedBy: "\n").map { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return line }
            return st.before + t + st.after
        }.joined(separator: "\n")
    }

    private var output: String {
        var parts: [String] = []
        let on = [useHan, useRom, useZy], styles = [styleHan, styleRom, styleZy], pre = [preHan, preRom, preZy]
        for i in 0..<3 where on[i] {
            let t = texts[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let w = Self.wrap(t, styles[i])
            let p = pre[i].trimmingCharacters(in: .whitespaces)
            if p.isEmpty { parts.append(w) }
            else if Self.styles[min(max(styles[i], 0), Self.styles.count - 1)].block || Self.styles[min(max(styles[i], 0), Self.styles.count - 1)].lineStart { parts.append(p + "\n" + w) }
            else { parts.append(p + " " + w) }
        }
        return parts.joined(separator: gap ? "\n\n" : "\n")
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection(0, $useHan, $styleHan, $preHan)
                typeSection(1, $useRom, $styleRom, $preRom)
                typeSection(2, $useZy, $styleZy, $preZy)
                Section {
                    Toggle(tr("段跟段中間空一行"), isOn: $gap)
                } footer: {
                    Text(tr("這些是 Discord 的格式：文字本身會被包起來，例如 **粗體**、||暗藏||、> 引用。"))
                }
                .listRowBackground(T.fn.opacity(0.7))
                Section(tr("預覽")) {
                    Text(output.isEmpty ? trs("（沒有選任何一段）") : output)
                        .ffFont(.footnote, mono: true)
                        .foregroundStyle(output.isEmpty ? T.muted : T.glyph)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(T.fn.opacity(0.7))
                Section {
                    Button {
                        UIPasteboard.general.string = output
                        done = true
                        Task { try? await Task.sleep(nanoseconds: 700_000_000); dismiss() }
                    } label: {
                        Label(done ? trs("已複製") : trs("複製"), systemImage: done ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .softButton()
                    .disabled(output.isEmpty)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 2, bottom: 4, trailing: 2))
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("選擇複製"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } } }
        }
    }

    private func typeSection(_ i: Int, _ on: Binding<Bool>, _ style: Binding<Int>, _ pre: Binding<String>) -> some View {
        Section {
            Toggle(tr("複製\(names[i])"), isOn: on)
            if on.wrappedValue {
                Picker(tr("格式"), selection: style) {
                    ForEach(0..<Self.styles.count, id: \.self) { Text(trs(Self.styles[$0].name)).tag($0) }
                }
                .pickerStyle(.menu)
                HStack {
                    Text(tr("前面加")).foregroundStyle(T.muted)
                    TextField(tr("（不加）"), text: pre).multilineTextAlignment(.trailing).clearButton(pre)
                }
            }
        } header: {
            Text(names[i])
        }
        .listRowBackground(T.fn.opacity(0.7))
    }
}

/// 鹿港偏好用詞 …: from 詞彙比較 (各地講法), the words recorded for this place and for no more than one other of the
/// 10 places; the ones only this place has first
struct PlaceWordsPage: View {
    let dict: Dict
    let place: Int
    @AppStorage("rom") private var rom = 0
    // (shown again when 聲調顏色 changes)
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.marksKey) private var toneMarks = false
    @EnvironmentObject var store: Store
    @State private var query = ""

    struct Word: Hashable {
        let han: String
        let codes: String
        let zh: [String]           // the meanings (華語) it's listed for
        let others: [Int]          // the other place that uses it (empty: only this one)
        let usual: [String]        // the word(s) most places use for the same meaning instead (醫院 → 病院)
    }

    /// "鹿港偏好用詞" (the place's name without its 偏泉腔 / 混合腔)
    static func title(_ dict: Dict, _ place: Int) -> String {
        let n = place < dict.raw.places.count ? dict.raw.places[place] : ""
        return trs(String(n.prefix(2))) + tr("偏好用詞")
    }

    private static var cache: [Int: [Word]] = [:]
    static func words(_ dict: Dict, _ place: Int) -> [Word] {
        if let c = cache[place] { return c }
        // where each word is used, for any meaning (a word that's everywhere for another meaning isn't this place's)
        var placesOf: [String: Set<Int>] = [:]
        for e in dict.raw.cmp { for r in e.rows { placesOf[r.han, default: []].insert(r.place) } }
        var byWord: [String: (codes: String, zh: [String], usual: [String])] = [:]
        var order: [String] = []
        for e in dict.raw.cmp {
            // the words most places use for this meaning (the most places; at least 3)
            var count: [String: Set<Int>] = [:]
            for r in e.rows { count[r.han, default: []].insert(r.place) }
            for r in e.rows where r.place == place {
                guard let ps = placesOf[r.han], ps.count <= 2 else { continue }
                if byWord[r.han] == nil { byWord[r.han] = (r.codes, [], []); order.append(r.han) }
                if !byWord[r.han]!.zh.contains(e.zh) { byWord[r.han]!.zh.append(e.zh) }
                let others = count.filter { $0.key != r.han && $0.value.count >= 3 }
                if let most = others.values.map(\.count).max() {
                    for (h, _) in others.filter({ $0.value.count == most }).sorted(by: { $0.key < $1.key })
                    where !byWord[r.han]!.usual.contains(h) { byWord[r.han]!.usual.append(h) }
                }
            }
        }
        let out = order.compactMap { h -> Word? in
            guard let w = byWord[h] else { return nil }
            return Word(han: h, codes: w.codes, zh: w.zh, others: (placesOf[h] ?? []).subtracting([place]).sorted(), usual: w.usual)
        }
        // only here first, then here and one other place; each in the order of 詞彙比較
        let sorted = out.filter { $0.others.isEmpty } + out.filter { !$0.others.isEmpty }
        cache[place] = sorted
        return sorted
    }

    var body: some View {
        let all = Self.words(dict, place)
        // (the usual word finds the place's: 病院 → 金門 醫院)
        let list = query.isEmpty ? all : all.filter { w in
            w.han.contains(query) || w.zh.contains { $0.contains(query) } || w.usual.contains { $0.contains(query) }
        }
        let only = list.filter { $0.others.isEmpty }, shared = list.filter { !$0.others.isEmpty }
        let name = trs(String((place < dict.raw.places.count ? dict.raw.places[place] : "").prefix(2)))
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.muted)
                    TextField(tr("台語漢字（這裡的或一般的講法）或華語"), text: $query)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .clearButton($query)
                }
                Text(tr("教育部辭典的「詞彙比較」（各地講法）裡，只記在這個地方，或這裡和另外一個地方的詞。只比較這 10 個地方，而且只有調查過的意思。"))
                    .ffFont(.footnote).foregroundStyle(T.muted)
            }
            .listRowBackground(T.fn.opacity(0.7))
            if !only.isEmpty {
                Section(tr("只有\(name)（\(only.count)）")) { ForEach(only, id: \.self) { row($0) } }
                    .listRowBackground(T.fn.opacity(0.7))
            }
            if !shared.isEmpty {
                Section(tr("\(name)和另外一個地方（\(shared.count)）")) { ForEach(shared, id: \.self) { row($0) } }
                    .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .appBackground()
        .navigationTitle(Self.title(dict, place))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }

    @ViewBuilder private func row(_ w: Word) -> some View {
        let key = dict.keyOf(Opt(han: w.han, codes: w.codes.split(separator: " ").map(String.init)))
        // in tone colours, as the place says it (the reading 詞彙比較 gives for this place, its tone changes)
        let own = w.han + "\t" + w.codes
        let colours = toneSys != 0 && !w.codes.isEmpty
        let content = VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if colours {
                    Text(dict.hanText(own, place, base: T.glyph)).scaledFont(18, weight: .semibold).toneGlow()
                    Text(dict.wordText(own, rom, place)).toneGlow().latFont(15).foregroundStyle(T.greenInk)
                } else {
                    Text(w.han).scaledFont(18, weight: .semibold).foregroundStyle(T.glyph)
                    if !w.codes.isEmpty {
                        Text(dict.codes(w.codes, rom, place)).latFont(15).foregroundStyle(T.greenInk)
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Chip(text: tr("華"), fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
                Text(w.zh.joined(separator: "、")).ffFont(.footnote).foregroundStyle(T.glyph).lineLimit(2)
            }
            // what most places say instead, each in a box
            if !w.usual.isEmpty {
                HStack(alignment: .center, spacing: 6) {
                    Text(tr("一般講：")).ffFont(.caption).foregroundStyle(T.muted)
                    ForEach(w.usual.prefix(4), id: \.self) { h in
                        Text(h).ffFont(.subheadline).foregroundStyle(T.oliveInk)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 7).fill(T.olive))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.oliveEdge, lineWidth: 1.2))
                    }
                }
            }
            if !w.others.isEmpty {
                Text(tr("也在：") + w.others.compactMap { $0 < dict.raw.places.count ? trs(String(dict.raw.places[$0].prefix(2))) : nil }.joined(separator: "、"))
                    .ffFont(.caption).foregroundStyle(T.muted)
            }
        }
        if let key, dict.raw.defs.m[key] != nil {
            NavigationLink(value: DictKey(k: key)) { content }
        } else {
            content
        }
    }
}


/// 台語: 通行 and every 腔口 with its reading; the one chosen in green, the others grey (the way 客語's accents are
/// shown); a reading the dictionary doesn't give (worked out by rule) is marked 推測
struct TwPlaceRows: View {
    let dict: Dict
    let key: String
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    var body: some View {
        // every 腔口 side by side (the name, its reading under it), wrapping onto more lines when needed
        if !dict.raw.places.isEmpty {
            FlowLayout(spacing: 10) {
                cell(-1)
                ForEach(dict.raw.places.indices, id: \.self) { p in cell(p) }
            }
        }
    }
    private func cell(_ p: Int) -> some View {
        let mine = p == place
        let guessed = p >= 0 && !dict.guessedSyllables(key, p).isEmpty
        let name = p < 0 ? trs("通行") : String(dict.raw.places[p].prefix(2))
        return VStack(alignment: .center, spacing: 2) {
            HStack(spacing: 3) {
                Chip(text: name, fill: mine ? T.twFill : T.fn, edge: mine ? T.twEdge : T.fnEdge, ink: mine ? T.twInk : T.muted)
                if guessed { Text(tr("推測")).ffFont(.caption2).foregroundStyle(T.muted) }
            }
            Text(dict.wordText(key, rom, p)).latFont(15).foregroundStyle(T.greenInk)
            if rom != 3 { Text(dict.wordText(key, 3, p)).ffFont(.caption).foregroundStyle(T.purpleInk) }
            if p >= 0 {
                ForEach(dict.alsoSaid(key, p), id: \.self) { x in
                    Text(tr("也講") + " " + dict.codes(x, rom, p)).ffFont(.caption2).foregroundStyle(T.muted)
                }
            }
        }
    }
}
