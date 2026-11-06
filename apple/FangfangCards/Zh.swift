import Foundation
import SwiftUI
import AVFoundation

// MARK: - 華語 mode
//
// The 華語 deck comes from 《兩岸常用詞典》 (中華文化總會), built into zh.json by tools/build_mandarin.py.
// The dictionary's 注音 is kept as it is; 漢語拼音 is spelled from it here, by rule.

enum Lang {
    /// 0 = 台語, 1 = 華語
    static let key = "lang"
    static var isZh: Bool { UserDefaults.standard.integer(forKey: key) == 1 }
    /// 華語 reading: 0 = 拼音, 1 = 注音
    static let romKey = "zhRom"
    static var zhRom: Int { UserDefaults.standard.integer(forKey: romKey) }
    /// 華語 reading of: 0 = 臺灣, 1 = 大陸
    static let placeKey = "zhPlace"
    static var zhPlace: Int { UserDefaults.standard.integer(forKey: placeKey) }
    static let romNames = ["拼音", "注音"]
    /// HSK 3.0 levels (7 = 7–9)
    static func hskName(_ l: Int) -> String { l >= 7 ? "HSK 7–9" : "HSK \(l)" }
    /// the word list the 華語 cards follow: 0 = HSK 3.0, 1 = TOCFL
    static let listKey = "zhList"
    static var zhList: Int { UserDefaults.standard.integer(forKey: listKey) }
    static let listNames = ["HSK", "TOCFL"]
    static let tocflNames = ["", "準備一級", "準備二級", "入門級", "基礎級", "進階級", "高階級", "流利級"]
    static func tocflName(_ l: Int) -> String { l > 0 && l < tocflNames.count ? tocflNames[l] : "" }
    static func levelName(_ list: Int, _ l: Int) -> String { list == 1 ? "TOCFL " + tocflName(l) : hskName(l) }
    static let placeNames = ["臺灣", "大陸"]

    /// a 華語 word's key: "漢字\t注音" (台語 keys have syllable codes in letters after the tab)
    static func isZhKey(_ k: String) -> Bool {
        guard let t = k.firstIndex(of: "\t"), let s = k[k.index(after: t)...].unicodeScalars.first else { return false }
        return (0x3100...0x312F).contains(s.value) || (0x31A0...0x31BF).contains(s.value) || s == "˙" || s == "字"
    }
    /// a character card's key: "好\t字"
    static func charKey(_ ch: String) -> String { ch + "\t字" }
    /// the character of a character card's key (nil = a word)
    static func charOf(_ k: String) -> String? { k.hasSuffix("\t字") ? String(k.dropLast(2)) : nil }
    /// the 新詞 topics of the character cards: 100 + level, 108 = more characters
    static let charTopicBase = 100
    static let moreChars = 108
    /// 台語: the most common words, 500 a group (1000 + group), and the most common characters (2000 + group)
    static let freqWordBase = 1000
    static let freqCharBase = 2000
    static let freqSize = 500
    static func isFreqTopic(_ t: Int) -> Bool { t >= freqWordBase }
    static func freqName(_ t: Int, count: Int) -> String {
        let g = t >= freqCharBase ? t - freqCharBase : t - freqWordBase
        return (t >= freqCharBase ? "常用字 " : "常用詞 ") + "\(g * freqSize + 1)–\(g * freqSize + count)"
    }
}

// MARK: - 注音 → 拼音

enum Zhuyin {
    private static let initials: [Character: String] = [
        "ㄅ": "b", "ㄆ": "p", "ㄇ": "m", "ㄈ": "f", "ㄉ": "d", "ㄊ": "t", "ㄋ": "n", "ㄌ": "l", "ㄍ": "g", "ㄎ": "k",
        "ㄏ": "h", "ㄐ": "j", "ㄑ": "q", "ㄒ": "x", "ㄓ": "zh", "ㄔ": "ch", "ㄕ": "sh", "ㄖ": "r", "ㄗ": "z", "ㄘ": "c", "ㄙ": "s"]
    private static let finals: [String: String] = [
        "": "", "ㄚ": "a", "ㄛ": "o", "ㄜ": "e", "ㄝ": "ê", "ㄞ": "ai", "ㄟ": "ei", "ㄠ": "ao", "ㄡ": "ou",
        "ㄢ": "an", "ㄣ": "en", "ㄤ": "ang", "ㄥ": "eng", "ㄦ": "er",
        "ㄧ": "i", "ㄧㄚ": "ia", "ㄧㄛ": "io", "ㄧㄝ": "ie", "ㄧㄞ": "iai", "ㄧㄠ": "iao", "ㄧㄡ": "iu",
        "ㄧㄢ": "ian", "ㄧㄣ": "in", "ㄧㄤ": "iang", "ㄧㄥ": "ing",
        "ㄨ": "u", "ㄨㄚ": "ua", "ㄨㄛ": "uo", "ㄨㄞ": "uai", "ㄨㄟ": "ui", "ㄨㄢ": "uan", "ㄨㄣ": "un",
        "ㄨㄤ": "uang", "ㄨㄥ": "ong",
        "ㄩ": "ü", "ㄩㄝ": "üe", "ㄩㄢ": "üan", "ㄩㄣ": "ün", "ㄩㄥ": "iong"]
    private static let alone: [String: String] = [
        "i": "yi", "ia": "ya", "io": "yo", "ie": "ye", "iai": "yai", "iao": "yao", "iu": "you", "ian": "yan",
        "in": "yin", "iang": "yang", "ing": "ying", "u": "wu", "ua": "wa", "uo": "wo", "uai": "wai",
        "ui": "wei", "uan": "wan", "un": "wen", "uang": "wang", "ong": "weng", "ü": "yu", "üe": "yue",
        "üan": "yuan", "ün": "yun", "iong": "yong"]
    private static let marks: [Character: [String]] = [
        "a": ["ā", "á", "ǎ", "à"], "e": ["ē", "é", "ě", "è"], "i": ["ī", "í", "ǐ", "ì"], "o": ["ō", "ó", "ǒ", "ò"],
        "u": ["ū", "ú", "ǔ", "ù"], "ü": ["ǖ", "ǘ", "ǚ", "ǜ"], "ê": ["ê̄", "ế", "ê̌", "ề"]]
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    /// the tone of a syllable: 1–4, 0 = light tone (˙)
    static func tone(_ s: String) -> Int {
        if s.hasPrefix("˙") || s.hasSuffix("˙") { return 0 }
        switch s.last {
        case "ˊ": return 2
        case "ˇ": return 3
        case "ˋ": return 4
        default: return 1
        }
    }

    /// the letters without the tone mark
    static func bare(_ s: String) -> String { s.filter { !"ˊˇˋ˙".contains($0) } }

    /// the syllable with another tone
    static func withTone(_ s: String, _ t: Int) -> String {
        let b = bare(s)
        switch t {
        case 0: return "˙" + b
        case 2: return b + "ˊ"
        case 3: return b + "ˇ"
        case 4: return b + "ˋ"
        default: return b
        }
    }

    /// one 注音 syllable in 拼音 with its tone mark ("" when it can't be spelled)
    static func pinyin(_ s: String) -> String {
        lock.lock(); if let c = cache[s] { lock.unlock(); return c }; lock.unlock()
        let r = spell(s)
        lock.lock(); cache[s] = r; lock.unlock()
        return r
    }

    private static func spell(_ s0: String) -> String {
        let t = tone(s0)
        var s = bare(s0)
        guard !s.isEmpty else { return "" }
        var er = false
        if s.count > 1, s.hasSuffix("ㄦ") { er = true; s.removeLast() }
        let ini = s.first.flatMap { initials[$0] } ?? ""
        let rest = ini.isEmpty ? s : String(s.dropFirst())
        guard var f = finals[rest] else { return s0 }
        var p: String
        if !ini.isEmpty {
            if f.isEmpty {
                guard ["zh", "ch", "sh", "r", "z", "c", "s"].contains(ini) else { return s0 }
                f = "i"
            }
            if ["j", "q", "x"].contains(ini) { f = f.replacingOccurrences(of: "ü", with: "u") }
            p = ini + f
        } else {
            p = alone[f] ?? f
        }
        if er { p += "r" }
        guard (1...4).contains(t) else { return p }
        // where the tone mark goes: a, e (ê), o in ou, else the last vowel
        let chars = Array(p)
        var v: Int?
        if let i = chars.firstIndex(of: "a") { v = i }
        else if let i = chars.firstIndex(of: "e") { v = i }
        else if let i = chars.firstIndex(of: "ê") { v = i }
        else if let i = chars.firstIndex(of: "o"), i + 1 < chars.count, chars[i + 1] == "u" { v = i }
        else { v = chars.lastIndex { "iouü".contains($0) } }
        guard let i = v, let m = marks[chars[i]] else { return p }
        return String(chars[..<i]) + m[t - 1] + String(chars[(i + 1)...])
    }

    /// a word's syllables as one word: chīfàn, Xī'ān
    static func joinPinyin(_ sy: [String]) -> String {
        var s = ""
        for p in sy where !p.isEmpty {
            if !s.isEmpty, let f = p.first, "aāáǎàoōóǒòeēéěèê".contains(f) { s += "'" }
            s += p
        }
        return s
    }

    private static var plainCache: [String: String] = [:]
    /// one 注音 syllable as 拼音 letters without tone, for searching ("ㄔ" → "chi", "ㄌㄩˋ" → "lv")
    static func plainSyllable(_ s: String) -> String {
        let b = bare(s)
        lock.lock(); if let c = plainCache[b] { lock.unlock(); return c }; lock.unlock()
        let r = plain(pinyin(b))
        lock.lock(); plainCache[b] = r; lock.unlock()
        return r
    }

    /// 拼音 without tone marks, for searching: ü → v
    static func plain(_ s: String) -> String {
        let a = s.lowercased().replacingOccurrences(of: "ü", with: "v").replacingOccurrences(of: "u:", with: "v")
        return a.applyingTransform(.stripDiacritics, reverse: false)?.filter { $0.isLetter || $0.isNumber } ?? a
    }

    /// the colour of a 華語 tone (the 台語 colours: 1 red, 2 like 台語 5, 3 blue, 4 like 台語 2, light grey)
    static func color(_ t: Int, _ sys: Int) -> Color? {
        guard sys != 0 else { return nil }
        switch t {
        case 0...4: return ToneColors.zhColor(t)       // the colours picked in 設定 (red, green, blue, purple, grey)
        default: return nil
        }
    }

    static func isHan(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        return (0x3400...0x9FFF).contains(v) || (0x20000...0x3FFFF).contains(v) || (0xF900...0xFAFF).contains(v)
    }
}

// MARK: - the 華語 dictionary

struct ZhEx {
    let h: String           // the sentence
    let src: String         // where it's from (old books), or a note
    let code: String        // its reading, word by word (see build_mandarin.py)
}

struct ZhSense {
    let n: Int
    let text: String
    let ex: [ZhEx]
}

struct ZhEntry {
    let k: String
    let h: String
    let tw: [String]        // 注音 syllables, one per 漢字 ("-" = 兒 sharing the syllable before)
    let lu: [String]?       // 大陸 reading, where it differs
    let spec: Int           // 1 臺灣特有, 2 大陸特有
    let alt: String?        // 簡化字
    let senses: [ZhSense]
    var en: String? = nil   // English (CC-CEDICT)
    var hsk = 0             // HSK 3.0 level (1–6, 7 = 7–9), 0 = not on the list
    var tocfl = 0           // TOCFL level (1 準備一級 … 7 流利級), 0 = not on the list
    /// the level on a word list (0 HSK, 1 TOCFL)
    func level(_ list: Int) -> Int { list == 1 ? tocfl : hsk }
    var extra = false       // an HSK word the dictionary doesn't have (added, with the English meaning)
    var pos: [String] = []  // 詞類 (from the HSK / TOCFL lists), in the 台語 dictionary's names
    var syn: [String] = []  // 近義詞 (教育部《重編國語辭典修訂本》)
    var ant: [String] = []  // 反義詞
    /// the English meanings, one each (CC-CEDICT separates them with ;)
    var enList: [String] {
        (en ?? "").components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// syllables for 臺灣 (0) or 大陸 (1)
    func syl(_ place: Int) -> [String] { place == 1 ? (lu ?? tw) : tw }
}

/// a radical and its characters, for looking a character up by its 部首
struct ZhRadical: Identifiable {
    let radical: String
    let strokes: Int
    let chars: [(ch: String, rest: Int)]
    var id: String { radical }
}

/// a character with its meanings from 教育部《重編國語辭典修訂本》 (each reading: 注音, 拼音, [(詞類, meaning)])
struct ZhChar {
    struct Reading { let zy: String; let py: String; let defs: [(pos: String, text: String)]; let label: String? }
    let h: String
    let readings: [Reading]     // the usual reading first
    let hsk: Int                // HSK 3.0 character level (7 = 7–9), 0 = not on the list
    let tocfl: Int              // TOCFL (TBCL) character level, 0 = not on the list
    let radical: String?
    let strokes: Int?
    func level(_ list: Int) -> Int { list == 1 ? tocfl : hsk }
}

/// one word of a sentence: its characters and, for each character, its syllable ("_" = not a 漢字)
struct ZhPiece {
    let text: [String]
    let tw: [String]?
    let lu: [String]?
    func syl(_ place: Int) -> [String]? { place == 1 ? (lu ?? tw) : tw }
}

final class ZhDict: @unchecked Sendable {
    let entries: [ZhEntry]
    /// how many of the first entries are study cards (the rest are rare words and references)
    let cardCount: Int
    let index: [String: Int]
    let byHan: [String: [Int]]
    private let byPlain: [String: [Int]]       // 拼音 without tones: "chifan"
    private let byToned: [String: [Int]]       // "chi1fan4"
    private let byZy: [String: [Int]]          // 注音 without tones
    private let byZyToned: [String: [Int]]
    let maxLen: Int
    /// the character cards (教育部《重編國語辭典修訂本》), the listed ones first, the more common first
    let chars: [ZhChar]
    let charIndex: [String: Int]
    /// 部首 lookup: the radicals (fewest strokes first) with their characters (by the strokes besides the radical)
    let radicals: [ZhRadical]
    /// 部首組合: radical → every character with it anywhere inside (empty with an older zh.json)
    let radicalInside: [String: [String]]
    /// a character's number of strokes
    let strokesOf: [String: Int]

    /// the same as sets (made the first time they're needed)
    lazy var radicalSets: [String: Set<String>] = radicalInside.mapValues { Set($0) }

    /// the characters that have all these radicals inside them (fewest strokes first)
    func charsWith(radicals rs: [String]) -> [String] {
        guard let first = rs.min(by: { (radicalInside[$0]?.count ?? 0) < (radicalInside[$1]?.count ?? 0) }),
              let base = radicalInside[first] else { return [] }
        let others = rs.filter { $0 != first }.map { radicalSets[$0] ?? [] }
        return base.filter { c in others.allSatisfy { $0.contains(c) } }
    }

    /// one entry of zh.json
    private static func makeEntry(_ e: [String: Any]) -> ZhEntry? {
        guard let k = e["k"] as? String, let h = e["h"] as? String, let s = e["s"] as? String else { return nil }
        var senses: [ZhSense] = []
        for (i, d) in (e["d"] as? [[Any]] ?? []).enumerated() {
            let t = d.first as? String ?? ""
            let xs = (d.count > 1 ? d[1] as? [[String]] : nil) ?? []
            senses.append(ZhSense(n: i + 1, text: t, ex: xs.map { ZhEx(h: $0[0], src: $0.count > 1 ? $0[1] : "", code: $0.count > 2 ? $0[2] : "") }))
        }
        return ZhEntry(k: k, h: h, tw: s.components(separatedBy: " "),
                       lu: (e["l"] as? String)?.components(separatedBy: " "),
                       spec: e["p"] as? Int ?? 0, alt: e["a"] as? String, senses: senses, en: e["n"] as? String,
                       hsk: e["x"] as? Int ?? 0, tocfl: e["y"] as? Int ?? 0, extra: (e["q"] as? Int ?? 0) == 1,
                       pos: e["w"] as? [String] ?? [], syn: e["j"] as? [String] ?? [], ant: e["f"] as? [String] ?? [])
    }

    /// reads zh.json: the entries are one per line at the end, so they're read in parts on all the cores at
    /// the same time (much faster than one big read); an older file (all on one line) is read in one go
    private static func readFile(_ data: Data) throws -> (obj: [String: Any], entries: [ZhEntry]) {
        let marker = Data(",\"e\":[\n".utf8)
        guard let r = data.range(of: marker) else {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let es = obj["e"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            return (obj, es.compactMap { makeEntry($0) })
        }
        var head = Data(data[data.startIndex..<r.lowerBound])
        head.append(contentsOf: Array("}".utf8))
        guard let obj = try JSONSerialization.jsonObject(with: head) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        // where each line starts and ends
        let start = r.upperBound
        var lines: [Range<Int>] = []
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let base = data.startIndex
            var a = start - base
            let n = buf.count
            for i in a..<n where buf[i] == 0x0A {
                lines.append((a + base)..<(i + base)); a = i + 1
            }
            if a < n { lines.append((a + base)..<(n + base)) }
        }
        // the last line is "]}"
        lines = lines.filter { $0.count > 2 }
        let parts = max(4, ProcessInfo.processInfo.activeProcessorCount * 2)
        let per = (lines.count + parts - 1) / max(parts, 1)
        var results = [[ZhEntry]](repeating: [], count: parts)
        var failed = false
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: parts) { p in
            let lo = p * per, hi = min(lines.count, lo + per)
            guard lo < hi else { return }
            var chunk = Data("[".utf8)
            for i in lo..<hi {
                var l = lines[i]
                if data[l.upperBound - 1] == UInt8(ascii: ",") { l = l.lowerBound..<(l.upperBound - 1) }
                if i > lo { chunk.append(UInt8(ascii: ",")) }
                chunk.append(data[l])
            }
            chunk.append(UInt8(ascii: "]"))
            guard let es = (try? JSONSerialization.jsonObject(with: chunk)) as? [[String: Any]] else {
                lock.lock(); failed = true; lock.unlock(); return
            }
            let made = es.compactMap { makeEntry($0) }
            lock.lock(); results[p] = made; lock.unlock()
        }
        if failed { throw CocoaError(.fileReadCorruptFile) }
        return (obj, results.flatMap { $0 })
    }

    init(data: Data) throws {
        let (obj, out) = try Self.readFile(data)
        cardCount = obj["nc"] as? Int ?? out.count
        var m = 1
        var index: [String: Int] = [:], byHan: [String: [Int]] = [:]
        var byPlain: [String: [Int]] = [:], byToned: [String: [Int]] = [:], byZy: [String: [Int]] = [:], byZyToned: [String: [Int]] = [:]
        for (i, e) in out.enumerated() {
            index[e.k] = i
            byHan[e.h, default: []].append(i)
            if let a = e.alt, a != e.h { byHan[a, default: []].append(i) }
            m = max(m, e.h.unicodeScalars.count)
            for syl in [e.tw] + (e.lu.map { [$0] } ?? []) {
                let ss = syl.filter { $0 != "-" }
                let py = ss.map { Zhuyin.plainSyllable($0) }
                let toned = zip(ss, py).map { $1 + ([1, 2, 3, 4].contains(Zhuyin.tone($0)) ? String(Zhuyin.tone($0)) : "") }
                Self.add(&byPlain, py.joined(), i)
                Self.add(&byToned, toned.joined(), i)
                Self.add(&byZy, ss.map { Zhuyin.bare($0) }.joined(), i)
                Self.add(&byZyToned, ss.joined(), i)
            }
        }
        entries = out
        self.index = index; self.byHan = byHan
        self.byPlain = byPlain; self.byToned = byToned; self.byZy = byZy; self.byZyToned = byZyToned
        maxLen = min(m, 12)
        var cs: [ZhChar] = []
        for c in obj["c"] as? [[String: Any]] ?? [] {
            guard let h = c["h"] as? String else { continue }
            var rs: [ZhChar.Reading] = []
            for r in c["m"] as? [[Any]] ?? [] {
                guard r.count >= 3, let zy = r[0] as? String, let py = r[1] as? String, let ds = r[2] as? [[String]] else { continue }
                rs.append(ZhChar.Reading(zy: zy, py: py, defs: ds.map { (pos: $0.first ?? "", text: $0.count > 1 ? $0[1] : "") },
                                         label: r.count > 3 ? r[3] as? String : nil))
            }
            guard !rs.isEmpty else { continue }
            cs.append(ZhChar(h: h, readings: rs, hsk: c["x"] as? Int ?? 0, tocfl: c["y"] as? Int ?? 0,
                             radical: c["b"] as? String, strokes: c["n"] as? Int))
        }
        chars = cs
        var rads: [ZhRadical] = []
        for r in obj["r"] as? [[Any]] ?? [] {
            guard r.count >= 4, let rad = r[0] as? String, let n = r[1] as? Int, let cs = r[2] as? String, let res = r[3] as? [Int] else { continue }
            let list = cs.unicodeScalars.map { String($0) }
            rads.append(ZhRadical(radical: rad, strokes: n, chars: Array(zip(list, res).map { (ch: $0.0, rest: $0.1) })))
        }
        radicals = rads
        // 部首組合: the characters with each radical anywhere inside (fewest strokes first); and every
        // character's strokes (the radical's + the rest)
        var inside: [String: [String]] = [:]
        for (r, v) in obj["rx"] as? [String: String] ?? [:] { inside[r] = v.unicodeScalars.map { String($0) } }
        radicalInside = inside
        var st: [String: Int] = [:]
        for r in rads { for c in r.chars where st[c.ch] == nil { st[c.ch] = r.strokes + c.rest } }
        strokesOf = st
        var ci: [String: Int] = [:]
        for (i, c) in cs.enumerated() { ci[c.h] = i }
        charIndex = ci
    }

    /// a character as a card: its usual reading and that reading's meanings; the other readings as 又
    func charCard(_ i: Int, list: Int = Lang.zhList) -> Card {
        let c = chars[i]
        let main = c.readings[0]
        let defs = main.defs.map { Def(p: $0.pos, t: $0.text, x: [], sy: nil, an: nil) }
        let others = c.readings.dropFirst().map { Other(l: $0.label ?? "又", r: [$0.py], z: $0.zy) }
        let l = c.level(list)
        let topic = l > 0 ? Lang.charTopicBase + l : Lang.moreChars
        return Card(k: Lang.charKey(c.h), h: c.h, r: [main.py], z: main.zy, a: nil, g: "", d: defs,
                    c: nil, zo: nil, v: nil, o: others.isEmpty ? nil : Array(others), s: nil, t: "漢字",
                    sy: nil, an: nil, cats: [topic], zs: [main.zy], zl: nil)
    }

    /// the dictionary entry of a character read a certain way (for 「查詞典」 on a character card)
    func entry(char ch: String, zy: String) -> ZhEntry? {
        (byHan[ch] ?? []).map { entries[$0] }.first { $0.h == ch && $0.tw.first == zy }
            ?? (byHan[ch] ?? []).map { entries[$0] }.first { $0.h == ch }
    }

    private static func add(_ d: inout [String: [Int]], _ k: String, _ i: Int) {
        if d[k]?.last != i { d[k, default: []].append(i) }
    }

    func entry(_ k: String) -> ZhEntry? { index[k].map { entries[$0] } }

    /// the other readings of the same 漢字
    func others(_ e: ZhEntry) -> [ZhEntry] { (byHan[e.h] ?? []).map { entries[$0] }.filter { $0.k != e.k && $0.h == e.h } }

    // MARK: readings

    /// a word's reading: 0 = 拼音, 1 = 注音; in tone colours when they're on
    func reading(_ syl: [String], _ mode: Int, colours: Int = ToneColors.system) -> AttributedString {
        var out = AttributedString()
        var first = true
        for s in syl where s != "-" && s != "_" {
            var a: AttributedString
            if mode == 1 {
                a = AttributedString((first ? "" : "\u{2009}") + s)
            } else {
                let p = Zhuyin.pinyin(s)
                let apos = !first && (p.first.map { "aāáǎàoōóǒòeēéěèê".contains($0) } ?? false)
                a = AttributedString((apos ? "'" : "") + p)
            }
            if let c = Zhuyin.color(Zhuyin.tone(s), colours) { a.swiftUI.foregroundColor = c }
            out += a
            first = false
        }
        return out
    }

    func readingPlain(_ syl: [String], _ mode: Int) -> String { String(reading(syl, mode, colours: 0).characters) }

    /// 漢字 in tone colours (one syllable per 漢字; 兒 after -ㄦ takes the colour before it)
    func hanText(_ han: String, _ syl: [String], base: Color?, colours: Int = ToneColors.system) -> AttributedString {
        var out = AttributedString(), i = 0, last = 1
        for u in han.unicodeScalars {
            var a = AttributedString(String(u))
            if Zhuyin.isHan(u), i < syl.count {
                let s = syl[i]; i += 1
                let t = s == "-" ? last : Zhuyin.tone(s)
                last = t
                if let c = Zhuyin.color(t, colours) { a.swiftUI.foregroundColor = c } else if let base { a.swiftUI.foregroundColor = base }
            } else if let base { a.swiftUI.foregroundColor = base }
            out += a
        }
        return out
    }

    // MARK: sentences

    static func pieces(_ x: ZhEx) -> [ZhPiece] { pieces(x.h, x.code) }

    static func pieces(_ text: String, _ code: String) -> [ZhPiece] {
        let chars = text.unicodeScalars.map { String($0) }
        var out: [ZhPiece] = []
        var i = 0
        for part in code.components(separatedBy: "|") {
            guard i < chars.count else { break }
            if part.isEmpty {
                out.append(ZhPiece(text: [chars[i]], tw: nil, lu: nil)); i += 1; continue
            }
            let sides = part.components(separatedBy: "/")
            let tw = sides[0].components(separatedBy: " ")
            let lu = sides.count > 1 ? sides[1].components(separatedBy: " ") : nil
            let n = min(tw.count, chars.count - i)
            out.append(ZhPiece(text: Array(chars[i..<i + n]), tw: tw, lu: lu))
            i += n
        }
        while i < chars.count { out.append(ZhPiece(text: [chars[i]], tw: nil, lu: nil)); i += 1 }
        return out
    }

    private static let pinyinPunct: [String: String] = [
        "，": ", ", "。": ". ", "、": ", ", "？": "? ", "！": "! ", "：": ": ", "；": "; ",
        "「": "“", "」": "” ", "『": "‘", "』": "’ ", "（": " (", "）": ") ", "…": "…", "—": "—", "─": "—"]

    /// a sentence's reading (0 拼音, 1 注音); `blank` = the word to leave out (例句填空)
    func sentence(_ ps: [ZhPiece], _ mode: Int, _ place: Int, blank: String? = nil, colours: Int = ToneColors.system) -> AttributedString {
        var out = AttributedString()
        var prevWord = false
        for p in ps {
            if let syl = p.syl(place) {
                if prevWord { out += AttributedString(" ") }
                if let blank, p.text.joined() == blank {
                    out += AttributedString("＿＿")
                } else {
                    // characters that aren't 漢字 inside a word (a comma in a saying) stay as they are
                    var word = AttributedString(), sy: [String] = []
                    func flush() { if !sy.isEmpty { word += reading(sy, mode, colours: colours); sy = [] } }
                    for (i, s) in syl.enumerated() {
                        if s == "_" {
                            flush()
                            let ch = i < p.text.count ? p.text[i] : ""
                            word += AttributedString(mode == 0 ? (Self.pinyinPunct[ch] ?? ch) : ch)
                        } else { sy.append(s) }
                    }
                    flush()
                    out += word
                }
                prevWord = true
            } else {
                let ch = p.text.joined()
                if mode == 0 {
                    if let q = Self.pinyinPunct[ch] { out += AttributedString(q); prevWord = false; continue }
                    if ch.allSatisfy({ $0.isNumber || $0.isLetter }) {
                        if prevWord { out += AttributedString(" ") }
                        out += AttributedString(ch); prevWord = true; continue
                    }
                }
                out += AttributedString(ch)
                prevWord = false
            }
        }
        // no space before punctuation; spaces not doubled
        var s = out
        while let r = s.range(of: "  ") { s.replaceSubrange(r, with: AttributedString(" ")) }
        for p in [" ,", " .", " ?", " !", " :", " ;", " )", " ”", " ’"] {
            while let r = s.range(of: p) { s.replaceSubrange(r, with: AttributedString(String(p.dropFirst()))) }
        }
        while let f = s.characters.first, f == " " { s.characters.removeFirst() }
        while let l = s.characters.last, l == " " { s.characters.removeLast() }
        // a sentence in 拼音 starts with a capital letter
        if mode == 0, let i = s.characters.firstIndex(where: { $0.isLetter }) {
            let ch = s.characters[i]
            s.characters.replaceSubrange(i...i, with: String(ch).uppercased())
        }
        return s
    }

    /// a sentence's 漢字, in tone colours when they're on
    func sentenceHan(_ ps: [ZhPiece], _ place: Int, base: Color, blank: String? = nil, colours: Int = ToneColors.system) -> AttributedString {
        var out = AttributedString()
        for p in ps {
            if let blank, p.text.joined() == blank {
                var a = AttributedString("＿＿"); a.swiftUI.foregroundColor = base; out += a; continue
            }
            var last = 1
            for (i, ch) in p.text.enumerated() {
                var a = AttributedString(ch)
                if let syl = p.syl(place), i < syl.count, syl[i] != "_" {
                    let t = syl[i] == "-" ? last : Zhuyin.tone(syl[i])
                    last = t
                    a.swiftUI.foregroundColor = Zhuyin.color(t, colours) ?? base
                } else {
                    a.swiftUI.foregroundColor = base
                }
                out += a
            }
        }
        return out
    }

    // MARK: cards

    /// the entry as a card (the same shape as a 台語 card)
    func card(_ i: Int, list: Int = Lang.zhList) -> Card {
        let e = entries[i]
        let defs: [Def] = e.senses.map { s in
            Def(p: "", t: s.text, x: s.ex.map { x in
                let blankable = x.h != e.h && x.h.contains(e.h) && Self.pieces(x).contains { $0.text.joined() == e.h }
                // (the reading is worked out when it's shown: Store.exampleRom)
                return Example(h: x.h, r: [""], z: x.src, n: "tts:" + x.h,
                               bh: blankable ? x.h.replacingOccurrences(of: e.h, with: "＿＿") : nil,
                               br: blankable ? [""] : nil, w: x.code)
            }, sy: nil, an: nil)
        }
        let variant: [String: Variant]? = e.lu.map { lu in
            ["1": Variant(r: [readingPlain(lu, 0)], z: readingPlain(lu, 1))]
        }
        return Card(k: e.k, h: e.h, r: [readingPlain(e.tw, 0)], z: readingPlain(e.tw, 1), a: nil, g: "", d: defs,
                    c: nil, zo: nil, v: variant, o: nil, s: nil,
                    t: e.spec == 1 ? "臺灣特有" : (e.spec == 2 ? "大陸特有" : nil),
                    sy: nil, an: nil, cats: e.level(list) > 0 ? [e.level(list)] : nil, zs: e.tw, zl: e.lu)
    }

    // MARK: looking up

    struct Found {
        var words: [Int] = []          // the word itself (漢字 or reading)
        var starts: [Int] = []         // words starting with it
        var contains: [Int] = []       // words with it inside
        var defs: [Int] = []           // meanings that mention it
        var english: [Int] = []        // English meanings with the word
        var tones: [Int] = []          // words with these tones
        var toneLabel = ""
        /// several words searched at once (陰謀論 → 陰謀, 論; or 陰謀 論): each word and its entries
        var parts: [String] = []
        var partWords: [[Int]] = []
        var empty: Bool { parts.isEmpty && words.isEmpty && starts.isEmpty && contains.isEmpty && defs.isEmpty && english.isEmpty && tones.isEmpty }
    }

    /// the tones of a word as digits ("34", 0 = light tone)
    func toneDigits(_ e: ZhEntry, _ place: Int) -> String {
        e.syl(place).filter { $0 != "-" && $0 != "_" }.map { String(Zhuyin.tone($0)) }.joined()
    }

    func search(_ q0: String, place: Int = 0) -> Found {
        let q = q0.trimmingCharacters(in: .whitespacesAndNewlines)
        var f = Found()
        guard !q.isEmpty else { return f }
        // only tone numbers: words with those tones, one per syllable (0 or 5 = light tone): 34、3-4、1 0
        if q.allSatisfy({ "012345 -,，、".contains($0) }), q.contains(where: { $0.isNumber }) {
            let want = String(q.filter { $0.isNumber }.map { $0 == "5" ? "0" : $0 })
            f.toneLabel = want.map(String.init).joined(separator: "-")
            for (i, e) in entries.enumerated() where e.senses.contains(where: { !$0.text.hasPrefix("參見") }) {
                if toneDigits(e, place) == want { f.tones.append(i); if f.tones.count >= 500 { break } }
            }
            return f
        }
        // * = one or more characters, ? = exactly one (the same as in 台語): 人* 、*子、*水*、?子
        let wild = q.replacingOccurrences(of: "＊", with: "*").replacingOccurrences(of: "？", with: "?")
        if wild.contains("*") || wild.contains("?") {
            var pat = "^"
            for ch in wild {
                switch ch {
                case "*": pat += ".+"
                case "?": pat += "."
                default: pat += NSRegularExpression.escapedPattern(for: String(ch))
                }
            }
            pat += "$"
            guard let re = try? NSRegularExpression(pattern: pat) else { return f }
            func hit(_ s: String) -> Bool { re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
            for (i, e) in entries.enumerated() where hit(e.h) || (e.alt.map(hit) ?? false) {
                f.words.append(i)
                if f.words.count >= 500 { break }
            }
            return f
        }
        let scalars = q.unicodeScalars
        if let ps = Segmenter.parts(q, maxLen: maxLen, isWord: { byHan[$0] != nil }) {
            f.parts = ps
            f.partWords = ps.map { byHan[$0] ?? [] }
            // (陰謀論 itself may still be inside longer words)
            if !q.contains(where: { $0.isWhitespace }) {
                for (i, e) in entries.enumerated() where e.h.contains(q) || (e.alt?.contains(q) ?? false) {
                    f.contains.append(i); if f.contains.count >= 150 { break }
                }
            }
            return f
        }
        if scalars.contains(where: { Zhuyin.isHan($0) }) {
            f.words = byHan[q] ?? []
            var seen = Set(f.words)
            for (i, e) in entries.enumerated() where e.h != q {
                if e.h.hasPrefix(q) || (e.alt?.hasPrefix(q) ?? false) {
                    if f.starts.count < 150, seen.insert(i).inserted { f.starts.append(i) }
                } else if e.h.contains(q) || (e.alt?.contains(q) ?? false) {
                    if f.contains.count < 150, seen.insert(i).inserted { f.contains.append(i) }
                }
                if f.starts.count >= 150 && f.contains.count >= 150 { break }
            }
            for (i, e) in entries.enumerated() where !seen.contains(i) {
                if e.senses.contains(where: { $0.text.contains(q) }) { f.defs.append(i); if f.defs.count >= 80 { break } }
            }
            return f
        }
        if scalars.contains(where: { (0x3100...0x312F).contains($0.value) }) {
            let z = q.filter { !$0.isWhitespace }
            let toned = z.contains { "ˊˇˋ˙".contains($0) }
            f.words = (toned ? byZyToned[z] : byZy[Zhuyin.bare(z)]) ?? []
            return f
        }
        // 拼音: with or without tone numbers
        let p = Zhuyin.plain(q).replacingOccurrences(of: "5", with: "").replacingOccurrences(of: "0", with: "")
        let toned = p.contains { $0.isNumber }
        f.words = (toned ? byToned[p] : byPlain[p]) ?? []
        if !toned && f.words.count < 30 {
            var seen = Set(f.words)
            for (k, v) in byPlain where k.hasPrefix(p) && k != p {
                for i in v where seen.insert(i).inserted { f.starts.append(i) }
                if f.starts.count > 120 { break }
            }
            f.starts.sort()
        }
        if !toned { f.english = english(q) }
        return f
    }

    /// words whose English meaning has the word(s): a meaning that is just the word first ("eat", "to eat"),
    /// then meanings that start with it, then the rest. Within each: words that give it as their first meaning
    /// first, then the more common words (the entries are in order of how common they are). A meaning with a
    /// note in brackets ("(computing) (coll.) slow") counts one step lower, so 慢 comes before 卡 for "slow".
    func english(_ q0: String) -> [Int] {
        let q = q0.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var hits: [(tier: Int, later: Int, i: Int)] = []
        let bare = q.hasPrefix("to ") ? String(q.dropFirst(3)) : q
        let inWord = #"[^a-z]"# + NSRegularExpression.escapedPattern(for: bare) + #"[^a-z]"#
        for (i, e) in entries.enumerated() {
            guard let en = e.en?.lowercased(), en.contains(bare) else { continue }
            var best = 9, bestPos = 1
            for (pos, g0) in en.components(separatedBy: ";").enumerated() {
                // without notes in brackets: "(bound form) to walk" → "to walk"
                var g = g0
                var noted = false
                while let r = g.range(of: #"\([^()]*\)"#, options: .regularExpression) { g.removeSubrange(r); noted = true }
                g = g.trimmingCharacters(in: .whitespaces)
                let v = g.hasPrefix("to ") ? String(g.dropFirst(3)) : g
                var t = 9
                if v == bare { t = 0 }
                else if v.hasPrefix(bare + " ") || v.hasPrefix(bare + ",") { t = 1 }
                else if (" " + v + " ").range(of: inWord, options: .regularExpression) != nil { t = 2 }
                if t < 9 && noted { t += 1 }
                let p = pos == 0 ? 0 : 1
                if t < best || (t == best && p < bestPos) { best = t; bestPos = p }
            }
            if best <= 3 { hits.append((min(best, 3), bestPos, i)) }
        }
        hits.sort { ($0.tier, $0.later, $0.i) < ($1.tier, $1.later, $1.i) }
        return Array(hits.prefix(250).map { $0.i })
    }

    /// the entry for a word of a sentence: the one read the way the sentence reads it
    func entry(for p: ZhPiece) -> ZhEntry? {
        let text = p.text.joined()
        let cands = (byHan[text] ?? []).filter { entries[$0].h == text || entries[$0].alt == text }
        let tw = (p.tw ?? []).filter { $0 != "_" }
        if let i = cands.first(where: { entries[$0].tw.filter { $0 != "_" } == tw }) { return entries[i] }
        return usual(text).map { entries[$0] }
    }

    // MARK: 轉換: splitting text into words

    /// one character on its own in a sentence: the reading it usually has there
    static let aloneReading: [String: String] = [
        "的": "˙ㄉㄜ", "了": "˙ㄌㄜ", "著": "˙ㄓㄜ", "得": "˙ㄉㄜ", "們": "˙ㄇㄣ", "麼": "˙ㄇㄜ", "嗎": "˙ㄇㄚ",
        "呢": "˙ㄋㄜ", "吧": "˙ㄅㄚ", "啊": "˙ㄚ", "都": "ㄉㄡ", "還": "ㄏㄞˊ", "個": "ㄍㄜˋ", "沒": "ㄇㄟˊ",
        "給": "ㄍㄟˇ", "那": "ㄋㄚˋ", "哪": "ㄋㄚˇ", "誰": "ㄕㄟˊ", "會": "ㄏㄨㄟˋ", "要": "ㄧㄠˋ", "說": "ㄕㄨㄛ",
        "為": "ㄨㄟˋ", "中": "ㄓㄨㄥ", "好": "ㄏㄠˇ", "看": "ㄎㄢˋ", "只": "ㄓˇ", "長": "ㄔㄤˊ", "重": "ㄓㄨㄥˋ",
        "地": "ㄉㄧˋ", "大": "ㄉㄚˋ", "和": "ㄏㄜˊ", "把": "ㄅㄚˇ", "少": "ㄕㄠˇ", "種": "ㄓㄨㄥˇ", "行": "ㄒㄧㄥˊ"]

    /// the usual entry for a word
    func usual(_ han: String) -> Int? {
        guard let is_ = byHan[han]?.filter({ entries[$0].h == han || entries[$0].alt == han }), !is_.isEmpty else { return nil }
        if is_.count == 1 { return is_[0] }
        if let want = Self.aloneReading[han], let i = is_.first(where: { entries[$0].tw.first == want }) { return i }
        return is_.max { entries[$0].senses.count < entries[$1].senses.count }
    }

    /// text split into the dictionary's words (fewest words; then the more common ones), with readings
    func convert(_ text: String) -> [(text: String, entry: Int?)] {
        let chars = text.unicodeScalars.map { String($0) }
        let n = chars.count
        guard n > 0 else { return [] }
        var best = [(Int, Int)?](repeating: nil, count: n + 1)
        var back = [(Int, Int?)](repeating: (0, nil), count: n + 1)
        best[0] = (0, 0)
        for i in 0..<n {
            guard let cur = best[i] else { continue }
            let (cnt, sc) = cur
            var cands: [(Int, Int?)] = []
            if let u = chars[i].unicodeScalars.first, Zhuyin.isHan(u) {
                var L = min(maxLen, n - i)
                while L >= 1 {
                    let w = chars[i..<i + L].joined()
                    if let e = usual(w) { cands.append((i + L, e)) }
                    L -= 1
                }
            }
            if cands.isEmpty { cands.append((i + 1, nil)) }
            for (j, e) in cands {
                let ns = (cnt + 1, sc + (e ?? entries.count))
                if best[j] == nil || ns < best[j]! { best[j] = ns; back[j] = (i, e) }
            }
        }
        var out: [(text: String, entry: Int?)] = []
        var j = n
        while j > 0 { let (i, e) = back[j]; out.append((chars[i..<j].joined(), e)); j = i }
        return out.reversed()
    }

    /// 轉換: the text as pieces with readings (一 / 不 change their tone before another syllable)
    func convertPieces(_ text: String) -> [ZhPiece] {
        var ps: [ZhPiece] = []
        for (t, e) in convert(text) {
            let chars = t.unicodeScalars.map { String($0) }
            if let e {
                let en = entries[e]
                // the entry's syllables, one per character (a comma inside a saying has none)
                var tw: [String] = [], lu: [String] = [], k = 0
                for ch in chars {
                    if let u = ch.unicodeScalars.first, Zhuyin.isHan(u), k < en.tw.count {
                        tw.append(en.tw[k]); lu.append(en.lu.map { k < $0.count ? $0[k] : en.tw[k] } ?? en.tw[k]); k += 1
                    } else { tw.append("_"); lu.append("_") }
                }
                ps.append(ZhPiece(text: chars, tw: tw, lu: en.lu == nil ? nil : lu))
            } else {
                for ch in chars { ps.append(ZhPiece(text: [ch], tw: nil, lu: nil)) }
            }
        }
        let num = Set("〇零一二三四五六七八九十百千萬億兩第".map { String($0) })
        for i in ps.indices where ps[i].text == ["一"] || ps[i].text == ["不"] {
            guard i + 1 < ps.count, let next = ps[i + 1].tw?.first, next != "_" else { continue }
            if ps[i].text == ["一"] && ((i > 0 && num.contains(ps[i - 1].text.last ?? "")) || num.contains(ps[i + 1].text.first ?? "")) { continue }
            let t = Zhuyin.tone(next)
            var new: String?
            if ps[i].text == ["不"] { if t == 4 { new = "ㄅㄨˊ" } }
            else if t == 4 { new = "ㄧˊ" } else if (1...3).contains(t) { new = "ㄧˋ" }
            if let new { ps[i] = ZhPiece(text: ps[i].text, tw: [new], lu: nil) }
        }
        return ps
    }
}

// MARK: - reading aloud (the device's own 華語 voice)

@MainActor
final class ZhSpeech: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = ZhSpeech()
    private let synth = AVSpeechSynthesizer()
    var onFinish: (() -> Void)?

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        let lang = Lang.zhPlace == 1 ? "zh-CN" : "zh-TW"
        u.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: "zh-TW")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        u.volume = Float(UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.8)
        synth.speak(u)
    }

    func stop() { synth.stopSpeaking(at: .immediate) }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }
}
