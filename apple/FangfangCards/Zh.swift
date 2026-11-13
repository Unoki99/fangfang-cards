import Foundation
import SwiftUI
import AVFoundation

// MARK: - 華語 mode
//
// The 華語 deck comes from 《兩岸常用詞典》 (中華文化總會), built into zh.json by tools/build_mandarin.py.
// The dictionary's 注音 is kept as it is; 漢語拼音 is spelled from it here, by rule.

enum Lang {
    /// 0 = 台語, 1 = 華語, 2 = 粵語, 3 = 客語, 4 = 日語
    static let key = "lang"
    static let count = 5
    static var current: Int { min(max(UserDefaults.standard.integer(forKey: key), 0), count - 1) }
    /// a language with a 華語-style dictionary (華語, 粵語 or 客語)
    static var isZh: Bool { current != 0 }
    /// 粵語 (Cantonese): the same pages as 華語, its own dictionary (yue.json) and reading (粵拼 / 耶魯)
    static var isYue: Bool { current == 2 }
    /// 客語 (Taiwanese Hakka): the same pages as 華語, its own dictionary (hak.json, 教育部《臺灣客語辭典》), six accents
    static var isHak: Bool { current == 3 }
    /// 日語: the same pages as 華語, its own dictionary (ja.json, JMdict and KANJIDIC2), read in kana or rōmaji
    static var isJa: Bool { current == 4 }
    /// 粵語 and 客語: no HSK / TOCFL lists (the words come in groups of how common they are)
    static var ownGroups: Bool { current >= 2 }
    static let names = ["台語", "華語", "粵語", "客語", "日語"]
    /// 華語 reading: 0 = 拼音, 1 = 注音 (粵語, its own setting: 0 = 粵拼, 1 = 耶魯; 客語: 0 = 拼音, 1 = 注音)
    static var romKey: String { isJa ? jaRomKey : (isYue ? yueRomKey : (isHak ? hakRomKey : "zhRom")) }
    /// 日語: 0 = rōmaji, 1 = かな (the first time: かな)
    static let jaRomKey = "jaRom"
    static let yueRomKey = "yueRom"
    static let hakRomKey = "hakRom"
    static var zhRom: Int { UserDefaults.standard.integer(forKey: romKey) }
    /// 華語 reading of: 0 = 臺灣, 1 = 大陸 (客語: the accent, 0 四縣 … 5 南四縣)
    static var placeKey: String { isJa ? "jaPlace" : (isHak ? hakPlaceKey : "zhPlace") }
    static let hakPlaceKey = "hakPlace"
    static var zhPlace: Int { UserDefaults.standard.integer(forKey: placeKey) }
    /// 客語: the accent chosen
    static var hakAccent: Int { min(max(UserDefaults.standard.integer(forKey: hakPlaceKey), 0), hakAccents.count - 1) }
    static let hakAccents = ["四縣", "海陸", "大埔", "饒平", "詔安", "南四縣"]
    static var romNames: [String] { isJa ? ["羅馬字", "假名"] : (isYue ? ["粵拼", "耶魯"] : ["拼音", "注音"]) }
    /// HSK 3.0 levels (7 = 7–9)
    static func hskName(_ l: Int) -> String { l >= 7 ? "HSK 7–9" : "HSK \(l)" }
    /// the word list the 華語 cards follow: 0 = HSK 3.0, 1 = TOCFL
    static let listKey = "zhList"
    static var zhList: Int { UserDefaults.standard.integer(forKey: listKey) }
    static let listNames = ["HSK", "TOCFL"]
    static let tocflNames = ["", "準備一級", "準備二級", "入門級", "基礎級", "進階級", "高階級", "流利級"]
    static func tocflName(_ l: Int) -> String { l > 0 && l < tocflNames.count ? tocflNames[l] : "" }
    static func levelName(_ list: Int, _ l: Int) -> String {
        if ownGroups { return "常用詞 \((l - 1) * yueGroup + 1)–\(l * yueGroup)" }
        return list == 1 ? "TOCFL " + tocflName(l) : hskName(l)
    }
    /// 粵語: the words and characters come in groups of how common they are (no official lists)
    static let yueGroup = 500
    static func yueCharLevelName(_ l: Int) -> String { "常用字 \((l - 1) * yueGroup + 1)–\(l * yueGroup)" }
    static var placeNames: [String] { isJa ? ["日本語"] : (isHak ? hakAccents : zhPlaceNames) }
    /// 華語's readings: 國語 (臺灣), 普通話 (大陸), 四川話 (成都, from Wiktionary; a word without one: 普通話's)
    static let zhPlaceNames = ["國語", "普通話", "四川話"]

    /// a 華語 or 粵語 word's key: "漢字\t注音", "漢字\t粵jyut6 ping3" (台語 keys have syllable codes in letters
    /// after the tab)
    static func isZhKey(_ k: String) -> Bool {
        guard let t = k.firstIndex(of: "\t"), let s = k[k.index(after: t)...].unicodeScalars.first else { return false }
        return (0x3100...0x312F).contains(s.value) || (0x31A0...0x31BF).contains(s.value) || s == "˙" || s == "字" || s == "粵" || s == "客" || s == "日"
    }
    /// a 粵語 word's or character's key ("漢字\t粵…")
    static func isYueKey(_ k: String) -> Bool {
        guard let t = k.firstIndex(of: "\t") else { return false }
        return k[k.index(after: t)...].hasPrefix("粵")
    }
    /// a 客語 word's or character's key ("漢字\t客…")
    static func isHakKey(_ k: String) -> Bool {
        guard let t = k.firstIndex(of: "\t") else { return false }
        return k[k.index(after: t)...].hasPrefix("客")
    }
    /// a 日語 word's or kanji's key ("食べる\t日たべる", "食\t日字")
    static func isJaKey(_ k: String) -> Bool {
        guard let t = k.firstIndex(of: "\t") else { return false }
        return k[k.index(after: t)...].hasPrefix("日")
    }
    /// which language a key is of: 0 台語, 1 華語, 2 粵語, 3 客語, 4 日語
    static func kind(_ k: String) -> Int { isYueKey(k) ? 2 : (isHakKey(k) ? 3 : (isJaKey(k) ? 4 : (isZhKey(k) ? 1 : 0))) }
    /// a character card's key: "好\t字" (粵語: "好\t粵字", 客語: "好\t客字", 日語: "食\t日字")
    static func charKey(_ ch: String, yue: Bool = isYue, hak: Bool = isHak, ja: Bool = isJa) -> String {
        ch + (ja ? "\t日字" : (yue ? "\t粵字" : (hak ? "\t客字" : "\t字")))
    }
    /// the character of a character card's key (nil = a word)
    static func charOf(_ k: String) -> String? {
        if k.hasSuffix("\t粵字") || k.hasSuffix("\t客字") || k.hasSuffix("\t日字") { return String(k.dropLast(3)) }
        return k.hasSuffix("\t字") ? String(k.dropLast(2)) : nil
    }
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

    /// a 客語 syllable: letters, the tone category (a superscript digit) and the accent (a subscript digit): "bau¹₀"
    static func isHak(_ s: String) -> Bool {
        guard let l = s.unicodeScalars.last else { return false }
        return (0x2080...0x2089).contains(l.value)
    }
    private static let superDigits: [Unicode.Scalar: Int] = ["⁰": 0, "¹": 1, "²": 2, "³": 3, "⁴": 4, "⁵": 5, "⁶": 6, "⁷": 7, "⁸": 8, "⁹": 9]
    /// a 客語 syllable's parts: letters, tone category (1 陰平 2 上聲 3 去聲 4 陰入 5 陽平 7 陽去 8 陽入), accent
    static func hakParts(_ s: String) -> (letters: String, tone: Int, accent: Int) {
        let u = Array(s.unicodeScalars)
        guard u.count >= 3, isHak(s) else { return (s, 0, 0) }
        let acc = Int(u[u.count - 1].value - 0x2080)
        let t = superDigits[u[u.count - 2]] ?? 0
        var l = String.UnicodeScalarView(); l.append(contentsOf: u[..<(u.count - 2)])
        return (String(l), t, acc)
    }
    private static let superOf = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]

    /// a 粵語 syllable (Jyutping: letters and a tone number, "goi1")
    static func isJyut(_ s: String) -> Bool {
        guard let f = s.unicodeScalars.first, let l = s.unicodeScalars.last else { return false }
        return f.isASCII && f.properties.isLowercase && ("1"..."6").contains(Character(l))
    }

    /// the tone of a syllable: 1–4, 0 = light tone (˙); 粵語 1–6
    static func tone(_ s: String) -> Int {
        if isHak(s) { return hakParts(s).tone }
        if isJyut(s), let d = s.last?.wholeNumberValue { return d }
        if s.hasPrefix("˙") || s.hasSuffix("˙") { return 0 }
        switch s.last {
        case "ˊ": return 2
        case "ˇ": return 3
        case "ˋ": return 4
        default: return 1
        }
    }

    /// the letters without the tone mark
    static func bare(_ s: String) -> String {
        if isHak(s) { return hakParts(s).letters }
        return isJyut(s) ? String(s.dropLast()) : s.filter { !"ˊˇˋ˙".contains($0) }
    }

    /// the syllable with another tone
    static func withTone(_ s: String, _ t: Int) -> String {
        if isHak(s) { let p = hakParts(s); return p.letters + superOf[min(max(t, 0), 9)] + String(UnicodeScalar(0x2080 + UInt32(p.accent))!) }
        if isJyut(s) { return String(s.dropLast()) + String(t) }
        let b = bare(s)
        switch t {
        case 0: return "˙" + b
        case 2: return b + "ˊ"
        case 3: return b + "ˇ"
        case 4: return b + "ˋ"
        default: return b
        }
    }

    /// a 四川話 syllable as it's shown: a mark on the vowel for how the tone sounds ("ce1" → "cē"):
    /// 1 high level ā, 2 low falling a̱ (a line under it), 3 high falling à, 4 low dipping ǎ, 5 (入聲) like 2
    static func sichuan(_ s: String) -> String {
        guard let d = s.last?.wholeNumberValue else { return s }
        let letters = Array(String(s.dropLast()))
        let mark: String
        switch d {
        case 1: mark = "\u{0304}"
        case 2, 5: mark = "\u{0331}"
        case 3: mark = "\u{0300}"
        case 4: mark = "\u{030C}"
        default: return String(letters)
        }
        // where the mark goes, as in 拼音: a, e (ê), o in ou, else the last vowel (no vowel: the first letter, ng̀)
        var v: Int?
        if let i = letters.firstIndex(of: "a") { v = i }
        else if let i = letters.firstIndex(where: { $0 == "e" || $0 == "ê" }) { v = i }
        else if let i = letters.firstIndex(of: "o"), i + 1 < letters.count, letters[i + 1] == "u" { v = i }
        else { v = letters.lastIndex { "iouüv".contains($0) } }
        let i = v ?? 0
        guard i < letters.count else { return String(letters) }
        let out = String(letters[...i]) + mark + String(letters[(i + 1)...])
        return out.precomposedStringWithCanonicalMapping
    }

    /// one 注音 syllable in 拼音 with its tone mark ("" when it can't be spelled); a 粵語 syllable stays as it is
    static func pinyin(_ s: String) -> String {
        if isJyut(s) || isHak(s) { return s }
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
        if isHak(s) { return hakParts(s).letters }
        if isJyut(s) { return String(s.dropLast()) }
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
    static func color(_ t: Int, _ sys: Int, yue: Bool = Lang.isYue, hak: Bool = Lang.isHak) -> Color? {
        guard sys != 0 else { return nil }
        // 客語: its tone categories (陰平 1, 上聲 2, 去聲 3, 陰入 4, 陽平 5, 陽去 7, 陽入 8), in the colours picked for 客語
        if hak { return ToneColors.hakColor(t) }
        // 粵語: tones 1–6 (in the colours picked for 粵語)
        if yue { return (1...6).contains(t) ? ToneColors.yueColor(t) : nil }
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

// MARK: - 簡體

/// 設定 → 字形: 華語 and 粵語 shown in 簡體字. The keys and the data stay 正體; what's shown is changed, character by
/// character, with the pairs the dictionaries give (後→后, 開→开…).
enum Simp {
    static let key = "simplified"
    static var on: Bool { Lang.isZh && !Lang.isHak && UserDefaults.standard.bool(forKey: key) }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var table: [Character: Character] = [:]

    /// the pairs of a dictionary's words (正體 and 簡體 of the same length)
    static func learn(_ pairs: [(String, String)]) {
        var t: [Character: Character] = [:]
        for (h, a) in pairs where h.count == a.count {
            for (x, y) in zip(h, a) where x != y { t[x] = y }
        }
        lock.lock(); table.merge(t) { old, _ in old }; back = [:]; lock.unlock()
    }

    /// a 簡體 character's 正體 one (the first the dictionaries gave)
    static func reverse(_ c: Character) -> Character? {
        lock.lock(); defer { lock.unlock() }
        if back.isEmpty { for (t, s) in table where back[s] == nil { back[s] = t } }
        return back[c]
    }
    nonisolated(unsafe) private static var back: [Character: Character] = [:]

    /// in 簡體 (when that's chosen)
    static func show(_ s: String) -> String { on && !Lang.isJa ? convert(s) : s }
    static func convert(_ s: String) -> String {
        lock.lock(); defer { lock.unlock() }
        guard !table.isEmpty else { return s }
        return String(s.map { table[$0] ?? $0 })
    }
}

// MARK: - 粵拼 → 耶魯

enum Yale {
    private static let marks: [Int: String] = [1: "\u{0304}", 2: "\u{0301}", 3: "", 4: "\u{0300}", 5: "\u{0301}", 6: ""]
    private static let initials = ["gw", "kw", "ng", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "w", "z", "c", "s", "j"]

    /// one Jyutping syllable in Yale with tone marks: goi1 → gōi, m4 → m̀h, sik6 → sihk, zyu1 → jyū
    static func of(_ s: String) -> String {
        guard Zhuyin.isJyut(s), let t = s.last?.wholeNumberValue else { return s }
        let b = String(s.dropLast())
        var ini = initials.first { b.hasPrefix($0) && b.count > $0.count } ?? ""
        var fin = String(b.dropFirst(ini.count))
        ini = ["z": "j", "c": "ch", "j": "y"][ini] ?? ini
        if ini == "y" && fin.hasPrefix("yu") { ini = "" }
        if fin == "aa" { fin = "a" }
        if fin.hasPrefix("eo") || fin.hasPrefix("oe") { fin = "eu" + String(fin.dropFirst(2)) }
        let nasal = ini.isEmpty && (fin == "m" || fin == "ng")
        let syl = Array(ini + fin)
        let v = nasal ? 0 : (syl.firstIndex { "aeiou".contains($0) } ?? ini.count)
        var out = String(syl[...v]) + (marks[t] ?? "")
        var rest = String(syl[(v + 1)...])
        if t >= 4 {
            // the h after the vowels (before the final consonant)
            let vowels = String(rest.prefix { "aeiouy".contains($0) })
            if nasal { out += rest + "h"; rest = "" } else { out += vowels + "h"; rest = String(rest.dropFirst(vowels.count)) }
        }
        return (out + rest).precomposedStringWithCanonicalMapping
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
    /// 四川話 (成都): 四川話拼音 with the tone as a number ("ce1"), from Wiktionary (zh_sc.json); nil = none
    var sc: [String]? = nil
    /// where the 四川話 reading is from: 0 Wiktionary, 1 guessed (put together from how each character is read in
    /// other words), 2 predicted (from the regular sound changes from 普通話)
    var scKind = 0
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
    /// 粵語: the 華語 words with the same meaning (Wiktionary's dialect tables)
    var eq: [String] = []
    /// 粵語: a recording of the word (Wikimedia Commons), when there is one
    var audio: String? = nil
    /// 客語: the reading in each accent (0 四縣 … 5 南四縣; nil = that accent doesn't have the word); `tw` is the one
    /// of the accent chosen
    var acc: [[String]?]? = nil
    /// 客語: the accents that say it with another word (accent → word)
    var otherWords: [Int: String] = [:]
    /// 客語: the accent chosen doesn't have the word; its reading (`tw`) was put together from how that accent reads
    /// each of its characters
    var hakGuess = false
    /// 日語: JMdict's codes (v1, v5r, adj-i…; "*uk" for notes), for 活用
    var jp: [String] = []
    /// the English meanings, one each (CC-CEDICT separates them with ;)
    var enList: [String] {
        (en ?? "").components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// syllables for 國語 (0), 普通話 (1) or 四川話 (2: 普通話's when there's no 四川話 reading)
    func syl(_ place: Int) -> [String] { place == 2 ? (sc ?? lu ?? tw) : (place == 1 ? (lu ?? tw) : tw) }
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
    /// (四川話: filled in by ZhDict.sentence from the dictionary's words)
    func syl(_ place: Int) -> [String]? { place >= 1 ? (lu ?? tw) : tw }
}

final class ZhDict: @unchecked Sendable {
    let entries: [ZhEntry]
    /// the 粵語 dictionary (yue.json, tools/build_cantonese.py), not the 華語 one
    let isYue: Bool
    /// the 客語 dictionary (hak.json, tools/build_hakka.py)
    let isHak: Bool
    /// the 日語 dictionary (ja.json, Install/japanese.js)
    let isJa: Bool
    /// 1 華語, 2 粵語, 3 客語, 4 日語
    var lang: Int { isJa ? 4 : (isHak ? 3 : (isYue ? 2 : 1)) }
    /// 日語: what JMdict's codes mean (in English)
    let jaTags: [String: String]
    /// 日語: each entry's reading in hiragana (for "starts with"); empty for the other languages
    let jaKana: [String]
    /// 客語: the accent the readings (`tw`) are of, its tone marks (per accent, per tone) and each syllable's 注音
    let accent: Int
    let hakMarks: [[String]]
    let hakZy: [String: String]
    /// how many of the first entries are study cards (the rest are rare words and references)
    let cardCount: Int
    let index: [String: Int]
    let byHan: [String: [Int]]
    /// 粵語: a 華語 word → the 粵語 words for it (from the entries' 華語 words)
    let byMandarin: [String: [Int]]
    private let byPlain: [String: [Int]]       // 拼音 without tones: "chifan"
    private let byToned: [String: [Int]]       // "chi1fan4"
    private let byZy: [String: [Int]]          // 注音 without tones
    private let byZyToned: [String: [Int]]
    let maxLen: Int
    /// the character cards (教育部《重編國語辭典修訂本》), the listed ones first, the more common first
    let chars: [ZhChar]
    let charIndex: [String: Int]
    /// 部首 lookup: the radicals (fewest strokes first) with their characters (by the strokes besides the radical)
    private(set) var radicals: [ZhRadical]
    /// 部首組合: radical → every character with it anywhere inside (empty with an older zh.json)
    private(set) var radicalInside: [String: [String]]
    /// a character's number of strokes
    private(set) var strokesOf: [String: Int]
    /// each entry's English, in small letters (粵語: Wiktionary's meanings too), for the English search: made the
    /// first time it's needed, not every search (127,000 粵語 words made the search slow)
    private var englishCache: [String]? = nil
    private let englishLock = NSLock()
    private var englishTexts: [String] {
        englishLock.lock(); defer { englishLock.unlock() }
        if let c = englishCache { return c }
        let c = entries.map { e in
            (isYue ? (e.senses.map { $0.text }.joined(separator: ";") + ";" + (e.en ?? "")) : (e.en ?? "")).enFold
        }
        englishCache = c
        return c
    }
    /// (made ahead of the first English search, when the dictionary page opens)
    func warmEnglish() { _ = englishTexts }

    /// the same as sets (made the first time they're needed)
    lazy var radicalSets: [String: Set<String>] = radicalInside.mapValues { Set($0) }

    /// the characters that have all these radicals inside them (fewest strokes first)
    func charsWith(radicals rs: [String]) -> [String] {
        guard let first = rs.min(by: { (radicalInside[$0]?.count ?? 0) < (radicalInside[$1]?.count ?? 0) }),
              let base = radicalInside[first] else { return [] }
        let others = rs.filter { $0 != first }.map { radicalSets[$0] ?? [] }
        return base.filter { c in others.allSatisfy { $0.contains(c) } }
    }

    /// 部首查字 / 部首組合: the radicals with their characters, the characters with each radical anywhere inside
    /// (fewest strokes first), and every character's strokes (the radical's + the rest)
    private static func radicalData(_ obj: [String: Any]) -> ([ZhRadical], [String: [String]], [String: Int]) {
        var rads: [ZhRadical] = []
        for r in obj["r"] as? [[Any]] ?? [] {
            guard r.count >= 4, let rad = r[0] as? String, let n = r[1] as? Int, let cs = r[2] as? String, let res = r[3] as? [Int] else { continue }
            let list = cs.unicodeScalars.map { String($0) }
            rads.append(ZhRadical(radical: rad, strokes: n, chars: Array(zip(list, res).map { (ch: $0.0, rest: $0.1) })))
        }
        var inside: [String: [String]] = [:]
        for (r, v) in obj["rx"] as? [String: String] ?? [:] { inside[r] = v.unicodeScalars.map { String($0) } }
        var st: [String: Int] = [:]
        for r in rads { for c in r.chars where st[c.ch] == nil { st[c.ch] = r.strokes + c.rest } }
        return (rads, inside, st)
    }

    /// 粵語: yue.json doesn't carry the radicals (they're from the 華語 data, whose licence doesn't allow sharing
    /// them in another file), so they're read from zh.json's beginning when it's there
    func borrowRadicals(from data: Data) {
        guard radicals.isEmpty, let r = data.range(of: Data(",\"e\":[\n".utf8)) else { return }
        var head = Data(data[data.startIndex..<r.lowerBound])
        head.append(contentsOf: Array("}".utf8))
        guard let obj = (try? JSONSerialization.jsonObject(with: head)) as? [String: Any] else { return }
        let rd = Self.radicalData(obj)
        radicals = rd.0; radicalInside = rd.1; strokesOf = rd.2
        radicalSets = radicalInside.mapValues { Set($0) }
    }

    /// one entry of zh.json (客語: the readings of this accent, the main one when the accent doesn't have the word)
    private static func makeEntry(_ e: [String: Any], accent: Int) -> ZhEntry? {
        guard let k = e["k"] as? String, let h = e["h"] as? String, var s = e["s"] as? String else { return nil }
        var acc: [[String]?]? = nil
        if let v = e["v"] as? [Any] {
            let a = v.map { ($0 as? String)?.components(separatedBy: " ") }
            acc = a
            if accent < a.count, let mine = v[accent] as? String { s = mine }
        }
        var others: [Int: String] = [:]
        for (a, w) in e["o"] as? [String: String] ?? [:] { if let i = Int(a) { others[i] = w } }
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
                       pos: e["w"] as? [String] ?? [], syn: e["j"] as? [String] ?? [], ant: e["f"] as? [String] ?? [],
                       eq: e["m"] as? [String] ?? [], audio: e["u"] as? String, acc: acc, otherWords: others,
                       jp: e["jp"] as? [String] ?? [])
    }

    /// reads zh.json: the entries are one per line at the end, so they're read in parts on all the cores at
    /// the same time (much faster than one big read); an older file (all on one line) is read in one go
    private static func readFile(_ data: Data, accent: Int) throws -> (obj: [String: Any], entries: [ZhEntry]) {
        let marker = Data(",\"e\":[\n".utf8)
        guard let r = data.range(of: marker) else {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let es = obj["e"] as? [[String: Any]] else { throw CocoaError(.fileReadCorruptFile) }
            return (obj, es.compactMap { makeEntry($0, accent: accent) })
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
            let made = es.compactMap { makeEntry($0, accent: accent) }
            lock.lock(); results[p] = made; lock.unlock()
        }
        if failed { throw CocoaError(.fileReadCorruptFile) }
        return (obj, results.flatMap { $0 })
    }

    /// accent: 客語, the accent whose readings are used
    /// a word's 四川話 reading, by its 漢字 and 國語 reading ("車\tㄔㄜ" → ["ce1"]), for the sentences
    private var scByWord: [String: [String]] = [:]

    /// the 四川話 readings (zh_sc.json, tools/build_sichuan.py: key → ("ce1 …", kind)): from Wiktionary (0), guessed
    /// from how each character is read in other words (1), or predicted from the sound changes (2); empty when the
    /// file isn't there
    static var sichuanFile: [String: (String, Int)] { sichuanData.readings }
    /// zh_sc.json: the readings; 四川話's own words (not in the dictionary: 耍朋友, 日白 …); and the dictionary's
    /// words that 成都 says, with the 華語 words for them (擺龍門陣 → 聊天)
    struct SichuanData {
        var readings: [String: (String, Int)] = [:]
        var words: [[String: Any]] = []
        var eq: [String: [String]] = [:]
    }
    static let sichuanData: SichuanData = {
        guard let u = DataFiles.url("zh_sc"), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return SichuanData() }
        var s = SichuanData()
        for (k, v) in o["p"] as? [String: String] ?? [:] { s.readings[k] = (v, 2) }
        for (k, v) in o["g"] as? [String: String] ?? [:] { s.readings[k] = (v, 1) }
        for (k, v) in o["s"] as? [String: String] ?? [:] { s.readings[k] = (v, 0) }
        s.words = o["w"] as? [[String: Any]] ?? []
        s.eq = o["q"] as? [String: [String]] ?? [:]
        return s
    }()
    /// 四川話's own words have this `spec` (shown only when 讀音 = 四川話)
    static let sichuanSpec = 3
    /// the words of a spec (1 臺灣用語, 2 大陸用語, 3 四川話's own: those with a reading from Wiktionary first,
    /// then the guessed, then the predicted), the more common first; made once
    private var specCache: [Int: [Int]] = [:]
    func specWords(_ spec: Int) -> [Int] {
        if let c = specCache[spec] { return c }
        var l = entries.indices.filter { entries[$0].spec == spec && !entries[$0].senses.allSatisfy { $0.text.hasPrefix("參見") } }
        if spec == Self.sichuanSpec { l.sort { (entries[$0].scKind, $0) < (entries[$1].scKind, $1) } }
        specCache[spec] = l
        return l
    }
    var sichuanWordCount: Int { specWords(Self.sichuanSpec).count }

    /// (華語: with the 四川話 readings of zh_sc.json)
    /// from: the file it's read from (its entries are kept in a quick copy, so the next start reads that instead)
    init(data: Data, accent: Int = Lang.hakAccent, from url: URL? = nil) throws {
        let (obj, out0) = try Self.readQuick(data, accent: accent, from: url)
        let sichuan = obj["lang"] == nil ? Self.sichuanFile : [:]
        var out = out0, scw: [String: [String]] = [:]
        if !sichuan.isEmpty {
            for i in out.indices {
                guard let v = sichuan[out[i].k] else { continue }
                let (s, kind) = v
                let sy = s.components(separatedBy: " ")
                if sy.count == out[i].tw.count, sy.allSatisfy(Zhuyin.isJyut) {
                    out[i].sc = sy
                    out[i].scKind = kind
                    scw[out[i].h + "\t" + out[i].tw.joined(separator: " ")] = sy
                }
            }
        }
        scByWord = scw
        // 客語: a word the accent chosen doesn't have (惜圓): each character read the way this accent reads it
        if obj["lang"] as? String == "hak" { Self.fillAccent(&out, accent: accent) }
        // 四川話's own words, after the dictionary's (so they're never study cards); and the 華語 words for the
        // dictionary's words that 成都 says
        if obj["lang"] == nil {
            let sd = Self.sichuanData
            if !sd.eq.isEmpty {
                for i in out.indices { if let m = sd.eq[out[i].h] { out[i].eq = m } }
            }
            for w in sd.words {
                guard let h = w["h"] as? String, let s = w["s"] as? String, let z = w["z"] as? String else { continue }
                let sy = s.components(separatedBy: " "), tw = z.components(separatedBy: " ")
                guard sy.count == tw.count, sy.allSatisfy(Zhuyin.isJyut) else { continue }
                let ms = w["m"] as? [String] ?? []
                let en = w["e"] as? [String] ?? []
                let text = ms.isEmpty ? "四川話的詞。" : "四川話，意思同「" + ms.prefix(3).joined(separator: "」、「") + "」。"
                var e = ZhEntry(k: h + "\t" + z + "#川", h: h, tw: tw, lu: nil, sc: sy, scKind: w["k"] as? Int ?? 2,
                                spec: Self.sichuanSpec, alt: nil, senses: [ZhSense(n: 1, text: text, ex: [])])
                e.en = en.isEmpty ? nil : en.map { $0.replacingOccurrences(of: ";", with: ",") }.joined(separator: "; ")
                e.eq = ms
                out.append(e)
            }
        }
        cardCount = obj["nc"] as? Int ?? out.count
        isYue = obj["lang"] as? String == "yue"
        isHak = obj["lang"] as? String == "hak"
        isJa = obj["lang"] as? String == "ja"
        jaTags = obj["tags"] as? [String: String] ?? [:]
        self.accent = accent
        hakMarks = obj["ht"] as? [[String]] ?? []
        hakZy = obj["hz"] as? [String: String] ?? [:]
        var m = 1
        let ja = obj["lang"] as? String == "ja"
        var index: [String: Int] = [:], byHan: [String: [Int]] = [:]
        var byPlain: [String: [Int]] = [:], byToned: [String: [Int]] = [:], byZy: [String: [Int]] = [:], byZyToned: [String: [Int]] = [:]
        var jk: [String] = []
        if ja { jk.reserveCapacity(out.count) }
        for (i, e) in out.enumerated() {
            index[e.k] = i
            byHan[e.h, default: []].append(i)
            if let a = e.alt, a != e.h { byHan[a, default: []].append(i) }
            m = max(m, e.h.unicodeScalars.count)
            // 日語: the reading in hiragana and in rōmaji ("たべる", "taberu"), and the other spellings
            if ja {
                let kana = JaKana.hiragana(e.tw.joined())
                jk.append(kana)
                Self.add(&byPlain, kana, i)
                Self.add(&byPlain, JaKana.romaji(kana).filter { $0.isLetter }, i)
                for o in e.eq { byHan[o, default: []].append(i); Self.add(&byPlain, JaKana.hiragana(o), i) }
                continue
            }
            // (四川話 too: "ce1", "ce")
            for syl in [e.tw] + (e.lu.map { [$0] } ?? []) + (e.sc.map { [$0] } ?? []) {
                let ss = syl.filter { $0 != "-" }
                let py = ss.map { Zhuyin.plainSyllable($0) }
                let toned = zip(ss, py).map { $1 + ((Zhuyin.isJyut($0) || Zhuyin.isHak($0) || [1, 2, 3, 4].contains(Zhuyin.tone($0))) ? String(Zhuyin.tone($0)) : "") }
                Self.add(&byPlain, py.joined(), i)
                Self.add(&byToned, toned.joined(), i)
                Self.add(&byZy, ss.map { Zhuyin.bare($0) }.joined(), i)
                Self.add(&byZyToned, ss.joined(), i)
            }
        }
        entries = out
        jaKana = jk
        Simp.learn(out.compactMap { e in e.alt.map { (e.h, $0) } })
        var byM: [String: [Int]] = [:]
        for (i, e) in out.enumerated() { for m in e.eq where byM[m]?.last != i { byM[m, default: []].append(i) } }
        // 客語: its meanings are written in 華語 ("聊天、閒談。"): each short piece of a meaning is a 華語 word for it
        if obj["lang"] as? String == "hak" {
            let seps = CharacterSet(charactersIn: "、。；，;,：:（）()「」『』 　\n？！?!")
            for (i, e) in out.enumerated() {
                for s in e.senses where !s.text.hasPrefix("參見") {
                    for piece in s.text.components(separatedBy: seps) where !piece.isEmpty && piece.count <= 6 && piece != e.h {
                        if byM[piece]?.last != i { byM[piece, default: []].append(i) }
                    }
                }
            }
        }
        byMandarin = byM
        self.index = index; self.byHan = byHan
        self.byPlain = byPlain; self.byToned = byToned; self.byZy = byZy; self.byZyToned = byZyToned
        maxLen = min(m, 12)
        var cs: [ZhChar] = []
        for c in obj["c"] as? [[String: Any]] ?? [] {
            guard let h = c["h"] as? String else { continue }
            var rs: [ZhChar.Reading] = []
            for r in c["m"] as? [[Any]] ?? [] {
                guard r.count >= 3, var zy = r[0] as? String, var py = r[1] as? String, let ds = r[2] as? [[String]] else { continue }
                // 粵語: [耶魯, 粵拼, …]; the 粵拼 syllable is kept as the one the readings are made from
                if obj["lang"] as? String == "yue" { zy = py }
                // 客語: [syllable, syllable, meanings, label, [the syllable in each accent]]: this accent's
                if r.count > 4, let v = r[4] as? [Any], accent < v.count, let mine = v[accent] as? String { zy = mine; py = mine }
                // 日語: [the readings in kana, …]: rōmaji made from them
                if obj["lang"] as? String == "ja" { py = JaKana.romaji(zy) }
                rs.append(ZhChar.Reading(zy: zy, py: py, defs: ds.map { (pos: $0.first ?? "", text: $0.count > 1 ? $0[1] : "") },
                                         label: r.count > 3 ? r[3] as? String : nil))
            }
            guard !rs.isEmpty else { continue }
            cs.append(ZhChar(h: h, readings: rs, hsk: c["x"] as? Int ?? 0, tocfl: c["y"] as? Int ?? 0,
                             radical: c["b"] as? String, strokes: c["n"] as? Int))
        }
        chars = cs
        let rd = Self.radicalData(obj)
        radicals = rd.0; radicalInside = rd.1; strokesOf = rd.2
        var ci: [String: Int] = [:]
        for (i, c) in cs.enumerated() { ci[c.h] = i }
        charIndex = ci
    }

    /// a character as a card: its usual reading (or reading `r`) and that reading's meanings; the other readings as 又
    func charCard(_ i: Int, list: Int = Lang.zhList, reading r: Int = 0) -> Card {
        let c = chars[i]
        let r = r < c.readings.count ? r : 0
        let main = c.readings[r]
        let defs = main.defs.map { Def(p: $0.pos, t: $0.text, x: [], sy: nil, an: nil) }
        let others = c.readings.enumerated().filter { $0.offset != r }.map(\.element).map { Other(l: $0.label ?? "又", r: [isHak ? readingPlain([$0.zy], 0) : $0.py], z: isYue ? Yale.of($0.zy) : (isHak ? readingPlain([$0.zy], 1) : $0.zy)) }
        let l = c.level(list)
        let topic = l > 0 ? Lang.charTopicBase + l : Lang.moreChars
        // (四川話: the reading of the character's own word read this way)
        let own = lang == 1 ? byHan[c.h]?.lazy.map { self.entries[$0] }.first(where: { $0.tw == [main.zy] }) : nil
        // (粵語: zy is the 粵拼 syllable, z its 耶魯)
        return Card(k: Lang.charKey(c.h, yue: isYue, hak: isHak, ja: isJa), h: Simp.show(c.h), r: [isHak ? readingPlain([main.py], 0) : main.py],
                    z: isYue ? Yale.of(main.zy) : (isHak ? readingPlain([main.zy], 1) : main.zy), a: nil, g: "", d: defs,
                    c: nil, zo: nil, v: nil, o: others.isEmpty ? nil : Array(others), s: nil, t: "漢字",
                    sy: nil, an: nil, cats: [topic], zs: [main.zy], zl: nil,
                    // (四川話: the reading of the character's own word read this way)
                    zc: own?.sc, zcKind: own?.scKind)
    }

    /// which of a character's readings a syllable is (the one in a word: 中 in 中獎 is ㄓㄨㄥˋ, not ㄓㄨㄥ); the
    /// syllables are tried in order (臺灣's, then 大陸's), each first as it is, then without the tone
    func readingIndex(_ i: Int, _ syllables: [String]) -> Int? {
        let rs = chars[i].readings
        for s in syllables where s != "-" && s != "_" && !s.isEmpty {
            if let j = rs.firstIndex(where: { $0.zy == s }) { return j }
        }
        for s in syllables where s != "-" && s != "_" && !s.isEmpty {
            let b = Zhuyin.plainSyllable(s)
            if let j = rs.firstIndex(where: { Zhuyin.plainSyllable($0.zy) == b }) { return j }
        }
        return nil
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

    /// 客語: each syllable's colour as the word says it (變調: every syllable but the last one by its accent's rules)
    private func hakTints(_ syl: [String], _ colours: Int) -> [String: Color]? {
        guard isHak, colours != 0 else { return nil }
        let idx = syl.indices.filter { Zhuyin.isHak(syl[$0]) }
        guard let firstIdx = idx.first else { return nil }
        let accent = Zhuyin.hakParts(syl[firstIdx]).accent
        let parts = idx.map { i -> (cat: Int, stop: Bool) in
            let p = Zhuyin.hakParts(syl[i])
            let l = p.letters
            return (p.tone, (l.last.map { "bdg".contains($0) } ?? false) && !l.hasSuffix("ng"))
        }
        let ps = HakSandhi.pitches(parts, accent: accent)
        var out: [String: Color] = [:]
        for (n, i) in idx.enumerated() {
            if let p = ps[n], let c = ToneColors.hakPitchColor(p.pitch, short: p.short, seven: colours != 5) { out["\(i)"] = c }
        }
        return out
    }

    /// a word's reading: 0 = 拼音, 1 = 注音; in tone colours when they're on
    func reading(_ syl: [String], _ mode: Int, colours: Int = ToneColors.system) -> AttributedString {
        // 日語: rōmaji (0) or kana (1, each script in its colour)
        if isJa {
            let kana = syl.filter { $0 != "-" && $0 != "_" }.joined()
            if mode == 0 { return AttributedString(JaKana.romaji(kana)) }
            return colours != 0 ? JaInk.word(kana) : AttributedString(kana)
        }
        var out = AttributedString()
        var first = true
        let hak = hakTints(syl, colours)
        for (si, s) in syl.enumerated() where s != "-" && s != "_" {
            var a: AttributedString
            if Zhuyin.isHak(s) {
                // 客語: 拼音 (0) or 注音 (1), with the accent's tone mark after the syllable
                a = AttributedString((first ? "" : " ") + hakSyllable(s, mode))
            } else if Zhuyin.isJyut(s) && !isYue {
                // 四川話: 四川話拼音 with the tone as a small number ("ce¹"), also when 注音 is chosen
                a = AttributedString((first ? "" : " ") + Zhuyin.sichuan(s))
            } else if Zhuyin.isJyut(s) {
                // 粵語: 粵拼 (0) or 耶魯 (1), a space between syllables
                a = AttributedString((first ? "" : " ") + (mode == 1 ? Yale.of(s) : s))
            } else if mode == 1 {
                a = AttributedString((first ? "" : "\u{2009}") + s)
            } else {
                let p = Zhuyin.pinyin(s)
                let apos = !first && (p.first.map { "aāáǎàoōóǒòeēéěèê".contains($0) } ?? false)
                a = AttributedString((apos ? "'" : "") + p)
            }
            if let hak, let c = hak["\(si)"] { a.swiftUI.foregroundColor = c }
            else if let c = tint(s, Zhuyin.tone(s), colours) { a.swiftUI.foregroundColor = c }
            out += a
            first = false
        }
        return out
    }

    /// a syllable's tone colour (四川話's own colours: 1 red, 2 and 5 teal, 3 purple, 4 blue)
    private func tint(_ s: String, _ t: Int, _ colours: Int) -> Color? {
        if colours != 0, !isYue, !isHak, Zhuyin.isJyut(s) { return ToneColors.scColor(t) }
        // 客語: by how the syllable's own accent says the tone (七聲: the 入聲 in colours of their own)
        if colours != 0, isHak, Zhuyin.isHak(s) { return ToneColors.hakAccentColor(Zhuyin.hakParts(s).accent, t, seven: colours != 5) }
        return Zhuyin.color(t, colours, yue: isYue, hak: isHak)
    }

    /// one 客語 syllable as it's shown: 拼音 (0) or 注音 (1), then its accent's tone mark ("bauˊ", "ㄅㄠˊ")
    func hakSyllable(_ s: String, _ mode: Int) -> String {
        let p = Zhuyin.hakParts(s)
        let mark = p.accent < hakMarks.count && p.tone < hakMarks[p.accent].count ? hakMarks[p.accent][p.tone] : ""
        return (mode == 1 ? (hakZy[p.letters] ?? p.letters) : p.letters) + mark
    }

    func readingPlain(_ syl: [String], _ mode: Int) -> String { String(reading(syl, mode, colours: 0).characters) }

    /// 漢字 in tone colours (one syllable per 漢字; 兒 after -ㄦ takes the colour before it)
    func hanText(_ han0: String, _ syl: [String], base: Color?, colours: Int = ToneColors.system) -> AttributedString {
        // 日語: kanji, hiragana and katakana each in their colour
        if isJa {
            var out = AttributedString()
            for ch in han0 {
                var a = AttributedString(String(ch))
                let kind = JaKana.isKanji(ch) || JaKana.isHiragana(ch) || JaKana.isKatakana(ch)
                if colours != 0 && kind { a.swiftUI.foregroundColor = JaColors.of(ch) } else if let base { a.swiftUI.foregroundColor = base }
                out += a
            }
            return out
        }
        var out = AttributedString(), i = 0, last = 1, lastSyl = ""
        let han = Simp.show(han0)       // (簡體, when chosen: one character for one)
        let hak = hakTints(syl, colours)
        var lastHak: Color?
        for u in han.unicodeScalars {
            var a = AttributedString(String(u))
            if Zhuyin.isHan(u), i < syl.count {
                let s = syl[i]; i += 1
                let t = s == "-" ? last : Zhuyin.tone(s)
                if s != "-" { lastSyl = s; lastHak = hak?["\(i - 1)"] }
                last = t
                if let c = lastHak { a.swiftUI.foregroundColor = c }
                else if let c = tint(lastSyl, t, colours) { a.swiftUI.foregroundColor = c } else if let base { a.swiftUI.foregroundColor = base }
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

    /// a word of a sentence's syllables (四川話: the dictionary word's 四川話 reading, when it has one)
    func pieceSyl(_ p: ZhPiece, _ place: Int) -> [String]? {
        if place == 2, let tw = p.tw, let s = scByWord[p.text.joined() + "\t" + tw.joined(separator: " ")] { return s }
        return p.syl(place)
    }

    /// a sentence's reading (0 拼音, 1 注音); `blank` = the word to leave out (例句填空)
    func sentence(_ ps: [ZhPiece], _ mode: Int, _ place: Int, blank: String? = nil, colours: Int = ToneColors.system) -> AttributedString {
        var out = AttributedString()
        var prevWord = false
        for p in ps {
            if let syl = pieceSyl(p, place) {
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
        if mode == 0, lang == 1, let i = s.characters.firstIndex(where: { $0.isLetter }) {
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
            var last = 1, lastSyl = ""
            for (i, ch) in p.text.enumerated() {
                var a = AttributedString(Simp.show(ch))
                if let syl = pieceSyl(p, place), i < syl.count, syl[i] != "_" {
                    let t = syl[i] == "-" ? last : Zhuyin.tone(syl[i])
                    if syl[i] != "-" { lastSyl = syl[i] }
                    last = t
                    a.swiftUI.foregroundColor = tint(lastSyl, t, colours) ?? base
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
                // (客語: the sentences aren't split into words; they're written for the word)
                let blankable = x.h != e.h && x.h.contains(e.h) && (isHak || Self.pieces(x).contains { $0.text.joined() == e.h })
                // (the reading is worked out when it's shown: Store.exampleRom)
                // (客語: no voice reads it, and the sentences have no reading word by word)
                return Example(h: Simp.show(x.h), r: [""], z: x.src, n: isHak ? "" : "tts:" + x.h,
                               bh: blankable ? Simp.show(x.h.replacingOccurrences(of: e.h, with: "＿＿")) : nil,
                               br: blankable ? [""] : nil, w: x.code.isEmpty ? nil : x.code)
            }, sy: nil, an: nil)
        }
        let variant: [String: Variant]? = e.lu.map { lu in
            ["1": Variant(r: [readingPlain(lu, 0)], z: readingPlain(lu, 1))]
        }
        return Card(k: e.k, h: Simp.show(e.h), r: [readingPlain(e.tw, 0)], z: readingPlain(e.tw, 1), a: nil, g: "", d: defs,
                    c: nil, zo: nil, v: variant, o: nil, s: nil,
                    t: e.spec == 1 ? "臺灣特有" : (e.spec == 2 ? "大陸特有" : (e.spec == Self.sichuanSpec ? "四川話" : nil)),
                    sy: nil, an: nil, cats: e.level(list) > 0 ? [e.level(list)] : nil, zs: e.tw, zl: e.lu, web: e.audio, zc: e.sc, zcKind: e.scKind)
    }

    // MARK: looking up

    struct Found {
        var words: [Int] = []          // the word itself (漢字 or reading)
        var starts: [Int] = []         // words starting with it
        var contains: [Int] = []       // words with it inside
        var defs: [Int] = []           // meanings that mention it
        var english: [Int] = []        // English meanings with the word
        var mandarin: [Int] = []       // 粵語: the words for this 華語 word (華語 → 粵語)
        var englishFirst = false       // the English meanings shown before the readings
        var tones: [Int] = []          // words with these tones
        var toneLabel = ""
        /// several words searched at once (陰謀論 → 陰謀, 論; or 陰謀 論): each word and its entries
        var parts: [String] = []
        var partWords: [[Int]] = []
        var empty: Bool { mandarin.isEmpty && parts.isEmpty && words.isEmpty && starts.isEmpty && contains.isEmpty && defs.isEmpty && english.isEmpty && tones.isEmpty }
    }

    /// the tones of a word as digits ("34", 0 = light tone)
    func toneDigits(_ e: ZhEntry, _ place: Int) -> String {
        e.syl(place).filter { $0 != "-" && $0 != "_" }.map { String(Zhuyin.tone($0)) }.joined()
    }

    /// (四川話's own words only when 讀音 = 四川話)
    func search(_ q0: String, place: Int = 0) -> Found {
        var f = search0(q0, place: place)
        guard lang == 1, place != 2 else { return f }
        let keep: (Int) -> Bool = { self.entries[$0].spec != Self.sichuanSpec }
        f.words = f.words.filter(keep); f.starts = f.starts.filter(keep); f.contains = f.contains.filter(keep)
        f.defs = f.defs.filter(keep); f.english = f.english.filter(keep); f.tones = f.tones.filter(keep)
        f.partWords = f.partWords.map { $0.filter(keep) }
        f.mandarin = []
        return f
    }

    private func search0(_ q0: String, place: Int) -> Found {
        let q = q0.trimmingCharacters(in: .whitespacesAndNewlines)
        var f = Found()
        guard !q.isEmpty else { return f }
        // 日語 (* and ? still go to the common search below)
        if isJa, !q.contains(where: { "*?＊？".contains($0) }) { return searchJa(q) }
        // only tone numbers: words with those tones, one per syllable (0 or 5 = light tone): 34、3-4、1 0
        if q.allSatisfy({ "012345678 -,，、".contains($0) }), q.contains(where: { $0.isNumber }) {
            let want = lang != 1 ? String(q.filter { $0.isNumber }) : String(q.filter { $0.isNumber }.map { $0 == "5" ? "0" : $0 })
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
        // 粵語: the words for a 華語 word (聊天 → 傾偈, 吹水…); 四川話 too (聊天 → 擺龍門陣, 日白…)
        // 客語: the words whose meaning is that 華語 word (聊天 → 打嘴鼓…)
        if isYue || isHak || lang == 1, let ms = byMandarin[q] { f.mandarin = ms }
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
        // (粵語: 粵拼, its tone numbers 1–6 are all kept)
        let p = lang != 1 ? Zhuyin.plain(q) : Zhuyin.plain(q).replacingOccurrences(of: "5", with: "").replacingOccurrences(of: "0", with: "")
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
        if !toned {
            let h = englishHits(q)
            f.english = h.list
            // an English word that's also spelled like a syllable ("me", "I"): the English first, when a meaning is
            // just that word
            f.englishFirst = h.best <= 1
        }
        return f
    }

    /// 日語: the word itself (kanji, kana or rōmaji), the dictionary word of a form (食べなかった → 食べる), the
    /// words starting with it, the words with it inside, and the English meanings (a meaning that is just the word
    /// first: "eat" → 食べる before 食う before 食事)
    private func searchJa(_ q: String) -> Found {
        var f = Found()
        var seen = Set<Int>()
        func take(_ is_: [Int]) -> [Int] { is_.sorted().filter { seen.insert($0).inserted } }
        let latin = q.unicodeScalars.allSatisfy { $0.isASCII }
        let letters = q.lowercased().filter { $0.isLetter }
        var kana = JaKana.hiragana(q)
        if latin, let k = JaKana.fromRomaji(letters) { kana = k }
        var exact = (byHan[q] ?? []) + (byPlain[kana] ?? [])
        if latin { exact += byPlain[letters] ?? [] }
        f.words = take(exact)
        // a form of a word: its dictionary form (only words that conjugate)
        var forms: [Int] = []
        for key in Set([q, kana]) {
            for (base, _) in JaGrammar.deinflect(key) {
                for i in (byHan[base] ?? []) + (byPlain[base] ?? []) where JaGrammar.classOf(entries[i]) != nil { forms.append(i) }
            }
        }
        f.words += take(forms)
        // starting with it, then with it inside
        if !latin || JaKana.fromRomaji(letters) != nil {
            var starts: [Int] = [], inside: [Int] = []
            for (i, e) in entries.enumerated() where !seen.contains(i) {
                let r = i < jaKana.count ? jaKana[i] : ""
                if e.h.hasPrefix(q) || (!kana.isEmpty && r.hasPrefix(kana)) {
                    if starts.count < 150 { starts.append(i) }
                } else if !latin, e.h.contains(q), inside.count < 150 {
                    inside.append(i)
                }
                if starts.count >= 150 && (latin || inside.count >= 150) { break }
            }
            f.starts = take(starts)
            f.contains = take(inside)
        }
        if latin && letters.count >= 1 {
            let h = englishHits(q)
            f.english = h.list
            // an English word asked for (no word read that way, or a meaning that's exactly it): English first
            f.englishFirst = h.best <= 1 && (f.words.isEmpty || h.best == 0)
        }
        return f
    }

    /// words whose English meaning has the word(s): a meaning that is just the word first ("eat", "to eat"),
    /// then meanings that start with it, then the rest. Within each: words that give it as their first meaning
    /// first, then the more common words (the entries are in order of how common they are). A meaning with a
    /// note in brackets ("(computing) (coll.) slow") counts one step lower, so 慢 comes before 卡 for "slow".
    /// "to park" (a verb) puts "to park" before "park" (a noun), and the other way round.
    func english(_ q0: String) -> [Int] { englishHits(q0).list }

    /// (and how close the best one is: 0 = a meaning that's exactly the words)
    func englishHits(_ q0: String) -> (list: [Int], best: Int) {
        let q = q0.enFold.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 || q == "i" || q == "a" else { return ([], 9) }
        var hits: [(tier: Int, later: Int, i: Int)] = []
        let wantVerb = q.hasPrefix("to ")
        let bare = wantVerb ? String(q.dropFirst(3)) : q
        let inWord = #"[^a-z]"# + NSRegularExpression.escapedPattern(for: bare) + #"[^a-z]"#
        let texts = englishTexts
        for i in texts.indices {
            // (粵語: Wiktionary's meanings are the senses, CC-Canto's / CC-CEDICT's the English)
            let en = texts[i]
            guard !en.isEmpty, en.contains(bare) else { continue }
            var best = 9, bestPos = 1
            for (pos, g0) in en.components(separatedBy: ";").enumerated() {
                // without notes in brackets: "(bound form) to walk" → "to walk"
                var g = g0
                var noted = false
                while let r = g.range(of: #"\([^()]*\)"#, options: .regularExpression) { g.removeSubrange(r); noted = true }
                g = g.trimmingCharacters(in: .whitespaces)
                let isVerb = g.hasPrefix("to ")
                let v = isVerb ? String(g.dropFirst(3)) : g
                var t = 9
                if v == bare { t = 0 }
                else if v.hasPrefix(bare + " ") || v.hasPrefix(bare + ",") { t = 2 }
                else if (" " + v + " ").range(of: inWord, options: .regularExpression) != nil { t = 4 }
                // a verb asked for and a noun found (or the other way round): one step lower
                if t < 9 && isVerb != wantVerb && (wantVerb || t == 0) { t += wantVerb ? 2 : 1 }
                if t < 9 && noted { t += 1 }
                let p = pos == 0 ? 0 : 1
                if t < best || (t == best && p < bestPos) { best = t; bestPos = p }
            }
            if best <= 5 { hits.append((best, bestPos, i)) }
        }
        hits.sort { ($0.tier, $0.later, $0.i) < ($1.tier, $1.later, $1.i) }
        return (Array(hits.prefix(250).map { $0.i }), hits.first?.tier ?? 9)
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
        if lang == 1, let want = Self.aloneReading[han], let i = is_.first(where: { entries[$0].tw.first == want }) { return i }
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
        if lang != 1 { return ps }      // (一 / 不 changing tone is 華語's)
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

    /// the best voice the device has: 粵語 (香港 Cantonese), or 華語 (臺灣 / 大陸); nil = no Cantonese voice
    static func voice(yue: Bool) -> AVSpeechSynthesisVoice? {
        let want = yue ? ["zh-HK", "yue-CN", "yue-HK"] : [Lang.zhPlace >= 1 ? "zh-CN" : "zh-TW", "zh-TW", "zh-CN"]
        let all = AVSpeechSynthesisVoice.speechVoices()
        for w in want {
            if let best = all.filter({ $0.language == w }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) { return best }
        }
        return yue ? nil : AVSpeechSynthesisVoice(language: "zh-TW")
    }

    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        if Lang.isJa {
            // 日語: the device's best Japanese voice
            let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
            u.voice = all.max(by: { $0.quality.rawValue < $1.quality.rawValue }) ?? AVSpeechSynthesisVoice(language: "ja-JP")
        } else if Lang.isYue {
            // no Cantonese voice: say how to get one (instead of reading it in 華語)
            guard let v = Self.voice(yue: true) else {
                Store.shared.speechHint = tr("這台裝置還沒有粵語的語音。到「設定 → 輔助使用 → 朗讀內容 → 聲音 → 中文」，下載「中文（香港）」的聲音（例如 Sinji），再回來就可以聽了。")
                onFinish?()
                return
            }
            u.voice = v
        } else {
            u.voice = Self.voice(yue: false)
        }
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


// MARK: - a quick copy of the entries (instant start)
//
// Reading zh.json (45 MB of JSON) takes seconds every time the app starts. The entries it makes are kept in a
// file of their own (Caches/ZhCache), written in a simple binary form that reads in a fraction of the time; it's
// made again whenever the dictionary file (or the app) changes.

private struct BinOut {
    var d = Data()
    mutating func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
    mutating func int(_ v: Int) { u32(UInt32(bitPattern: Int32(truncatingIfNeeded: v))) }
    mutating func str(_ v: String) { let u = Array(v.utf8); u32(UInt32(u.count)); d.append(contentsOf: u) }
    mutating func optStr(_ v: String?) { if let v { str(v) } else { u32(0xFFFF_FFFF) } }
    mutating func strs(_ v: [String]) { u32(UInt32(v.count)); for x in v { str(x) } }
    mutating func optStrs(_ v: [String]?) { if let v { strs(v) } else { u32(0xFFFF_FFFF) } }
}

private struct BinIn {
    let p: UnsafeRawBufferPointer
    var o = 0
    init(_ p: UnsafeRawBufferPointer) { self.p = p }
    mutating func u32() throws -> UInt32 {
        guard o + 4 <= p.count else { throw CocoaError(.fileReadCorruptFile) }
        let v = p.loadUnaligned(fromByteOffset: o, as: UInt32.self)
        o += 4
        return UInt32(littleEndian: v)
    }
    mutating func int() throws -> Int { Int(Int32(bitPattern: try u32())) }
    mutating func count() throws -> Int {
        let n = Int(try u32())
        guard n <= p.count else { throw CocoaError(.fileReadCorruptFile) }
        return n
    }
    mutating func bytes(_ n: Int) throws -> UnsafeRawBufferPointer {
        guard n >= 0, o + n <= p.count else { throw CocoaError(.fileReadCorruptFile) }
        let r = UnsafeRawBufferPointer(rebasing: p[o..<(o + n)])
        o += n
        return r
    }
    mutating func str() throws -> String { let n = try count(); return String(decoding: try bytes(n), as: UTF8.self) }
    mutating func optStr() throws -> String? {
        let n = try u32()
        if n == 0xFFFF_FFFF { return nil }
        return String(decoding: try bytes(Int(n)), as: UTF8.self)
    }
    mutating func strs() throws -> [String] {
        let n = try count()
        var out: [String] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try str()) }
        return out
    }
    mutating func optStrs() throws -> [String]? {
        let n = try u32()
        if n == 0xFFFF_FFFF { return nil }
        o -= 4
        return try strs()
    }
}

extension ZhDict {
    private static let quickVersion: UInt32 = 2
    private static let quickMagic: UInt32 = 0x3146_4646      // "FFF1"

    private static func quickURL(_ src: URL, _ accent: Int) -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZhCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(src.deletingPathExtension().lastPathComponent + "-\(accent).bin")
    }

    /// what the quick copy was made from: the file (its name, size and date), the accent and the app's version
    private static func quickStamp(_ src: URL, _ accent: Int) -> String {
        let a = try? FileManager.default.attributesOfItem(atPath: src.path)
        let size = (a?[.size] as? NSNumber)?.int64Value ?? 0
        let date = Int64((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let info = Bundle.main.infoDictionary
        let app = (info?["CFBundleShortVersionString"] as? String ?? "") + "/" + (info?["CFBundleVersion"] as? String ?? "")
        let installed = src.path.contains("/Dictionaries/") ? "i" : "b"
        return "\(quickVersion)|\(src.lastPathComponent)|\(installed)|\(size)|\(date)|\(accent)|\(app)"
    }

    /// the entries: from the quick copy when it's there and up to date, otherwise from the file (and the quick copy
    /// is made, in the background, for next time)
    fileprivate static func readQuick(_ data: Data, accent: Int, from url: URL?) throws -> (obj: [String: Any], entries: [ZhEntry]) {
        guard let url else { return try readFile(data, accent: accent) }
        let q = quickURL(url, accent)
        let stamp = quickStamp(url, accent)
        if let r = try? readQuickFile(q, stamp: stamp, accent: accent) { return r }
        let made = try readFile(data, accent: accent)
        // the head (everything before the entries), as it is in the file
        let marker = Data(",\"e\":[\n".utf8)
        if let r = data.range(of: marker) {
            var head = Data(data[data.startIndex..<r.lowerBound])
            head.append(contentsOf: Array("}".utf8))
            let entries = made.entries
            Task.detached(priority: .background) {
                writeQuickFile(q, stamp: stamp, head: head, entries: entries)
            }
        }
        return made
    }

    private static func writeQuickFile(_ q: URL, stamp: String, head: Data, entries: [ZhEntry]) {
        var w = BinOut()
        w.u32(quickMagic)
        w.str(stamp)
        w.u32(UInt32(head.count)); w.d.append(head)
        w.u32(UInt32(entries.count))
        for e in entries {
            w.str(e.k); w.str(e.h); w.strs(e.tw); w.optStrs(e.lu); w.int(e.spec); w.optStr(e.alt)
            w.u32(UInt32(e.senses.count))
            for s in e.senses {
                w.str(s.text)
                w.u32(UInt32(s.ex.count))
                for x in s.ex { w.str(x.h); w.str(x.src); w.str(x.code) }
            }
            w.optStr(e.en); w.int(e.hsk); w.int(e.tocfl); w.int(e.extra ? 1 : 0)
            w.strs(e.pos); w.strs(e.syn); w.strs(e.ant); w.strs(e.eq); w.optStr(e.audio)
            if let acc = e.acc {
                w.u32(UInt32(acc.count))
                for a in acc { w.optStrs(a) }
            } else { w.u32(0xFFFF_FFFF) }
            let others = e.otherWords.sorted { $0.key < $1.key }
            w.u32(UInt32(others.count))
            for (k, v) in others { w.int(k); w.str(v) }
            w.strs(e.jp)
        }
        let tmp = q.appendingPathExtension("tmp")
        do {
            try w.d.write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: q)
            try FileManager.default.moveItem(at: tmp, to: q)
        } catch { try? FileManager.default.removeItem(at: tmp) }
    }

    private static func readQuickFile(_ q: URL, stamp: String, accent: Int) throws -> (obj: [String: Any], entries: [ZhEntry]) {
        let data = try Data(contentsOf: q, options: .mappedIfSafe)
        return try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) throws -> (obj: [String: Any], entries: [ZhEntry]) in
            var r = BinIn(raw)
            guard try r.u32() == quickMagic, try r.str() == stamp else { throw CocoaError(.fileReadCorruptFile) }
            let headBytes = try r.bytes(try r.count())
            guard let obj = try JSONSerialization.jsonObject(with: Data(bytes: headBytes.baseAddress!, count: headBytes.count)) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let n = try r.count()
            var out: [ZhEntry] = []
            out.reserveCapacity(n)
            for _ in 0..<n {
                let k = try r.str(), h = try r.str(), tw = try r.strs(), lu = try r.optStrs(), spec = try r.int(), alt = try r.optStr()
                let ns = try r.count()
                var senses: [ZhSense] = []
                senses.reserveCapacity(ns)
                for i in 0..<ns {
                    let text = try r.str()
                    let nx = try r.count()
                    var ex: [ZhEx] = []
                    for _ in 0..<nx { ex.append(ZhEx(h: try r.str(), src: try r.str(), code: try r.str())) }
                    senses.append(ZhSense(n: i + 1, text: text, ex: ex))
                }
                let en = try r.optStr(), hsk = try r.int(), tocfl = try r.int(), extra = try r.int() == 1
                let pos = try r.strs(), syn = try r.strs(), ant = try r.strs(), eq = try r.strs(), audio = try r.optStr()
                var acc: [[String]?]? = nil
                let na = try r.u32()
                if na != 0xFFFF_FFFF {
                    var a: [[String]?] = []
                    for _ in 0..<Int(na) { a.append(try r.optStrs()) }
                    acc = a
                }
                var others: [Int: String] = [:]
                for _ in 0..<(try r.count()) { let a = try r.int(); others[a] = try r.str() }
                let jp = try r.strs()
                out.append(ZhEntry(k: k, h: h, tw: tw, lu: lu, spec: spec, alt: alt, senses: senses, en: en,
                                   hsk: hsk, tocfl: tocfl, extra: extra, pos: pos, syn: syn, ant: ant,
                                   eq: eq, audio: audio, acc: acc, otherWords: others, jp: jp))
            }
            return (obj, out)
        }
    }
}


// MARK: - 客語: a word an accent doesn't have

extension ZhDict {
    /// a word the accent chosen doesn't have is shown in another accent's reading (`tw` is the first accent that has
    /// it). Instead, each character gets the reading this accent has for it: from the words both accents have,
    /// "惜 in 四縣 siag is xiag in this accent" (the most common one when there are several). A character no word tells
    /// keeps the other accent's reading.
    fileprivate static func fillAccent(_ out: inout [ZhEntry], accent: Int) {
        // (source accent, character, its syllable there) → this accent's syllables for it, counted
        var map: [String: [String: Int]] = [:]
        func chars(_ h: String) -> [String] { h.unicodeScalars.filter { Zhuyin.isHan($0) }.map { String($0) } }
        for e in out {
            guard let acc = e.acc, accent < acc.count, let mine = acc[accent] else { continue }
            let cs = chars(e.h)
            guard cs.count == mine.count else { continue }
            for (a, other) in acc.enumerated() where a != accent {
                guard let other, other.count == cs.count else { continue }
                for i in cs.indices { map["\(a)\u{1}\(cs[i])\u{1}\(other[i])", default: [:]][mine[i], default: 0] += 1 }
            }
        }
        for i in out.indices {
            guard let acc = out[i].acc, accent < acc.count, acc[accent] == nil else { continue }
            let cs = chars(out[i].h)
            var tw = out[i].tw
            guard cs.count == tw.count else { continue }
            var changed = false
            for n in cs.indices where Zhuyin.isHak(tw[n]) {
                let a = Zhuyin.hakParts(tw[n]).accent
                if let hits = map["\(a)\u{1}\(cs[n])\u{1}\(tw[n])"], let best = hits.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key {
                    tw[n] = best; changed = true
                }
            }
            if changed {
                out[i] = ZhEntry(k: out[i].k, h: out[i].h, tw: tw, lu: out[i].lu, sc: out[i].sc, scKind: out[i].scKind,
                                 spec: out[i].spec, alt: out[i].alt, senses: out[i].senses, en: out[i].en, hsk: out[i].hsk,
                                 tocfl: out[i].tocfl, extra: out[i].extra, pos: out[i].pos, syn: out[i].syn, ant: out[i].ant,
                                 eq: out[i].eq, audio: out[i].audio, acc: out[i].acc, otherWords: out[i].otherWords, hakGuess: true,
                                 jp: out[i].jp)
            }
        }
    }
}
