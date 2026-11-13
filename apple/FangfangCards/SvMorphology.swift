import SwiftUI

// MARK: - 瑞典語: a word's morphemes (詞素), their colours, and what each prefix, suffix and ending means and does

/// one morpheme of a Swedish word, from sv.json's "s" ("be:p tal:r:tala a:e"): its letters, what it is, and for a
/// root the word it comes from (tal → tala). A phrase (hitta på) has its words' morphemes with a space between
/// them ("_:w").
struct SvMorpheme: Hashable, Identifiable, Sendable {
    enum Kind: String, Hashable, Sendable { case root = "r", prefix = "p", suffix = "s", link = "l", ending = "e", space = "w" }
    var id: Int
    var text: String
    var kind: Kind
    var lemma: String = ""

    /// "text:kind[:lemma]" each (empty strings: none)
    static func parse(_ syl: [String]) -> [SvMorpheme] {
        var out: [SvMorpheme] = []
        for s in syl where !s.isEmpty {
            let p = s.components(separatedBy: ":")
            guard p.count >= 2, !p[0].isEmpty, let k = Kind(rawValue: p[1]) else { continue }
            out.append(SvMorpheme(id: out.count, text: k == .space ? " " : p[0], kind: k, lemma: p.count > 2 ? p[2] : ""))
        }
        return out
    }

    /// back to sv.json's way of writing it
    var code: String { kind == .space ? "_:w" : text + ":" + kind.rawValue + (lemma.isEmpty ? "" : ":" + lemma) }

    /// the word to look up for a root (its lemma, or its own letters)
    var word: String { (lemma.isEmpty ? text : lemma).lowercased() }

    /// what it is, in Chinese
    var kindName: String {
        switch kind {
        case .root: return "詞根"
        case .prefix: return "前綴"
        case .suffix: return "後綴"
        case .link: return "連接音"
        case .ending: return "詞尾"
        case .space: return ""
        }
    }

    /// numbered again from 0 (after putting pieces together)
    static func renumbered(_ ms: [SvMorpheme]) -> [SvMorpheme] {
        ms.enumerated().map { i, m in var m = m; m.id = i; return m }
    }

    /// a form of a word (betalade of betala, samtyckliga of samtycklig): the word's morphemes for the part the form
    /// shares with it, then the rest as an ending; the letters as the form writes them (Hittade)
    static func forForm(_ form: String, lemma: String, _ ms0: [SvMorpheme]) -> [SvMorpheme] {
        let orig = Array(form), low = orig.map { $0.lowercased() }
        let ms = ms0.isEmpty ? [SvMorpheme(id: 0, text: lemma, kind: .root)] : ms0
        func fits(_ list: [SvMorpheme]) -> Bool {
            let t = Array(list.map(\.text).joined().lowercased())
            return !list.isEmpty && t.count <= low.count && zip(t, low).allSatisfy { String($0.0) == $0.1 }
        }
        // the word without its ending (tal-a → tal + ade), else the whole word (samtycklig + a), else the part they share
        var use = ms
        while let l = use.last, l.kind == .ending { use.removeLast() }
        if !fits(use) || form.lowercased() == lemma.lowercased() { use = ms }
        if !fits(use) {
            let t = Array(ms.map(\.text).joined().lowercased())
            var n = 0
            while n < t.count && n < low.count && String(t[n]) == low[n] { n += 1 }
            var cut: [SvMorpheme] = [], at = 0
            for m in ms where at < n {
                let take = min(m.text.count, n - at)
                var c = m; c.text = String(m.text.prefix(take)); cut.append(c)
                at += take
            }
            use = cut
        }
        var out: [SvMorpheme] = [], at = 0
        for m in use {
            let n = m.text.count
            guard at + n <= orig.count else { break }
            var c = m; c.text = String(orig[at..<(at + n)]); out.append(c)
            at += n
        }
        if at < orig.count {
            let rest = String(orig[at...])
            // (ta → tag-, dra → drag-: the stem's -g / -d stays with the root)
            if ["g", "d"].contains(rest.lowercased()), let l = out.last, l.kind == .root, let v = l.text.last, "aeiouyåäöAEIOUYÅÄÖ".contains(v) {
                out[out.count - 1].text += rest
            } else {
                out.append(SvMorpheme(id: 0, text: rest, kind: .ending))
            }
        }
        return renumbered(out)
    }
}

/// the colours (設定 → 瑞典語 → 顏色): two for roots (one after the other in a compound: sjuk|hus), prefixes,
/// suffixes, linking letters, endings. An affix on an affix takes the colour of the one next to it, darker: in
/// samtyck|lig|a, -a is -lig's pink, darker; in o|be|…, o- is be-'s teal, darker
enum SvColors {
    static let keys = ["svColor.root", "svColor.root2", "svColor.prefix", "svColor.suffix", "svColor.link", "svColor.ending"]
    static let names = ["詞根", "第二個詞根", "前綴", "後綴", "連接音", "詞尾"]
    static let standard: [Int] = [0xffe991, 0xffb36b, 0x6fe0cf, 0xff94c8, 0xbdbdbd, 0xc7a6ff]
    static func hex(_ i: Int) -> Int { (UserDefaults.standard.object(forKey: keys[i]) as? Int) ?? standard[i] }
    static func color(_ i: Int) -> Color { Color(hex: UInt32(truncatingIfNeeded: hex(i))) }

    private static func base(_ k: SvMorpheme.Kind) -> Int {
        switch k {
        case .root: return 0
        case .prefix: return 2
        case .suffix: return 3
        case .link, .space: return 4
        case .ending: return 5
        }
    }

    /// which colour a morpheme takes in its word, and how many steps darker: roots alternate (0, 1, 0…, again from
    /// 0 in each word of a phrase); a prefix before prefixes is a step darker for each; a suffix or ending after
    /// suffixes and endings takes the first one's colour, a step darker for each after it
    static func style(of m: SvMorpheme, in ms: [SvMorpheme]) -> (index: Int, depth: Int) {
        guard let i = ms.firstIndex(where: { $0.id == m.id }) else { return (base(m.kind), 0) }
        switch m.kind {
        case .root:
            var n = 0, j = i - 1
            while j >= 0 && ms[j].kind != .space { if ms[j].kind == .root { n += 1 }; j -= 1 }
            return (n % 2 == 0 ? 0 : 1, 0)
        case .prefix:
            var d = 0, j = i + 1
            while j < ms.count && ms[j].kind == .prefix { d += 1; j += 1 }
            return (2, d)
        case .suffix, .ending:
            var st = i
            while st > 0 && (ms[st - 1].kind == .suffix || ms[st - 1].kind == .ending) { st -= 1 }
            return (base(ms[st].kind), i - st)
        case .link, .space:
            return (4, 0)
        }
    }

    /// a colour a few steps darker
    static func shade(_ c: Color, _ depth: Int) -> Color {
        guard depth > 0 else { return c }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(c).getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return c }
        let f = pow(0.74, CGFloat(depth))
        return Color(hue: Double(h), saturation: Double(min(1, s * (1 + 0.18 * CGFloat(depth)))), brightness: Double(b * f), opacity: Double(a))
    }

    static func color(of m: SvMorpheme, in ms: [SvMorpheme]) -> Color {
        let st = style(of: m, in: ms)
        return shade(color(st.index), st.depth)
    }
    /// (for the colour picker's numbers: which colour it's of)
    static func index(of m: SvMorpheme, in ms: [SvMorpheme]) -> Int { style(of: m, in: ms).index }

    /// the morphemes as coloured text (one morpheme: in `base`)
    static func attributed(_ ms: [SvMorpheme], base: Color?, colours: Bool = ToneColors.system != 0) -> AttributedString {
        var out = AttributedString()
        for m in ms {
            var a = AttributedString(m.text)
            if colours && ms.filter({ $0.kind != .space }).count > 1 && m.kind != .space { a.swiftUI.foregroundColor = color(of: m, in: ms) }
            else if let base { a.swiftUI.foregroundColor = base }
            out += a
        }
        return out
    }
}

extension ZhDict {
    /// 瑞典語: a word as written (Hittade, bilarna, på): the morphemes of the entry it's the word or a form of (the
    /// form's ending added), in its own letters; [] when the dictionary doesn't have it
    static func svWordMorphemes(_ w: String, _ es: [ZhEntry], _ idx: [Int]) -> [SvMorpheme] {
        guard !w.isEmpty, !idx.isEmpty else { return [] }
        let low = w.lowercased()
        let e = idx.map { es[$0] }.first { $0.h.lowercased() == low && !$0.h.contains(" ") } ?? idx.map { es[$0] }.first { !$0.h.contains(" ") }
        guard let e else { return [] }
        let ms = SvMorpheme.parse(e.tw)
        if e.h.lowercased() == low {
            if ms.isEmpty { return [SvMorpheme(id: 0, text: w, kind: .root)] }
            if ms.map(\.text).joined().lowercased() == low { return SvMorpheme.forForm(w, lemma: e.h, ms) }
            return [SvMorpheme(id: 0, text: w, kind: .root)]
        }
        return SvMorpheme.forForm(w, lemma: e.h, ms)
    }

    /// 瑞典語: a sentence with each word in its morphemes' colours (hyphens: split, sam-tyck-lig-a); punctuation and
    /// words the dictionary doesn't have in `base`
    func svSentence(_ text: String, hyphens: Bool, base: Color, colours: Bool = ToneColors.system != 0) -> AttributedString {
        var out = AttributedString()
        for (li, line) in text.components(separatedBy: "\n").enumerated() {
            if li > 0 { out += AttributedString("\n") }
            for (n, t) in line.split(separator: " ").enumerated() {
                if n > 0 { out += AttributedString(" ") }
                let s = String(t)
                let lead = String(s.prefix { !$0.isLetter && !$0.isNumber })
                let rest = s.dropFirst(lead.count)
                let tail = String(rest.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
                let core = String(rest.dropLast(tail.count))
                var a = AttributedString(lead); a.swiftUI.foregroundColor = base; out += a
                let ms = core.isEmpty ? [] : svMorphemes(ofWord: core)
                if ms.count > 1 && hyphens {
                    for (i, m) in ms.enumerated() {
                        if i > 0 { var d = AttributedString("-"); d.swiftUI.foregroundColor = T.muted.opacity(0.7); out += d }
                        var b = AttributedString(m.text); b.swiftUI.foregroundColor = colours ? SvColors.color(of: m, in: ms) : base; out += b
                    }
                } else if ms.count > 1 {
                    out += SvColors.attributed(ms, base: base, colours: colours)
                } else {
                    var c = AttributedString(core); c.swiftUI.foregroundColor = base; out += c
                }
                var z = AttributedString(tail); z.swiftUI.foregroundColor = base; out += z
            }
        }
        return out
    }

    /// 瑞典語, when the dictionary is read: -are and -ast(e) on an adjective or adverb are its comparative and
    /// superlative (sen|are 更晚, snar|are, snabb|ast), not -are of a person (läs|are); and a phrase without morphemes
    /// of its own (hitta på) gets its words'
    static func svFix(_ es0: [ZhEntry], _ byPlain: [String: [Int]]) -> [ZhEntry] {
        var es = es0
        func describes(_ w: String) -> Bool {
            (byPlain[w.lowercased()] ?? []).contains { i in es0[i].pos.contains { $0 == "形容詞" || $0 == "副詞" } }
        }
        func noun(_ e: ZhEntry) -> Bool { e.pos.contains("名詞") || e.pos.contains("動詞") }
        for i in es.indices {
            let e = es[i]
            guard !e.h.contains(" ") else { continue }
            var ms = SvMorpheme.parse(e.tw)
            let low = e.h.lowercased()
            if let last = ms.last, last.kind == .suffix, last.text.lowercased() == "are", ms.count >= 2, !noun(e) {
                // the word before -are: what the roots and suffixes before it make (tidig|are → tidig)
                let stem = ms.dropLast().map(\.text).joined()
                if e.pos.contains(where: { $0 == "形容詞" || $0 == "副詞" }) || describes(stem) || describes(ms[ms.count - 2].word) {
                    ms[ms.count - 1].kind = .ending
                    es[i].tw = ms.map(\.code)
                }
            } else if ms.isEmpty, !noun(e) {
                // (no morphemes: senast, snabbast, närmare… made from the adjective when it's there)
                for end in ["aste", "ast", "are"] where low.hasSuffix(end) && low.count > end.count + 1 {
                    let stem = String(e.h.dropLast(end.count))
                    if describes(stem) {
                        es[i].tw = [stem + ":r:" + stem.lowercased(), String(e.h.suffix(end.count)) + ":e"]
                        break
                    }
                }
            }
        }
        func headword(_ w: String) -> Bool { (byPlain[w.lowercased()] ?? []).contains { es0[$0].h.lowercased() == w.lowercased() && !es0[$0].h.contains(" ") } }
        // splits that make two words better: det|s|amma → det|samma (samma is a word), allt|ing → all|ting
        for i in es.indices {
            var ms = SvMorpheme.parse(es[i].tw)
            guard ms.count >= 2 else { continue }
            var changed = false
            var j = 0
            while j + 1 < ms.count {
                if ms[j].kind == .link, ms[j].text.lowercased() == "s", ms[j + 1].kind == .root, j > 0,
                   headword("s" + ms[j + 1].text), ms[j + 1].text.count >= 3 {
                    ms[j + 1].text = ms[j].text + ms[j + 1].text
                    ms[j + 1].lemma = ms[j + 1].text.lowercased()
                    ms.remove(at: j)
                    changed = true
                    continue
                }
                if ms[j].kind == .root, ms[j + 1].kind == .suffix, ms[j].text.count >= 4, j + 2 == ms.count {
                    let x = ms[j].text, sfx = ms[j + 1].text
                    let a = String(x.dropLast()), w2 = String(x.suffix(1)) + sfx
                    if a.count >= 3, w2.count >= 4, headword(a), headword(w2) {
                        ms[j].text = a; ms[j].lemma = a.lowercased()
                        ms[j + 1] = SvMorpheme(id: 0, text: w2, kind: .root, lemma: w2.lowercased())
                        changed = true
                    }
                }
                j += 1
            }
            if changed { es[i].tw = SvMorpheme.renumbered(ms).map(\.code) }
        }
        // o- that isn't "not": only where the dictionary has the o-word both ways, ovan "above" and o|van
        // "unaccustomed" (the meaning says which: "un-", "not", 不…), and in words made from the "above" one
        // (ovan|på "on top of"). olycka, olycklig, ovanlig keep their o-
        let negative = try? NSRegularExpression(pattern: "\\b(un|in|im|ir|il|non|dis|mis)\\w|\\bnot\\b|\\bwithout\\b|\\bno\\b|\\bbad|不|非|無|沒|未|失", options: .caseInsensitive)
        func negated(_ e: ZhEntry) -> Bool {
            let text = ([e.en ?? ""] + e.jp).joined(separator: " ")
            guard let negative else { return false }
            return negative.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        /// the o-word has an entry that isn't "not…" and one that is
        func bothWays(_ w: String) -> Bool {
            let es = (byPlain[w.lowercased()] ?? []).map { es0[$0] }.filter { $0.h.lowercased() == w.lowercased() }
            return es.contains { !negated($0) } && es.contains { negated($0) }
        }
        for i in es.indices {
            var ms = SvMorpheme.parse(es[i].tw)
            guard ms.count >= 2, ms[0].kind == .prefix, ms[0].text.lowercased() == "o", ms[1].kind == .root,
                  bothWays("o" + ms[1].text), !negated(es[i]) else { continue }
            ms[1].text = ms[0].text + ms[1].text
            ms[1].lemma = ms[1].text.lowercased()
            ms.remove(at: 0)
            es[i].tw = SvMorpheme.renumbered(ms).map(\.code)
        }
        // -ning that's -ing on a verb ending in -n (var|ning → varn|ing: varna, not vara)
        func verb(_ w: String) -> Bool { (byPlain[w.lowercased()] ?? []).contains { es0[$0].pos.contains("動詞") && es0[$0].h.lowercased() == w.lowercased() } }
        for i in es.indices {
            var ms = SvMorpheme.parse(es[i].tw)
            guard ms.count >= 2 else { continue }
            var changed = false
            for j in 1..<ms.count where ms[j].kind == .suffix && ms[j].text.lowercased() == "ning" && ms[j - 1].kind == .root {
                let stem = ms[j - 1].text + "n"
                if verb(stem + "a") {
                    ms[j - 1].text = stem; ms[j - 1].lemma = (stem + "a").lowercased()
                    ms[j].text = String(ms[j].text.dropFirst())
                    changed = true
                }
            }
            if changed { es[i].tw = ms.map(\.code) }
        }
        // verbs made of a short verb (omhänder|ta, an|ta, upp|dra): its forms say so (omhändertog), so the -a isn't
        // an infinitive ending: the part before it (om|händer) and the short verb as a root
        let short: [(String, String)] = [("ta", "tog"), ("dra", "drog"), ("ge", "gav"), ("be", "bad"), ("gå", "gick"), ("se", "såg"),
                                         ("få", "fick"), ("stå", "stod"), ("slå", "slog"), ("dö", "dog"), ("le", "log")]
        for i in es.indices where es[i].pos.contains("動詞") && !es[i].h.contains(" ") {
            let e = es[i], low = e.h.lowercased()
            let ms = SvMorpheme.parse(e.tw)
            guard ms.isEmpty || ms.last?.kind == .ending else { continue }
            for (v, past) in short where low.hasSuffix(v) && low.count > v.count + 1 {
                let front = String(e.h.dropLast(v.count))
                guard e.eq.contains(where: { $0.lowercased().replacingOccurrences(of: "|", with: "") == front.lowercased() + past }) else { continue }
                var pm = svWordMorphemes(front, es0, byPlain[front.lowercased()] ?? [])
                if pm.isEmpty {
                    // (om|händer: a prefix and a word)
                    let fl = front.lowercased()
                    if let p = SvAffixes.prefixes.keys.sorted(by: { $0.count > $1.count }).first(where: { fl.hasPrefix($0) && fl.count - $0.count >= 3 && !(byPlain[String(fl.dropFirst($0.count))] ?? []).isEmpty }) {
                        pm = [SvMorpheme(id: 0, text: String(front.prefix(p.count)), kind: .prefix),
                              SvMorpheme(id: 0, text: String(front.dropFirst(p.count)), kind: .root)]
                    } else {
                        pm = [SvMorpheme(id: 0, text: front, kind: .root)]
                    }
                }
                es[i].tw = (pm + [SvMorpheme(id: 0, text: String(e.h.suffix(v.count)), kind: .root, lemma: v)]).map(\.code)
                break
            }
        }
        for i in es.indices where es[i].h.contains(" ") && SvMorpheme.parse(es[i].tw).isEmpty {
            if let t = svPhrase(es[i].h, es, byPlain) { es[i].tw = t }
        }
        return es
    }

    /// 瑞典語: a phrase without morphemes of its own (hitta på, skiljer sig): each word's, a space between them
    static func svPhrase(_ h: String, _ es: [ZhEntry], _ byPlain: [String: [Int]]) -> [String]? {
        let words = h.split(separator: " ").map(String.init)
        guard words.count > 1 else { return nil }
        var out: [SvMorpheme] = []
        for (i, w) in words.enumerated() {
            if i > 0 { out.append(SvMorpheme(id: 0, text: " ", kind: .space)) }
            let ms = svWordMorphemes(w, es, byPlain[w.lowercased()] ?? [])
            out += ms.isEmpty ? [SvMorpheme(id: 0, text: w, kind: .root)] : ms
        }
        return out.map(\.code)
    }
}

/// what a prefix, suffix, linking letter or ending means and does
struct SvAffix {
    /// what it means (Chinese)
    let zh: String
    /// what it does to the word (Chinese)
    let does: String
    /// the same in English
    let en: String
    /// an example: the word without it → with it
    let ex: String
}

enum SvAffixes {
    static let prefixes: [String: SvAffix] = [
        "o": .init(zh: "不、非", does: "加在形容詞或名詞前面，意思變成相反。", en: "un-, not: turns the meaning into its opposite", ex: "lycklig 幸福 → olycklig 不幸"),
        "be": .init(zh: "（使動）", does: "把動詞變成及物動詞，或把名詞、形容詞變成動詞：對某物做某事。", en: "makes a verb take an object, or makes a verb of a noun or adjective", ex: "tala 說 → betala 付錢；fri 自由 → befria 解放"),
        "för": .init(zh: "使…、過度、提前", does: "把形容詞或名詞變成動詞（使變得…），或表示過頭、在前。", en: "makes verbs (make something…), or means too much / before", ex: "bättre 更好 → förbättra 改善"),
        "an": .init(zh: "向、對", does: "表示朝向、接觸或開始，常見於從德語借來的詞。", en: "towards, on (often in words from German)", ex: "komma 來 → ankomma 到達"),
        "av": .init(zh: "離開、去掉", does: "表示分開、去除、結束。", en: "off, away, from", ex: "bryta 折 → avbryta 打斷"),
        "in": .init(zh: "進、入", does: "表示向裡面。", en: "in, into", ex: "gång 走 → ingång 入口"),
        "ut": .init(zh: "出、外", does: "表示向外面或做完。", en: "out", ex: "gång 走 → utgång 出口"),
        "upp": .init(zh: "上、起", does: "表示向上、開始或完成。", en: "up", ex: "gång 走 → uppgång 上升"),
        "till": .init(zh: "向、加", does: "表示到某處、加上或屬於。", en: "to, towards, added", ex: "gång 走 → tillgång 取得、資源"),
        "över": .init(zh: "上方、超過", does: "表示在上面、越過或太多。", en: "over, above, too much", ex: "gång 走 → övergång 過渡"),
        "under": .init(zh: "下方、不足", does: "表示在下面、少於。", en: "under, below", ex: "gång 走 → undergång 滅亡"),
        "efter": .init(zh: "之後", does: "表示在後面、跟隨。", en: "after", ex: "middag 午餐 → eftermiddag 下午"),
        "före": .init(zh: "之前", does: "表示在前面、先。", en: "before, fore-", ex: "gå 走 → föregå 先於"),
        "fram": .init(zh: "向前", does: "表示向前、出來。", en: "forward, forth", ex: "steg 步 → framsteg 進步"),
        "om": .init(zh: "重新、圍繞", does: "表示再一次、改變或環繞。", en: "re-, around, about", ex: "göra 做 → omgöra 重做"),
        "mot": .init(zh: "相對、反", does: "表示對著、反對。", en: "against, counter-", ex: "gift 毒 → motgift 解毒劑"),
        "med": .init(zh: "一起", does: "表示共同、跟隨。", en: "with, co-", ex: "arbetare 工人 → medarbetare 同事"),
        "miss": .init(zh: "錯、失", does: "表示做錯或不好。", en: "mis-, wrongly", ex: "förstå 了解 → missförstå 誤會"),
        "sam": .init(zh: "共同", does: "表示一起、合作。", en: "together, co-", ex: "arbete 工作 → samarbete 合作"),
        "sär": .init(zh: "分開、特別", does: "表示分開或特殊。", en: "apart, special", ex: "skilja 分 → särskilja 區分"),
        "van": .init(zh: "不好、錯", does: "表示不正確、不好的。", en: "mis-, bad", ex: "tro 信仰 → vantro 不信"),
        "åter": .init(zh: "再、回", does: "表示再一次或回來。", en: "re-, back", ex: "seende 見 → återseende 重逢"),
        "ur": .init(zh: "原、最初；出", does: "表示最早的、原始的，或向外。", en: "original, primeval; out of", ex: "skog 森林 → urskog 原始森林"),
        "er": .init(zh: "（得到）", does: "表示得到、達到（從德語借來）。", en: "gain, achieve (from German)", ex: "känna 知道 → erkänna 承認"),
        "ge": .init(zh: "（集合、完成）", does: "從德語借來的前綴，常沒有獨立意思。", en: "a prefix from German, often without its own meaning", ex: "gemensam 共同的、gestalt 形狀"),
        "bi": .init(zh: "旁、副", does: "表示次要的、在旁邊的。", en: "by-, secondary", ex: "sak 事 → bisak 次要的事"),
        "all": .init(zh: "全、非常", does: "表示全部或非常。", en: "all-, very", ex: "makt 力量 → allmakt 全能"),
        "icke": .init(zh: "非", does: "表示不是、沒有。", en: "non-", ex: "rökare 吸菸者 → icke-rökare 不吸菸的人"),
        "anti": .init(zh: "反", does: "表示反對、對抗。", en: "anti-", ex: "kropp 身體 → antikropp 抗體"),
        "super": .init(zh: "超", does: "表示超過、非常。", en: "super-", ex: "makt 力量 → supermakt 超級大國"),
        "mini": .init(zh: "小、迷你", does: "表示很小。", en: "mini-", ex: "buss 巴士 → minibuss 小巴"),
        "multi": .init(zh: "多", does: "表示很多。", en: "multi-", ex: "kulturell 文化的 → multikulturell 多元文化的"),
        "inter": .init(zh: "之間、國際", does: "表示在…之間。", en: "inter-, between", ex: "nationell 國家的 → internationell 國際的"),
        "ex": .init(zh: "前、出", does: "表示以前的，或向外。", en: "ex-, former; out", ex: "man 丈夫 → exman 前夫"),
        "re": .init(zh: "再、回", does: "表示再一次或回來。", en: "re-, again", ex: "agera 行動 → reagera 反應"),
        "pre": .init(zh: "前", does: "表示之前。", en: "pre-, before", ex: "historisk 歷史的 → prehistorisk 史前的"),
        "post": .init(zh: "後", does: "表示之後。", en: "post-, after", ex: "modern 現代的 → postmodern 後現代的"),
        "sub": .init(zh: "下、次", does: "表示在下面、次一級。", en: "sub-, under", ex: "kultur 文化 → subkultur 次文化"),
        "trans": .init(zh: "跨、越過", does: "表示穿過、轉到另一邊。", en: "trans-, across", ex: "atlantisk 大西洋的 → transatlantisk 跨大西洋的"),
    ]

    static let suffixes: [String: SvAffix] = [
        "het": .init(zh: "…性、…度", does: "把形容詞變成名詞（en-詞）：那種性質、狀態。", en: "-ness, -ity: makes a noun of an adjective", ex: "fri 自由的 → frihet 自由"),
        "ning": .init(zh: "…的行為、結果", does: "把動詞變成名詞（en-詞）：那個動作或它的結果。", en: "-ing, -tion: makes a noun of a verb", ex: "öppna 打開 → öppning 開口"),
        "ing": .init(zh: "…的行為、結果", does: "把動詞變成名詞（en-詞）：那個動作或它的結果。", en: "-ing: makes a noun of a verb", ex: "parkera 停車 → parkering 停車場"),
        "are": .init(zh: "…的人、…器", does: "把動詞變成名詞（en-詞）：做這件事的人或工具。", en: "-er: the one who does it, or a tool", ex: "läsa 讀 → läsare 讀者"),
        "ande": .init(zh: "…的人；…中的", does: "動詞的現在分詞：正在做的（形容詞），或做這件事的人、這個動作（名詞）。", en: "-ing (present participle), or a noun of a verb", ex: "studera 讀書 → studerande 學生"),
        "ende": .init(zh: "…的人；…中的", does: "動詞的現在分詞（長母音結尾的動詞）：正在做的，或那個動作。", en: "-ing (present participle of verbs in a long vowel)", ex: "bo 住 → boende 住所、居民"),
        "lig": .init(zh: "…的、像…的", does: "把名詞或動詞變成形容詞。", en: "-ly, -ful: makes an adjective", ex: "vän 朋友 → vänlig 友善的"),
        "ig": .init(zh: "有…的、多…的", does: "把名詞變成形容詞：有那樣東西的。", en: "-y: makes an adjective of a noun", ex: "sol 太陽 → solig 晴朗的"),
        "isk": .init(zh: "…的、…式的", does: "把名詞變成形容詞：屬於、像那樣的。", en: "-ic, -ish: makes an adjective", ex: "Kina 中國 → kinesisk 中國的"),
        "bar": .init(zh: "可以…的", does: "把動詞變成形容詞：可以被那樣做的。", en: "-able: can be done", ex: "äta 吃 → ätbar 可以吃的"),
        "sam": .init(zh: "有…傾向的", does: "把動詞或名詞變成形容詞：常常那樣、有那種性質的。", en: "-some, -ful: tending to", ex: "arbeta 工作 → arbetsam 勤勞的"),
        "lös": .init(zh: "沒有…的、無…", does: "把名詞變成形容詞：沒有那樣東西的。", en: "-less: without", ex: "arbete 工作 → arbetslös 失業的"),
        "fri": .init(zh: "無…的、免…", does: "把名詞變成形容詞：沒有、不用…的。", en: "-free: without", ex: "alkohol 酒精 → alkoholfri 無酒精的"),
        "full": .init(zh: "充滿…的", does: "把名詞變成形容詞：有很多那樣東西的。", en: "-ful: full of", ex: "hopp 希望 → hoppfull 充滿希望的"),
        "aktig": .init(zh: "像…的、有點…", does: "把名詞或形容詞變成形容詞：像那樣的、帶一點那樣的。", en: "-ish, -like", ex: "barn 小孩 → barnaktig 幼稚的"),
        "mässig": .init(zh: "依…的、…方面的", does: "把名詞變成形容詞：按照、關於那樣東西的。", en: "according to, -wise", ex: "regel 規則 → regelmässig 有規律的"),
        "skap": .init(zh: "…關係、…身分、…感", does: "把名詞或形容詞變成名詞（ett-詞）：一種關係、狀態或群體。", en: "-ship: a relation, state or group", ex: "vän 朋友 → vänskap 友誼"),
        "dom": .init(zh: "…狀態、…時期", does: "把名詞或形容詞變成名詞（en-詞）：狀態、時期或領域。", en: "-dom, -hood", ex: "ung 年輕 → ungdom 青春、青年"),
        "else": .init(zh: "…的行為、結果", does: "把動詞變成名詞（en- 或 ett-詞）：動作或它的結果。", en: "makes a noun of a verb (the act or its result)", ex: "röra 動 → rörelse 運動"),
        "nad": .init(zh: "…的行為、結果", does: "把動詞變成名詞（en-詞）。", en: "makes a noun of a verb", ex: "bygga 建 → byggnad 建築"),
        "eri": .init(zh: "…店、…業、…行為", does: "把名詞或動詞變成名詞（ett-詞）：地方、行業或一種行為。", en: "-ery: a place, trade or activity", ex: "baka 烘焙 → bageri 麵包店"),
        "era": .init(zh: "（動詞）", does: "把外來的詞變成動詞（重音在 e 上）。", en: "makes a verb (often of words from other languages)", ex: "studie 研究 → studera 讀書"),
        "ering": .init(zh: "…的行為", does: "-era 動詞的名詞：那個動作。", en: "the noun of an -era verb", ex: "reparera 修理 → reparering 修理"),
        "tion": .init(zh: "…的行為、結果", does: "外來的名詞後綴（en-詞），常和 -era 動詞成對。", en: "-tion (from Latin)", ex: "informera 告知 → information 資訊"),
        "sion": .init(zh: "…的行為、結果", does: "外來的名詞後綴（en-詞）。", en: "-sion (from Latin)", ex: "diskutera 討論 → diskussion 討論"),
        "itet": .init(zh: "…性", does: "外來的名詞後綴（en-詞）：性質。", en: "-ity (from Latin)", ex: "aktiv 活躍的 → aktivitet 活動"),
        "ism": .init(zh: "…主義", does: "名詞後綴（en-詞）：思想、主義。", en: "-ism", ex: "social 社會的 → socialism 社會主義"),
        "ist": .init(zh: "…者、…家", does: "名詞後綴（en-詞）：做這件事或信這個主義的人。", en: "-ist: a person", ex: "gitarr 吉他 → gitarrist 吉他手"),
        "inna": .init(zh: "女…", does: "把指人的名詞變成女性的。", en: "-ess: a woman", ex: "lärare 老師 → lärarinna 女老師"),
        "ska": .init(zh: "女…；…語", does: "表示女性，或語言、學問。", en: "a woman; a language", ex: "sångare 歌手 → sångerska 女歌手"),
        "ör": .init(zh: "…者", does: "外來的名詞後綴（en-詞）：做這件事的人。", en: "-eur, -or: a person", ex: "regissera 導演 → regissör 導演"),
        "vis": .init(zh: "以…方式、按…", does: "把名詞或形容詞變成副詞：用那種方式、一個一個地。", en: "-wise, -ly: makes an adverb", ex: "steg 步 → stegvis 逐步地"),
    ]

    static let links: [String: SvAffix] = [
        "s": .init(zh: "（連接音）", does: "複合詞的兩個詞中間加的 -s-，本身沒有意思，只是把兩個詞接起來（前面的詞常已是複合詞，或以 -ing、-het、-tion 等結尾）。", en: "a linking -s- between the parts of a compound: no meaning of its own", ex: "arbete + plats → arbetsplats 工作地點"),
        "e": .init(zh: "（連接音）", does: "複合詞的兩個詞中間加的 -e-，本身沒有意思。", en: "a linking -e-: no meaning of its own", ex: "（較少見，多在舊詞裡）"),
        "a": .init(zh: "（連接音）", does: "複合詞的兩個詞中間加的 -a-，本身沒有意思（多是古老的用法）。", en: "a linking -a-: no meaning of its own", ex: "gäst + bud → gästabud 宴會"),
        "u": .init(zh: "（連接音）", does: "複合詞的兩個詞中間加的 -u-，本身沒有意思（前面的詞原來以 -a 結尾）。", en: "a linking -u-: no meaning of its own", ex: "gata + korsning → gatukorsning 十字路口"),
        "o": .init(zh: "（連接音）", does: "複合詞的兩個詞中間加的 -o-，本身沒有意思（前面的詞原來以 -a 結尾）。", en: "a linking -o-: no meaning of its own", ex: "kvinna + rörelse → kvinnorörelse 婦女運動"),
        "es": .init(zh: "（連接音）", does: "複合詞的兩個詞中間加的 -es-，本身沒有意思。", en: "a linking -es-: no meaning of its own", ex: "（很少見）"),
    ]

    static let endings: [String: SvAffix] = [
        "are": .init(zh: "更…（比較級）", does: "加在形容詞或副詞後面，變成比較級：比較兩個東西，「更…」。", en: "-er: the comparative of an adjective or adverb (more …)", ex: "sen 晚 → senare 更晚、後來；snar 不久 → snarare 寧可、倒不如"),
        "ast": .init(zh: "最…（最高級）", does: "加在形容詞或副詞後面，變成最高級：「最…」。", en: "-est: the superlative (most …)", ex: "sen 晚 → senast 最晚、最近；snabb 快 → snabbast 最快"),
        "aste": .init(zh: "最…（最高級，限定形）", does: "最高級的限定形，用在 den／det／de 或所有格後面。", en: "-est, the definite form (den snabbaste)", ex: "snabb 快 → den snabbaste 最快的"),
        "a": .init(zh: "（不定式）", does: "動詞的原形（不定式）詞尾。變化時換成別的詞尾：-ar（現在）、-ade（過去）、-at（完成）。", en: "the infinitive ending of a verb (-ar now, -ade past, -at perfect)", ex: "tal-a → talar 說、talade 說了"),
    ]

    static func of(_ m: SvMorpheme) -> SvAffix? {
        let t = m.text.lowercased()
        switch m.kind {
        case .prefix: return prefixes[t]
        case .suffix: return suffixes[t]
        case .link: return links[t]
        case .ending: return endings[t]
        case .root, .space: return nil
        }
    }
}

extension ZhDict {
    /// 瑞典語: the entries of a word (or one of its forms)
    func svEntries(_ word: String) -> [ZhEntry] { svIndices(word).map { entries[$0] } }

    /// 瑞典語: the other words with the same morpheme (the same root, or the same prefix or suffix), common ones first
    func svWords(with m: SvMorpheme, except k: String, limit: Int = 60) -> [ZhEntry] {
        var out: [ZhEntry] = []
        let t = m.text.lowercased(), w = m.word
        for e in entries where e.k != k {
            for o in SvMorpheme.parse(e.tw) where o.kind == m.kind {
                let same = m.kind == .root ? (o.word == w || o.text.lowercased() == t) : o.text.lowercased() == t
                if same { out.append(e); break }
            }
            if out.count >= limit { break }
        }
        return out
    }
}

// MARK: - the parts of a word, in the entry

/// 瑞典語 in an entry: the word in its parts (tap one to see what it means and does), its Chinese meanings and its
/// forms (the ending of each in colour)
struct SvWordExtras: View {
    let dict: ZhDict
    let entry: ZhEntry
    @EnvironmentObject var store: Store
    @State private var open: SvMorpheme?

    var body: some View {
        let ms = SvMorpheme.parse(dict.svSyl(entry))
        VStack(alignment: .leading, spacing: 12) {
            if !entry.svZh.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Chip(text: tr("中"), fill: T.rust, edge: T.rustEdge, ink: T.rustInk)
                    Text(entry.svZh.joined(separator: "、")).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
                    if entry.svZhGuessed { Text(tr("（由英文推測）")).ffFont(.caption).foregroundStyle(T.muted) }
                }
            }
            if ms.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("詞的組成（點一個看它的意思）")).ffFont(.caption, .semibold).foregroundStyle(T.muted)
                    FlowLayout(spacing: 6) {
                        ForEach(Array(ms.enumerated()), id: \.offset) { i, m in
                            if m.kind == .space {
                                // (a phrase: a gap between its words)
                                Color.clear.frame(width: 14, height: 1)
                            } else {
                                if i > 0 && ms[i - 1].kind != .space { Text("+").ffFont(.subheadline).foregroundStyle(T.muted) }
                                Button { open = m } label: { part(m, ms) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
            }
            if !entry.eq.isEmpty { forms(ms) }
        }
        .sheet(item: $open) { m in
            SvMorphemeSheet(dict: dict, entry: entry, m: m, all: ms).environmentObject(store)
        }
    }

    private func part(_ m: SvMorpheme, _ ms: [SvMorpheme]) -> some View {
        let c = SvColors.color(of: m, in: ms)
        return VStack(spacing: 2) {
            Text(m.text).latFont(20).fontWeight(.semibold).foregroundStyle(T.glyph)
            Text(trs(m.kindName)).ffFont(.caption2).foregroundStyle(T.muted)
            if let g = SvMorphemeSheet.gloss(dict, m) {
                Text(g).ffFont(.caption2).foregroundStyle(T.glyph.opacity(0.85)).lineLimit(1)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(c.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    /// the word's forms, the letters after the part they share with the word in the ending's colour
    private func forms(_ ms: [SvMorpheme]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Chip(text: tr("變化"), fill: T.blue, edge: T.blueEdge, ink: T.blueInk)
            FlowLayout(spacing: 6) {
                ForEach(entry.eq, id: \.self) { f in
                    Text(formText(f, ms)).latFont(16)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(T.fn.opacity(0.8)))
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// a form: the word's morphemes, then the rest (its ending) in colour
    func formText(_ f: String, _ ms: [SvMorpheme]) -> AttributedString {
        let fm = SvMorpheme.forForm(f, lemma: entry.h, ms)
        return SvColors.attributed(fm, base: T.glyph, colours: true)
    }
}

/// one morpheme: what it is, what it means and does, and the other words with it
struct SvMorphemeSheet: View {
    let dict: ZhDict
    let entry: ZhEntry
    let m: SvMorpheme
    let all: [SvMorpheme]
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss

    /// a short meaning for a part: a root's word's Chinese (or English), an affix's meaning
    static func gloss(_ dict: ZhDict, _ m: SvMorpheme) -> String? {
        if m.kind == .root { return dict.svWordGloss(m.word) }
        return SvAffixes.of(m)?.zh
    }

    var body: some View {
        let c = SvColors.color(of: m, in: all)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // the word with this part lit up
                    HStack(spacing: 0) {
                        ForEach(all) { o in
                            Text(o.text).latFont(30).fontWeight(o.id == m.id ? .bold : .regular)
                                .foregroundStyle(o.id == m.id ? T.glyph : T.muted.opacity(0.6))
                                .padding(.horizontal, 2)
                                .background(RoundedRectangle(cornerRadius: 6).fill(o.id == m.id ? c.opacity(0.5) : .clear))
                        }
                    }
                    HStack(spacing: 8) {
                        Text(m.kind == .root ? m.text : (m.kind == .prefix ? m.text + "-" : (m.kind == .link ? "-" + m.text + "-" : "-" + m.text)))
                            .latFont(24).fontWeight(.semibold).foregroundStyle(T.glyph)
                        Chip(text: trs(m.kindName), fill: c.opacity(0.5), edge: c, ink: T.glyph)
                    }
                    if m.kind == .root { root } else { affix }
                    others
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(T.bg.ignoresSafeArea())
            .navigationTitle(m.text)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
            .navigationDestination(for: ZhKey.self) { ZhEntryView(dict: dict, key: $0.k) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// a root: the word it comes from, with its meanings
    @ViewBuilder private var root: some View {
        let es = dict.svEntries(m.word).filter { $0.k != entry.k }
        Text(tr("詞根是詞的核心，帶著主要的意思；前綴、後綴和詞尾加在它前後，改變詞的意思或詞類。"))
            .ffFont(.subheadline).foregroundStyle(T.muted)
        if es.isEmpty {
            if let e = dict.svEntries(m.word).first { meaning(e) }
        } else {
            ForEach(es.prefix(3), id: \.k) { e in
                NavigationLink(value: ZhKey(k: e.k)) { meaning(e) }.buttonStyle(.plain)
            }
        }
    }

    private func meaning(_ e: ZhEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(dict.hanText(e.h, e.tw, base: T.glyph)).latFont(20).fontWeight(.semibold)
                if let p = e.pos.first { InfoChip.yellow(p) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").ffFont(.caption).foregroundStyle(T.muted)
            }
            if !e.svZh.isEmpty { Text(e.svZh.joined(separator: "、")).ffFont(.body).foregroundStyle(T.glyph) }
            if let en = e.en, !en.isEmpty { Text(en).ffFont(.subheadline).foregroundStyle(T.muted).lineLimit(3) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }

    /// a prefix, suffix, linking letter or ending: what it means and does
    @ViewBuilder private var affix: some View {
        if let a = SvAffixes.of(m) {
            VStack(alignment: .leading, spacing: 8) {
                row(tr("意思"), a.zh)
                row(tr("作用"), a.does)
                row(tr("英文"), a.en)
                row(tr("例子"), a.ex)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
        } else {
            Text(tr("這個部分沒有說明。")).ffFont(.subheadline).foregroundStyle(T.muted)
        }
    }

    private func row(_ name: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).ffFont(.caption, .semibold).foregroundStyle(T.muted).frame(width: 40, alignment: .leading)
            Text(text).ffFont(.body).foregroundStyle(T.glyph).textSelection(.enabled)
        }
    }

    /// other words with this part (not for linking letters and endings: almost every word has them)
    @ViewBuilder private var others: some View {
        if m.kind != .link && m.kind != .ending {
            let ws = dict.svWords(with: m, except: entry.k)
            if !ws.isEmpty {
                Text(m.kind == .root ? tr("有這個詞根的詞") : (m.kind == .prefix ? tr("有這個前綴的詞") : tr("有這個後綴的詞")))
                    .ffFont(.subheadline, .semibold).foregroundStyle(T.glyph)
                FlowLayout(spacing: 6) {
                    ForEach(ws, id: \.k) { e in
                        NavigationLink(value: ZhKey(k: e.k)) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(dict.hanText(e.h, e.tw, base: T.glyph)).latFont(16).fontWeight(.medium)
                                if let g = e.svZh.first ?? e.en?.components(separatedBy: ";").first {
                                    Text(g).ffFont(.caption2).foregroundStyle(T.muted).lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 9).fill(T.fn.opacity(0.8)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// 瑞典語: an example sentence (Folkets lexikon's) and its English: each word in its morphemes' colours (the form's
/// ending too: samtyck|lig|a); tap a word to open it
struct SvExampleBody: View {
    let dict: ZhDict
    let ex: ZhEx
    @EnvironmentObject var store: Store
    @State private var tapped: ZhKey?
    @AppStorage(ToneColors.key) private var toneSys = 0

    /// a word as it's written in the sentence: the punctuation around it, the word, and its entry
    private struct Word { let lead: String; let core: String; let tail: String; let key: String?; let ms: [SvMorpheme] }
    @State private var compound: SvWordRef?

    private func words() -> [Word] {
        ex.h.split(separator: " ").map { t in
            let s = String(t)
            let lead = String(s.prefix { !$0.isLetter && !$0.isNumber })
            let rest = s.dropFirst(lead.count)
            let tail = String(rest.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
            let core = String(rest.dropLast(tail.count))
            let key = core.isEmpty ? nil : dict.svKey(core)
            return Word(lead: lead, core: core, tail: tail, key: key, ms: core.isEmpty ? [] : dict.svMorphemes(ofWord: core))
        }
    }

    private func text(_ w: Word) -> AttributedString {
        var lead = AttributedString(w.lead); lead.swiftUI.foregroundColor = T.muted
        var tail = AttributedString(w.tail); tail.swiftUI.foregroundColor = T.muted
        var mid = AttributedString(w.core)
        if w.ms.isEmpty { mid.swiftUI.foregroundColor = T.glyph } else { mid = SvColors.attributed(w.ms, base: T.glyph, colours: toneSys != 0) }
        return lead + mid + tail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PlayButton(path: "tts:" + ex.h, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                FlowLayout(spacing: 5) {
                    ForEach(Array(words().enumerated()), id: \.offset) { _, w in
                        Text(text(w)).latFont(17)
                            .onTapGesture {
                                if let key = w.key { tapped = ZhKey(k: key) }
                                else if !w.ms.isEmpty { compound = SvWordRef(id: w.core) }
                            }
                    }
                }
                .toneGlow()
                if !ex.src.isEmpty { Text(ex.src).ffFont(.subheadline).foregroundStyle(T.muted).textSelection(.enabled) }
            }
        }
        .sheet(item: $tapped) { k in ZhEntrySheet(dict: dict, key: k.k).environmentObject(store) }
        .sheet(item: $compound) { w in SvCompoundSheet(dict: dict, word: w.id).environmentObject(store) }
    }
}

// MARK: - 轉換 (瑞典語)

/// 瑞典語 text pasted in: every word in its morphemes' colours (tap one to open it), the text with its words split
/// into morphemes (sam-tyck-lig-a), and the words in it with their meanings
struct SvConvertPane: View {
    let dict: ZhDict
    /// the 歌詞 window: no typing, only the coloured words (left) and the words split into morphemes (right)
    let lyrics: Bool
    @EnvironmentObject var store: Store
    @AppStorage private var text: String
    @AppStorage(ToneColors.key) private var toneSys = 0
    @State private var words: [Tok] = []
    @State private var copied: Int?
    @State private var tapped: ZhKey?
    @State private var compound: SvWordRef?
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    /// one word of the text: the punctuation around it, the word, its morphemes and entry; a line break before it
    struct Tok: Sendable {
        let lead: String, core: String, tail: String
        let ms: [SvMorpheme]
        let key: String?
        let newLine: Bool
        /// (a compound the dictionary doesn't have: its parts' entries)
        var parts: [String] = []
    }

    init(dict: ZhDict, textKey: String = "svConvText", lyrics: Bool = false) {
        self.dict = dict
        self.lyrics = lyrics
        _text = AppStorage(wrappedValue: "", textKey)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if lyrics {
                    if !words.isEmpty {
                        // (letters only: no glow here, it got slow)
                        LyricsColumns { coloured; split }.environment(\.noToneGlow, true)
                    }
                } else {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(tr("輸入或貼上瑞典文…")).foregroundStyle(T.muted).padding(.horizontal, 5).padding(.vertical, 8)
                    }
                    TextEditor(text: $text)
                        .scaledFont(18)
                        .focused($focused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: 6) {
                        Button {
                            if let s = UIPasteboard.general.string { text = s }
                        } label: { Image(systemName: "doc.on.clipboard") }
                        if !text.isEmpty {
                            Button { text = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel(tr("清除"))
                        }
                    }
                    .scaledFont(18)
                    .foregroundStyle(T.muted)
                    .padding(10)
                }
                if !words.isEmpty {
                    coloured
                    split
                    vocabulary
                    Text(tr("詞素是照詞典的詞推算的：變化過的詞，多出來的部分當作詞尾。詞典裡沒有的詞不上色。"))
                        .ffFont(.caption).foregroundStyle(T.muted)
                }
                }
            }
            .padding()
            .frame(maxWidth: lyrics ? 1100 : 760)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { run() }
        .onChange(of: text) { run() }
        .sheet(item: $tapped) { k in ZhEntrySheet(dict: dict, key: k.k).environmentObject(store) }
        .sheet(item: $compound) { w in SvCompoundSheet(dict: dict, word: w.id).environmentObject(store) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(tr("完成")) { focused = false }
            }
        }
    }

    private func box<C: View>(_ title: String, copy i: Int? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).ffFont(.caption, .bold).foregroundStyle(T.muted)
                Spacer()
                if i == 0 { PlayButton(path: "tts:" + text, size: 28) }
                if let i {
                    Button { UIPasteboard.general.string = plain(i); flash(i) } label: {
                        Image(systemName: copied == i ? "checkmark" : "doc.on.doc").foregroundStyle(T.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.55)))
    }

    /// a word as coloured text: its morphemes (with a hyphen between them when split), the punctuation in grey
    private func ink(_ w: Tok, hyphens: Bool) -> AttributedString {
        var out = AttributedString()
        var lead = AttributedString(w.lead); lead.swiftUI.foregroundColor = T.muted; out += lead
        if w.ms.isEmpty {
            var a = AttributedString(w.core); a.swiftUI.foregroundColor = T.glyph; out += a
        } else if hyphens {
            for (i, m) in w.ms.enumerated() {
                if i > 0 { var d = AttributedString("-"); d.swiftUI.foregroundColor = T.muted.opacity(0.7); out += d }
                var a = AttributedString(m.text)
                a.swiftUI.foregroundColor = toneSys != 0 && w.ms.count > 1 ? SvColors.color(of: m, in: w.ms) : T.glyph
                out += a
            }
        } else {
            out += SvColors.attributed(w.ms, base: T.glyph, colours: toneSys != 0)
        }
        var tail = AttributedString(w.tail); tail.swiftUI.foregroundColor = T.muted; out += tail
        return out
    }

    /// the text, each word in colour: tap a word to open it
    private var coloured: some View {
        box(trs("瑞典文"), copy: 0) {
            SwellWords(pieces: words.map { (ink($0, hyphens: false) + AttributedString(" "), $0.key != nil || !$0.parts.isEmpty, $0.newLine, 0) }, vPad: 3) { j in
                if let k = words[j].key { focused = false; tapped = ZhKey(k: k) }
                else if !words[j].parts.isEmpty { focused = false; compound = SvWordRef(id: words[j].core) }
            }
            .latFont(20)
            .toneGlow()
        }
    }

    /// the text with its words split into morphemes
    private var split: some View {
        box(trs("詞素"), copy: 1) {
            if lyrics {
                // (the 歌詞 window: these words swell and open too)
                SwellWords(pieces: words.map { (ink($0, hyphens: true) + AttributedString(" "), $0.key != nil || !$0.parts.isEmpty, $0.newLine, 0) }, vPad: 3) { j in
                    if let k = words[j].key { tapped = ZhKey(k: k) }
                    else if !words[j].parts.isEmpty { compound = SvWordRef(id: words[j].core) }
                }
                .latFont(17)
                .toneGlow()
            } else {
            Text(words.enumerated().reduce(into: AttributedString()) { out, p in
                if p.offset > 0 { out += AttributedString(p.element.newLine ? "\n" : " ") }
                out += ink(p.element, hyphens: true)
            })
            .latFont(17).toneGlow().textSelection(.enabled)
            }
        }
    }

    /// the words in the text (each once, in the order they come), with their meaning
    private var vocabulary: some View {
        var seen = Set<String>()
        let list = words.flatMap { w -> [(Tok, ZhEntry)] in
            ((w.key.map { [$0] }) ?? w.parts).compactMap { k -> (Tok, ZhEntry)? in
                guard seen.insert(k).inserted, let e = dict.entry(k) else { return nil }
                return (w, e)
            }
        }
        return box(trs("詞彙") + "（\(list.count)）") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, item in
                    let w = item.0
                    let e = item.1
                    Button { focused = false; tapped = ZhKey(k: e.k) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(dict.hanText(e.h, e.tw, base: T.glyph)).latFont(17).fontWeight(.semibold).toneGlow()
                            if w.core.lowercased() != e.h.lowercased() {
                                Text(w.core).latFont(13).foregroundStyle(T.muted)
                            }
                            Text(e.svZh.first ?? e.en?.components(separatedBy: ";").first ?? "")
                                .ffFont(.subheadline).foregroundStyle(T.glyph.opacity(0.85)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").ffFont(.caption).foregroundStyle(T.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func plain(_ i: Int) -> String {
        if i == 0 { return text }
        var out = ""
        for (n, w) in words.enumerated() {
            if n > 0 { out += w.newLine ? "\n" : " " }
            out += w.lead + (w.ms.isEmpty ? w.core : w.ms.map(\.text).joined(separator: "-")) + w.tail
        }
        return out
    }

    private func flash(_ m: Int) {
        copied = m
        Task { try? await Task.sleep(nanoseconds: 1_200_000_000); if copied == m { copied = nil } }
    }

    private func run() {
        task?.cancel()
        let t = text, d = dict
        task = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { () -> [Tok] in Self.tokens(t, d) }.value
            guard !Task.isCancelled else { return }
            words = r
        }
    }

    /// the words of the text, line by line
    nonisolated static func tokens(_ t: String, _ d: ZhDict) -> [Tok] {
        var out: [Tok] = []
        for (li, line) in t.components(separatedBy: "\n").enumerated() {
            var first = li > 0
            for piece in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                let s = String(piece)
                let lead = String(s.prefix { !$0.isLetter && !$0.isNumber })
                let rest = s.dropFirst(lead.count)
                let tail = String(rest.reversed().prefix { !$0.isLetter && !$0.isNumber }.reversed())
                let core = String(rest.dropLast(tail.count))
                let ms = core.isEmpty ? [] : d.svMorphemes(ofWord: core)
                let key = ms.isEmpty ? nil : d.svKey(core)
                let parts = key == nil && !ms.isEmpty ? (d.svEstimate(core)?.parts ?? []).compactMap { $0.entry.map { d.entries[$0].k } } : []
                out.append(Tok(lead: lead, core: core, tail: tail, ms: ms, key: key, newLine: first, parts: parts))
                first = false
            }
        }
        return out
    }
}

// MARK: - 瑞典語 compounds the dictionary doesn't have (varningsområdet = varning + s + område + t)

/// one part of a compound: a word of the dictionary (entry), or a linking letter between two
struct SvPart: Hashable, Sendable {
    let text: String
    let entry: Int?
    let link: Bool
}

/// a compound word to show (Identifiable for a sheet)
struct SvWordRef: Identifiable, Hashable { let id: String }

extension ZhDict {
    /// 瑞典語: a word the dictionary doesn't have, split into words it has: each part before another is a word
    /// (varning) or a word without its last -a / -e (flick|vän ← flicka), a linking letter (s, e, a, u, o) may come
    /// between two, and the last part is a word or one of its forms (området). The fewest parts win, then the fewest
    /// linking letters, then the longest first part. nil: no way to split it into two words or more
    func svCompound(_ word: String) -> [SvPart]? {
        let orig = Array(word)
        let low = Array(word.lowercased())
        let n = low.count
        guard n >= 6, n <= 40, low.count == orig.count, !low.contains(" ") else { return nil }
        func key(_ a: Int, _ b: Int) -> String { String(low[a..<b]) }
        func shown(_ a: Int, _ b: Int) -> String { String(orig[a..<b]) }
        func headword(_ s: String) -> Int? {
            svIndices(s).first { entries[$0].h.lowercased() == s && !entries[$0].h.contains(" ") }
        }
        func front(_ s: String) -> Int? { headword(s) ?? headword(s + "a") ?? headword(s + "e") }
        // (the endings are the rules' to work out: svEstimate)
        // (a form of a shorter word first: områden → område + n, though the dictionary also has områden itself)
        func last(_ s: String) -> Int? {
            if let b = svIndices(s).first(where: { let h = entries[$0].h.lowercased(); return h.count < s.count && s.hasPrefix(h) && !h.contains(" ") }) { return b }
            return headword(s) ?? svIndices(s).first { !entries[$0].h.contains(" ") }
        }
        func words(_ c: [SvPart]) -> Int { c.filter { !$0.link }.count }
        func links(_ c: [SvPart]) -> Int { c.filter(\.link).count }
        func better(_ c: [SvPart], than t: [SvPart]?) -> Bool {
            guard let t else { return true }
            if words(c) != words(t) { return words(c) < words(t) }
            if links(c) != links(t) { return links(c) < links(t) }
            return c[0].text.count > t[0].text.count
        }
        var memo: [Int: [SvPart]] = [:]
        var tried = Set<Int>()
        func best(_ i: Int) -> [SvPart]? {
            if tried.contains(i) { return memo[i] }
            tried.insert(i)
            var top: [SvPart]? = nil
            if n - i >= 3, let e = last(key(i, n)) { top = [SvPart(text: shown(i, n), entry: e, link: false)] }
            if n - i >= 6 {
                for j in stride(from: n - 3, through: i + 3, by: -1) {
                    guard let e = front(key(i, j)) else { continue }
                    let head = SvPart(text: shown(i, j), entry: e, link: false)
                    if let r = best(j) {
                        let c = [head] + r
                        if better(c, than: top) { top = c }
                    }
                    if j < n - 3, "seauo".contains(low[j]), let r = best(j + 1) {
                        let c = [head, SvPart(text: shown(j, j + 1), entry: nil, link: true)] + r
                        if better(c, than: top) { top = c }
                    }
                }
            }
            memo[i] = top
            return top
        }
        guard let r = best(0), words(r) >= 2 else { return nil }
        return r
    }

    /// 瑞典語: a form the dictionary doesn't list (bussarna, vännen): the word left when a usual ending is taken off
    /// (-arna, -en, -et, -er…; a doubled last letter as one: vänn → vän)
    func svInflected(_ s0: String) -> Int? {
        let s = s0.lowercased()
        func headword(_ w: String) -> Int? {
            svIndices(w).first { entries[$0].h.lowercased() == w && !entries[$0].h.contains(" ") }
        }
        for end in ["arnas", "ernas", "ornas", "arna", "erna", "orna", "ens", "ets", "en", "et", "na", "ar", "er", "or", "ade", "de", "te", "t", "n", "s"] {
            guard s.hasSuffix(end), s.count - end.count >= 2 else { continue }
            let st = String(s.dropLast(end.count))
            var tries = [st]
            if st.count > 2, let l = st.last, st.dropLast().last == l { tries.append(String(st.dropLast())) }
            if end == "n" { tries.append(st + "e") }
            for t in tries { if let i = headword(t) { return i } }
        }
        return nil
    }

    /// 瑞典語: the entry a word as written is (the word, one of its forms, or a form the dictionary doesn't list)
    func svKey(_ w: String) -> String? {
        if let e = svEntries(w).first { return e.k }
        return svInflected(w).map { entries[$0].k }
    }

    /// the morphemes of a compound's parts (each part's own, the last part's form ending after it)
    func svCompoundMorphemes(_ parts: [SvPart]) -> [SvMorpheme] {
        var out: [SvMorpheme] = []
        for p in parts {
            if p.link { out.append(SvMorpheme(id: 0, text: p.text, kind: .link)); continue }
            guard let i = p.entry else { continue }
            // (each word of a compound whole, varning|s|område|t: what each word is made of is in its own entry)
            let e = entries[i]
            out += SvMorpheme.forForm(p.text, lemma: e.h, []).map { m in var m = m; if m.kind == .root { m.lemma = e.h }; return m }
        }
        return SvMorpheme.renumbered(out)
    }

    /// a short meaning of an entry: its first Chinese one, else its first English one
    func svGloss(_ e: ZhEntry) -> String {
        e.svZh.first ?? e.en?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// 瑞典語: a word's morphemes ("text:kind" each): its own, or for a word the dictionary has without them
    /// (Arvsfonden), worked out by the rules (arvs|fond|en)
    func svSyl(_ e: ZhEntry) -> [String] {
        guard isSv, SvMorpheme.parse(e.tw).count <= 1, !e.h.contains(" ") else { return e.tw }
        let w = svWordSyl(e.h)
        return w.isEmpty ? e.tw : w
    }

    /// a word's short meaning: the first one of each entry it has (grund: 膚淺／基礎, the adjective and the noun)
    func svWordGloss(_ w: String) -> String? {
        let low = w.lowercased()
        var es = svEntries(low).filter { $0.h.lowercased() == low }
        if es.isEmpty { es = Array(svEntries(low).prefix(1)) }
        var gs: [String] = []
        for e in es { let g = svGloss(e); if !g.isEmpty && !gs.contains(g) { gs.append(g) } }
        return gs.isEmpty ? nil : gs.prefix(2).joined(separator: "／")
    }
}

// MARK: - 瑞典語 words the dictionary doesn't have, worked out by rules (omhändertagandet = omhänderta + -ande + -t)

/// a word class, for the rules: noun, verb, adjective, adverb; `any`: the dictionary doesn't say
enum SvCls: String, Sendable {
    case n, v, a, d, any
    static func of(_ pos: [String]) -> [SvCls] {
        var out: [SvCls] = []
        for p in pos {
            switch p {
            case "名詞", "專有名詞": out.append(.n)
            case "動詞": out.append(.v)
            case "形容詞", "序數詞": out.append(.a)
            case "副詞": out.append(.d)
            default: break
            }
        }
        return out.isEmpty ? [.any] : out
    }
    var name: String {
        switch self {
        case .n: return "名詞"
        case .v: return "動詞"
        case .a: return "形容詞"
        case .d: return "副詞"
        case .any: return ""
        }
    }
}

/// a suffix or ending the rules know: what it's added to, what the word is then, and what it does
struct SvRule: Sendable {
    let text: String
    let kind: SvMorpheme.Kind
    let from: [SvCls]
    let to: SvCls
    let zh: String
    let en: String
}

enum SvRules {
    private static func r(_ t: String, _ k: SvMorpheme.Kind, _ f: [SvCls], _ to: SvCls, _ zh: String, _ en: String) -> SvRule {
        SvRule(text: t, kind: k, from: f, to: to, zh: zh, en: en)
    }
    static let all: [SvRule] = [
        // nouns' endings
        r("arna", .ending, [.n], .n, "名詞複數的限定形（the …s）", "plural, definite (the …s)"),
        r("erna", .ending, [.n], .n, "名詞複數的限定形（the …s）", "plural, definite (the …s)"),
        r("orna", .ending, [.n], .n, "名詞複數的限定形（the …s）", "plural, definite (the …s)"),
        r("ar", .ending, [.n], .n, "名詞複數", "plural"),
        r("er", .ending, [.n], .n, "名詞複數", "plural"),
        r("or", .ending, [.n], .n, "名詞複數", "plural"),
        r("na", .ending, [.n], .n, "名詞複數的限定形", "plural, definite"),
        r("en", .ending, [.n], .n, "名詞單數的限定形（en-詞：the）", "singular, definite (en-word: the)"),
        r("et", .ending, [.n], .n, "名詞單數的限定形（ett-詞：the）", "singular, definite (ett-word: the)"),
        r("n", .ending, [.n], .n, "名詞的限定形（the）", "definite (the)"),
        r("t", .ending, [.n], .n, "名詞單數的限定形（ett-詞：the）", "singular, definite (ett-word: the)"),
        r("s", .ending, [.n], .n, "所有格（…的）", "genitive ('s)"),
        // adjectives' endings
        r("t", .ending, [.a], .a, "形容詞的中性（ett-詞）或副詞", "neuter (ett-word), or an adverb"),
        r("a", .ending, [.a], .a, "形容詞的複數或限定形", "plural or definite"),
        r("e", .ending, [.a], .a, "形容詞的限定形（男性）", "definite (masculine)"),
        r("are", .ending, [.a, .d], .a, "比較級（更…）", "comparative (more …)"),
        r("ast", .ending, [.a, .d], .a, "最高級（最…）", "superlative (most …)"),
        r("aste", .ending, [.a], .a, "最高級的限定形（最…的）", "superlative, definite"),
        // verbs' endings
        r("ar", .ending, [.v], .v, "動詞現在式", "present tense"),
        r("er", .ending, [.v], .v, "動詞現在式", "present tense"),
        r("r", .ending, [.v], .v, "動詞現在式", "present tense"),
        r("ade", .ending, [.v], .v, "動詞過去式", "past tense"),
        r("de", .ending, [.v], .v, "動詞過去式", "past tense"),
        r("te", .ending, [.v], .v, "動詞過去式", "past tense"),
        r("at", .ending, [.v], .v, "動詞完成式（har …at）", "supine (har …at)"),
        r("it", .ending, [.v], .v, "動詞完成式（har …it）", "supine (har …it)"),
        r("s", .ending, [.v], .v, "被動或相互（-s 動詞）", "passive or reciprocal (-s)"),
        r("ad", .ending, [.v], .a, "過去分詞（被…的）", "past participle"),
        r("en", .ending, [.v], .a, "過去分詞（被…的）", "past participle"),
        // suffixes that make another kind of word
        r("ande", .suffix, [.v], .n, "把動詞變成名詞：那個動作（…的行為）", "makes a noun of a verb: the act"),
        r("ende", .suffix, [.v], .n, "把動詞變成名詞：那個動作（…的行為）", "makes a noun of a verb: the act"),
        r("ning", .suffix, [.v], .n, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb: the act or its result"),
        r("ing", .suffix, [.v], .n, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb: the act or its result"),
        r("are", .suffix, [.v], .n, "把動詞變成名詞：做這件事的人或工具", "makes a noun of a verb: one who does it"),
        r("else", .suffix, [.v], .n, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb"),
        r("nad", .suffix, [.v], .n, "把動詞變成名詞：動作或它的結果", "makes a noun of a verb"),
        r("eri", .suffix, [.v, .n], .n, "名詞：地方、行業或一種行為", "a place, trade or activity"),
        r("bar", .suffix, [.v], .a, "把動詞變成形容詞：可以被…的", "makes an adjective of a verb: can be done"),
        r("sam", .suffix, [.v, .n], .a, "變成形容詞：有…傾向的", "makes an adjective: tending to"),
        r("het", .suffix, [.a], .n, "把形容詞變成名詞：…性、…度", "makes a noun of an adjective: -ness"),
        r("lig", .suffix, [.n, .v], .a, "變成形容詞：…的、像…的", "makes an adjective: -ly, -ful"),
        r("ig", .suffix, [.n], .a, "把名詞變成形容詞：有…的", "makes an adjective of a noun: -y"),
        r("isk", .suffix, [.n], .a, "把名詞變成形容詞：…的、…式的", "makes an adjective of a noun: -ic"),
        r("lös", .suffix, [.n], .a, "把名詞變成形容詞：沒有…的", "makes an adjective of a noun: -less"),
        r("fri", .suffix, [.n], .a, "把名詞變成形容詞：無…的", "makes an adjective of a noun: -free"),
        r("full", .suffix, [.n], .a, "把名詞變成形容詞：充滿…的", "makes an adjective of a noun: -ful"),
        r("aktig", .suffix, [.n, .a], .a, "變成形容詞：像…的、有點…", "makes an adjective: -ish"),
        r("mässig", .suffix, [.n], .a, "把名詞變成形容詞：依…的、…方面的", "makes an adjective of a noun: -wise"),
        r("skap", .suffix, [.n, .a], .n, "變成名詞：…關係、…身分", "makes a noun: -ship"),
        r("dom", .suffix, [.a, .n], .n, "變成名詞：…狀態、…時期", "makes a noun: -dom, -hood"),
        r("itet", .suffix, [.a], .n, "把形容詞變成名詞：…性", "makes a noun of an adjective: -ity"),
        r("ism", .suffix, [.a, .n], .n, "變成名詞：…主義", "makes a noun: -ism"),
        r("ist", .suffix, [.n], .n, "名詞：…者、…家", "a person: -ist"),
        r("inna", .suffix, [.n], .n, "名詞：女…", "a woman: -ess"),
        r("vis", .suffix, [.n, .a], .d, "變成副詞：以…方式、按…", "makes an adverb: -wise"),
        r("era", .suffix, [.n], .v, "把名詞變成動詞", "makes a verb of a noun"),
    ]
}

/// one step of working a word out: the suffix or ending added, what it does, and what the word is then
struct SvStep: Hashable, Sendable {
    let text: String
    let kind: SvMorpheme.Kind
    let zh: String
    let en: String
    let cls: SvCls
}

/// a word worked out: its base (one dictionary word, or a compound of several), what was added to it, and its
/// morphemes
struct SvEstimate: Sendable {
    var ms: [SvMorpheme]
    var cls: SvCls
    var parts: [SvPart]
    var steps: [SvStep]
    /// (how much is guessed: the fewer the better)
    var cost: Int
    /// (how many letters were added to or taken off a base: tal → tala)
    var adj: Int = 0
}

extension ZhDict {
    /// 瑞典語: a word the dictionary doesn't have, worked out from words it has and the rules: the base word
    /// (or a compound of words, or a prefix and a word), then the suffixes and endings each fitting the kind of word
    /// it's added to (-ande on a verb makes a noun, and a noun takes -t, -en, -ar…). nil: no way to
    func svEstimate(_ word: String, skipSelf: Bool = false) -> SvEstimate? {
        let w = word.lowercased()
        guard w.count >= 3, w.count <= 40, w.count == word.count, !w.contains(" ") else { return nil }
        var memo: [String: [SvEstimate]] = [:]

        func headwords(_ s: String) -> [Int] { svIndices(s).filter { !entries[$0].h.contains(" ") } }
        /// the word itself: a dictionary word or one of its forms, a compound of them, or a prefix and one
        func core(_ s: String, prefixOK: Bool = true) -> [SvEstimate] {
            var out: [SvEstimate] = []
            // (skipSelf: the word is in the dictionary but without its parts, Arvsfonden: worked out all the same)
            for i in (skipSelf && s == w ? [] : headwords(s)) {
                let e = entries[i]
                let ms = SvMorpheme.forForm(s, lemma: e.h, SvMorpheme.parse(e.tw))
                for c in SvCls.of(e.pos) {
                    out.append(SvEstimate(ms: ms, cls: c, parts: [SvPart(text: s, entry: i, link: false)], steps: [], cost: c == .any ? 1 : 0))
                }
            }
            if !out.isEmpty { return out }
            if let p = svCompound(s) {
                let ms = svCompoundMorphemes(p)
                let cls = p.last?.entry.map { SvCls.of(entries[$0].pos) } ?? [.any]
                let joins = p.filter { !$0.link }.count - 1
                return cls.map { c in SvEstimate(ms: ms, cls: c, parts: p, steps: [], cost: 3 * joins) }
            }
            if prefixOK {
                for (pre, a) in SvAffixes.prefixes.sorted(by: { $0.key.count > $1.key.count }) where s.hasPrefix(pre) && s.count - pre.count >= 3 {
                    let rest = String(s.dropFirst(pre.count))
                    for r in core(rest, prefixOK: false) {
                        var x = r
                        x.ms = SvMorpheme.renumbered([SvMorpheme(id: 0, text: pre, kind: .prefix)] + r.ms)
                        x.steps = [SvStep(text: pre, kind: .prefix, zh: "前綴：" + a.zh, en: a.en, cls: r.cls)] + r.steps
                        x.cost += 2
                        out.append(x)
                    }
                    if !out.isEmpty { break }
                }
            }
            return out
        }

        /// the morphemes of `b` (worked out) for the letters of `base` (the rules' base may be the word with an -a
        /// more, tal → tala, or without the -g of tag → ta: those letters stay with the root)
        func onto(_ base: String, _ b: String, _ ms: [SvMorpheme]) -> [SvMorpheme] {
            guard b != base else { return ms }
            var out = SvMorpheme.forForm(base, lemma: b, ms)
            if out.count >= 2, let l = out.last, l.kind == .ending, l.text.count == 1, out[out.count - 2].kind == .root {
                out[out.count - 2].text += l.text
                out.removeLast()
            }
            return out
        }

        func better(_ x: SvEstimate, _ y: SvEstimate) -> Bool {
            if x.cost != y.cost { return x.cost < y.cost }
            if x.adj != y.adj { return x.adj < y.adj }
            return x.ms.count < y.ms.count
        }

        func analyze(_ s: String) -> [SvEstimate] {
            if let m = memo[s] { return m }
            memo[s] = []
            var best: [SvCls: SvEstimate] = [:]
            func keep(_ x: SvEstimate) { if let o = best[x.cls], !better(x, o) { return }; best[x.cls] = x }
            for x in core(s) { keep(x) }
            for rule in SvRules.all where s.hasSuffix(rule.text) && s.count - rule.text.count >= 2 {
                let base = String(s.dropLast(rule.text.count))
                var cands = [base]
                if rule.from.contains(.v) || rule.from.contains(.n) { cands.append(base + "a") }
                if rule.from.contains(.n) { cands.append(base + "e") }
                if rule.from.contains(.v), let l = base.last, l == "g" || l == "d", base.count > 2 { cands.append(String(base.dropLast())) }
                // (vänn|en → vän: a doubled last letter as one)
                if base.count > 3, let l = base.last, base.dropLast().last == l, !"aeiouyåäö".contains(l) { cands.append(String(base.dropLast())) }
                for b in cands {
                    for r in analyze(b) where rule.from.contains(r.cls) || r.cls == .any {
                        var x = r
                        x.ms = SvMorpheme.renumbered(onto(base, b, r.ms) + [SvMorpheme(id: 0, text: rule.text, kind: rule.kind)])
                        x.steps = r.steps + [SvStep(text: rule.text, kind: rule.kind, zh: rule.zh, en: rule.en, cls: rule.to)]
                        x.cls = rule.to
                        x.cost = r.cost + 1 + (r.cls == .any ? 1 : 0)
                        x.adj = r.adj + (b == base ? 0 : 1)
                        keep(x)
                    }
                }
            }
            let out = Array(best.values).sorted { better($0, $1) }
            memo[s] = out
            return out
        }

        guard var top = analyze(w).first, !top.steps.isEmpty || top.parts.count > 1 else { return nil }
        // (in the letters as written: Omhändertagandet)
        let orig = Array(word)
        var at = 0
        top.ms = top.ms.map { m in
            var m = m
            let n = m.text.count
            if at + n <= orig.count { m.text = String(orig[at..<(at + n)]) }
            at += n
            return m
        }
        return top
    }
}

/// a word the dictionary doesn't have, worked out: the word in colour, split into morphemes, what it's made of
/// (each word opens its entry) and each step (-ande: makes a noun of a verb…)
struct SvCompoundBlock: View {
    let dict: ZhDict
    let word: String
    let est: SvEstimate
    @AppStorage(ToneColors.key) private var toneSys = 0

    var body: some View {
        let ms = est.ms
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SvColors.attributed(ms, base: T.glyph, colours: toneSys != 0)).latFont(26).fontWeight(.semibold).toneGlow()
                if est.cls != .any { InfoChip.yellow(trs(est.cls.name)) }
            }
            Text(ms.enumerated().reduce(into: AttributedString()) { out, p in
                if p.offset > 0 { var d = AttributedString("-"); d.swiftUI.foregroundColor = T.muted.opacity(0.7); out += d }
                var a = AttributedString(p.element.text)
                a.swiftUI.foregroundColor = toneSys != 0 ? SvColors.color(of: p.element, in: ms) : T.greenInk
                out += a
            }).latFont(17).toneGlow()
            // the words it's made of: varning（警告）＋ område（區域）
            Text(est.parts.compactMap { p -> String? in
                guard !p.link, let i = p.entry else { return nil }
                let g = dict.svGloss(dict.entries[i])
                return dict.entries[i].h + (g.isEmpty ? "" : "（" + g + "）")
            }.joined(separator: " ＋ "))
            .ffFont(.subheadline).foregroundStyle(T.glyph.opacity(0.9))
            ForEach(Array(est.parts.enumerated()), id: \.offset) { _, p in
                if p.link {
                    HStack(spacing: 8) {
                        Text("-" + p.text + "-").latFont(16).foregroundStyle(SvColors.color(4))
                        Text(tr("連接音：把兩個詞接起來，沒有意思")).ffFont(.caption).foregroundStyle(T.muted)
                    }
                } else if let i = p.entry {
                    let e = dict.entries[i]
                    NavigationLink(value: ZhKey(k: e.k)) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(dict.hanText(e.h, e.tw, base: T.glyph)).latFont(18).fontWeight(.semibold).toneGlow()
                            if p.text.lowercased() != e.h.lowercased() { Text(p.text).latFont(13).foregroundStyle(T.muted) }
                            if let pos = e.pos.first { InfoChip.yellow(pos) }
                            Text(dict.svGloss(e)).ffFont(.subheadline).foregroundStyle(T.glyph.opacity(0.85)).lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").ffFont(.caption).foregroundStyle(T.muted)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(T.fn.opacity(0.8)))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
            // each prefix, suffix and ending added, what it does, and what the word is then
            if !est.steps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(est.steps.enumerated()), id: \.offset) { _, st in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(st.kind == .prefix ? st.text + "-" : "-" + st.text).latFont(16).fontWeight(.semibold)
                                .foregroundStyle(SvColors.color(st.kind == .prefix ? 2 : (st.kind == .suffix ? 3 : 5)))
                                .frame(minWidth: 52, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(UILang.english ? st.en : st.zh).ffFont(.subheadline).foregroundStyle(T.glyph)
                                if st.cls != .any && st.kind != .prefix {
                                    Text(tr("→ ") + trs(st.cls.name)).ffFont(.caption).foregroundStyle(T.muted)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(T.fn.opacity(0.5)))
            }
            Text(tr("這個詞詞典裡沒有：照詞典裡的詞和構詞規則推算，可能有誤。"))
                .ffFont(.caption).foregroundStyle(T.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// a worked-out word in a sheet (tapped in a sentence or in 轉換)
struct SvCompoundSheet: View {
    let dict: ZhDict
    let word: String
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                if let est = dict.svEstimate(word) {
                    SvCompoundBlock(dict: dict, word: word, est: est).padding()
                }
            }
            .background(T.bg.ignoresSafeArea())
            .navigationTitle(word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } } }
            .navigationDestination(for: ZhKey.self) { ZhEntryView(dict: dict, key: $0.k) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// 瑞典語: 華語 meanings guessed from the English ones (CC-CEDICT the other way round, marked ≈ in sv.json) for words
/// without Chinese ones: shown or not (設定 → 瑞典語)
enum SvGuess {
    static let key = "svGuessZh"
    static var on: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

extension ZhEntry {
    /// 瑞典語: the Chinese meanings (the guessed ones only when 設定 says)
    var svZh: [String] {
        let g = SvGuess.on
        return jp.compactMap { $0.hasPrefix("≈") ? (g ? String($0.dropFirst()) : nil) : $0 }
    }
    /// (they're guessed from the English)
    var svZhGuessed: Bool { SvGuess.on && (jp.first?.hasPrefix("≈") ?? false) }
}

/// 瑞典語: the words the last search found through the English of a 華語 word (their entries say so)
struct SvVia {
    let zh: String
    let en: String
    nonisolated(unsafe) static var found: [String: SvVia] = [:]
}
