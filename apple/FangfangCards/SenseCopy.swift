import SwiftUI

/// Copying one meaning of a word to the clipboard, in a layout set in 設定 (複製意思的格式).
enum SenseCopy {
    static let tplKey = "senseCopyTpl"
    static let exKey = "senseCopyExTpl"
    static let sepKey = "senseCopySep"
    static let presetKey = "senseCopyPreset"

    struct Preset { let name: String; let tpl: String; let ex: String; let sep: Int }
    static let presets: [Preset] = [
        Preset(name: "簡單",
               tpl: "{漢字}　{羅馬字}　{方音}\n{號}. 〔{詞類}〕{意思}\n{所有例句}",
               ex: "・{例句}\n　{例句羅馬字}\n　{例句華語}", sep: 0),
        Preset(name: "Discord",
               tpl: "## {漢字}\n**{羅馬字}**　{方音}\n> {號}. *{詞類}* {意思}\n{所有例句}",
               ex: "- {例句}\n  {例句羅馬字}\n  -# {例句華語}", sep: 0),
        Preset(name: "一行（Tab 分開）",
               tpl: "{漢字}\t{羅馬字}\t{方音}\t{詞類}\t{意思}\t{所有例句}\t{詞音檔}",
               ex: "{例句}（{例句羅馬字}）{例句華語}", sep: 2),
    ]
    static let seps = ["換行", "空一行", "<br>", "；"]
    private static let sepText = ["\n", "\n\n", "<br>", "；"]

    static let wordTokens = ["{漢字}", "{羅馬字}", "{皓羅}", "{台羅}", "{白話字}", "{方音}", "{華語}", "{號}", "{詞類}", "{意思}", "{詞音檔}", "{所有例句}"]
    static let exTokens = ["{例句}", "{例句羅馬字}", "{例句皓羅}", "{例句台羅}", "{例句白話字}", "{例句方音}", "{例句華語}", "{例句音檔}"]

    static var tpl: String { UserDefaults.standard.string(forKey: tplKey) ?? presets[0].tpl }
    static var exTpl: String { UserDefaults.standard.string(forKey: exKey) ?? presets[0].ex }
    static var sep: Int { UserDefaults.standard.object(forKey: sepKey) as? Int ?? presets[0].sep }

    // 華語: a layout of its own (設定 → 詞典 → 複製意思的格式（華語）)
    static let zhTplKey = "zh.senseCopyTpl"
    static let zhExKey = "zh.senseCopyExTpl"
    static let zhSepKey = "zh.senseCopySep"
    static let zhPresets: [Preset] = [
        Preset(name: "簡單",
               tpl: "{漢字}　{羅馬字}　{注音}\n{號}. 〔{詞類}〕{意思}\n{英文}\n{所有例句}",
               ex: "・{例句}\n　{例句羅馬字}\n　{例句出處}", sep: 0),
        Preset(name: "Discord",
               tpl: "## {漢字}\n**{羅馬字}**　{注音}\n> {號}. *{詞類}* {意思}\n> {英文}\n{所有例句}",
               ex: "- {例句}\n  {例句羅馬字}\n  -# {例句出處}", sep: 0),
        Preset(name: "一行（Tab 分開）",
               tpl: "{漢字}\t{拼音}\t{注音}\t{詞類}\t{意思}\t{英文}\t{所有例句}",
               ex: "{例句}（{例句拼音}）", sep: 2),
    ]
    static let zhWordTokens = ["{漢字}", "{簡體}", "{羅馬字}", "{拼音}", "{注音}", "{號}", "{詞類}", "{意思}", "{英文}", "{英文列表}", "{所有例句}"]
    static let zhExTokens = ["{例句}", "{例句羅馬字}", "{例句拼音}", "{例句注音}", "{例句出處}"]
    static var zhTpl: String { UserDefaults.standard.string(forKey: zhTplKey) ?? zhPresets[0].tpl }
    static var zhExTpl: String { UserDefaults.standard.string(forKey: zhExKey) ?? zhPresets[0].ex }
    static var zhSep: Int { UserDefaults.standard.object(forKey: zhSepKey) as? Int ?? zhPresets[0].sep }

    /// the name of the layout chosen (or 自訂)
    static func styleName(zh: Bool) -> String {
        let (t, e, sp) = zh ? (zhTpl, zhExTpl, zhSep) : (tpl, exTpl, sep)
        return (zh ? zhPresets : presets).first { $0.tpl == t && $0.ex == e && $0.sep == sp }.map { trs($0.name) } ?? trs("自訂")
    }

    /// fills a template. An empty value takes the brackets or ** around it along with it,
    /// and a line left with nothing on it is dropped.
    static func fill(_ t: String, _ v: [String: String]) -> String {
        var out: [String] = []
        for line in t.components(separatedBy: "\n") {
            var s = line
            for (k, val) in v where s.contains(k) {
                if val.isEmpty {
                    let esc = NSRegularExpression.escapedPattern(for: k)
                    s = s.replacingOccurrences(of: "[〔（(\\[「*_~]*" + esc + "[〕）)\\]」*_~]*", with: "", options: .regularExpression)
                } else {
                    s = s.replacingOccurrences(of: k, with: val)
                }
            }
            // a line that only had empty values on it goes; a line left blank on purpose stays
            if s != line && s.trimmingCharacters(in: CharacterSet(charactersIn: " \t　-#>*_・.。:：")).isEmpty { continue }
            out.append(s)
        }
        return out.joined(separator: "\n")
    }

    static func text(_ d: Dict, key: String, sense i: Int, rom: Int, place: Int,
                     tpl: String = SenseCopy.tpl, exTpl: String = SenseCopy.exTpl, sep: Int = SenseCopy.sep) -> String {
        let all = d.senses(key)
        guard i >= 0, i < all.count else { return "" }
        let m = all[i]
        let r = min(max(rom, 0), 2)
        let han = Dict.hanOf(key)
        let exs: [String] = m.ex.map { x in
            let tp = x.count > 1 ? x[1] : ""
            func s(_ sys: Int) -> String { tp.isEmpty ? "" : d.sentence(tp, sys, place: place, han: x[0]) }
            return fill(exTpl, [
                "{例句羅馬字}": s(r), "{例句皓羅}": s(0), "{例句台羅}": s(1), "{例句白話字}": s(2), "{例句方音}": s(3),
                "{例句華語}": x.count > 2 ? x[2] : "", "{例句音檔}": x.count > 3 ? x[3] : "", "{例句}": x[0],
            ])
        }
        let joined = exs.joined(separator: sepText[min(max(sep, 0), sepText.count - 1)])
        let gl = (d.gl[key] ?? []).map(\.t).joined(separator: "、")
        var v: [String: String] = [
            "{羅馬字}": d.word(key, r, place), "{皓羅}": d.word(key, 0, place), "{台羅}": d.word(key, 1, place),
            "{白話字}": d.word(key, 2, place), "{方音}": d.word(key, 3, place), "{華語}": gl,
            "{號}": "\(m.n)", "{詞類}": m.pos, "{意思}": m.text,
            "{詞音檔}": d.raw.au[key].map { "\($0)(1)" } ?? "",
            "{所有例句}": joined, "{漢字}": han,
        ]
        // the sentences are put in last, so what they contain is never read as a token
        let body = v.removeValue(forKey: "{所有例句}")!
        var out = fill(tpl, v)
        if out.contains("{所有例句}") {
            out = body.isEmpty
                ? fill(out, ["{所有例句}": ""])
                : out.replacingOccurrences(of: "{所有例句}", with: body)
        } else if !body.isEmpty {
            out += "\n" + body
        }
        return out
    }
}

/// the copy button on a meaning in the dictionary
struct SenseCopyButton: View {
    let dict: Dict
    let key: String
    let sense: Int
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @State private var done = false
    var body: some View {
        Button {
            UIPasteboard.general.string = SenseCopy.text(dict, key: key, sense: sense, rom: rom, place: place)
            withAnimation(.snappy) { done = true }
            Task { try? await Task.sleep(nanoseconds: 1_200_000_000); withAnimation(.snappy) { done = false } }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc")
                .ffFont(.subheadline, .semibold)
                .foregroundStyle(done ? T.greenInk : T.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(done ? T.green : T.fn.opacity(0.8)))
                .overlay(Circle().stroke(done ? T.greenEdge : T.fnEdge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? trs("已複製") : trs("複製這個意思"))
    }
}

/// 設定 → 複製意思的格式 (台語 or 華語: each has its own)
struct SenseCopySettings: View {
    var zh = false
    @EnvironmentObject var store: Store
    @AppStorage(SenseCopy.tplKey) private var twTpl = SenseCopy.presets[0].tpl
    @AppStorage(SenseCopy.exKey) private var twEx = SenseCopy.presets[0].ex
    @AppStorage(SenseCopy.sepKey) private var twSep = SenseCopy.presets[0].sep
    @AppStorage(SenseCopy.zhTplKey) private var zhTpl = SenseCopy.zhPresets[0].tpl
    @AppStorage(SenseCopy.zhExKey) private var zhEx = SenseCopy.zhPresets[0].ex
    @AppStorage(SenseCopy.zhSepKey) private var zhSep = SenseCopy.zhPresets[0].sep
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1

    private var tpl: Binding<String> { zh ? $zhTpl : $twTpl }
    private var exTpl: Binding<String> { zh ? $zhEx : $twEx }
    private var sep: Binding<Int> { zh ? $zhSep : $twSep }
    private var presets: [SenseCopy.Preset] { zh ? SenseCopy.zhPresets : SenseCopy.presets }

    private var sample: (key: String, sense: Int)? {
        if zh {
            if let s = store.savedSenses.first(where: { Lang.isZhKey($0.key) && Lang.charOf($0.key) == nil }) { return (s.key, s.sense) }
            guard let d = store.zh else { return nil }
            for h in ["吃飯", "吃", "走"] { if let i = d.usual(h) { return (d.entries[i].k, 0) } }
            return nil
        }
        if let s = store.savedSenses.first(where: { !Lang.isZhKey($0.key) }) { return (s.key, s.sense) }
        guard let d = store.dict else { return nil }
        for h in ["食飯", "食", "行"] {
            if let k = d.raw.defs.m.keys.first(where: { Dict.hanOf($0) == h }) { return (k, 0) }
        }
        return nil
    }

    var body: some View {
        Form {
            Section(tr("樣式")) {
                ForEach(Array(presets.enumerated()), id: \.offset) { _, p in
                    Button {
                        tpl.wrappedValue = p.tpl; exTpl.wrappedValue = p.ex; sep.wrappedValue = p.sep
                    } label: {
                        HStack {
                            Text(trs(p.name)).foregroundStyle(T.glyph)
                            Spacer()
                            if tpl.wrappedValue == p.tpl && exTpl.wrappedValue == p.ex && sep.wrappedValue == p.sep {
                                Image(systemName: "checkmark").foregroundStyle(T.greenInk)
                            }
                        }
                    }
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section {
                TextEditor(text: tpl)
                    .ffFont(.footnote, mono: true)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .clearButton(tpl, editor: true)
                tokenRow(zh ? SenseCopy.zhWordTokens : SenseCopy.wordTokens) { tpl.wrappedValue += $0 }
            } header: {
                Text(tr("整個意思"))
            } footer: {
                Text(tr("{所有例句} 是例句放的位置（沒寫就放在最後）。值是空的時候，旁邊的括號或 ** 也會一起拿掉。點下面的名字可以加到最後面。")
                     + (zh ? trs("{英文} 是英文解釋（用 ; 分開），{英文列表} 是一行一個、有編號。") : ""))
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section {
                TextEditor(text: exTpl)
                    .ffFont(.footnote, mono: true)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .clearButton(exTpl, editor: true)
                tokenRow(zh ? SenseCopy.zhExTokens : SenseCopy.exTokens) { exTpl.wrappedValue += $0 }
                Picker(tr("例句跟例句中間"), selection: sep) {
                    ForEach(0..<SenseCopy.seps.count, id: \.self) { Text(SenseCopy.seps[$0]).tag($0) }
                }
            } header: {
                Text(tr("每個例句"))
            } footer: {
                Text((zh ? trs("{羅馬字} 和 {例句羅馬字} 跟著上面選的拼音或注音；也可以直接用 {拼音}、{注音}。")
                         : trs("{羅馬字} 和 {例句羅馬字} 跟著設定裡選的羅馬字；也可以直接用 {皓羅}、{台羅}、{白話字}。"))
                     + trs("Discord 看得懂 **粗體**、*斜體*、## 標題、> 引用、- 清單、-# 小字。"))
            }
            .listRowBackground(T.fn.opacity(0.7))
            Section(tr("預覽")) {
                if let s = sample, let text = preview(s) {
                    Text(text)
                        .ffFont(.footnote, mono: true)
                        .foregroundStyle(T.glyph)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(tr("詞典載入中…")).foregroundStyle(T.muted)
                }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(zh ? trs("複製意思的格式（華語）") : trs("複製意思的格式（台語）"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if zh { store.preloadZh() } else { store.loadDict() } }
    }

    private func preview(_ s: (key: String, sense: Int)) -> String? {
        if zh {
            guard let d = store.zh else { return nil }
            return SenseCopy.zhText(d, key: s.key, sense: s.sense, rom: store.zhRom, place: store.zhPlace,
                                    tpl: tpl.wrappedValue, exTpl: exTpl.wrappedValue, sep: sep.wrappedValue)
        }
        guard let d = store.dict else { return nil }
        return SenseCopy.text(d, key: s.key, sense: s.sense, rom: rom, place: place,
                              tpl: tpl.wrappedValue, exTpl: exTpl.wrappedValue, sep: sep.wrappedValue)
    }

    private func tokenRow(_ tokens: [String], add: @escaping (String) -> Void) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(tokens, id: \.self) { t in
                Button { add(t) } label: {
                    Text(t).ffFont(.caption).foregroundStyle(T.oliveInk)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(T.fn))
                        .overlay(Capsule().stroke(T.fnEdge, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 華語 meanings

extension SenseCopy {
    /// a 華語 meaning, in the 華語 layout: {羅馬字} = 拼音 or 注音 as shown, {拼音}, {注音}, {英文}, {詞類} (from the word
    /// lists). The 台語 names still work ({方音} = 注音, {皓羅}/{台羅}/{白話字} = 拼音, {例句華語} = where it's from).
    static func zhText(_ d: ZhDict, key: String, sense i: Int, rom: Int, place: Int,
                       tpl: String = SenseCopy.zhTpl, exTpl: String = SenseCopy.zhExTpl, sep: Int = SenseCopy.zhSep) -> String {
        guard let e = d.entry(key), i >= 0, i < e.senses.count else { return "" }
        let m = e.senses[i]
        let syl = e.syl(place)
        let exs: [String] = m.ex.map { x in
            let ps = ZhDict.pieces(x)
            func s(_ mode: Int) -> String { String(d.sentence(ps, mode, place, colours: 0).characters) }
            let py = s(0), zy = s(1)
            return fill(exTpl, [
                "{例句羅馬字}": s(rom), "{例句拼音}": py, "{例句注音}": zy, "{例句出處}": x.src,
                "{例句皓羅}": py, "{例句台羅}": py, "{例句白話字}": py, "{例句方音}": zy,
                "{例句華語}": x.src, "{例句音檔}": "", "{例句}": x.h,
            ])
        }
        let joined = exs.joined(separator: sepText[min(max(sep, 0), sepText.count - 1)])
        let py = d.readingPlain(syl, 0), zy = d.readingPlain(syl, 1)
        let ens = e.enList
        let v: [String: String] = [
            "{羅馬字}": d.readingPlain(syl, rom), "{拼音}": py, "{注音}": zy, "{皓羅}": py, "{台羅}": py, "{白話字}": py,
            "{方音}": zy, "{華語}": "", "{簡體}": e.alt.flatMap { $0 == e.h ? nil : $0 } ?? "",
            "{號}": "\(m.n)", "{詞類}": e.pos.joined(separator: "、"), "{意思}": m.text, "{詞音檔}": "",
            "{英文列表}": ens.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
            "{英文}": ens.joined(separator: "; "), "{漢字}": e.h,
        ]
        var out = fill(tpl, v)
        if out.contains("{所有例句}") {
            out = joined.isEmpty ? fill(out, ["{所有例句}": ""]) : out.replacingOccurrences(of: "{所有例句}", with: joined)
        } else if !joined.isEmpty {
            out += "\n" + joined
        }
        return out
    }
}

/// the copy button on a 華語 meaning
struct ZhSenseCopyButton: View {
    let dict: ZhDict
    let key: String
    let sense: Int
    @EnvironmentObject var store: Store
    @State private var done = false
    var body: some View {
        Button {
            UIPasteboard.general.string = SenseCopy.zhText(dict, key: key, sense: sense, rom: store.zhRom, place: store.zhPlace)
            withAnimation(.snappy) { done = true }
            Task { try? await Task.sleep(nanoseconds: 1_200_000_000); withAnimation(.snappy) { done = false } }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc")
                .ffFont(.subheadline, .semibold)
                .foregroundStyle(done ? T.greenInk : T.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(done ? T.green : T.fn.opacity(0.8)))
                .overlay(Circle().stroke(done ? T.greenEdge : T.fnEdge, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? trs("已複製") : trs("複製這個意思"))
    }
}
