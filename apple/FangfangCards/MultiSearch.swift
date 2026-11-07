import SwiftUI

// Searching several words at once: 陰謀論 (not a word) → 陰謀 + 論, or typed with spaces: 陰謀 論.

/// the rainbow the app uses for things that need a colour each (red, orange, yellow, green, teal, blue, purple, pink),
/// from the colours in 選聲調顏色
enum Rainbow {
    private static let columns = [1, 2, 3, 4, 5, 6, 7, 0]
    static func shades(_ i: Int) -> [UInt32] { ToneColors.palette[columns[((i % columns.count) + columns.count) % columns.count]].shades }
    /// the fill, edge and text colours of a capsule
    static func fill(_ i: Int) -> Color { Color(hex: shades(i)[4]) }
    static func edge(_ i: Int) -> Color { Color(hex: shades(i)[2]) }
    static func ink(_ i: Int) -> Color { Color(hex: shades(i)[0]) }
}

enum Segmenter {
    /// the words a search is made of, or nil when it's one search:
    /// - 漢字 typed with spaces between them (羅馬字 with spaces is one word: tsiah png)
    /// - 漢字 that aren't a word, split into the longest words from the left (isWord says what's a word)
    static func parts(_ q0: String, maxLen: Int = 8, isWord: (String) -> Bool) -> [String]? {
        let q = q0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !q.contains(where: { "*＊?？".contains($0) }) else { return nil }
        let latin = q.unicodeScalars.contains { ConvertEngine.isLatinLetter($0.value) || ConvertEngine.isZy($0.value) || ("0"..."9").contains(Character($0)) }
        let spaced = q.split(whereSeparator: { $0 == " " || $0 == "　" || $0 == "," || $0 == "，" || $0 == "、" }).map(String.init)
        if spaced.count > 1 {
            guard !latin else { return nil }
            var out: [String] = []
            for p in spaced where !out.contains(p) { out.append(p) }
            return out.count > 1 ? Array(out.prefix(12)) : nil
        }
        guard !latin, q.unicodeScalars.allSatisfy({ ConvertEngine.isHan($0.value) }), q.count >= 2, !isWord(q) else { return nil }
        let cs = Array(q)
        var out: [String] = []
        var i = 0
        while i < cs.count {
            var step = 1
            for L in stride(from: min(maxLen, cs.count - i), through: 2, by: -1) where isWord(String(cs[i..<i + L])) { step = L; break }
            let w = String(cs[i..<i + step])
            if !out.contains(w) { out.append(w) }
            i += step
        }
        return out.count > 1 ? Array(out.prefix(12)) : nil
    }
}

/// one capsule per word of the search, like the 皓羅 and 台・通行 buttons: grey until you tap one, then in its own colour
struct WordPickRow: View {
    let words: [String]
    @Binding var picked: Int?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                    let on = picked == i
                    Button { picked = on ? nil : i } label: {
                        Text(w)
                            .ffFont(.subheadline, .bold)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Capsule().fill(on ? Rainbow.fill(i) : T.fn.opacity(0.8)))
                            .overlay(Capsule().stroke(on ? Rainbow.edge(i) : T.fnEdge, lineWidth: 2))
                            .foregroundStyle(on ? Rainbow.ink(i) : T.glyph)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(w)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 3)
        }
    }
}

// MARK: - 日語借詞

extension Dict {
    /// words the dictionary says come from Japanese (源自日語「…」, 借自日語…), the more common first
    struct JapaneseWord: Hashable { let key: String; let from: String }
    func japaneseWords() -> [JapaneseWord] {
        let re = try! NSRegularExpression(pattern: "(?:源自|借自|來自|譯自|出自)日語|日語原作|日語外來語")
        let src = try! NSRegularExpression(pattern: "日語(?:原作)?「([^」]+)」")
        var out: [(key: String, from: String, s: Double)] = []
        for (k, i) in raw.defs.m {
            let t = raw.defs.t[i]
            let ns = NSRange(t.startIndex..., in: t)
            guard re.firstMatch(in: t, range: ns) != nil else { continue }
            var from = ""
            if let m = src.firstMatch(in: t, range: ns), let r = Range(m.range(at: 1), in: t) { from = String(t[r]) }
            out.append((k, from, score(Dict.hanOf(k), Dict.codesOf(k))))
        }
        return out.sorted { $0.s > $1.s }.map { JapaneseWord(key: $0.key, from: $0.from) }
    }
}

/// 查詞 → 日語借詞: every word from Japanese, with the Japanese word
struct JapaneseWordsPage: View {
    let dict: Dict
    @EnvironmentObject var store: Store
    @State private var list: [Dict.JapaneseWord]?
    var body: some View {
        List {
            if let list {
                Section(tr("\(list.count) 個詞")) {
                    ForEach(list, id: \.key) { w in
                        NavigationLink(value: DictKey(k: w.key)) {
                            VStack(alignment: .leading, spacing: 3) {
                                DictRow(dict: dict, key: w.key)
                                if !w.from.isEmpty {
                                    HStack(spacing: 6) {
                                        Chip(text: tr("日"), fill: T.rust, edge: T.rustEdge, ink: T.rustInk)
                                        Text(w.from).ffFont(.footnote).foregroundStyle(T.rustInk)
                                    }
                                }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if store.cardStatus(w.key) == 0 {
                                Button { store.toggleUnknown(w.key) } label: { Label(tr("加到不熟"), systemImage: "star") }.tint(T.rustEdge)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button { store.toggleSaved(w.key) } label: {
                                Label(store.isSaved(w.key) ? "取消收藏" : "收藏", systemImage: "bookmark")
                            }.tint(T.oliveEdge)
                        }
                    }
                }
                .listRowBackground(T.fn.opacity(0.7))
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("日語借詞"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        .task {
            guard list == nil else { return }
            let d = dict
            list = await Task.detached(priority: .userInitiated) { d.japaneseWords() }.value
        }
    }
}
