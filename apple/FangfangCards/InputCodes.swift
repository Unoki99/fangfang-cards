import SwiftUI

/// 倉頡 / 五筆 / 無蝦米 codes of characters (inputcodes.json, made by tools/build_inputcodes.py).
/// Shown under the headword in the dictionary when 設定 → 輸入法拆碼 is on.
final class InputCodes: @unchecked Sendable {
    static let shared = InputCodes()
    static let onKey = "imeOn"
    static let systemKeys = ["imeCJ", "imeWB", "imeLiu"]
    static let names = ["倉頡", "五筆", "無蝦米"]
    static let short = ["倉", "五", "蝦"]

    private var tables: [[String: String]] = [[:], [:], [:]]
    private var loaded = false
    private let lock = NSLock()

    /// 倉頡 letters as 字根
    private static let radicals: [Character: String] = [
        "a": "日", "b": "月", "c": "金", "d": "木", "e": "水", "f": "火", "g": "土", "h": "竹", "i": "戈", "j": "十",
        "k": "大", "l": "中", "m": "一", "n": "弓", "o": "人", "p": "心", "q": "手", "r": "口", "s": "尸", "t": "廿",
        "u": "山", "v": "女", "w": "田", "x": "難", "y": "卜", "z": "重"]

    private func load() {
        lock.lock(); defer { lock.unlock() }
        guard !loaded else { return }
        loaded = true
        guard let url = DataFiles.url("inputcodes"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return }
        tables = [obj["c"] ?? [:], obj["w"] ?? [:], obj["l"] ?? [:]]
    }

    /// is there a table for this system (無蝦米 only when you added your own)
    func has(_ system: Int) -> Bool { load(); return !tables[system].isEmpty }

    /// the codes of a character in a system: what to show ("口卜人 ryo", "KHU")
    func code(_ ch: String, _ system: Int) -> String? {
        load()
        guard let c = tables[system][ch], !c.isEmpty else { return nil }
        let first = String(c.split(separator: " ").first ?? "")
        switch system {
        case 0: return first.compactMap { Self.radicals[$0] }.joined() + " " + first
        default: return first.uppercased()
        }
    }

    /// the systems to show (設定), when it's on at all
    static var shown: [Int] {
        guard UserDefaults.standard.bool(forKey: onKey) else { return [] }
        return (0..<3).filter { UserDefaults.standard.object(forKey: systemKeys[$0]) as? Bool ?? ($0 == 0) }
    }
}

/// under the headword: each character with its codes
struct InputCodesRow: View {
    let han: String
    @AppStorage(InputCodes.onKey) private var on = false
    @AppStorage("imeCJ") private var cj = true
    @AppStorage("imeWB") private var wb = false
    @AppStorage("imeLiu") private var liu = false

    var body: some View {
        let systems = on ? [cj, wb, liu].enumerated().filter { $0.element }.map(\.offset) : []
        let chars = han.unicodeScalars.filter { Zhuyin.isHan($0) }.map { String($0) }
        if !systems.isEmpty && !chars.isEmpty {
            FlowLayout(spacing: 8) {
                ForEach(Array(chars.enumerated()), id: \.offset) { _, ch in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ch).ffFont(.subheadline, .semibold).foregroundStyle(T.glyph)
                        ForEach(systems, id: \.self) { s in
                            HStack(spacing: 4) {
                                Text(InputCodes.short[s]).ffFont(.caption2, .bold).foregroundStyle(T.muted)
                                Text(InputCodes.shared.code(ch, s) ?? "—").ffFont(.caption, mono: true).foregroundStyle(T.oliveInk)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 10).fill(T.fn.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.fnEdge, lineWidth: 1))
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tr("輸入法拆碼"))
        }
    }
}

/// 設定 → 輸入法拆碼
struct InputCodesSettings: View {
    @AppStorage(InputCodes.onKey) private var on = false
    @AppStorage("imeCJ") private var cj = true
    @AppStorage("imeWB") private var wb = false
    @AppStorage("imeLiu") private var liu = false
    var body: some View {
        Section {
            Toggle(tr("在詞典顯示輸入法拆碼"), isOn: $on)
            if on {
                Toggle(tr("倉頡"), isOn: $cj)
                Toggle(tr("五筆（86 版）"), isOn: $wb)
                Toggle(tr("無蝦米"), isOn: $liu)
                    .disabled(!InputCodes.shared.has(2))
            }
        } header: {
            Text(tr("輸入法拆碼"))
        } footer: {
            Text(InputCodes.shared.has(2) ? "顯示在詞典每個詞的上面。"
                 : "顯示在詞典每個詞的上面。無蝦米要用自己的碼表：把 .cin 檔放到 tools 資料夾，執行 build-data.sh ime。")
        }
    }
}

// MARK: - headword whose characters can be tapped

/// the characters of an AttributedString, one each (keeping their colours)
func splitCharacters(_ a: AttributedString) -> [AttributedString] {
    var out: [AttributedString] = []
    var i = a.characters.startIndex
    while i < a.characters.endIndex {
        let j = a.characters.index(after: i)
        out.append(AttributedString(a[i..<j]))
        i = j
    }
    return out
}

/// a headword: each character that is a word of its own (read the same way) can be tapped to see it
struct TappableHeadword: View {
    let text: AttributedString
    /// for each character: what to open when it's tapped (nil = not tappable)
    let targets: [String?]
    var size: CGFloat = 44
    let onTap: (String) -> Void

    var body: some View {
        let chars = splitCharacters(text)
        HStack(spacing: 0) {
            ForEach(Array(chars.enumerated()), id: \.offset) { i, ch in
                let t = Text(ch).scaledFont(size, weight: .semibold)
                if chars.count > 1, i < targets.count, let k = targets[i] {
                    // the whole character is the button
                    Button { onTap(k) } label: { t.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityHint("看這個字")
                } else {
                    t
                }
            }
        }
    }
}
