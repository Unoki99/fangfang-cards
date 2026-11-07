import SwiftUI

// MARK: - 華語 character cards: a character with its meanings from 教育部《重編國語辭典修訂本》

/// a character's page (from a character card): every reading with its meanings, the words with it, and the
/// card's buttons
struct ZhCharView: View {
    let dict: ZhDict
    let ch: String
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            if let i = dict.charIndex[ch] {
                ZhCharBody(dict: dict, char: dict.chars[i])
                    .padding()
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
            } else {
                Text(tr("找不到這個字。")).foregroundStyle(T.muted).padding()
            }
        }
        .appBackground()
        .navigationTitle(ch)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
    }
}

/// the same in a sheet from the bottom
struct ZhCharSheet: View {
    let dict: ZhDict
    let ch: String
    /// the dictionary's entry for a character, read its usual way
    static func entry(_ dict: ZhDict, _ ch: String) -> ZhEntry? {
        let zy = dict.charIndex[ch].map { dict.chars[$0].readings.first?.zy ?? "" } ?? ""
        return dict.entry(char: ch, zy: zy)
    }
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                // straight to the 兩岸 dictionary's entry for the usual reading (with the character card's buttons
                // and 《重編國語辭典》 at the bottom), not a page that only leads to it
                if let e = ZhCharSheet.entry(dict, ch) {
                    ZhEntryView(dict: dict, key: e.k)
                } else {
                    ZhCharView(dict: dict, ch: ch)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
            .navigationDestination(for: ZhKey.self) { ZhEntryView(dict: dict, key: $0.k) }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .presentationDragIndicator(.visible)
    }
}

struct ZhCharBody: View {
    let dict: ZhDict
    let char: ZhChar
    @EnvironmentObject var store: Store

    private var key: String { Lang.charKey(char.h) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 14) {
                    Text(dict.hanText(char.h, [char.readings[0].zy], base: T.glyph)).scaledFont(64, weight: .semibold).toneGlow()
                    PlayButton(path: "tts:" + char.h)
                    Spacer()
                }
                HStack(spacing: 8) {
                    let st = store.cardStatus(key) ?? 0
                    if st == 1 {
                        Chip(text: tr("卡片：熟悉"), fill: T.green, edge: T.greenEdge, ink: T.greenInk)
                    } else {
                        Button { withAnimation(.snappy) { store.toggleUnknown(key) } } label: {
                            Label(st == 2 ? trs("在「不熟」") : trs("加到「不熟」"), systemImage: st == 2 ? "star.fill" : "star")
                                .ffFont(.subheadline, .semibold)
                                .foregroundStyle(st == 2 ? T.rustInk : T.glyph)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(st == 2 ? T.rust : T.fn.opacity(0.8)))
                                .overlay(Capsule().stroke(st == 2 ? T.rustEdge : T.fnEdge, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                    let known = store.zhCharSets().known.contains(char.h)
                    if known { Chip(text: tr("在熟悉的詞裡"), fill: T.blue, edge: T.blueEdge, ink: T.blueInk) }
                }
                HStack(spacing: 6) {
                    if char.hsk > 0 { Chip(text: tr("漢字 ") + Lang.hskName(char.hsk), fill: T.green, edge: T.greenEdge, ink: T.greenInk) }
                    if char.tocfl > 0 { Chip(text: tr("漢字 ") + UILang.label(Lang.levelName(1, char.tocfl)), fill: T.blue, edge: T.blueEdge, ink: T.blueInk) }
                    if let r = char.radical { Text(tr("部首 \(r)")).ffFont(.footnote).foregroundStyle(T.muted) }
                    if let n = char.strokes { Text(tr("\(n) 畫")).ffFont(.footnote).foregroundStyle(T.muted) }
                }
                InputCodesRow(han: char.h)
            }
            ForEach(Array(char.readings.enumerated()), id: \.offset) { _, r in reading(r) }
            words
            Text(tr("資料：教育部《重編國語辭典修訂本》（CC BY-ND 3.0 TW），g0v 萌典整理。只收字的解釋和用例，引用的古書省略。"))
                .ffFont(.caption2).foregroundStyle(T.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reading(_ r: ZhChar.Reading) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(dict.reading([r.zy], store.zhRom)).latFont(22).toneGlow().foregroundStyle(T.greenInk)
                Text(dict.reading([r.zy], store.zhRom == 0 ? 1 : 0)).ffFont(.subheadline).foregroundStyle(T.purpleInk)
                if let l = r.label { Chip(text: l, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                Spacer(minLength: 4)
                // the 兩岸 dictionary's entry for the character read this way
                if let e = dict.entry(char: char.h, zy: r.zy), e.tw.first == r.zy {
                    NavigationLink(value: ZhKey(k: e.k)) {
                        Label(tr("詞典"), systemImage: "character.book.closed").ffFont(.caption, .semibold).foregroundStyle(T.oliveInk)
                    }
                }
            }
            ForEach(Array(r.defs.enumerated()), id: \.offset) { i, d in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(i + 1).").ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                    if !d.pos.isEmpty { Chip(text: d.pos, fill: T.fn, edge: T.fnEdge, ink: T.muted) }
                    Text(d.text).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    /// the cards' words with this character (the word list's, in order)
    @ViewBuilder private var words: some View {
        let ws = Array(store.cards.lazy.filter { Lang.charOf($0.k) == nil && $0.h.count > 1 && $0.h.contains(char.h) }.prefix(40))
        if !ws.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("有這個字的詞")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                FlowLayout(spacing: 6) {
                    ForEach(ws, id: \.k) { c in
                        NavigationLink(value: ZhKey(k: c.k)) {
                            HStack(spacing: 4) {
                                Text(c.h).foregroundStyle(statusInk(c))
                                Text(store.cardRom(c, 0, -1)).latFont(12).foregroundStyle(T.greenInk.opacity(0.85))
                            }
                            .ffFont(.subheadline)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(T.fn.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func statusInk(_ c: Card) -> Color {
        switch store.status(c) {
        case 1?: return Color(hex: 0x6eaaff)
        case 2?: return Color(hex: 0xffa94d)
        default: return T.glyph
        }
    }
}

/// a character's card (漢字卡): 加到「不熟」/ 在「不熟」/ 熟悉, and its 部首 and strokes; in its dictionary entry
struct ZhCharCardRow: View {
    let dict: ZhDict
    let ch: String
    @EnvironmentObject var store: Store
    var body: some View {
        if let i = dict.charIndex[ch] {
            let char = dict.chars[i]
            let key = Lang.charKey(ch)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    let st = store.cardStatus(key) ?? 0
                    if st == 1 {
                        Chip(text: tr("漢字卡：熟悉"), fill: T.green, edge: T.greenEdge, ink: T.greenInk)
                    } else {
                        Button { withAnimation(.snappy) { store.toggleUnknown(key) } } label: {
                            Label(st == 2 ? trs("漢字卡在「不熟」") : trs("漢字卡加到「不熟」"), systemImage: st == 2 ? "star.fill" : "star")
                                .ffFont(.subheadline, .semibold)
                                .foregroundStyle(st == 2 ? T.rustInk : T.glyph)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(Capsule().fill(st == 2 ? T.rust : T.fn.opacity(0.8)))
                                .overlay(Capsule().stroke(st == 2 ? T.rustEdge : T.fnEdge, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 6) {
                    if char.hsk > 0 { Chip(text: tr("漢字 ") + Lang.hskName(char.hsk), fill: T.green, edge: T.greenEdge, ink: T.greenInk) }
                    if char.tocfl > 0 { Chip(text: tr("漢字 ") + UILang.label(Lang.levelName(1, char.tocfl)), fill: T.blue, edge: T.blueEdge, ink: T.blueInk) }
                    if let r = char.radical { Text(tr("部首 \(r)")).ffFont(.footnote).foregroundStyle(T.muted) }
                    if let n = char.strokes { Text(tr("\(n) 畫")).ffFont(.footnote).foregroundStyle(T.muted) }
                }
            }
        }
    }
}

// MARK: - 學習進度 → 認識的漢字: every character, and which you know

struct ZhCharListView: View {
    @EnvironmentObject var store: Store
    @State private var filter = 0        // 0 all, 1 熟悉, 2 不熟, 3 not seen
    @State private var open: CharRef?
    @State private var query = ""

    struct CharRef: Identifiable { let ch: String; var id: String { ch } }

    var body: some View {
        let sets = store.zhCharSets()
        let shown = sets.all.filter { ch in
            switch filter {
            case 1: return sets.known.contains(ch)
            case 2: return sets.unknown.contains(ch)
            case 3: return !sets.known.contains(ch) && !sets.unknown.contains(ch)
            default: return true
            }
        }.filter { query.isEmpty || query.contains($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SplitPotionBar(known: sets.all.isEmpty ? 0 : Double(sets.known.count) / Double(sets.all.count),
                               unknown: sets.all.isEmpty ? 0 : Double(sets.unknown.count) / Double(sets.all.count), label: trs("認識的漢字"))
                Picker("", selection: $filter) {
                    Text(tr("全部 \(sets.all.count)")).tag(0)
                    Text(tr("熟悉 \(sets.known.count)")).tag(1)
                    Text(tr("不熟 \(sets.unknown.count)")).tag(2)
                    Text(tr("沒看過")).tag(3)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(T.muted)
                    TextField(tr("找字，例如：愛"), text: $query)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .clearButton($query)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                if !query.isEmpty && shown.isEmpty {
                    Text(tr("這裡沒有「\(query)」。")).ffFont(.footnote).foregroundStyle(T.muted)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                    ForEach(shown, id: \.self) { ch in
                        let k = sets.known.contains(ch), u = sets.unknown.contains(ch)
                        Text(ch).scaledFont(24)
                            .foregroundStyle(k ? Color(hex: 0xcfe2ff) : (u ? Color(hex: 0xffe1c2) : T.glyph))
                            .frame(width: 46, height: 46)
                            .background(RoundedRectangle(cornerRadius: 10).fill(k ? Color(hex: 0x4f7dff).opacity(0.35)
                                                                               : (u ? Color(hex: 0xffa94d).opacity(0.3) : T.fn.opacity(0.7))))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(k ? Color(hex: 0x6eaaff) : (u ? Color(hex: 0xffa94d) : T.fnEdge), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            // hold: 熟悉 ⇄ 不熟 (its character card); tap: open it
                            .onLongPressGesture(minimumDuration: 0.4) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.snappy) { _ = store.setCharKnown(ch, !k) }
                            }
                            .onTapGesture { open = CharRef(ch: ch) }
                            .accessibilityElement()
                            .accessibilityLabel(ch + (k ? trs("，熟悉") : (u ? trs("，不熟") : "")))
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction { open = CharRef(ch: ch) }
                            .accessibilityAction(named: k ? trs("標成不熟") : trs("標成熟悉")) { _ = store.setCharKnown(ch, !k) }
                    }
                }
                Text(tr("按住一個字可以在熟悉和不熟之間換。藍色 = 熟悉（在熟悉的詞裡，或漢字卡往右滑；熟悉的詞裡的字，漢字卡也會自動標成熟悉）；橘色 = 不熟（只在不熟的詞或漢字卡裡）；沒有顏色 = 還沒看過。這裡是所有可以滑的卡片裡的字（詞卡和漢字卡，每個字只算一次），照卡片的順序排。點一個字看它的意思和有這個字的詞。"))
                    .ffFont(.caption).foregroundStyle(T.muted)
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle(tr("認識的漢字"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $open) { r in
            if let z = store.zh { ZhCharOrWordSheet(dict: z, ch: r.ch).environmentObject(store) }
        }
    }
}

/// a character from the list: its character card's page, or (a rare one without a card) its dictionary entry
struct ZhCharOrWordSheet: View {
    let dict: ZhDict
    let ch: String
    var body: some View {
        if dict.charIndex[ch] != nil {
            ZhCharSheet(dict: dict, ch: ch)
        } else if let e = dict.entry(char: ch, zy: "") {
            ZhEntrySheet(dict: dict, key: e.k)
        } else {
            Text(tr("找不到這個字。")).foregroundStyle(T.muted).padding()
        }
    }
}
