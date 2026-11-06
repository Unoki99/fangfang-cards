import Foundation

/// One example sentence. `bh`/`br` are the fill-in-the-blank versions (word replaced by ＿＿).
struct Example: Decodable {
    let h: String          // 漢字
    let r: [String]        // 皓羅, 台羅, 白話字
    let z: String          // 華語
    let n: String          // audio name, e.g. "3139-1-1"
    let bh: String?
    let br: [String]?
    /// 華語: the sentence's reading, word by word (see Zh.swift)
    var w: String? = nil
}

struct Def: Decodable {
    let p: String          // word class
    let t: String          // meaning
    let x: [Example]
    let sy: [[String]]?    // synonyms: [漢字, 皓羅]
    let an: [[String]]?    // antonyms
}

/// the word as said in one place (腔口)
struct Variant: Decodable {
    let r: [String]        // 皓羅, 台羅, 白話字
    let z: String          // 方音
}

/// another reading: 又 / 俗 / 合
struct Other: Decodable {
    let l: String
    let r: [String]
    let z: String
}

struct Topic: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let count: Int
    init(id: Int, name: String, count: Int) { self.id = id; self.name = name; self.count = count }
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        id = try c.decode(Int.self)
        name = try c.decode(String.self)
        count = try c.decode(Int.self)
    }
}

struct Card: Decodable, Identifiable, Hashable {
    let k: String          // "漢字\tcodes" (same key as the website / extension)
    let h: String          // 漢字
    let r: [String]        // 皓羅, 台羅, 白話字
    let z: String          // 方音
    let a: Int?            // MOE audio id
    let g: String          // 白 / 文 / 俗
    let d: [Def]
    let c: [String]?       // syllable codes
    let zo: String?        // 方音 when a place is chosen (Tâi-lô o shown as ㄛ)
    let v: [String: Variant]?   // place index -> reading there
    let o: [Other]?
    let s: Int?            // 1 = 替代字
    let t: String?         // 臺華共同 / 附錄
    let sy: [[String]]?
    let an: [[String]]?
    let cats: [Int]?
    /// 華語: the 注音 syllables (臺灣, and 大陸 where it differs)
    var zs: [String]? = nil
    var zl: [String]? = nil

    var id: String { k }
    var isZh: Bool { zs != nil }
    /// the word's recording (台語), or the device's voice (華語)
    var audio: String? { isZh ? "tts:" + h : a.map { Audio.wordPath($0) } }
    static func == (l: Card, r: Card) -> Bool { l.k == r.k }
    func hash(into h: inout Hasher) { h.combine(k) }

    /// reading in 皓羅 / 台羅 / 白話字 (i), in a place (-1 = 通行)
    func rom(_ i: Int, _ place: Int = -1) -> String {
        let j = min(max(i, 0), r.count - 1)
        if place >= 0, let x = v?[String(place)] { return x.r[min(j, x.r.count - 1)] }
        return r[j]
    }
    func zy(_ place: Int = -1) -> String {
        guard place >= 0 else { return z }
        if let x = v?[String(place)] { return x.z }
        return zo ?? z
    }
    func differs(in place: Int) -> Bool { place >= 0 && v?[String(place)] != nil }
    var syllables: Int { r[0].split(separator: "-").count }
    var firstMeaning: String { d.first?.t ?? "" }
    /// the meaning an example sentence belongs to (成 in 伊佮𪜶老爸生做誠成 → 相似, not 完成)
    func meaning(of x: Example) -> Def? { d.first { $0.x.contains { $0.n == x.n && $0.h == x.h } } }
    var blankExamples: [Example] { d.flatMap { $0.x }.filter { $0.bh != nil && $0.br != nil } }
    var firstExample: Example? { d.lazy.compactMap { $0.x.first }.first }
    /// examples for the swipe card: one from each of two different meanings (meaning number, example);
    /// with only one meaning that has examples, two of its examples
    var cardExamples: [(n: Int, x: Example)] {
        var out: [(n: Int, x: Example)] = []
        for (i, def) in d.enumerated() { if let x = def.x.first { out.append((i + 1, x)) }; if out.count == 2 { return out } }
        if out.count == 1, let i = d.firstIndex(where: { !$0.x.isEmpty }), d[i].x.count > 1 { out.append((i + 1, d[i].x[1])) }
        return out
    }
}

struct DeckFile: Decodable {
    let v: Int
    let cards: [Card]
    let syl: [String: [String]]?   // syllable code -> 皓羅, 台羅, 白話字 (incl. every tone, for 聲調練習)
    let places: [String]?
    let topics: [Topic]?
}

/// Saved progress. status: 1 = 熟悉 (known), 2 = 不熟 (unknown)
struct Progress: Codable {
    var status: [String: Int] = [:]
    var added: [String: Double] = [:]
    var streak: [String: Int] = [:]
    /// 收藏 in 轉換: key -> time saved (negative = removed, so synced devices remove it too)
    var saved: [String: Double] = [:]
    /// 收藏 of one meaning of a word, or one example sentence of it: SavedSense.id -> time saved (negative = removed)
    var senses: [String: Double] = [:]
    /// 自訂: words you added yourself (key -> time added; negative = removed, so synced devices remove it too)
    var own: [String: Double] = [:]
    /// 本週學習: words picked for this week (key -> time picked; negative = taken out)
    var week: [String: Double] = [:]
    /// when this week started, for 台語 ("tw") and 華語 ("zh") (0 = no week going)
    var weekStart: [String: Double] = [:]

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent([String: Int].self, forKey: .status) ?? [:]
        added = try c.decodeIfPresent([String: Double].self, forKey: .added) ?? [:]
        streak = try c.decodeIfPresent([String: Int].self, forKey: .streak) ?? [:]
        saved = try c.decodeIfPresent([String: Double].self, forKey: .saved) ?? [:]
        senses = try c.decodeIfPresent([String: Double].self, forKey: .senses) ?? [:]
        week = try c.decodeIfPresent([String: Double].self, forKey: .week) ?? [:]
        weekStart = try c.decodeIfPresent([String: Double].self, forKey: .weekStart) ?? [:]
        own = try c.decodeIfPresent([String: Double].self, forKey: .own) ?? [:]
    }
}

enum Audio {
    static let defaultBase = "https://unoki99.github.io/fangfang/"
    static func wordPath(_ id: Int) -> String { "audio/\(id / 1000)/\(id)(1).mp3" }
    static func examplePath(_ name: String) -> String {
        if name.hasPrefix("tts:") { return name }      // 華語: read by the device
        let id = Int(name.split(separator: "-").first ?? "0") ?? 0
        return "leku/\(id / 1000)/\(name).mp3"
    }
}

/// a saved meaning of a word (sense = its number, from 0), with one of its example sentences or none
struct SavedSense: Hashable {
    let key: String          // the word ("漢字\tcodes")
    let sense: Int
    let ex: String           // the sentence: its recording name, or its 漢字 when it has none; "" = the meaning only

    var id: String { key + "\u{1}" + String(sense) + "\u{1}" + ex }
    init(key: String, sense: Int, ex: String = "") { self.key = key; self.sense = sense; self.ex = ex }
    init?(id: String) {
        let p = id.components(separatedBy: "\u{1}")
        guard p.count == 3, let n = Int(p[1]) else { return nil }
        key = p[0]; sense = n; ex = p[2]
    }
    /// how an example sentence ([漢字, template, 華語, audio]) is named here
    static func exID(_ e: [String]) -> String { e.count > 3 && !e[3].isEmpty ? e[3] : (e.first ?? "") }
}
