import Foundation

// MARK: - 台語 words' English (Wiktionary)
//
// tw_en.json (tools/build_tw_english.py): English meanings for the 教育部 dictionary's words, from the Wiktionary
// pages with the same 漢字 and the same Hokkien reading. A file of its own: the dictionary's data and its search
// results stay as they are; the English is only added (a line on a word's page, a section in the search).

enum TwEnglish {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var table: [String: String]?
    /// words with meanings Wiktionary marks as Hokkien's own (they come first among equals)
    nonisolated(unsafe) private static var hokkien: Set<String> = []

    /// key → meanings (read the first time; empty when the file isn't there)
    private static var all: [String: String] {
        lock.lock(); defer { lock.unlock() }
        if let t = table { return t }
        var t: [String: String] = [:], h = Set<String>()
        if let url = Bundle.main.url(forResource: "tw_en", withExtension: "json"),
           let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let e = obj["e"] as? [String: String] {
            for (k, v) in e {
                if v.hasPrefix("*") { t[k] = String(v.dropFirst()); h.insert(k) } else { t[k] = v }
            }
        }
        table = t; hokkien = h
        return t
    }

    static var available: Bool { !all.isEmpty }

    /// a word's English meanings, one each
    static func meanings(_ key: String) -> [String] {
        guard let s = all[key] else { return [] }
        return s.components(separatedBy: "; ").filter { !$0.isEmpty }
    }

    /// the words whose English has the word(s): a meaning that is just the word first ("eat", "to eat"), then
    /// meanings that start with it, then the rest; "to park" (a verb) before "park" (a noun) and the other way round;
    /// the closer the meaning is to the word, the higher ("quality" before "good quality" before a long description
    /// that has "quality" somewhere in it); among equals, Hokkien's own meanings first, then the shorter words
    static func search(_ q0: String, limit: Int = 200) -> [String] {
        let q = q0.enFold.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 || q == "i" || q == "a", q.unicodeScalars.allSatisfy({ $0.isASCII }) else { return [] }
        let t = all
        let wantVerb = q.hasPrefix("to ")
        let bare = wantVerb ? String(q.dropFirst(3)) : q
        let inWord = #"[^a-z]"# + NSRegularExpression.escapedPattern(for: bare) + #"[^a-z]"#
        let qWords = bare.split(separator: " ").count
        var hits: [(tier: Int, later: Int, hok: Int, len: Int, k: String)] = []
        for (k, en0) in t {
            let en = en0.enFold
            guard en.contains(bare) else { continue }
            var best = 99, bestPos = 1
            for (pos, g0) in en.components(separatedBy: "; ").enumerated() {
                var g = g0
                var noted = false
                while let r = g.range(of: #"\([^()]*\)"#, options: .regularExpression) { g.removeSubrange(r); noted = true }
                // (several meanings in one: "to eat, to have a meal")
                for part in g.components(separatedBy: ",") {
                    let p = part.trimmingCharacters(in: .whitespaces)
                    let isVerb = p.hasPrefix("to ")
                    let v = isVerb ? String(p.dropFirst(3)) : p
                    var tier = 9
                    if v == bare { tier = 0 }
                    else if v.hasPrefix(bare + " ") { tier = 2 }
                    else if (" " + v + " ").range(of: inWord, options: .regularExpression) != nil { tier = 4 }
                    if tier < 9 && isVerb != wantVerb && (wantVerb || tier == 0) { tier += wantVerb ? 2 : 1 }
                    if tier < 9 && noted { tier += 1 }
                    guard tier < 9 else { continue }
                    // how much more the meaning says than the word (each word more: a little lower; a long
                    // description that only mentions it: at the end)
                    let extra = max(0, v.split(separator: " ").count - qWords)
                    tier = tier * 10 + min(extra, 9) + (extra > 4 ? 20 : 0)
                    let p0 = pos == 0 ? 0 : 1
                    if tier < best || (tier == best && p0 < bestPos) { best = tier; bestPos = p0 }
                }
            }
            if best < 90 {
                let han = k.split(separator: "\t").first.map(String.init) ?? k
                hits.append((best, bestPos, hokkien.contains(k) ? 0 : 1, han.count, k))
            }
        }
        hits.sort { ($0.tier, $0.later, $0.hok, $0.len, $0.k) < ($1.tier, $1.later, $1.hok, $1.len, $1.k) }
        return Array(hits.prefix(limit).map { $0.k })
    }
}
