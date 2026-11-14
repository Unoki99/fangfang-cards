import SwiftUI

// MARK: - 說文解字 (段玉裁《說文解字注》, from cjkvi-dict, GPLv2)
//
// Installed like a dictionary (設定 → 詞典資料 → 說文解字): the phone downloads swjz.xml and makes shuowen.json
// (Install/shuowen.js). A single character's entry shows 許慎's text, 段玉裁's notes (folded away), and its 六書
// (from the text: 形聲 when it names a sound part, 象形, 指事, 會意).

enum Shuowen {
    struct Item { let text: String; let notes: String?; let liushu: String? }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var table: [String: [Item]]?

    /// read again (after installing or removing it)
    static func reset() { lock.lock(); table = nil; lock.unlock() }

    static var available: Bool { DataFiles.has("shuowen") }

    private static var all: [String: [Item]] {
        lock.lock(); defer { lock.unlock() }
        if let t = table { return t }
        var t: [String: [Item]] = [:]
        if let u = DataFiles.url("shuowen"), let d = try? Data(contentsOf: u, options: .mappedIfSafe),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any], let c = o["c"] as? [String: [[String: String]]] {
            for (ch, list) in c {
                t[ch] = list.compactMap { x in x["e"].map { Item(text: $0, notes: x["d"], liushu: x["l"]) } }
            }
        }
        table = t
        return t
    }

    static func of(_ ch: String) -> [Item] { all[ch] ?? [] }
    /// the character's 六書 (nil: not known)
    static func liushu(_ ch: String) -> String? { of(ch).lazy.compactMap(\.liushu).first }
}

/// a character's 說文解字: under its meanings
struct ShuowenBlock: View {
    let ch: String
    var body: some View {
        let items = Shuowen.of(ch)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(tr("《說文解字》")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                    if let l = Shuowen.liushu(ch) { InfoChip.yellow(tr("六書：") + l) }
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(it.text).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                        if let n = it.notes, !n.isEmpty {
                            DisclosureGroup {
                                Text(n).ffFont(.footnote).foregroundStyle(T.glyph.opacity(0.85)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            } label: {
                                Text(tr("段玉裁注")).ffFont(.footnote, .semibold).foregroundStyle(T.muted)
                            }
                            .tint(T.muted)
                        }
                    }
                }
                Text(tr("資料：段玉裁《說文解字注》（cjkvi-dict，GPLv2）。六書照說文的寫法判斷（「…聲」為形聲），可能有誤。"))
                    .ffFont(.caption2).foregroundStyle(T.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.55)))
        }
    }
}


/// Safari 查詞: the sentences on web pages the word was saved from
struct FoundSentences: View {
    let key: String
    @EnvironmentObject var store: Store
    var body: some View {
        let list = store.foundSentences(key)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("你看到、聽到的句子")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                ForEach(list.reversed(), id: \.self) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // (saved from the 歌詞 page while the radio played: the radio's own sound)
                        if let c = store.clip(s) { PlayButton(path: c, size: 26) }
                        Text(s).ffFont(.subheadline).foregroundStyle(T.glyph).textSelection(.enabled)
                    }
                }
                Text(tr("「例句填空」也會用這些句子出題。")).ffFont(.caption2).foregroundStyle(T.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.55)))
        }
    }
}


/// 常用度: how common a word is (its place in the language's list of words, most common first), as five bars
/// how common a word is, small: the bars alone (the rows of a list of words), in the language's colour
struct FrequencyBars: View {
    let key: String
    @EnvironmentObject var store: Store
    var body: some View {
        let r = store.rankOf(key)
        if r != Int.max {
            let n = FrequencyBadge.level(r)
            let ink = T.langColors(Lang.kind(key)).ink
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(1...5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i <= n ? ink : T.fnEdge)
                        .frame(width: 4, height: CGFloat(5 + i * 3))
                        .shadow(color: i <= n ? ink.opacity(0.45) : .clear, radius: 2)
                }
            }
            .fixedSize()
            .accessibilityElement()
            .accessibilityLabel(tr("常用度：第 \(r + 1) 個"))
        }
    }
}

struct FrequencyBadge: View {
    let key: String
    @EnvironmentObject var store: Store
    /// the bars a place gets: the first 1000 words 5, then 3000, 8000, 20000
    static func level(_ rank: Int) -> Int {
        switch rank {
        case ..<1000: return 5
        case ..<3000: return 4
        case ..<8000: return 3
        case ..<20000: return 2
        default: return 1
        }
    }
    var body: some View {
        let r = store.rankOf(key)
        if r != Int.max {
            let n = Self.level(r)
            // (the language's own colour: 華語 blue, 台語 green, 粵語 yellow, 客語 red, 日語 pink, 瑞典語 teal)
            let ink = T.langColors(Lang.kind(key)).ink
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(1...5, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i <= n ? ink : T.fnEdge)
                            .frame(width: 6, height: CGFloat(6 + i * 3))
                            .shadow(color: i <= n ? ink.opacity(0.5) : .clear, radius: 3)
                    }
                }
                Text([trs("少見"), trs("不常用"), trs("一般"), trs("常用"), trs("很常用")][n - 1]).ffFont(.caption, .bold)
                    .foregroundStyle(n >= 3 ? ink : T.muted)
                Text(tr("第 \(r + 1) 個")).ffFont(.caption2).foregroundStyle(T.muted)
            }
            .fixedSize()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tr("常用度：第 \(r + 1) 個"))
        }
    }
}
