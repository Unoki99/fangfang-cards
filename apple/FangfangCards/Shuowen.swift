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
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s).ffFont(.subheadline).foregroundStyle(T.glyph).textSelection(.enabled)
                            // (from a video's subtitles: the same line in the second language, and the video)
                            let tr = store.foundTranslation(s)
                            if !tr.isEmpty {
                                Text(tr).ffFont(.footnote).foregroundStyle(T.muted).textSelection(.enabled)
                            }
                            if let src = store.foundSource(s) {
                                Text("— " + src).ffFont(.caption2).foregroundStyle(T.muted.opacity(0.8)).lineLimit(2)
                            }
                        }
                    }
                }
                Text(tr("「例句填空」會用這些句子出題。")).ffFont(.caption2).foregroundStyle(T.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.55)))
        }
    }
}


/// 常用度: how common a word is (its place in the language's list of words, most common first), as a hollow ring:
/// the more common, the fuller (by %, not steps) and the warmer its colour, along the 台語 tone colours (blue for
/// the rarest, through teal, green, purple… to red for the most common)
enum FrequencyRing {
    /// how full: rank 0 → 1, 100 → about 0.8, 1000 → 0.6, 10 000 → 0.3, 60 000 and past → nearly empty
    static func fill(_ rank: Int) -> Double {
        let x = log(Double(rank) + 1) / log(60000)
        return max(0.04, min(1, 1 - x * x))
    }
    /// the name used for the ring in place of an SF Symbol (TileLabel, the 學習紀錄 tiles)
    static let icon = "ff.ring"
    /// the colour, from nearly empty to full: purple, blue, teal, green, yellow, orange, red, pink (and the shades
    /// between them)
    private static let stops: [Color] = [
        Color(red: 0.58, green: 0.38, blue: 0.86),   // purple
        Color(red: 0.24, green: 0.48, blue: 0.95),   // blue
        Color(red: 0.10, green: 0.68, blue: 0.70),   // teal
        Color(red: 0.30, green: 0.72, blue: 0.32),   // green
        Color(red: 0.95, green: 0.78, blue: 0.16),   // yellow
        Color(red: 0.97, green: 0.55, blue: 0.14),   // orange
        Color(red: 0.90, green: 0.22, blue: 0.20),   // red
        Color(red: 0.96, green: 0.36, blue: 0.62),   // pink
    ]
    @MainActor static func color(_ f: Double) -> Color {
        let cs = stops
        let x = max(0, min(1, f)) * Double(cs.count - 1)
        let i = min(Int(x), cs.count - 2), t = x - Double(i)
        func rgb(_ c: Color) -> (Double, Double, Double) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b))
        }
        let p = rgb(cs[i]), q = rgb(cs[i + 1])
        return Color(red: p.0 + (q.0 - p.0) * t, green: p.1 + (q.1 - p.1) * t, blue: p.2 + (q.2 - p.2) * t)
    }
}

/// the ring itself
struct FrequencyRingView: View {
    var rank: Int = 0
    var size: CGFloat = 16
    var line: CGFloat = 3
    /// how full, when not from a place (an icon)
    var fill: Double? = nil
    var body: some View {
        let f = fill ?? FrequencyRing.fill(rank)
        let c = FrequencyRing.color(f)
        ZStack {
            Circle().stroke(T.fnEdge.opacity(0.6), lineWidth: line)
            Circle().trim(from: 0, to: f)
                .stroke(c, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: c.opacity(0.5), radius: 2)
        }
        .frame(width: size, height: size)
    }
}

/// how common a word is, small: the ring alone (the rows of a list of words)
struct FrequencyBars: View {
    let key: String
    @EnvironmentObject var store: Store
    var body: some View {
        let r = store.rankOf(key)
        if r != Int.max {
            FrequencyRingView(rank: r)
                .fixedSize()
                .accessibilityElement()
                .accessibilityLabel(tr("常用度：第 \(r + 1) 個"))
        }
    }
}

struct FrequencyBadge: View {
    let key: String
    @EnvironmentObject var store: Store
    /// the step a place is in: by how full its ring is (FreqLevels.cuts: 80, 60, 40, 20 %)
    static func level(_ rank: Int) -> Int {
        let c = FreqLevels.cuts
        if rank < c[0] { return 5 }
        if rank < c[1] { return 4 }
        if rank < c[2] { return 3 }
        if rank < c[3] { return 2 }
        return 1
    }
    var body: some View {
        let r = store.rankOf(key)
        if r != Int.max {
            let n = Self.level(r)
            // (the language's own colour: 華語 blue, 台語 green, 粵語 yellow, 客語 red, 日語 pink, 瑞典語 teal)
            let ink = T.langColors(Lang.kind(key)).ink
            let f = FrequencyRing.fill(r)
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(Int((f * 100).rounded()))%").ffFont(.caption, mono: true).foregroundStyle(FrequencyRing.color(f))
                    FrequencyRingView(rank: r, size: 30, line: 4.5)
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
