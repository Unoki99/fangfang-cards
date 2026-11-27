import SwiftUI

// MARK: - 自訂: your own words in 華語, 粵語, 客語, 日語 and 瑞典語
//
// The same list as 台語's 自訂 (Progress.own and .ownInfo, so they sync and go in the backup), with keys of the
// dictionary's own kind and "#自" at the end: "吃飯\tㄔ ㄈㄢˋ#自", "食飯\t粵sik6 faan6#自", "hej\t瑞hej:r#自". When a
// dictionary is read, its language's words are put after its own (ZhDict.init), so they're found like any word.

/// your words, as the dictionary needs them when it's read (a copy: it's read in the background)
enum ZhOwnWords {
    struct Word: Sendable {
        let key: String
        let h: String
        let tw: [String]
        let meaning: String
        let example: String
        let en: String
    }
    nonisolated(unsafe) private static var words: [Int: [Word]] = [:]
    private static let lock = NSLock()
    static func set(_ w: [Int: [Word]]) { lock.lock(); words = w; lock.unlock() }
    static func of(_ lang: Int) -> [Word] { lock.lock(); defer { lock.unlock() }; return words[lang] ?? [] }

    static let suffix = "#自"
    private static let marker = ["", "", "粵", "客", "日", "瑞", "英"]
    static func key(_ lang: Int, _ h: String, _ tw: [String]) -> String {
        h + "\t" + marker[min(max(lang, 0), 6)] + tw.joined(separator: " ") + suffix
    }
    static func isOwn(_ k: String) -> Bool { k.hasSuffix(suffix) && Lang.kind(k) >= 1 }
    static func han(_ k: String) -> String { k.firstIndex(of: "\t").map { String(k[..<$0]) } ?? k }
    /// the syllables back from a key
    static func syllables(_ k: String) -> [String] {
        guard let t = k.firstIndex(of: "\t") else { return [] }
        var r = String(k[k.index(after: t)...].dropLast(suffix.count))
        if Lang.kind(k) >= 2, !r.isEmpty { r.removeFirst() }
        return r.split(separator: " ").map(String.init)
    }

    /// a reading as you type it (華語: 拼音 with or without tones, or 注音; 粵語: 粵拼 with tone numbers; 客語: 客語
    /// 拼音 with tone numbers, e.g. siid8 fan3; 日語: かな; 瑞典語: nothing) → the dictionary's syllables; nil = can't
    /// be read
    static func syllables(_ typed0: String, han: String, lang: Int, dict: ZhDict) -> [String]? {
        let typed = typed0.trimmingCharacters(in: .whitespacesAndNewlines)
        let hans = han.filter { $0.unicodeScalars.first.map(Zhuyin.isHan) ?? false }.map(String.init)
        switch lang {
        case 6:
            // (英語: the reading in IPA as typed, the same for both; "-" when there isn't one)
            let r = typed.isEmpty ? "-" : typed.replacingOccurrences(of: " ", with: "")
            return [r, r]
        case 5:
            let ws = han.split(separator: " ").map { $0.lowercased() + ":r" }
            return ws.isEmpty ? nil : Array(ws.map { [$0] }.joined(separator: ["_:w"]))
        case 4:
            let k = JaKana.hiragana(typed.isEmpty ? han : typed)
            return k.isEmpty ? nil : [k]
        case 2:
            let t = typed.lowercased()
            let ps = t.contains(" ") ? t.split(separator: " ").map(String.init) : matches(#"[a-z]+[1-6]"#, t)
            guard !ps.isEmpty, ps.allSatisfy(Zhuyin.isJyut), hans.isEmpty || ps.count == hans.count else { return nil }
            return ps
        case 3:
            let t = typed.lowercased()
            let ps = t.contains(" ") ? t.split(separator: " ").map(String.init) : matches(#"[a-z]+[1-8]"#, t)
            let sup = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
            let acc = String(UnicodeScalar(0x2080 + UInt32(min(max(Lang.hakAccent, 0), 9)))!)
            var out: [String] = []
            for p in ps {
                guard let d = p.last?.wholeNumberValue, (1...8).contains(d) else { return nil }
                let letters = String(p.dropLast())
                guard !letters.isEmpty, letters.allSatisfy({ $0.isLetter }) else { return nil }
                out.append(letters + sup[d] + acc)
            }
            guard !out.isEmpty, hans.isEmpty || out.count == hans.count else { return nil }
            return out
        default:
            return dict.zhuyin(typed, han: hans)
        }
    }

    private static func matches(_ pattern: String, _ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }
}

extension ZhDict {
    /// 華語: 拼音 (chi1 fan4, chīfàn, chifan) or 注音 (ㄔ ㄈㄢˋ) → 注音 syllables, one a character. A syllable without
    /// a tone takes the character's own reading with those letters (飯 fan → ㄈㄢˋ); 5 or 0 = light tone.
    func zhuyin(_ typed: String, han: [String]) -> [String]? {
        let n = han.count
        // 注音 as it is (with spaces, or ending at each tone mark)
        if typed.unicodeScalars.contains(where: { (0x3100...0x312F).contains($0.value) }) {
            var ps = typed.split(separator: " ").map(String.init)
            if ps.count != n {
                ps = []
                var cur = ""
                for ch in typed where ch != " " {
                    if ch == "˙" { if !cur.isEmpty { ps.append(cur) }; cur = "˙"; continue }
                    cur.append(ch)
                    if "ˊˇˋ".contains(ch) { ps.append(cur); cur = "" }
                }
                if !cur.isEmpty { ps.append(cur) }
            }
            return ps.count == n || n == 0 ? ps : nil
        }
        // 拼音: letters and their tones (a mark on a vowel, or a number after the syllable)
        var letters: [Character] = []
        var toneAt: [Int: Int] = [:]          // letter index → tone
        let marks: [UInt32: Int] = [0x304: 1, 0x301: 2, 0x30C: 3, 0x300: 4]
        let low = typed.lowercased().replacingOccurrences(of: "u:", with: "v").replacingOccurrences(of: "ü", with: "v")
        var breaks: Set<Int> = []
        for u in low.decomposedStringWithCanonicalMapping.unicodeScalars {
            if let t = marks[u.value] { toneAt[max(letters.count - 1, 0)] = t; continue }
            if u.value == 0x308 { if let l = letters.last, l == "u" { letters[letters.count - 1] = "v" }; continue }
            if let d = Int(String(u)), (0...5).contains(d) { toneAt[max(letters.count - 1, 0)] = d == 5 ? 0 : d; breaks.insert(letters.count); continue }
            if u == " " || u == "'" || u == "-" { breaks.insert(letters.count); continue }
            if CharacterSet.letters.contains(u) { letters.append(Character(u)) }
        }
        let table = pinyinTable
        // split the letters into syllables: at the spaces and numbers first, the longest syllable that fits
        var syls: [(String, Int?)] = []
        var i = 0
        while i < letters.count {
            var best = 0
            for len in stride(from: min(6, letters.count - i), through: 1, by: -1) {
                if (i + 1..<i + len).contains(where: { breaks.contains($0) }) { continue }
                if table[String(letters[i..<i + len])] != nil { best = len; break }
            }
            guard best > 0 else { return nil }
            let t = (i..<i + best).compactMap { toneAt[$0] }.first
            syls.append((String(letters[i..<i + best]), t))
            i += best
        }
        guard !syls.isEmpty, n == 0 || syls.count == n else { return nil }
        var out: [String] = []
        for (j, s) in syls.enumerated() {
            let (p, t) = s
            guard let byTone = table[p] else { return nil }
            if let t, let z = byTone[t] { out.append(z); continue }
            if let t, let any = [1, 2, 3, 4, 0].lazy.compactMap({ byTone[$0] }).first { out.append(Zhuyin.withTone(any, t)); continue }
            // (no tone: the character's own reading with these letters, else the first tone there is)
            if n > 0, let z = charReading(han[j], plain: p) { out.append(z); continue }
            guard let z = [1, 2, 3, 4, 0].lazy.compactMap({ byTone[$0] }).first else { return nil }
            out.append(z)
        }
        return out
    }

    /// a character's reading with these 拼音 letters (飯, "fan" → ㄈㄢˋ)
    private func charReading(_ ch: String, plain: String) -> String? {
        for i in byHan[ch] ?? [] where entries[i].tw.count == 1 {
            let z = entries[i].tw[0]
            if Zhuyin.plainSyllable(z) == plain { return z }
        }
        return nil
    }
}

/// 拼音 letters → tone → 注音, from the dictionary's own syllables (made once)
private final class PinyinTableBox: @unchecked Sendable {
    static let shared = PinyinTableBox()
    let lock = NSLock()
    var table: [String: [Int: String]]?
}
extension ZhDict {
    fileprivate var pinyinTable: [String: [Int: String]] {
        let b = PinyinTableBox.shared
        b.lock.lock(); defer { b.lock.unlock() }
        if let t = b.table { return t }
        var t: [String: [Int: String]] = [:]
        for e in entries.prefix(60_000) where !e.own {
            for z in e.tw where z != "-" && z != "_" && !z.isEmpty {
                let p = Zhuyin.plainSyllable(z)
                guard !p.isEmpty, p.allSatisfy({ $0.isLetter }) else { continue }
                let tone = Zhuyin.tone(z)
                if t[p]?[tone] == nil { t[p, default: [:]][tone] = z }
            }
        }
        b.table = t
        return t
    }
}

// MARK: - 詞典 → 自訂 (華語, 粵語, 客語, 日語, 瑞典語)

struct ZhOwnPane: View {
    let dict: ZhDict
    @EnvironmentObject var store: Store
    @State private var adding = false
    @State private var shareItem: ShareItem?
    @State private var message: String?

    var body: some View {
        let keys = store.zhOwnKeys(dict.lang)
        List {
            Section {
                Button { adding = true } label: {
                    Label(tr("加一個詞"), systemImage: "plus.circle.fill").ffFont(.headline).foregroundStyle(T.ownInk)
                }
                if !keys.isEmpty {
                    Button { export(keys) } label: {
                        Label(tr("匯出 CSV"), systemImage: "square.and.arrow.up").ffFont(.headline).foregroundStyle(T.ownInk)
                    }
                }
                if let message { Text(message).ffFont(.footnote).foregroundStyle(T.muted) }
            } footer: {
                Text(tr("自己加的詞不是詞典的內容，用紫色和「自訂」標示。查詞找得到，也可以加到「不熟」練習。"))
            }
            .listRowBackground(T.fn.opacity(0.7))
            if !keys.isEmpty {
                Section {
                    ForEach(keys, id: \.self) { k in
                        Group {
                            if let e = dict.entry(k) {
                                NavigationLink(value: ZhKey(k: k)) { ZhWordRow(dict: dict, entry: e) }
                            } else {
                                // (added just now: the dictionary is being read again)
                                Text(ZhOwnWords.han(k)).scaledFont(20, weight: .semibold).foregroundStyle(T.ownInk)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { withAnimation { store.removeOwn(k) } } label: { Label(tr("刪除"), systemImage: "trash") }
                        }
                    }
                } header: {
                    Text(tr("\(keys.count) 個詞（往左滑刪除）"))
                }
                .listRowBackground(T.fn.opacity(0.7))
            }
        }
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $adding) { AddZhOwnSheet(dict: dict).environmentObject(store) }
        .sheet(item: $shareItem) { ShareSheet(url: $0.url) }
    }

    /// word, reading (as shown), meaning, example
    private func export(_ keys: [String]) {
        func q(_ s: String) -> String {
            s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
        }
        var rows = ["word,reading,meaning,example"]
        for k in keys {
            let i = store.ownInfo(k)
            let r = String(dict.reading(ZhOwnWords.syllables(k), store.zhRom).characters)
            rows.append([ZhOwnWords.han(k), r, i.meaning, i.example].map(q).joined(separator: ","))
        }
        let text = "\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n"
        let name = "方方-自訂詞-" + ["", "華語", "粵語", "客語", "日語", "瑞典語", "英語"][min(max(dict.lang, 0), 6)] + ".csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if (try? Data(text.utf8).write(to: url, options: .atomic)) != nil { shareItem = ShareItem(url: url) } else { message = trs("匯出失敗。") }
    }
}

/// add a word: the word, its reading (in the language's spelling), meaning, example
struct AddZhOwnSheet: View {
    let dict: ZhDict
    var word0 = ""
    var reading0 = ""
    var meaning0 = ""
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var word = ""
    @State private var reading = ""
    @State private var meaning = ""
    @State private var example = ""
    @State private var problem: String?

    private var lang: Int { dict.lang }
    private var readingHint: String {
        switch lang {
        case 2: return tr("粵拼，要有聲調數字：sik6 faan6")
        case 3: return tr("客語拼音，要有聲調類別的數字：siid8 fan3")
        case 4: return tr("かな（可以不填，詞是かな的話）")
        case 5: return ""
        case 6: return tr("IPA 讀音（可以不填）")
        default: return tr("拼音（chi1 fan4、chīfàn，聲調可以不打）或注音")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(lang >= 5 ? tr("詞") : tr("漢字")) {
                    TextField(lang == 6 ? tr("例：doomscroll") : lang == 5 ? tr("例：fika") : tr("例：吃飯"), text: $word).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                if lang != 5 {
                    Section {
                        TextField(readingHint, text: $reading).autocorrectionDisabled().textInputAutocapitalization(.never)
                        if let r = parsed {
                            Text(dict.reading(r, store.zhRom)).latFont(16).foregroundStyle(T.greenInk)
                        }
                    } header: { Text(tr("讀音")) }
                }
                Section(tr("意思（可以不填）")) { TextField(tr("意思"), text: $meaning, axis: .vertical) }
                Section(tr("例句（可以不填）")) { TextField(tr("例句"), text: $example, axis: .vertical) }
                if let problem { Text(problem).foregroundStyle(T.rustInk) }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .navigationTitle(tr("加一個詞"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(tr("加入")) { add() }.disabled(word.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
        .onAppear { if word.isEmpty { word = word0; reading = reading0; meaning = meaning0 } }
    }

    private var parsed: [String]? {
        let w = word.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty, lang >= 5 || lang == 4 || !reading.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ZhOwnWords.syllables(reading, han: w, lang: lang, dict: dict)
    }

    private func add() {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let tw = parsed else { problem = tr("讀不懂這個讀音：") + readingHint; return }
        let key = ZhOwnWords.key(lang, w, tw)
        if store.isOwn(key) { problem = tr("這個詞已經在「自訂」裡了。"); return }
        store.addZhOwn(key, meaning: meaning, example: example)
        dismiss()
    }
}
