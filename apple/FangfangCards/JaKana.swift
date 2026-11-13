import Foundation

// MARK: - 日語: kana and rōmaji (the dictionary itself is ZhDict, read from ja.json like 華語 / 粵語 / 客語)

enum JaKana {
    static func isHiragana(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) } }
    static func isKatakana(_ c: Character) -> Bool { c.unicodeScalars.allSatisfy { (0x30A0...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value) } }
    static func isKanji(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) || $0.value == 0x3005 || (0x20000...0x2FA1F).contains($0.value) }
    }

    /// katakana → hiragana (ー stays)
    static func hiragana(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { u in
            (0x30A1...0x30F6).contains(u.value) ? Unicode.Scalar(u.value - 0x60)! : u
        }))
    }
    static func katakana(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { u in
            (0x3041...0x3096).contains(u.value) ? Unicode.Scalar(u.value + 0x60)! : u
        }))
    }

    private static let table: [(String, String)] = {
        var t: [(String, String)] = [
            ("kya", "きゃ"), ("kyu", "きゅ"), ("kyo", "きょ"), ("sha", "しゃ"), ("shu", "しゅ"), ("sho", "しょ"), ("she", "しぇ"),
            ("cha", "ちゃ"), ("chu", "ちゅ"), ("cho", "ちょ"), ("che", "ちぇ"), ("nya", "にゃ"), ("nyu", "にゅ"), ("nyo", "にょ"),
            ("hya", "ひゃ"), ("hyu", "ひゅ"), ("hyo", "ひょ"), ("mya", "みゃ"), ("myu", "みゅ"), ("myo", "みょ"),
            ("rya", "りゃ"), ("ryu", "りゅ"), ("ryo", "りょ"), ("gya", "ぎゃ"), ("gyu", "ぎゅ"), ("gyo", "ぎょ"),
            ("ja", "じゃ"), ("ju", "じゅ"), ("jo", "じょ"), ("je", "じぇ"), ("bya", "びゃ"), ("byu", "びゅ"), ("byo", "びょ"),
            ("pya", "ぴゃ"), ("pyu", "ぴゅ"), ("pyo", "ぴょ"), ("tsu", "つ"), ("shi", "し"), ("chi", "ち"),
            ("sya", "しゃ"), ("syu", "しゅ"), ("syo", "しょ"), ("tya", "ちゃ"), ("tyu", "ちゅ"), ("tyo", "ちょ"),
            ("jya", "じゃ"), ("jyu", "じゅ"), ("jyo", "じょ"), ("dzu", "づ"), ("fa", "ふぁ"), ("fi", "ふぃ"), ("fe", "ふぇ"), ("fo", "ふぉ"),
            ("ti", "てぃ"), ("di", "でぃ"), ("tu", "つ"), ("si", "し"), ("zi", "じ"), ("hu", "ふ"), ("fu", "ふ"), ("ji", "じ"),
            ("wo", "を"), ("wa", "わ"), ("ya", "や"), ("yu", "ゆ"), ("yo", "よ"), ("nn", "ん"), ("n'", "ん"), ("-", "ー"),
            ("a", "あ"), ("i", "い"), ("u", "う"), ("e", "え"), ("o", "お"),
        ]
        let rows: [(String, String)] = [("k", "かきくけこ"), ("g", "がぎぐげご"), ("s", "さ_すせそ"), ("z", "ざ_ずぜぞ"),
                                         ("t", "た__てと"), ("d", "だぢづでど"), ("n", "なにぬねの"), ("h", "はひ_へほ"),
                                         ("b", "ばびぶべぼ"), ("p", "ぱぴぷぺぽ"), ("m", "まみむめも"), ("r", "らりるれろ")]
        for (c, ks) in rows {
            for (v, k) in zip(["a", "i", "u", "e", "o"], ks) where k != "_" { t.append((c + v, String(k))) }
        }
        return t.sorted { $0.0.count > $1.0.count }
    }()

    /// rōmaji (Hepburn, or the keyboard ways) → hiragana; nil when it isn't rōmaji
    static func fromRomaji(_ s: String) -> String? {
        let cs = Array(s.lowercased())
        var out = ""
        var i = 0
        while i < cs.count {
            let c = cs[i]
            if c == " " { i += 1; continue }
            // a doubled consonant: っ
            if i + 1 < cs.count, c == cs[i + 1], c.isLetter, !"aeioun".contains(c) { out += "っ"; i += 1; continue }
            if c == "t", i + 2 < cs.count, cs[i + 1] == "c", cs[i + 2] == "h" { out += "っ"; i += 1; continue }
            var hit = false
            for (r, k) in table where i + r.count <= cs.count && String(cs[i..<(i + r.count)]) == r {
                out += k; i += r.count; hit = true; break
            }
            if hit { continue }
            // n before a consonant (or at the end)
            if c == "n" { out += "ん"; i += 1; continue }
            return nil
        }
        return out.isEmpty ? nil : out
    }

    private static let back: [String: String] = {
        var m: [String: String] = [:]
        for (r, k) in table where m[k] == nil && !["si", "zi", "tu", "hu", "sya", "syu", "syo", "tya", "tyu", "tyo", "jya", "jyu", "jyo", "nn", "n'", "dzu"].contains(r) {
            m[k] = r
        }
        m["ん"] = "n"; m["を"] = "o"; m["づ"] = "zu"; m["ぢ"] = "ji"
        return m
    }()

    /// hiragana or katakana → rōmaji (Hepburn)
    static func romaji(_ s: String) -> String {
        let cs = Array(hiragana(s))
        var out = ""
        var i = 0
        var double = false
        var afterN = false
        while i < cs.count {
            if cs[i] == "っ" { double = true; i += 1; continue }
            let isN = cs[i] == "ん"
            var p: String
            if i + 1 < cs.count, let r = back[String(cs[i...(i + 1)])] { p = r; i += 2 }
            else if let r = back[String(cs[i])] { p = r; i += 1 }
            else if cs[i] == "ー", let last = out.last { p = String(last); i += 1 }
            else { p = String(cs[i]); i += 1 }
            if double, let f = p.first { p = (p.hasPrefix("ch") ? "t" : String(f)) + p; double = false }
            // (ん before a vowel or y: n')
            if afterN, let f = p.first, "aiueoy".contains(f) { out += "'" }
            out += p
            afterN = isN
        }
        return out
    }
}
