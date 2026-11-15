import SwiftUI

// 依常用度列出: a dictionary's words by how common they are, in the five steps of the bars beside each word
// (很常用, 常用, 一般, 不常用, 少見), like 依詞類列出. Each step shows how many of its words are 熟悉 / 不熟; inside,
// the words, the most common first, and 全部 / 新詞 / 不熟 / 熟悉 to see only some.

/// the bars' five steps (FrequencyBadge.level): 5 很常用 … 1 少見
enum FreqLevels {
    static let names = [5: "很常用", 4: "常用", 3: "一般", 2: "不常用", 1: "少見"]
    static let ranges = [5: "前 1000 個", 4: "1001–3000", 3: "3001–8000", 2: "8001–20000", 1: "20000 以後"]
    static func name(_ l: Int) -> String { trs(names[l] ?? "") }
    /// the places (from 0, the most common) of a step's words: the same steps as FrequencyBadge.level
    static func bounds(_ l: Int) -> (Int, Int) {
        switch l {
        case 5: return (0, 1000)
        case 4: return (1000, 3000)
        case 3: return (3000, 8000)
        case 2: return (8000, 20000)
        default: return (20000, Int.max)
        }
    }
    /// 新詞's topic for a step: -105 很常用 … -101 少見
    static func topic(_ l: Int) -> Int { -100 - l }
    static func level(ofTopic t: Int) -> Int? { (-105 ... -101).contains(t) ? -100 - t : nil }
}

/// the bars of a step, in the language's colour
struct FreqLevelBars: View {
    let level: Int
    let kind: Int
    var body: some View {
        let ink = T.langColors(kind).ink
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= level ? ink : T.fnEdge)
                    .frame(width: 5, height: CGFloat(5 + i * 3))
            }
        }
        .fixedSize()
    }
}

/// the list of steps; `keys` the words; `row` how a word is shown (and opened)
struct FreqBandsPage: View {
    let keys: [String]
    let row: (String) -> AnyView
    @EnvironmentObject var store: Store

    /// the words of each step, the most common first (words without a place: none)
    private var byLevel: [Int: [String]] {
        var out: [Int: [(Int, String)]] = [:]
        for k in keys {
            let r = store.rankOf(k)
            guard r != Int.max else { continue }
            out[FrequencyBadge.level(r), default: []].append((r, k))
        }
        return out.mapValues { $0.sorted { $0.0 < $1.0 }.map(\.1) }
    }

    var body: some View {
        let levels = byLevel
        let kind = keys.first.map(Lang.kind) ?? store.lang
        List {
            Section {
                ForEach([5, 4, 3, 2, 1], id: \.self) { l in
                    let ks = levels[l] ?? []
                    if !ks.isEmpty {
                        NavigationLink {
                            FreqBandPage(keys: ks, level: l, kind: kind, row: row)
                        } label: {
                            label(l, ks, kind)
                        }
                    }
                }
            } footer: {
                Text(tr("和每個詞旁邊的常用度一樣分五級。綠色是熟悉的詞，紅色是不熟的詞。"))
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(tr("依常用度列出"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ l: Int, _ ks: [String], _ kind: Int) -> some View {
        let st = ks.map { store.wordStatus($0) }
        let known = st.filter { $0 == 1 }.count, unknown = st.filter { $0 == 2 }.count
        let n = max(ks.count, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                FreqLevelBars(level: l, kind: kind)
                Text(FreqLevels.name(l)).ffFont(.body, .semibold).foregroundStyle(T.glyph)
                Text(trs(FreqLevels.ranges[l] ?? "")).ffFont(.caption).foregroundStyle(T.muted)
                Spacer()
                Text(tr("\(ks.count) 個詞")).ffFont(.caption).foregroundStyle(T.muted)
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    Rectangle().fill(T.greenEdge).frame(width: g.size.width * CGFloat(known) / CGFloat(n))
                    Rectangle().fill(T.rustEdge).frame(width: g.size.width * CGFloat(unknown) / CGFloat(n))
                    Rectangle().fill(T.fnEdge.opacity(0.5))
                }
                .clipShape(Capsule())
            }
            .frame(height: 6)
            Text(tr("熟悉 \(known)・不熟 \(unknown)")).ffFont(.caption2).foregroundStyle(T.muted)
        }
        .padding(.vertical, 4)
    }
}

/// one step's words
struct FreqBandPage: View {
    let keys: [String]
    let level: Int
    let kind: Int
    let row: (String) -> AnyView
    @EnvironmentObject var store: Store
    /// -1 全部, 0 新詞, 2 不熟, 1 熟悉
    @State private var show = -1

    var body: some View {
        let list = keys.filter { show < 0 || store.wordStatus($0) == show }
        List {
            Section {
                Picker(tr("顯示"), selection: $show) {
                    Text(tr("全部")).tag(-1)
                    Text(tr("新詞")).tag(0)
                    Text(tr("不熟")).tag(2)
                    Text(tr("熟悉")).tag(1)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            Section(tr("\(list.count) 個詞")) {
                ForEach(list.prefix(3000), id: \.self) { k in row(k) }
            }
            .listRowBackground(T.fn.opacity(0.7))
        }
        .scrollContentBackground(.hidden)
        .appBackground()
        .navigationTitle(FreqLevels.name(level))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { FreqLevelBars(level: level, kind: kind) } }
    }
}
