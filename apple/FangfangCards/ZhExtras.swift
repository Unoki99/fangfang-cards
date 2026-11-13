import SwiftUI

// 華語: English meanings as a list, 依詞類列出, and the 主要解釋 setting

/// 設定 → 華語 → 主要解釋: the 華語 meaning (from 《兩岸常用詞典》) or the English one (CC-CEDICT), on the cards and in lists
enum ZhMeaning {
    /// 華語's
    static let key = "zhMainEnglish"
    /// 台語's (English from Wiktionary) and 客語's
    static let twKey = "twMainEnglish"
    static let hakKey = "hakMainEnglish"
    static var english: Bool { UserDefaults.standard.bool(forKey: key) }
    /// a language's main meaning is the English one (粵語's meanings are English already)
    static func english(_ lang: Int) -> Bool {
        switch lang {
        case 0: return UserDefaults.standard.bool(forKey: twKey)
        case 2: return true
        case 3: return UserDefaults.standard.bool(forKey: hakKey)
        default: return english
        }
    }
}

/// a blue square with a number, the shape of the 詞類 chips (the English meanings)
struct EnNum: View {
    let n: Int
    var body: some View { Chip(text: "\(n)", fill: T.blue, edge: T.blueEdge, ink: T.blueInk).monospacedDigit() }
}

/// the English meanings (CC-CEDICT separates them with ;), numbered
struct ZhEnglishList: View {
    let items: [String]
    var max = 0                 // 0 = all of them
    var lineLimit: Int? = nil
    var font: FFStyle = .subheadline
    var body: some View {
        let shown = max > 0 ? Array(items.prefix(max)) : items
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if items.count > 1 { EnNum(n: i + 1) }
                    Text(t).ffFont(font).foregroundStyle(T.glyph.opacity(0.9)).lineLimit(lineLimit).textSelection(.enabled)
                }
            }
            if max > 0 && items.count > max {
                Text(tr("還有 \(items.count - max) 個意思")).ffFont(.caption).foregroundStyle(T.muted)
            }
        }
    }
}

extension ZhDict {
    /// the words of a 詞類 (the more common first)
    func wordsOfClass(_ c: String) -> [Int] {
        entries.indices.filter { entries[$0].pos.contains(c) }
    }
}

/// 依詞類列出 (華語): every word class with how many words it has (詞類 from the HSK / TOCFL lists)
struct ZhWordClassListPage: View {
    let dict: ZhDict
    struct ClassCount: Hashable { let c: String; let n: Int }
    @State private var counts: [ClassCount] = []
    var body: some View {
        List {
            Section {
                ForEach(counts, id: \.c) { x in
                    NavigationLink(value: ZhClassRef(cls: x.c)) {
                        HStack {
                            Text(x.c).foregroundStyle(T.glyph)
                            Spacer()
                            Text("\(x.n)").ffFont(.footnote, mono: true).foregroundStyle(T.muted)
                        }
                    }
                }
            } footer: {
                Text(tr("詞類來自 HSK 3.0 和 TOCFL 的詞表，所以只有詞表裡的詞有。"))
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("依詞類列出"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard counts.isEmpty else { return }
            let d = dict
            // in the order of the 台語 dictionary's list, then any others
            let order = WordClassPage.classes
            counts = await Task.detached(priority: .userInitiated) { () -> [ClassCount] in
                var n: [String: Int] = [:]
                for e in d.entries { for p in e.pos { n[p, default: 0] += 1 } }
                return n.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
                    .map { ClassCount(c: $0, n: n[$0]!) }
            }.value
        }
    }
}

/// the words of one 詞類 (華語)
struct ZhWordClassPage: View {
    let dict: ZhDict
    let cls: String
    @EnvironmentObject var store: Store
    @State private var list: [Int]?
    var body: some View {
        List {
            if let list {
                Section(tr("\(list.count) 個詞")) {
                    ForEach(list, id: \.self) { i in
                        let e = dict.entries[i]
                        NavigationLink(value: ZhKey(k: e.k)) { ZhWordRow(dict: dict, entry: e) }
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
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(cls)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
        .task {
            guard list == nil else { return }
            let d = dict, c = cls
            list = await Task.detached(priority: .userInitiated) { d.wordsOfClass(c) }.value
        }
    }
}
