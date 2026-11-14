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
                Text(tr("在網頁上看到的句子")).ffFont(.caption, .bold).foregroundStyle(T.muted)
                ForEach(list.reversed(), id: \.self) { s in
                    Text(s).ffFont(.subheadline).foregroundStyle(T.glyph).textSelection(.enabled)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.55)))
        }
    }
}
