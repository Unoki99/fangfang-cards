import SwiftUI

// 部首查字: two ways.
// 一個部首: tap a 康熙 radical, then the character (sorted by the strokes besides the radical).
// 組合部首: tap several radicals (氵 + 毋 → 海…): the characters that have all of them anywhere inside.
// The character tapped goes into the search.

struct RadicalPage: View {
    /// the dictionary has this character
    let isChar: (String) -> Bool
    let onPick: (String) -> Void
    @ObservedObject private var store = Store.shared
    @AppStorage("radicalMode") private var mode = 0          // 0 一個部首, 1 組合部首
    @State private var radical: ZhRadical?
    @State private var picked: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let d = store.zh {
                VStack(spacing: 0) {
                    Picker("", selection: $mode) {
                        Text(tr("一個部首")).tag(0)
                        Text(tr("組合部首")).tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
                    if mode == 1 {
                        RadicalCombine(dict: d, isChar: isChar, picked: $picked) { ch in onPick(ch); dismiss() }
                    } else if let r = radical {
                        RadicalChars(radical: r, isChar: isChar) { ch in onPick(ch); dismiss() }
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                Text(tr("點一個部首，再點你要的字。字會放進搜尋框。")).ffFont(.footnote).foregroundStyle(T.muted)
                                RadicalMap(radicals: d.radicals) { r in withAnimation(.snappy) { radical = r } }
                            }
                            .padding()
                            .frame(maxWidth: 760)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(tr("載入部首資料…")).ffFont(.footnote).foregroundStyle(T.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appBackground()
        .navigationTitle(mode == 0 ? (radical.map { tr("部首「\($0.radical)」") } ?? trs("部首查字")) : trs("組合部首"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == 0 && radical != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation(.snappy) { radical = nil } } label: { Label(tr("換部首"), systemImage: "square.grid.3x3") }
                }
            }
            if mode == 1 && !picked.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr("清除")) { withAnimation(.snappy) { picked = [] } }
                }
            }
        }
        .onAppear { if store.zh == nil { store.preloadZh() } }
    }
}

/// every radical, by its number of strokes. `picked` radicals are coloured (in the order picked);
/// `enabled` (when given) dims the radicals that would leave no character.
private struct RadicalMap: View {
    let radicals: [ZhRadical]
    var picked: [String] = []
    var enabled: Set<String>? = nil
    let onTap: (ZhRadical) -> Void
    /// the forms radicals take at the side of a character
    static let forms: [String: String] = [
        "人": "亻", "刀": "刂", "水": "氵", "手": "扌", "心": "忄", "犬": "犭", "示": "礻", "衣": "衤", "糸": "糹",
        "言": "訁", "金": "釒", "食": "飠", "艸": "艹", "辵": "⻌", "火": "灬", "爪": "爫", "网": "罒", "玉": "王",
        "肉": "⺼", "攴": "攵", "阜": "阝左", "邑": "阝右", "老": "耂", "足": "⻊", "竹": "⺮", "牛": "牜", "歹": "歺",
        "襾": "覀", "毋": "母",
    ]
    var body: some View {
        let groups = Dictionary(grouping: radicals.filter { $0.radical != "｜" }, by: { $0.strokes })
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(groups.keys.sorted(), id: \.self) { n in
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("\(n) 畫")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                        ForEach(groups[n] ?? []) { r in
                            let i = picked.firstIndex(of: r.radical)
                            let off = i == nil && enabled.map { !$0.contains(r.radical) } == true
                            Button { onTap(r) } label: {
                                VStack(spacing: -2) {
                                    Text(r.radical).scaledFont(24, weight: .medium)
                                    // the form it takes inside characters (氵 for 水)
                                    if let f = RadicalMap.forms[r.radical] { Text(f).ffFont(.caption2) }
                                }
                                    .foregroundStyle(i.map { Rainbow.ink($0) } ?? (off ? T.muted.opacity(0.4) : T.glyph))
                                    .frame(maxWidth: .infinity, minHeight: 46)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(i.map { Rainbow.fill($0) } ?? T.fn.opacity(off ? 0.35 : 0.8)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(i.map { Rainbow.edge($0) } ?? T.fnEdge, lineWidth: i == nil ? 1 : 2))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .disabled(off)
                            .accessibilityLabel(tr("部首 \(r.radical)"))
                            .accessibilityAddTraits(i != nil ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}

/// 組合部首: the radicals picked, the characters that have them all, and the radicals to pick from
private struct RadicalCombine: View {
    let dict: ZhDict
    let isChar: (String) -> Bool
    @Binding var picked: [String]
    let onPick: (String) -> Void
    @State private var found: [String] = []
    @State private var enabled: Set<String>?
    private let shownMax = 300

    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        // two areas: the radicals to pick from, and what's picked with what it finds
        // (iPad: the found characters on the right; iPhone: on the bottom half)
        GeometryReader { g in
            if hSize == .regular && g.size.width > 640 {
                HStack(spacing: 0) {
                    radicalArea
                    Rectangle().fill(T.fnEdge).frame(width: 1)
                    foundArea.frame(width: max(300, g.size.width * 0.42))
                }
            } else {
                VStack(spacing: 0) {
                    radicalArea
                    Rectangle().fill(T.fnEdge).frame(height: 1)
                    foundArea.frame(height: g.size.height * 0.5)
                }
            }
        }
        .onAppear { update() }
        .onChange(of: picked) { update() }
    }

    /// the radicals to pick from
    private var radicalArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if dict.radicalInside.isEmpty {
                    Text(tr("這份華語資料沒有字的組成。重新執行一次 build-data.sh（或 install.sh）就有了。"))
                        .ffFont(.footnote).foregroundStyle(T.muted)
                }
                RadicalMap(radicals: dict.radicals, picked: picked, enabled: enabled) { r in
                    withAnimation(.snappy) {
                        if picked.contains(r.radical) { picked.removeAll { $0 == r.radical } } else { picked.append(r.radical) }
                    }
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// the radicals picked (tap one to take it out) and the characters that have them all
    private var foundArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if picked.isEmpty {
                    Text(tr("還沒選部首")).ffFont(.subheadline).foregroundStyle(T.muted)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(picked.enumerated()), id: \.offset) { i, r in
                            Button { withAnimation(.snappy) { picked.removeAll { $0 == r } } } label: {
                                HStack(spacing: 4) {
                                    Text(r).ffFont(.headline)
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(Rainbow.fill(i)))
                                .overlay(Capsule().stroke(Rainbow.edge(i), lineWidth: 2))
                                .foregroundStyle(Rainbow.ink(i))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tr("拿掉 \(r)"))
                        }
                    }
                    .padding(.vertical, 2)
                }
                if !picked.isEmpty {
                    Text(tr("\(found.count) 個字")).ffFont(.footnote).foregroundStyle(T.muted).fixedSize()
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .background(T.fn.opacity(0.5))
            Rectangle().fill(T.fnEdge).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if picked.isEmpty {
                        Text(tr("點好幾個部首（例如 氵 和 毋），這裡會出現裡面都有這些部首的字。偏旁也算：氵 = 水、亻 = 人、扌 = 手、艹 = 艸、⻌ = 辵、阝 = 阜／邑…不可能再組合的部首會變淡。"))
                            .ffFont(.footnote).foregroundStyle(T.muted)
                    } else {
                        results
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(T.fn.opacity(0.25))
    }

    @ViewBuilder private var results: some View {
        if found.isEmpty {
            Text(tr("沒有字同時有這些部首。")).ffFont(.footnote).foregroundStyle(T.muted)
        } else {
            let shown = Array(found.prefix(shownMax))
            let groups = Dictionary(grouping: shown, by: { dict.strokesOf[$0] ?? 0 })
            ForEach(groups.keys.sorted(), id: \.self) { n in
                VStack(alignment: .leading, spacing: 6) {
                    Text(n == 0 ? trs("其他") : tr("\(n) 畫")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                        ForEach(groups[n] ?? [], id: \.self) { ch in
                            Button { onPick(ch) } label: {
                                Text(ch)
                                    .scaledFont(26, weight: .medium)
                                    .foregroundStyle(T.blueInk)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(T.fn.opacity(0.8)))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.fnEdge, lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if found.count > shownMax {
                Text(tr("只列出筆畫最少的 \(shownMax) 個字。再點一個部首可以縮小範圍。")).ffFont(.caption).foregroundStyle(T.muted)
            }
        }
    }

    /// the characters with every radical picked, and which radicals can still be added
    private func update() {
        guard !picked.isEmpty else { found = []; enabled = nil; return }
        found = dict.charsWith(radicals: picked).filter(isChar)
        // with not too many characters: dim the radicals that none of them has
        if found.count <= 4000 {
            var on = Set<String>()
            for (r, set) in dict.radicalSets where !picked.contains(r) {
                if found.contains(where: { set.contains($0) }) { on.insert(r) }
            }
            enabled = on
        } else {
            enabled = nil
        }
    }
}

/// the characters with one radical, by the strokes besides the radical
private struct RadicalChars: View {
    let radical: ZhRadical
    let isChar: (String) -> Bool
    let onPick: (String) -> Void
    var body: some View {
        let chars = radical.chars.filter { isChar($0.ch) }
        let groups = Dictionary(grouping: chars, by: { $0.rest })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if chars.isEmpty {
                    Text(tr("這個詞典沒有這個部首的字。")).ffFont(.footnote).foregroundStyle(T.muted)
                }
                ForEach(groups.keys.sorted(), id: \.self) { n in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(n == 0 ? trs("部首本身") : tr("再 \(n) 畫")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                            ForEach(Array((groups[n] ?? []).enumerated()), id: \.offset) { _, c in
                                Button { onPick(c.ch) } label: {
                                    Text(c.ch)
                                        .scaledFont(26, weight: .medium)
                                        .foregroundStyle(T.blueInk)
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(T.fn.opacity(0.8)))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.fnEdge, lineWidth: 1))
                                        .contentShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
    }
}
