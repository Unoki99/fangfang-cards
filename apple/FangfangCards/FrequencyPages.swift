import SwiftUI

// 依常用度列出: a dictionary's words by how common they are, in five steps by how full the ring beside each word is
// (很常用, 常用, 一般, 不常用, 少見), like 依詞類列出. Each step shows how many of its words are 熟悉 / 不熟; inside,
// the words, the most common first, and 全部 / 新詞 / 不熟 / 熟悉 to see only some.

/// the bars' five steps (FrequencyBadge.level): 5 很常用 … 1 少見
enum FreqLevels {
    static let names = [5: "很常用", 4: "常用", 3: "一般", 2: "不常用", 1: "少見"]
    static func name(_ l: Int) -> String { trs(names[l] ?? "") }
    /// the steps by how full the 常用度 ring is: 80–100 %, 60–80 %, 40–60 %, 20–40 %, under 20 % (FrequencyRing.fill);
    /// the places where the ring crosses 80, 60, 40 and 20 % (about 136, 1046, 5029, 18 800)
    static let cuts: [Int] = [0.8, 0.6, 0.4, 0.2].map { f in max(1, Int(pow(60000.0, (1 - f).squareRoot())) - 1) }
    static func range(_ l: Int) -> String {
        let pc = ["", "0–20%", "20–40%", "40–60%", "60–80%", "80–100%"][min(max(l, 1), 5)]
        let (lo, hi) = bounds(l)
        let at = hi == Int.max ? tr("\(lo) 以後") : (lo == 0 ? tr("前 \(hi) 個") : "\(lo + 1)–\(hi)")
        return tr("圓圈 \(pc)・") + at
    }
    /// the places (from 0, the most common) of a step's words: the same steps as FrequencyBadge.level
    static func bounds(_ l: Int) -> (Int, Int) {
        let c = cuts
        switch l {
        case 5: return (0, c[0])
        case 4: return (c[0], c[1])
        case 3: return (c[1], c[2])
        case 2: return (c[2], c[3])
        default: return (c[3], Int.max)
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
        // (the ring as full as the step's middle: like the ring beside each word)
        FrequencyRingView(size: 20, line: 3.5, fill: [0, 0.1, 0.3, 0.5, 0.7, 0.92][min(max(level, 0), 5)])
            .fixedSize()
    }
}

/// the list of steps; `keys` the words; `row` how a word is shown (and opened)
struct FreqBandsPage: View {
    let keys: [String]
    let row: (String) -> AnyView
    /// where a step opens: a value for the stack's own navigationDestination (a page pushed by a closure was thrown
    /// away when a word in it was opened by value: you saw the list again instead of the word)
    /// (0: by a closure, 1: TwFreqRef, 2: ZhFreqRef. The value's own type, not AnyHashable: a link whose value
    /// is an AnyHashable found no navigationDestination and did nothing)
    var link = 0
    @EnvironmentObject var store: Store

    /// the words of each step, the most common first (words without a place: none)
    private var byLevel: [Int: [String]] { Self.levels(keys, store) }

    static func levels(_ keys: [String], _ store: Store) -> [Int: [String]] {
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
                        if link == 1 {
                            NavigationLink(value: TwFreqRef(level: l)) { label(l, ks, kind) }
                        } else if link == 2 {
                            NavigationLink(value: ZhFreqRef(level: l)) { label(l, ks, kind) }
                        } else {
                            NavigationLink {
                                FreqBandPage(keys: ks, level: l, kind: kind, row: row)
                            } label: {
                                label(l, ks, kind)
                            }
                        }
                    }
                }
            } footer: {
                Text(tr("照每個詞旁邊常用度圓圈有多滿分五級。綠色是熟悉的詞，紅色是不熟的詞。"))
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
                Text(FreqLevels.range(l)).ffFont(.caption).foregroundStyle(T.muted)
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

/// 依常用度列出, opened by value (nil: the list of steps; else one step's words), so the words opened from it (by
/// value too) come on top of it instead of taking it away
struct TwFreqRef: Hashable { var level: Int? = nil }
struct ZhFreqRef: Hashable { var level: Int? = nil }

/// 台語: the 台語 cards by how common they are
struct TwFreqDestination: View {
    let dict: Dict
    let level: Int?
    @EnvironmentObject var store: Store
    var body: some View {
        let keys = store.lang == 0 ? store.cards.map(\.k) : []
        let row: (String) -> AnyView = { k in AnyView(EntryLink(value: DictKey(k: k)) { DictRow(dict: dict, key: k) }) }
        if let l = level {
            FreqBandPage(keys: FreqBandsPage.levels(keys, store)[l] ?? [], level: l, kind: keys.first.map(Lang.kind) ?? store.lang, row: row)
        } else {
            FreqBandsPage(keys: keys, row: row, link: 1)
        }
    }
}

/// 華語 (and the other dictionaries): the dictionary's words by how common they are
struct ZhFreqDestination: View {
    let dict: ZhDict
    let level: Int?
    @EnvironmentObject var store: Store
    var body: some View {
        let keys = dict.entries.map(\.k)
        let row: (String) -> AnyView = { k in
            AnyView(Group {
                if let e = dict.entry(k) { NavigationLink(value: ZhKey(k: k)) { ZhWordRow(dict: dict, entry: e) } }
            })
        }
        if let l = level {
            FreqBandPage(keys: FreqBandsPage.levels(keys, store)[l] ?? [], level: l, kind: keys.first.map(Lang.kind) ?? store.lang, row: row)
        } else {
            FreqBandsPage(keys: keys, row: row, link: 2)
        }
    }
}
