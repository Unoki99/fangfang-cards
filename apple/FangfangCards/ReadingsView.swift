import SwiftUI

// MARK: - 轉換 → 讀音: a word in 台語, 華語, 粵語 and 客語 side by side

/// the 華語 and 粵語 dictionaries for 讀音 (the one in use is the Store's; the other is read while the page is open)
@MainActor final class ReadingDicts: ObservableObject {
    @Published var zh: ZhDict?
    @Published var yue: ZhDict?
    @Published var hak: ZhDict?
    @Published var failed: [Int] = []
    private var started = false

    func load(_ store: Store) {
        if let d = store.zh { switch d.lang { case 2: yue = d; case 3: hak = d; case 4, 5: break; default: zh = d } }
        guard !started else { return }
        started = true
        for kind in [1, 2, 3] where [zh, zh, yue, hak][kind] == nil {
            Task.detached(priority: .userInitiated) { [weak self] in
                let d: ZhDict? = {
                    guard let url = DataFiles.url(["zh", "zh", "yue", "hak"][kind]),
                          let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
                    return try? ZhDict(data: data)
                }()
                await MainActor.run {
                    guard let self else { return }
                    if let d { switch kind { case 2: self.yue = d; case 3: self.hak = d; default: self.zh = d } } else { self.failed.append(kind) }
                }
            }
        }
    }
}

/// one row of the table: who says it (台語 purple, 華語 blue, 粵語 yellow), the reading (big, in tone colours) and
/// the other spelling (small)
private struct ReadingRow: Identifiable {
    let id = UUID()
    let lang: Int            // 0 台語, 1 華語, 2 粵語, 3 客語
    let label: String
    let main: AttributedString
    let other: String
    var note: String? = nil
}

struct ReadingsPane: View {
    @EnvironmentObject var store: Store
    @StateObject private var dicts = ReadingDicts()
    @AppStorage("readingsQuery") private var query = "學生"
    @AppStorage("rom") private var rom = 0
    @AppStorage("zhRom") private var zhRom = 0
    @AppStorage(Lang.yueRomKey) private var yueRom = 0
    @AppStorage(Lang.hakRomKey) private var hakRom = 0
    @AppStorage(ToneColors.key) private var toneSys = 0
    @AppStorage(ToneColors.versionKey) private var colorVersion = 0
    @AppStorage(Simp.key) private var simplified = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField(tr("漢字（詞或字），例如：學生、食飯、行"), text: $query)
                    .scaledFont(18)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .clearButton($query)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty { table(q) }
                Text(tr("台語照各地的讀音（教育部辭典寫的，或照規則推出來的）；華語分臺灣和大陸；粵語有幾個讀音就列幾個。詞典沒有這個詞的時候，照每個字的讀音排（「逐字」）。"))
                    .ffFont(.caption2).foregroundStyle(T.muted)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { dicts.load(store) }
    }

    // MARK: the table

    @ViewBuilder private func table(_ q: String) -> some View {
        let rows = taigiRows(q) + zhRows(q, kind: 1) + zhRows(q, kind: 2) + hakRows(q)
        let _ = colorVersion
        VStack(spacing: 0) {
            ForEach(rows) { r in
                HStack(spacing: 0) {
                    Text(r.label).ffFont(.subheadline, .bold).foregroundStyle(ink(r.lang))
                        .frame(width: labelWidth, alignment: .leading)
                        .padding(.vertical, 10)
                        .padding(.leading, 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.main).latFont(20).toneGlow()
                        if !r.other.isEmpty { Text(r.other).ffFont(.footnote).foregroundStyle(T.muted) }
                        if let n = r.note { Text(n).ffFont(.caption2).foregroundStyle(T.muted) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .overlay(alignment: .leading) { Rectangle().fill(edge(r.lang)).frame(width: 2) }   // (as thick as the border)
                }
                .background(fill(r.lang).opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(edge(r.lang), lineWidth: 2))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.top, 6)
            }
            if (dicts.zh == nil && !dicts.failed.contains(1)) || (dicts.yue == nil && !dicts.failed.contains(2))
                || (dicts.hak == nil && !dicts.failed.contains(3)) || store.dict == nil {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(tr("載入詞典…")).ffFont(.footnote).foregroundStyle(T.muted)
                }
                .padding(.top, 10)
            }
        }
    }

    private let labelWidth: CGFloat = 112
    private func fill(_ l: Int) -> Color { [T.twFill, T.blue, T.olive, T.hakFill, T.jaFill][min(l, 4)] }
    private func edge(_ l: Int) -> Color { [T.twEdge, T.blueEdge, T.oliveEdge, T.hakEdge, T.jaEdge][min(l, 4)] }
    private func ink(_ l: Int) -> Color { [T.twInk, T.blueInk, T.oliveInk, T.hakInk, T.jaInk][min(l, 4)] }

    // MARK: 客語: each accent (the ones that read it the same together)

    private func hakRows(_ q: String) -> [ReadingRow] {
        guard let d = dicts.hak else { return [] }
        let es = (d.byHan[q] ?? []).map { d.entries[$0] }.filter { $0.h == q }
        var out: [ReadingRow] = []
        for (n, e) in es.prefix(3).enumerated() {
            let alt = n > 0 ? "（" + trs("又") + "）" : ""
            let acc = e.acc ?? [e.tw]
            // the accents with the same reading (letters and tone category) in one row
            var groups: [(key: String, syl: [String], names: [String])] = []
            for (a, syl) in acc.enumerated() {
                guard let syl else { continue }
                let key = syl.map { let p = Zhuyin.hakParts($0); return p.letters + String(p.tone) }.joined(separator: " ")
                let name = trs(a < Lang.hakAccents.count ? Lang.hakAccents[a] : "")
                if let i = groups.firstIndex(where: { $0.key == key }) { groups[i].names.append(name) }
                else { groups.append((key, syl, [name])) }
            }
            for g in groups {
                out.append(ReadingRow(lang: 3, label: trs("客") + "・" + g.names.joined(separator: "、") + alt, main: d.reading(g.syl, hakRom),
                                      other: d.readingPlain(g.syl, 1 - hakRom)))
            }
        }
        if out.isEmpty {
            out.append(ReadingRow(lang: 3, label: trs("客語"), main: AttributedString("—"), other: "", note: tr("客語詞典沒有這個詞")))
        }
        return out
    }

    // MARK: 台語: 通行, then the places that say it another way

    private func taigiRows(_ q0: String) -> [ReadingRow] {
        guard let d = store.dict else { return [] }
        let q = Simp.convertBack(q0, in: d)
        let colours = toneSys != 0
        var out: [ReadingRow] = []
        let codesList = d.hanMap[q] ?? []
        if codesList.isEmpty {
            // not a word of the dictionary: each character's first reading
            let cs = q.map { d.hanMap[String($0)]?.first }
            if !q.isEmpty, cs.allSatisfy({ $0 != nil }) {
                let codes = cs.compactMap { $0 }.joined(separator: " ")
                out.append(ReadingRow(lang: 0, label: trs("台語") + "・" + trs("通行"), main: AttributedString(d.codes(codes, rom, -1)),
                                      other: d.codes(codes, 3, -1), note: tr("逐字")))
            } else {
                out.append(ReadingRow(lang: 0, label: trs("台語"), main: AttributedString("—"), other: "", note: tr("台語詞典沒有這個詞")))
            }
            return out
        }
        for (n, codes) in codesList.prefix(4).enumerated() {
            let key = q + "\t" + codes
            let alt = n > 0 ? "（" + trs("又") + "）" : ""
            out.append(ReadingRow(lang: 0, label: trs("臺") + "・" + trs("通行") + alt, main: d.wordText(key, rom, -1),
                                  other: String(d.wordText(key, 3, -1).characters)))
            // the places that say it differently (or, with tone colours, change its tones differently)
            var groups: [(codes: String, tones: [Int], places: [Int])] = []
            for p in d.raw.places.indices {
                let c = d.differsFromCommon(key, p) ? d.codesFor(key, p) : Dict.codesOf(key)
                let t = colours ? d.wordTones(key, p) : []
                if c == Dict.codesOf(key) && (!colours || t == d.wordTones(key, -1)) { continue }
                if let i = groups.firstIndex(where: { $0.codes == c && $0.tones == t }) { groups[i].places.append(p) }
                else { groups.append((c, t, [p])) }
            }
            for g in groups {
                let names = g.places.map { trs(String(d.raw.places[$0].prefix(2))) }.joined(separator: "、")
                let shownIn = g.codes == Dict.codesOf(key) ? -1 : g.places[0]
                out.append(ReadingRow(lang: 0, label: trs("臺") + "・" + names,
                                      main: d.wordText(key, rom, shownIn, tonesIn: g.places[0]),
                                      other: String(d.wordText(key, 3, shownIn, tonesIn: g.places[0]).characters),
                                      note: d.guessedSyllables(key, g.places[0]).isEmpty ? nil : tr("推測")))
            }
        }
        return out
    }

    // MARK: 華語 (臺灣, 大陸) and 粵語

    private func zhRows(_ q: String, kind: Int) -> [ReadingRow] {
        let lang = kind
        guard let d = kind == 2 ? dicts.yue : dicts.zh else { return [] }
        let mode = kind == 2 ? yueRom : zhRom
        let es = (d.byHan[q] ?? []).map { d.entries[$0] }.filter { $0.h == q || $0.alt == q }
        // (the same reading once: 華語 has a word several times for its meanings)
        var seen = Set<[String]>()
        var out: [ReadingRow] = []
        for e in es where seen.insert(e.tw).inserted {
            let n = out.count
            let alt = n > 0 ? "（" + trs("又") + "）" : ""
            if kind == 1 {
                out.append(ReadingRow(lang: lang, label: trs("國語") + alt, main: d.reading(e.tw, mode),
                                      other: d.readingPlain(e.tw, 1 - mode)))
                if let lu = e.lu, lu != e.tw {
                    out.append(ReadingRow(lang: lang, label: trs("普通話") + alt, main: d.reading(lu, mode),
                                          other: d.readingPlain(lu, 1 - mode)))
                }
                if let sc = e.sc {
                    out.append(ReadingRow(lang: lang, label: trs("四川話") + (e.scKind == 1 ? "（" + trs("推算") + "）" : (e.scKind == 2 ? "（" + trs("預測") + "）" : "")) + alt, main: d.reading(sc, mode), other: ""))
                }
            } else {
                out.append(ReadingRow(lang: lang, label: trs("粵語") + alt, main: d.reading(e.tw, mode),
                                      other: d.readingPlain(e.tw, 1 - mode)))
            }
            if out.count >= 6 { break }
        }
        if out.isEmpty {
            // not a word of the dictionary: each character's usual reading
            var syl: [String] = []
            for c in q {
                guard let i = (d.byHan[String(c)] ?? []).first(where: { d.entries[$0].h == String(c) || d.entries[$0].alt == String(c) }),
                      let s = d.entries[i].tw.first else { syl = []; break }
                syl.append(s)
            }
            if !syl.isEmpty {
                out.append(ReadingRow(lang: lang, label: kind == 2 ? trs("粵語") : trs("華語"), main: d.reading(syl, mode),
                                      other: d.readingPlain(syl, 1 - mode), note: tr("逐字")))
            } else {
                out.append(ReadingRow(lang: lang, label: kind == 2 ? trs("粵語") : trs("華語"), main: AttributedString("—"), other: "",
                                      note: kind == 2 ? tr("粵語詞典沒有這個詞") : tr("華語詞典沒有這個詞")))
            }
        }
        return out
    }
}

extension Simp {
    /// a word typed in 簡體: the 台語 dictionary's 正體 one (each character the 正體 one the 台語 dictionary has)
    static func convertBack(_ s: String, in d: Dict) -> String {
        if d.hanMap[s] != nil { return s }
        return String(s.map { ch in
            if d.hanMap[String(ch)] != nil { return ch }
            return reverse(ch) ?? ch
        })
    }
}
