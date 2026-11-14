import SwiftUI

// MARK: - 日語 grammar: the colours, conjugation (活用), the suffixes the 實驗室 chains, and finding a word's
// dictionary form (食べなかった → 食べる)

// the colours: kanji, hiragana, katakana, particles, grammatical suffixes (設定 in 日語 → 顏色)
enum JaColors {
    static let keys = ["jaColor.kanji", "jaColor.hira", "jaColor.kata", "jaColor.particle", "jaColor.suffix"]
    static let names = ["漢字", "平假名", "片假名", "助詞", "語尾（助動詞）"]
    static let standard: [Int] = [0xffe991, 0x97e6a3, 0x97c2ff, 0xff9494, 0xd4b7ff]
    static func hex(_ i: Int) -> Int { (UserDefaults.standard.object(forKey: keys[i]) as? Int) ?? standard[i] }
    static func color(_ i: Int) -> Color { Color(hex: UInt32(truncatingIfNeeded: hex(i))) }
    static var kanji: Color { color(0) }
    static var hira: Color { color(1) }
    static var kata: Color { color(2) }
    static var particle: Color { color(3) }
    static var suffix: Color { color(4) }

    static func of(_ c: Character) -> Color {
        if JaKana.isKanji(c) { return kanji }
        if JaKana.isKatakana(c) { return kata }
        if JaKana.isHiragana(c) { return hira }
        return T.glyph
    }
}

/// a piece of a word or sentence, coloured by what it is
struct JaPiece: Identifiable, Hashable {
    enum Kind: Hashable { case word, suffix, particle, plain }
    var id = UUID()
    var text: String
    var kind: Kind
    /// what it is (語幹, 使役, 否定…)
    var label: String = ""
    /// what it does (a sentence)
    var note: String = ""
    /// its dictionary form (食べる, させる…): the part both have stays, the rest is what changed
    var dict: String = ""
}

enum JaInk {
    /// the pieces as coloured text: words by their script, suffixes and particles in their own colours
    static func attributed(_ pieces: [JaPiece]) -> AttributedString {
        var out = AttributedString()
        for p in pieces {
            switch p.kind {
            case .suffix:
                var a = AttributedString(p.text); a.foregroundColor = JaColors.suffix; out += a
            case .particle:
                var a = AttributedString(p.text); a.foregroundColor = JaColors.particle; out += a
            case .word, .plain:
                for ch in p.text { var a = AttributedString(String(ch)); a.foregroundColor = JaColors.of(ch); out += a }
            }
        }
        return out
    }
    static func word(_ s: String) -> AttributedString { attributed([JaPiece(text: s, kind: .word)]) }

    /// a sentence written with marks: [は] a particle, {ます} a suffix, the rest by script
    static func marked(_ s: String) -> [JaPiece] {
        var out: [JaPiece] = []
        var cur = ""
        var kind = JaPiece.Kind.word
        func flush() { if !cur.isEmpty { out.append(JaPiece(text: cur, kind: kind)) }; cur = "" }
        for ch in s {
            switch ch {
            case "[": flush(); kind = .particle
            case "{": flush(); kind = .suffix
            case "]", "}": flush(); kind = .word
            default: cur.append(ch)
            }
        }
        flush()
        return out
    }
    static func plainText(_ marked: String) -> String { marked.filter { !"[]{}".contains($0) } }
}

// MARK: conjugation

enum JaClass: Equatable {
    enum Special: Equatable { case none, iku, aru, nasaru, us }
    case godan(String, Special)     // (the last kana)
    case ichidan, suru, kuru, adjI, adjII, adjNa
    case masu, masen, te, done

    var isVerb: Bool {
        switch self { case .godan, .ichidan, .suru, .kuru: return true; default: return false }
    }
    var isAdj: Bool { self == .adjI || self == .adjII }
    var name: String {
        switch self {
        case .godan: return "五段動詞"
        case .ichidan: return "一段動詞"
        case .suru: return "サ變動詞（する）"
        case .kuru: return "カ變動詞（来る）"
        case .adjI, .adjII: return "い形容詞"
        case .adjNa: return "な形容詞"
        default: return ""
        }
    }
}

enum JaForm: CaseIterable {
    case a, aSa, i, u, e, o, te, ta, imp, bare
    var name: String {
        switch self {
        case .a, .aSa: return "未然形"
        case .i: return "連用形"
        case .u: return "終止形（辭書形）"
        case .e: return "假定形"
        case .o: return "意向形"
        case .te: return "て形"
        case .ta: return "た形"
        case .imp: return "命令形"
        case .bare: return "語幹"
        }
    }
}

enum JaGrammar {
    private static let rows: [String: [String]] = [
        "く": ["か", "き", "く", "け", "こ"], "ぐ": ["が", "ぎ", "ぐ", "げ", "ご"], "す": ["さ", "し", "す", "せ", "そ"],
        "つ": ["た", "ち", "つ", "て", "と"], "ぬ": ["な", "に", "ぬ", "ね", "の"], "ぶ": ["ば", "び", "ぶ", "べ", "ぼ"],
        "む": ["ま", "み", "む", "め", "も"], "る": ["ら", "り", "る", "れ", "ろ"], "う": ["わ", "い", "う", "え", "お"],
    ]
    static let vowelRow = ["あ段", "い段", "う段", "え段", "お段"]

    /// the class of a dictionary word, and the text that conjugates (a する noun gets its する)
    static func classOf(_ e: ZhEntry) -> (JaClass, String)? {
        classOf(pos: e.jp, head: e.h, reading: e.tw.joined())
    }
    static func classOf(pos: [String], head: String, reading: String) -> (JaClass, String)? {
        let last = reading.last.map(String.init) ?? ""
        for p in pos {
            switch p {
            case "v1", "v1-s": return (.ichidan, head)
            case "v5k-s": return (.godan("く", .iku), head)
            case "v5r-i": return (.godan("る", .aru), head)
            case "v5aru": return (.godan("る", .nasaru), head)
            case "v5u-s": return (.godan("う", .us), head)
            case "v5u", "v5k", "v5g", "v5s", "v5t", "v5n", "v5b", "v5m", "v5r":
                return rows[last] != nil ? (.godan(last, .none), head) : nil
            case "vk": return (.kuru, head)
            case "vs-i", "vs-s": return head.hasSuffix("する") || head.hasSuffix("為る") ? (.suru, head) : nil
            case "adj-i": return head.hasSuffix("い") ? (.adjI, head) : nil
            case "adj-ix": return (.adjII, head)
            default: break
            }
        }
        if pos.contains("vs") { return (.suru, head + "する") }
        if pos.contains("adj-na") { return (.adjNa, head) }
        return nil
    }
    /// the same, for the reading (kana)
    static func readingOf(_ e: ZhEntry, _ c: JaClass) -> String {
        let r = e.tw.joined()
        if c == .suru && !e.h.hasSuffix("する") && !e.h.hasSuffix("為る") { return r + "する" }
        return r
    }

    private static func drop(_ s: String, _ n: Int) -> String { String(s.dropLast(n)) }
    static func voiced(_ c: JaClass) -> Bool {
        if case .godan(let k, _) = c { return ["ぐ", "ぬ", "ぶ", "む"].contains(k) }
        return false
    }

    /// the text in a form ("書く", godan く, .a → "書か"); nil: no such form
    static func stem(_ t: String, _ c: JaClass, _ f: JaForm) -> String? {
        switch c {
        case .godan(let k, let sp):
            guard let r = rows[k] else { return nil }
            let b = drop(t, 1)
            switch f {
            case .a, .aSa: return sp == .aru ? drop(t, 2) : b + r[0]
            case .i: return sp == .nasaru ? b + "い" : b + r[1]
            case .u: return t
            case .e: return b + r[3]
            case .o: return b + r[4]
            case .imp: return sp == .nasaru ? b + "い" : b + r[3]
            case .te, .ta:
                if sp == .iku { return b + "っ" }
                if sp == .us { return t }
                switch k {
                case "く", "ぐ": return b + "い"
                case "す": return b + "し"
                case "ぬ", "ぶ", "む": return b + "ん"
                default: return b + "っ"
                }
            case .bare: return b + r[1]
            }
        case .ichidan:
            let b = drop(t, 1)
            switch f {
            case .a, .aSa, .i, .te, .ta, .bare: return b
            case .u: return t
            case .e: return b + "れ"
            case .o: return b + "よ"
            case .imp: return b + "ろ"
            }
        case .suru:
            let b = drop(t, 2)
            switch f {
            case .a, .i, .te, .ta: return b + "し"
            case .aSa: return b + "さ"
            case .u: return t
            case .e: return b + "すれ"
            case .o: return b + "しよ"
            case .imp: return b + "しろ"
            case .bare: return b
            }
        case .kuru:
            if t.hasPrefix("来") {
                switch f {
                case .u: return t
                case .e: return "来れ"
                case .o: return "来よ"
                case .imp: return "来い"
                default: return "来"
                }
            }
            switch f {
            case .a, .aSa: return "こ"
            case .i, .te, .ta, .bare: return "き"
            case .u: return t
            case .e: return "くれ"
            case .o: return "こよ"
            case .imp: return "こい"
            }
        case .adjI, .adjII:
            let b = c == .adjII ? (t.hasPrefix("良") ? "良" : "よ") : drop(t, 1)
            switch f {
            case .a, .i, .te: return b + "く"
            case .u: return t
            case .e: return b + "けれ"
            case .o: return b + "かろ"
            case .ta: return b + "かっ"
            case .bare: return c == .adjII ? b + "さ" : b
            default: return nil
            }
        case .adjNa:
            switch f {
            case .a: return t + "じゃ"
            case .ta: return t + "だっ"
            case .u, .bare, .te, .i: return t
            default: return nil
            }
        case .masu:
            switch f {
            case .a: return "ませ"
            case .i, .te, .ta: return "まし"
            case .u: return t
            case .o: return "ましょ"
            default: return nil
            }
        case .masen, .te:
            return f == .u ? t : nil
        case .done:
            return nil
        }
    }

    // MARK: the suffixes

    struct Suffix: Identifiable {
        let id: String
        /// its name (中文)
        let name: String
        /// what it does (中文)
        let note: String
        var kind: JaPiece.Kind = .suffix
        /// for the class before it: the form that class must be in, the suffix's text, and the class it makes
        let attach: (JaClass) -> (JaForm, String, JaClass)?
    }

    static let suffixes: [Suffix] = [
        Suffix(id: "nai", name: "否定 ない", note: "「不…」。接在未然形後面；ない自己像い形容詞一樣活用（なかった、なくて）。") { c in
            if c.isVerb { return (.a, "ない", .adjI) }
            if c.isAdj { return (.a, "ない", .adjI) }
            if c == .adjNa { return (.a, "ない", .adjI) }
            return nil
        },
        Suffix(id: "masu", name: "禮貌 ます", note: "有禮貌的說法。接在連用形（ます形）後面。") { c in c.isVerb ? (.i, "ます", .masu) : nil },
        Suffix(id: "masen", name: "否定 ん", note: "ます的否定：ませ＋ん。") { c in c == .masu ? (.a, "ん", .masen) : nil },
        Suffix(id: "deshita", name: "過去 でした", note: "ません的過去：ませんでした。") { c in c == .masen ? (.u, "でした", .done) : nil },
        Suffix(id: "ta", name: "過去 た", note: "過去或完成。動詞用た形（音便：書いた、読んだ）。") { c in
            if c.isVerb { return (.ta, voiced(c) ? "だ" : "た", .done) }
            if c.isAdj || c == .adjNa || c == .masu { return (.ta, "た", .done) }
            return nil
        },
        Suffix(id: "te", name: "て形 て", note: "連接下一個動作「…然後…」，也接いる、しまう、ください。") { c in
            if c.isVerb { return (.te, voiced(c) ? "で" : "て", .te) }
            if c.isAdj || c == .masu { return (.te, "て", .te) }
            if c == .adjNa { return (.te, "で", .te) }
            return nil
        },
        Suffix(id: "tara", name: "條件 たら", note: "「…了以後／要是…的話」。") { c in
            if c.isVerb { return (.ta, voiced(c) ? "だら" : "たら", .done) }
            if c.isAdj || c == .adjNa || c == .masu { return (.ta, "たら", .done) }
            return nil
        },
        Suffix(id: "ba", name: "條件 ば", note: "「如果…」。接在假定形（え段）後面。") { c in
            if c.isVerb || c.isAdj { return (.e, "ば", .done) }
            if c == .adjNa { return (.u, "なら", .done) }
            return nil
        },
        Suffix(id: "you", name: "意向 う／よう", note: "「…吧！（一起）」或「打算…」。接在意向形（お段）後面。") { c in
            if c.isVerb || c == .masu { return (.o, "う", .done) }
            return nil
        },
        Suffix(id: "imp", name: "命令", note: "命令「…！」。五段動詞用え段，一段動詞加ろ。") { c in c.isVerb ? (.imp, "", .done) : nil },
        Suffix(id: "tai", name: "願望 たい", note: "「想…」。接在連用形後面；たい像い形容詞一樣活用。") { c in c.isVerb ? (.i, "たい", .adjI) : nil },
        Suffix(id: "seru", name: "使役 せる／させる", note: "「讓（人）…、叫（人）…」。五段動詞＋せる，其他＋させる；變成一段動詞。") { c in
            switch c {
            case .godan: return (.a, "せる", .ichidan)
            case .ichidan, .kuru: return (.a, "させる", .ichidan)
            case .suru: return (.aSa, "せる", .ichidan)
            default: return nil
            }
        },
        Suffix(id: "reru", name: "被動 れる／られる", note: "「被…」（也是尊敬）。五段動詞＋れる，其他＋られる；變成一段動詞。") { c in
            switch c {
            case .godan: return (.a, "れる", .ichidan)
            case .ichidan, .kuru: return (.a, "られる", .ichidan)
            case .suru: return (.aSa, "れる", .ichidan)
            default: return nil
            }
        },
        Suffix(id: "pot", name: "可能", note: "「能…、會…」。五段動詞：え段＋る；一段動詞：＋られる；する → できる。") { c in
            switch c {
            case .godan(_, let sp) where sp != .aru: return (.e, "る", .ichidan)
            case .ichidan, .kuru: return (.a, "られる", .ichidan)
            case .suru: return (.bare, "できる", .ichidan)
            default: return nil
            }
        },
        Suffix(id: "nagara", name: "同時 ながら", note: "「一邊…一邊…」。接在連用形後面。") { c in c.isVerb ? (.i, "ながら", .done) : nil },
        Suffix(id: "naide", name: "ないで", note: "「不…（就）…、別…」。") { c in c.isVerb ? (.a, "ないで", .done) : nil },
        Suffix(id: "sou", name: "樣態 そう", note: "「看起來好像…」。動詞接連用形，形容詞接語幹。") { c in
            if c.isVerb { return (.i, "そう", .adjNa) }
            if c.isAdj { return (.bare, "そう", .adjNa) }
            if c == .adjNa { return (.u, "そう", .adjNa) }
            return nil
        },
        Suffix(id: "naru", name: "變成 なる", note: "「變得…」。い形容詞く＋なる，な形容詞に＋なる。") { c in
            if c.isAdj { return (.i, "なる", .godan("る", .none)) }
            if c == .adjNa { return (.u, "になる", .godan("る", .none)) }
            return nil
        },
        Suffix(id: "iru", name: "持續 いる", note: "「正在…、…著」。て形＋いる；變成一段動詞。") { c in c == .te ? (.u, "いる", .ichidan) : nil },
        Suffix(id: "shimau", name: "完了 しまう", note: "「…完了、不小心…了」。て形＋しまう。") { c in c == .te ? (.u, "しまう", .godan("う", .none)) : nil },
        Suffix(id: "miru", name: "嘗試 みる", note: "「…看看」。て形＋みる。") { c in c == .te ? (.u, "みる", .ichidan) : nil },
        Suffix(id: "kudasai", name: "請求 ください", note: "「請…」。て形＋ください。") { c in c == .te ? (.u, "ください", .done) : nil },
        Suffix(id: "desu", name: "禮貌 です", note: "形容詞的禮貌說法。") { c in (c.isAdj || c == .adjNa) ? (.u, "です", .done) : nil },
        Suffix(id: "da", name: "斷定 だ", note: "な形容詞的普通說法「是…的」。") { c in c == .adjNa ? (.u, "だ", .done) : nil },
        Suffix(id: "na", name: "連體 な", note: "放在名詞前面修飾名詞（静かな部屋）。", kind: .particle) { c in c == .adjNa ? (.u, "な", .done) : nil },
        Suffix(id: "kara", name: "原因 から", note: "「因為…」。", kind: .particle) { c in
            (c.isVerb || c.isAdj || c == .masu || c == .masen) ? (.u, "から", .done) : nil
        },
        Suffix(id: "tekara", name: "之後 から", note: "「…之後（再…）」。て形＋から。", kind: .particle) { c in c == .te ? (.u, "から", .done) : nil },
        Suffix(id: "to", name: "條件 と", note: "「一…就…」（每次都會這樣）。", kind: .particle) { c in
            (c.isVerb || c.isAdj || c == .masu) ? (.u, "と", .done) : nil
        },
    ]
    static func suffix(_ id: String) -> Suffix? { suffixes.first { $0.id == id } }

    /// what can really follow each ending (the class alone lets through things nobody says: ない after ない gives
    /// 食べなくなくない…, させ after させ, られ after られ). nil: after the word itself, everything its class takes.
    static let after: [String: Set<String>] = [
        // 使役 (食べさせる): + 被動 = 使役受身 (食べさせられる); not 使役 again, not 可能 (it would be the same as 被動)
        "seru": ["nai", "masu", "ta", "te", "tara", "ba", "you", "imp", "tai", "reru", "nagara", "naide", "sou", "kara", "to"],
        // 被動 (食べられる): not 使役 or 被動 again, no 命令 / 意向
        "reru": ["nai", "masu", "ta", "te", "tara", "ba", "tai", "nagara", "naide", "sou", "kara", "to"],
        // 可能 (書ける, 食べられる): a state: no 命令, 意向, 願望, ながら
        "pot": ["nai", "masu", "ta", "te", "tara", "ba", "sou", "kara", "to"],
        // ない: なかった, なくて, なければ, なかったら, ないです, なくなる (not ない again)
        "nai": ["ta", "te", "ba", "tara", "desu", "naru", "kara", "to"],
        // たい: たかった, たくて, たければ, たくない, たいです, たくなる
        "tai": ["nai", "ta", "te", "ba", "tara", "desu", "naru", "kara", "to"],
        // なる (高くなる): a verb again
        "naru": ["nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "sou", "pot", "kara", "to"],
        // ます: ません, ました, まして, ましたら, ましょう, ますから, ますと
        "masu": ["masen", "ta", "te", "tara", "you", "kara", "to"],
        // ません: ませんでした, ませんから
        "masen": ["deshita", "kara"],
        // て: ている, てしまう, てみる, てください, てから
        "te": ["iru", "shimau", "miru", "kudasai", "tekara"],
        "iru": ["nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "kara", "to"],
        "shimau": ["nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "sou", "kara", "to"],
        "miru": ["nai", "masu", "ta", "te", "tara", "ba", "you", "tai", "kara", "to"],
        // そう (食べそう): そうだ, そうです, そうな, そうだった, そうで, そうなら, そうになる
        "sou": ["da", "desu", "na", "ta", "te", "ba", "naru"],
    ]
    /// ある: no 使役, 被動, 可能, 命令, 願望, 意向
    private static let notAfterAru: Set<String> = ["seru", "reru", "pot", "imp", "tai", "you"]

    /// can this ending come after the chain as it is?
    static func allowed(_ c: Chain, _ id: String) -> Bool {
        // each ending once (て may come twice: ていて): no loops like たく・なり・たく・なり…
        if id != "te" && c.ops.contains(id) { return false }
        // て: いる, しまう, みる, ください, から only after a verb's て (食べて・いる); after なくて, 高くて, まして
        // nothing more; after ていて, てみて only ください and から
        if c.ops.last == "te" {
            let prev = c.ops.dropLast().last
            var verbal: Bool
            if let prev { verbal = ["seru", "reru", "pot", "naru", "shimau"].contains(prev) } else { verbal = c.base.isVerb }
            if case .godan(_, .aru) = c.base, prev == nil { verbal = false }
            if verbal { return ["iru", "shimau", "miru", "kudasai", "tekara"].contains(id) }
            if prev == "iru" || prev == "miru" { return ["kudasai", "tekara"].contains(id) }
            return false
        }
        if let last = c.ops.last { return after[last]?.contains(id) ?? false }
        if case .godan(_, .aru) = c.cls, notAfterAru.contains(id) { return false }
        return true
    }

    /// a conjugation being built: the pieces, and the class of the last one (the one that conjugates next)
    struct Chain {
        var pieces: [JaPiece]
        var cls: JaClass
        var ops: [String] = []
        /// the word's own class (食べる: 一段動詞), whatever comes after it
        let base: JaClass

        init(_ text: String, _ cls: JaClass, label: String = "") {
            pieces = [JaPiece(text: text, kind: .word, label: label.isEmpty ? cls.name : label, note: "", dict: text)]
            self.cls = cls
            base = cls
        }

        /// the suffixes that can come next
        var next: [Suffix] { JaGrammar.suffixes.filter { $0.attach(cls) != nil && JaGrammar.allowed(self, $0.id) } }

        /// with one more suffix (nil: it can't come here)
        func adding(_ id: String) -> Chain? {
            guard JaGrammar.allowed(self, id), let s = JaGrammar.suffix(id), case let (f, text, c2)? = s.attach(cls), let last = pieces.last,
                  let st = JaGrammar.stem(last.text, cls, f) else { return nil }
            var ch = self
            var p = last
            p.text = st
            var form = f.name
            if case .godan(let k, _) = cls, let r = JaGrammar.rows[k], let i = r.firstIndex(where: { st.hasSuffix($0) }),
               [.a, .i, .e, .o, .imp].contains(f) {
                form += "（" + JaGrammar.vowelRow[i] + "）"
            }
            p.note = (p.note.isEmpty ? "" : p.note + "　") + "→ " + form
            ch.pieces[ch.pieces.count - 1] = p
            ch.pieces.append(JaPiece(text: text, kind: s.kind, label: s.name, note: s.note, dict: text))
            ch.cls = c2
            ch.ops.append(id)
            return ch
        }
        func adding(_ ids: [String]) -> Chain? {
            var c: Chain? = self
            for i in ids { c = c?.adding(i) }
            return c
        }
        var text: String { pieces.map(\.text).joined() }
    }

    /// the rows of the 活用 table: (name, English, suffixes)
    static func table(for c: JaClass) -> [(String, String, [String])] {
        if c.isVerb {
            var t: [(String, String, [String])] = [
                ("辭書形", "dictionary", []), ("ます形", "polite", ["masu"]),
                ("ない形", "negative", ["nai"]), ("ません", "polite negative", ["masu", "masen"]),
                ("た形", "past", ["ta"]), ("ました", "polite past", ["masu", "ta"]),
                ("なかった", "past negative", ["nai", "ta"]), ("ませんでした", "polite past negative", ["masu", "masen", "deshita"]),
                ("て形", "te-form", ["te"]), ("ている", "progressive", ["te", "iru"]),
                ("ないで", "without doing", ["naide"]), ("たい", "want to", ["tai"]),
                ("可能形", "potential", ["pot"]), ("受身形", "passive", ["reru"]),
                ("使役形", "causative", ["seru"]), ("使役受身", "causative-passive", ["seru", "reru"]),
                ("意向形", "volitional", ["you"]), ("ましょう", "polite volitional", ["masu", "you"]),
                ("命令形", "imperative", ["imp"]), ("ば形", "conditional", ["ba"]),
                ("たら", "if / when", ["tara"]), ("ながら", "while", ["nagara"]),
            ]
            if case .godan(_, .aru) = c { t.removeAll { $0.2 == ["pot"] } }
            return t
        }
        if c.isAdj {
            return [("辭書形", "dictionary", []), ("です", "polite", ["desu"]), ("否定", "negative", ["nai"]),
                    ("過去", "past", ["ta"]), ("過去否定", "past negative", ["nai", "ta"]), ("て形", "te-form", ["te"]),
                    ("ば形", "conditional", ["ba"]), ("たら", "if / when", ["tara"]), ("～そう", "looks", ["sou"]),
                    ("～なる", "become", ["naru"])]
        }
        if c == .adjNa {
            return [("～だ", "plain", ["da"]), ("～です", "polite", ["desu"]), ("～な＋名詞", "before a noun", ["na"]),
                    ("否定", "negative", ["nai"]), ("過去", "past", ["ta"]), ("過去否定", "past negative", ["nai", "ta"]),
                    ("て形", "te-form", ["te"]), ("なら", "if", ["ba"]), ("～そう", "looks", ["sou"]), ("～になる", "become", ["naru"])]
        }
        return []
    }

    /// the 活用 table in groups: forms that belong together (plain and polite, the voices, the conditionals) side by side
    struct ConjGroup: Identifiable {
        var id: String { name }
        let name: String
        let en: String
        /// the group's colour (the app's rainbow)
        let color: UInt32
        let rows: [(String, String, [String])]
    }
    static func groups(for c: JaClass) -> [ConjGroup] {
        let t = table(for: c)
        func g(_ name: String, _ en: String, _ color: UInt32, _ names: [String]) -> ConjGroup? {
            let rows = names.compactMap { n in t.first { $0.0 == n } }
            return rows.isEmpty ? nil : ConjGroup(name: name, en: en, color: color, rows: rows)
        }
        let green: UInt32 = 0x5fd38d, red: UInt32 = 0xff6b6b, yellow: UInt32 = 0xffd95a, blue: UInt32 = 0x6eaaff
        let purple: UInt32 = 0xb38bff, pink: UInt32 = 0xff8cc6, orange: UInt32 = 0xffa94d, teal: UInt32 = 0x4fd8c4
        let wine: UInt32 = 0xd0577a, olive: UInt32 = 0x9ccc5a, violet: UInt32 = 0x8f6bd8
        var out: [ConjGroup?]
        if c.isVerb {
            out = [g("現在", "present", green, ["辭書形", "ます形"]),
                   g("否定", "negative", red, ["ない形", "ません"]),
                   g("過去", "past", yellow, ["た形", "ました"]),
                   g("過去否定", "past negative", blue, ["なかった", "ませんでした"]),
                   g("て形", "te-form", purple, ["て形", "ている"]),
                   g("意向", "volitional", wine, ["意向形", "ましょう"]),
                   g("可能・受身・使役", "potential, passive, causative", orange, ["可能形", "受身形", "使役形", "使役受身"]),
                   g("條件・同時", "conditional, while", teal, ["ば形", "たら", "ながら"]),
                   g("ないで", "without", pink, ["ないで"]),
                   g("願望", "want", olive, ["たい"]),
                   g("命令", "imperative", violet, ["命令形"])]
        } else if c.isAdj {
            out = [g("現在", "present", green, ["辭書形", "です"]),
                   g("否定・過去", "negative, past", red, ["否定", "過去", "過去否定"]),
                   g("て形", "te-form", purple, ["て形"]),
                   g("條件", "conditional", teal, ["ば形", "たら"]),
                   g("樣子・變化", "looks, become", orange, ["～そう", "～なる"])]
        } else {
            out = [g("現在", "present", green, ["～だ", "～です", "～な＋名詞"]),
                   g("否定・過去", "negative, past", red, ["否定", "過去", "過去否定"]),
                   g("て形", "te-form", purple, ["て形"]),
                   g("條件", "conditional", teal, ["なら"]),
                   g("樣子・變化", "looks, become", orange, ["～そう", "～になる"])]
        }
        return out.compactMap { $0 }
    }

    // MARK: back to the dictionary form (for search)

    private static let endings: [(String, String)] = {
        var r: [(String, String)] = [
            // 一段
            ("ませんでした", "る"), ("ました", "る"), ("ません", "る"), ("ます", "る"), ("なかった", "る"), ("ない", "る"),
            ("させられる", "る"), ("られる", "る"), ("させる", "る"), ("たい", "る"), ("よう", "る"), ("れば", "る"),
            ("ている", "る"), ("た", "る"), ("て", "る"), ("ろ", "る"), ("ながら", "る"),
            // い形容詞
            ("くなかった", "い"), ("かった", "い"), ("くない", "い"), ("くて", "い"), ("ければ", "い"), ("く", "い"), ("さ", "い"), ("そう", "い"),
            // する・来る
            ("しませんでした", "する"), ("しました", "する"), ("しません", "する"), ("します", "する"), ("しない", "する"),
            ("した", "する"), ("して", "する"), ("させる", "する"), ("される", "する"), ("しよう", "する"), ("すれば", "する"),
            ("しろ", "する"), ("できる", "する"), ("したい", "する"), ("している", "する"),
            ("きます", "くる"), ("こない", "くる"), ("きた", "くる"), ("きて", "くる"), ("こよう", "くる"), ("くれば", "くる"), ("こい", "くる"),
            ("来ます", "来る"), ("来ない", "来る"), ("来た", "来る"), ("来て", "来る"), ("来よう", "来る"), ("来れば", "来る"), ("来い", "来る"),
            // 五段 て/た
            ("いて", "く"), ("いた", "く"), ("いで", "ぐ"), ("いだ", "ぐ"), ("して", "す"), ("した", "す"),
            ("って", "う"), ("った", "う"), ("って", "つ"), ("った", "つ"), ("って", "る"), ("った", "る"), ("って", "く"), ("った", "く"),
            ("んで", "む"), ("んだ", "む"), ("んで", "ぶ"), ("んだ", "ぶ"), ("んで", "ぬ"), ("んだ", "ぬ"),
        ]
        for (u, row) in rows {
            r.append((row[1] + "ませんでした", u)); r.append((row[1] + "ました", u)); r.append((row[1] + "ません", u))
            r.append((row[1] + "ます", u)); r.append((row[1] + "たい", u)); r.append((row[1] + "ながら", u))
            r.append((row[0] + "なかった", u)); r.append((row[0] + "ない", u)); r.append((row[0] + "れる", u)); r.append((row[0] + "せる", u))
            r.append((row[0] + "される", u)); r.append((row[3] + "ば", u)); r.append((row[3] + "る", u)); r.append((row[4] + "う", u))
            r.append((row[3], u))
        }
        return r.sorted { $0.0.count > $1.0.count }
    }()

    /// the dictionary forms a word can be a form of (two steps: 食べさせなかった → 食べさせる → 食べる)
    static func deinflect(_ s: String) -> [(String, String)] {
        var out: [(String, String)] = []
        var seen = Set<String>()
        var todo = [s]
        for _ in 0..<3 {
            var next: [String] = []
            for w in todo {
                for (end, base) in endings where w.hasSuffix(end) && w.count > end.count - (base == "する" || base == "くる" ? 1 : 0) {
                    let b = String(w.dropLast(end.count)) + base
                    if b != w && seen.insert(b).inserted { out.append((b, end)); next.append(b) }
                    if base == "する" { let n = String(w.dropLast(end.count)); if !n.isEmpty && seen.insert(n).inserted { out.append((n, end)) } }
                }
            }
            todo = next
        }
        return out
    }

}

// MARK: the meaning of a chain in English (roughly: 大意)

enum JaEnglish {
    private static let irregular: [String: (String, String)] = [
        "be": ("was", "been"), "eat": ("ate", "eaten"), "go": ("went", "gone"), "come": ("came", "come"), "see": ("saw", "seen"),
        "do": ("did", "done"), "make": ("made", "made"), "take": ("took", "taken"), "give": ("gave", "given"), "write": ("wrote", "written"),
        "read": ("read", "read"), "speak": ("spoke", "spoken"), "say": ("said", "said"), "buy": ("bought", "bought"), "drink": ("drank", "drunk"),
        "know": ("knew", "known"), "think": ("thought", "thought"), "teach": ("taught", "taught"), "find": ("found", "found"), "tell": ("told", "told"),
        "get": ("got", "gotten"), "hold": ("held", "held"), "leave": ("left", "left"), "lose": ("lost", "lost"), "meet": ("met", "met"),
        "pay": ("paid", "paid"), "sell": ("sold", "sold"), "send": ("sent", "sent"), "stand": ("stood", "stood"), "understand": ("understood", "understood"),
        "break": ("broke", "broken"), "choose": ("chose", "chosen"), "forget": ("forgot", "forgotten"), "wake": ("woke", "woken"),
        "wear": ("wore", "worn"), "sleep": ("slept", "slept"), "sit": ("sat", "sat"), "run": ("ran", "run"), "swim": ("swam", "swum"),
        "sing": ("sang", "sung"), "begin": ("began", "begun"), "bring": ("brought", "brought"), "build": ("built", "built"), "catch": ("caught", "caught"),
        "fall": ("fell", "fallen"), "feel": ("felt", "felt"), "fly": ("flew", "flown"), "grow": ("grew", "grown"), "hide": ("hid", "hidden"),
        "keep": ("kept", "kept"), "put": ("put", "put"), "ride": ("rode", "ridden"), "rise": ("rose", "risen"), "shut": ("shut", "shut"),
        "steal": ("stole", "stolen"), "throw": ("threw", "thrown"), "win": ("won", "won"), "hear": ("heard", "heard"), "have": ("had", "had"),
        "let": ("let", "let"), "cut": ("cut", "cut"), "hit": ("hit", "hit"), "lend": ("lent", "lent"), "spend": ("spent", "spent"),
        "draw": ("drew", "drawn"), "become": ("became", "become"), "forgive": ("forgave", "forgiven"), "lie": ("lay", "lain"), "show": ("showed", "shown"),
        "want": ("wanted", "wanted"), "try": ("tried", "tried"), "can": ("could", "could"),
    ]
    private static let doubling: Set<String> = ["run", "swim", "sit", "stop", "get", "put", "cut", "begin", "shop", "plan", "hit", "win", "drop", "chat", "jog", "hug", "nod", "rob", "beg", "dig", "let", "set"]

    private static func split(_ p: String) -> (String, String) {
        guard let sp = p.firstIndex(of: " ") else { return (p, "") }
        return (String(p[..<sp]), String(p[sp...]))
    }
    static func past(_ v: String) -> String {
        if let x = irregular[v] { return x.0 }
        if doubling.contains(v), let l = v.last { return v + String(l) + "ed" }
        if v.hasSuffix("e") { return v + "d" }
        if v.hasSuffix("y"), let b = v.dropLast().last, !"aeiou".contains(b) { return String(v.dropLast()) + "ied" }
        return v + "ed"
    }
    static func participle(_ v: String) -> String { irregular[v]?.1 ?? past(v) }
    static func gerund(_ v: String) -> String {
        if v == "be" { return "being" }
        if v.hasSuffix("ie") { return String(v.dropLast(2)) + "ying" }
        if doubling.contains(v), let l = v.last { return v + String(l) + "ing" }
        if v.hasSuffix("e") && !v.hasSuffix("ee") && v.count > 2 { return String(v.dropLast()) + "ing" }
        return v + "ing"
    }
    private static func onFirst(_ p: String, _ f: (String) -> String) -> String { let (a, b) = split(p); return f(a) + b }

    /// the first meaning, as a bare verb phrase ("to eat" → "eat"; an adjective: "be big")
    static func base(_ e: ZhEntry, _ c: JaClass) -> String {
        var g = e.senses.first?.text.components(separatedBy: ";").first ?? ""
        if let r = g.range(of: " (") { g = String(g[..<r.lowerBound]) }
        if g.hasPrefix("to ") { g = String(g.dropFirst(3)) }
        if c.isAdj || c == .adjNa { return "be " + g }
        return g
    }

    static func compose(_ base: String, _ ops: [String]) -> String {
        var p = base
        var neg = false, pastT = false, polite = false
        var mode = ""
        func pushNeg() { if neg { p = "not " + p; neg = false } }
        for op in ops {
            switch op {
            case "seru": pushNeg(); p = "make (someone) " + p
            case "reru":
                pushNeg()
                if p.hasPrefix("make (someone) ") { p = "be made to " + p.dropFirst(15) } else { p = "be " + onFirst(p, participle) }
            case "pot": pushNeg(); p = "be able to " + p
            case "tai": pushNeg(); p = "want to " + p
            case "naru": pushNeg(); p = p.hasPrefix("be ") ? "become " + p.dropFirst(3) : "come to " + p
            case "iru": pushNeg(); p = "be " + onFirst(p, gerund)
            case "shimau": pushNeg(); p += " (completely / regrettably)"
            case "miru": pushNeg(); p = "try " + onFirst(p, gerund)
            case "sou": pushNeg(); p = p.hasPrefix("be ") ? "seem " + p.dropFirst(3) : "seem about to " + p
            case "nai": neg.toggle()
            case "masen": neg.toggle(); polite = true
            case "masu", "desu": polite = true
            case "ta", "deshita": pastT = true
            case "te": mode = "te"
            case "tara": mode = "tara"
            case "ba": mode = "if"
            case "you": mode = "lets"
            case "imp": mode = "imp"
            case "nagara": mode = "while"
            case "naide": mode = "without"
            case "kudasai": mode = "please"
            case "kara": mode = "because"
            case "tekara": mode = "after"
            case "to": mode = "when"
            default: break
            }
        }
        if p.hasPrefix("not ") { p = String(p.dropFirst(4)); neg.toggle() }
        func finite(_ isPast: Bool) -> String {
            let (v, rest) = split(p)
            if v == "be" {
                return (isPast ? "was" : "is") + (neg ? " not" : "") + rest
            }
            if neg { return (isPast ? "did not " : "does not ") + p }
            return isPast ? JaEnglish.past(v) + rest : p
        }
        var out: String
        switch mode {
        case "te": out = (neg ? "not " : "") + onFirst(p, gerund) + " and…"
        case "tara": out = "if / when (it) " + finite(true)
        case "if": out = "if (it) " + finite(false)
        case "lets": out = "let's " + p
        case "imp": out = p + "!"
        case "while": out = "while " + onFirst(p, gerund)
        case "without": out = "without " + onFirst(p, gerund)
        case "please": out = "please " + (neg ? "don't " : "") + p
        case "because": out = "because (it) " + finite(pastT)
        case "after": out = "after " + onFirst(p, gerund)
        case "when": out = "when (it) " + finite(pastT)
        default: out = finite(pastT)
        }
        return out + (polite ? " (polite)" : "")
    }
}
