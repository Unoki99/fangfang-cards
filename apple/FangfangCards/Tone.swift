import SwiftUI

// 聲調顏色: with the 聲調 button on, every syllable (漢字, 羅馬字, 方音) is coloured by the tone it is
// actually said in, after tone sandhi.
//
// Every syllable takes its sandhi tone, except:
//  - the last syllable before punctuation or at the end (the end of a tone group)
//  - the last syllable of a noun (名詞, from the word's main meaning)
//  - the last syllable of a 時間詞
//  - the last syllable of a verb that ends with a noun (食飯: 飯 is a noun)
//  - the syllable before "--"
// Before 仔 a syllable takes its own change: 2, 3 → 1; 1, 5, 7, 8 and 4 ending in h → 7; 4 ending in p/t/k → 8
// (this wins over the "keeps its tone" cases above, but not over "--").
// A syllable joined to the next one with a single "-" always changes (女權 lù-khuán), and a word listed as
// both 名詞 and 量詞 right after a 數詞 or 代詞 is a 量詞 there (it changes too).
// Syllables after "--" are said in the light tone: grey.
// Sandhi follows the 腔口: 通行 and the 漳 / 混合 places 2→1, 5→7, 8→4 (8 ending in h → 3); the 泉 places 2→5, 5→3, 8→3.
// Tone 6 (鹿港 and other places that keep it) → 3.

enum ToneColors {
    static let key = "toneColors"
    /// 0 = off, 7 = 七聲, 5 = 五聲
    static var system: Int { UserDefaults.standard.integer(forKey: key) }
    static let marksKey = "toneMarksSandhi"
    /// the tone marks show the tone after sandhi too (tsia̍h-pn̄g → tsià-pn̄g)
    static var marks: Bool { UserDefaults.standard.object(forKey: marksKey) as? Bool ?? false }

    static let red = Color(hex: 0xff6b6b), purple = Color(hex: 0xc39bff), blue = Color(hex: 0x6eaaff)
    static let orange = Color(hex: 0xffa94d), green = Color(hex: 0x6fdc7f), yellow = Color(hex: 0xffe066)
    static let pink = Color(hex: 0xff8cc6), light = Color(hex: 0x8e8e93)
    /// tone 6 (鹿港 and other places that keep it): teal, the one hue the other tones don't use
    static let teal = Color(hex: 0x4fd8c4)

    /// the colour of a realized tone (0 = light tone); nil = leave the text colour as it is.
    /// The colours are the ones picked in 設定 → 顏色與外觀 → 選聲調顏色 (the standard ones until then).
    static func color(_ t: Int, _ sys: Int) -> Color? {
        if t == 0 { return twColor(0) }
        if sys == 5 {
            switch t {
            case 1, 8: return twColor(1)
            case 3, 4: return twColor(3)
            case 2, 5, 6, 7: return twColor(t)
            default: return nil
            }
        }
        return (1...8).contains(t) ? twColor(t) : nil
    }

    // MARK: colours you pick

    /// the tones that can have a colour of their own: 台語 1–8 and the light tone (0); 華語 1–4 and 輕聲 (0)
    static let twTones = [1, 2, 3, 4, 5, 6, 7, 8, 0]
    static let zhTones = [1, 2, 3, 4, 0]
    static let twStandard: [Int: UInt32] = [1: 0xff6b6b, 2: 0xc39bff, 3: 0x6eaaff, 4: 0xffa94d, 5: 0x6fdc7f,
                                            6: 0x4fd8c4, 7: 0xffe066, 8: 0xff8cc6, 0: 0x8e8e93]
    /// 華語: 1 red, 2 green (like 台語 5), 3 blue, 4 purple (like 台語 2), 輕聲 grey
    static let zhStandard: [Int: UInt32] = [1: 0xff6b6b, 2: 0x6fdc7f, 3: 0x6eaaff, 4: 0xc39bff, 0: 0x8e8e93]
    /// 粵語 1–6: 1 high level red, 2 high rising green, 3 mid level yellow, 4 low falling blue, 5 low rising
    /// purple, 6 low level teal
    static let yueTones = [1, 2, 3, 4, 5, 6]
    static let yueStandard: [Int: UInt32] = [1: 0xff6b6b, 2: 0x6fdc7f, 3: 0xffe066, 4: 0x6eaaff, 5: 0xc39bff, 6: 0x4fd8c4]
    /// 客語's tone categories (陰平 1, 上聲 2, 去聲 / 陰去 3, 陰入 4, 陽平 5, 陽去 7, 陽入 8), to start with in
    /// 台語's colours for the same categories
    static let hakTones = [1, 2, 3, 4, 5, 7, 8]
    static let hakStandard: [Int: UInt32] = [1: 0xff6b6b, 2: 0xc39bff, 3: 0x6eaaff, 4: 0xffa94d, 5: 0x6fdc7f, 7: 0xffe066, 8: 0xff8cc6]
    /// 四川話 (華語 with 讀音 = 四川話): 1 high level red, 2 low falling teal, 3 high falling purple, 4 low dipping
    /// blue, 5 (入聲, where it's kept) like 2
    static func scColor(_ t: Int) -> Color? {
        switch t {
        case 1: return red
        case 2, 5: return teal
        case 3: return purple
        case 4: return blue
        default: return nil
        }
    }

    /// the tones of a set of colours: 0 台語, 1 華語, 2 粵語, 3 客語
    static func tones(set: Int) -> [Int] { [twTones, zhTones, yueTones, hakTones][set >= 0 && set <= 3 ? set : 0] }

    /// the balls to pick from: one column per colour, in rainbow order, light at the top and dark at the bottom
    /// (the middle row is the standard colour)
    static let palette: [(name: String, shades: [UInt32])] = [
        ("粉紅", [0xffcbe5, 0xffacd6, 0xff8cc6, 0xc76d9a, 0x945173]),
        ("紅", [0xffbcbc, 0xff9494, 0xff6b6b, 0xc75353, 0x943e3e]),
        ("橘", [0xffd8af, 0xffc17f, 0xffa94d, 0xc7843c, 0x94622d]),
        ("黃", [0xfff1ba, 0xffe991, 0xffe066, 0xc7af50, 0x94823b]),
        ("綠", [0xbeefc5, 0x97e6a3, 0x6fdc7f, 0x57ac63, 0x40804a]),
        ("青", [0xb0ede4, 0x80e3d5, 0x4fd8c4, 0x3ea899, 0x2e7d72]),
        ("藍", [0xbed9ff, 0x97c2ff, 0x6eaaff, 0x5685c7, 0x406394]),
        ("紫", [0xe4d2ff, 0xd4b7ff, 0xc39bff, 0x9879c7, 0x715a94]),
        ("灰", [0xd1d1d6, 0xaeaeb2, 0x8e8e93, 0x636366, 0x48484a]),
    ]

    private static func storeKey(_ set: Int, _ t: Int) -> String { "toneColor." + ["tw.", "zh.", "yue.", "hak."][set >= 0 && set <= 3 ? set : 0] + String(t) }

    /// the colour picked for a tone (as hex); set 0 台語, 1 華語, 2 粵語, 3 客語
    static func hex(set: Int, _ t: Int) -> UInt32 {
        let std = [twStandard, zhStandard, yueStandard, hakStandard][set >= 0 && set <= 3 ? set : 0][t] ?? 0x8e8e93
        guard let v = UserDefaults.standard.object(forKey: storeKey(set, t)) as? Int else { return std }
        return UInt32(truncatingIfNeeded: v)
    }
    static func hex(zh: Bool, _ t: Int) -> UInt32 { hex(set: zh ? 1 : 0, t) }

    // read once (the colours are used for every syllable), made again when one is picked
    private static let lock = NSLock()
    nonisolated(unsafe) private static var caches: [Int: [Int: Color]] = [:]

    private static func table(_ set: Int) -> [Int: Color] {
        lock.lock(); defer { lock.unlock() }
        if let c = caches[set] { return c }
        var t: [Int: Color] = [:]
        for tone in tones(set: set) { t[tone] = Color(hex: hex(set: set, tone)) }
        caches[set] = t
        return t
    }

    static func twColor(_ t: Int) -> Color? { table(0)[t] }
    static func zhColor(_ t: Int) -> Color? { table(1)[t] }
    static func yueColor(_ t: Int) -> Color? { table(2)[t] }
    static func hakColor(_ t: Int) -> Color? { hakAccentColor(Lang.hakAccent, t, seven: system != 5) }

    /// 客語: each accent's tones by how they sound (調值, 教育部《臺灣客語辭典》's 聲調符號表): accent → category → pitch
    static let hakPitch: [[Int: String]] = [
        [1: "24", 5: "11", 2: "31", 3: "55", 4: "2", 8: "5"],                  // 四縣
        [1: "53", 5: "55", 2: "24", 3: "11", 7: "33", 4: "5", 8: "2"],         // 海陸
        [1: "35", 5: "113", 2: "31", 3: "53", 4: "21", 8: "54"],               // 大埔 (陰平 also 33)
        [1: "11", 5: "55", 2: "53", 7: "24", 4: "2", 8: "5"],                  // 饒平
        [1: "11", 2: "31", 4: "24", 5: "53", 7: "55", 8: "43"],                // 詔安
        [1: "24", 5: "11", 2: "31", 3: "55", 4: "2", 8: "5"],                  // 南四縣 (陰平 also 33)
    ]
    /// a 客語 tone's colour in an accent: the same pitch is the same colour in every accent (24/35 green, 11/113 blue,
    /// 31 teal, 55 red, 53 purple, 33 yellow). 入聲 (4, 8): in 七聲 their own colours (low orange, high pink), in 五聲
    /// the colour of the long tone they sound like (2/21 blue, 5/54 red, 24 green, 43 purple)
    static func hakAccentColor(_ accent: Int, _ cat: Int, seven: Bool) -> Color? {
        guard accent >= 0, accent < hakPitch.count, let p = hakPitch[accent][cat] else { return nil }
        return hakPitchColor(p, short: cat == 4 || cat == 8, seven: seven)
    }
    /// the colour of a pitch (short: an 入聲 syllable, ending in b, d, g)
    static func hakPitchColor(_ p: String, short: Bool, seven: Bool) -> Color? {
        if short {
            let low = ["2", "21", "24", "3"].contains(p)
            if seven { return low ? orange : pink }
            switch p {
            case "2", "21": return blue
            case "24": return green
            case "3": return yellow
            case "43": return purple
            default: return red
            }
        }
        switch p {
        case "24", "35": return green
        case "11", "113": return blue
        case "31": return teal
        case "55": return red
        case "53": return purple
        case "33": return yellow
        default: return nil
        }
    }

    /// picks a colour for a tone (nil = back to the standard one); everything is drawn again
    @MainActor static func set(set: Int, _ t: Int, _ v: UInt32?) {
        if let v { UserDefaults.standard.set(Int(v), forKey: storeKey(set, t)) }
        else { UserDefaults.standard.removeObject(forKey: storeKey(set, t)) }
        changed()
    }

    @MainActor static func resetAll(set: Int) {
        for t in tones(set: set) { UserDefaults.standard.removeObject(forKey: storeKey(set, t)) }
        changed()
    }

    @MainActor private static func changed() {
        lock.lock(); caches = [:]; lock.unlock()
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: versionKey) + 1, forKey: versionKey)
        Store.shared.objectWillChange.send()
        WidgetBridge.rebuildIfNeeded(Store.shared)
    }

    /// changes every time a colour is picked (pages that show tone colours redraw)
    static let versionKey = "toneColorVersion"
    /// all the picked colours, for knowing when the widgets' words must be made again
    static var signature: String {
        (0...3).flatMap { set in tones(set: set).map { String(hex(set: set, $0), radix: 16) } }.joined(separator: ",")
    }
}

/// one syllable while working out the tones of a stretch of text
struct ToneUnit {
    var code: String
    var light = false          // after "--": light tone
    var beforeLight = false    // right before "--": keeps its tone
    var keep = false           // last syllable of a noun / 時間詞 / verb ending in a noun: keeps its tone
    var phraseEnd = false      // before punctuation or at the end: keeps its tone
    var beforeA = false        // right before 仔: 仔-sandhi
}

extension Dict {
    /// the tone written in a syllable code, and whether a checked syllable ends in h (not p / t / k)
    func toneOf(_ code: String) -> (tone: Int, h: Bool) {
        guard let last = code.last, let t = last.wholeNumberValue else { return (0, false) }
        let body = code.dropLast()
        let hasVowel = body.contains { "iuaoøeIUɨəɵ".contains($0) }
        let stop = hasVowel && (body.last.map { "BDG".contains($0) } ?? false)
        return (t, !stop)
    }

    /// the syllable written in the tone it's said in (when that spelling exists)
    func sandhiCode(_ code: String, _ tone: Int) -> String {
        let (t, h) = toneOf(code)
        guard tone > 0, t != tone else { return code }
        // a syllable ending in p / t / k can only be written in tone 4 or 8 (ām would be a different syllable)
        if (t == 4 || t == 8) && !h && !(tone == 4 || tone == 8) { return code }
        let n = String(code.dropLast()) + String(tone)
        return isCode(n) ? n : code
    }

    /// 泉-leaning places use 5→3 and 8→3
    func quanSandhi(_ place: Int) -> Bool { place >= 0 && place < raw.places.count && raw.places[place].contains("泉") }

    /// the tone a syllable is said in when it changes (tone sandhi)
    func sandhiTone(_ code: String, _ place: Int) -> Int {
        let (t, h) = toneOf(code)
        let quan = quanSandhi(place)
        switch t {
        case 1: return 7
        case 2: return quan ? 5 : 1
        case 3: return 2
        case 5: return quan ? 3 : 7
        case 7, 6: return 3
        case 4: return h ? 2 : 8
        case 8: return h ? 3 : (quan ? 3 : 4)
        default: return t
        }
    }

    /// the tone a syllable is said in right before 仔
    func aSandhiTone(_ code: String) -> Int {
        let (t, h) = toneOf(code)
        switch t {
        case 2, 3: return 1
        case 1, 5, 6, 7, 8: return 7
        case 4: return h ? 7 : 8
        default: return t
        }
    }

    /// realized tone of each syllable (0 = light tone)
    func realizedTones(_ units: [ToneUnit], _ place: Int) -> [Int] {
        units.map { u in
            if u.light { return 0 }
            if u.beforeA && !u.beforeLight { return aSandhiTone(u.code) }
            if u.keep || u.phraseEnd || u.beforeLight { return toneOf(u.code).tone }
            return sandhiTone(u.code, place)
        }
    }

    /// a word used as a 量詞 here, so its tone changes:
    /// - listed as both 名詞 and 量詞, right after a 數詞 or 代詞 (一隻, 這擺);
    /// - a one-syllable 名詞 between a 代詞 and another 名詞 (這款種: 款 is a 量詞 here, even though the
    ///   dictionary only lists it as a 名詞)
    func classifierHere(_ key: String?, after prev: String?, before next: String? = nil) -> Bool {
        guard let key, let pos = raw.pos[key], pos.contains("名詞"),
              let prev, let pp = raw.pos[prev] else { return false }
        if pos.contains("量詞") && (pp.contains("數詞") || pp.contains("代詞")) { return true }
        if pp.contains("代詞"), Dict.codesOf(key).split(separator: " ").count == 1,
           let next, let np = raw.pos[next], np.contains("名詞") { return true }
        return false
    }

    /// nouns, 時間詞 and verbs ending in a noun keep the tone of their last syllable
    /// (`after` = the word before it, to tell a 量詞 from a 名詞)
    /// `sense` = the word class it has here, when that's known (an example sentence listed under one of the
    /// word's own meanings uses that meaning's class)
    func keepsLastTone(_ key: String?, after prev: String? = nil, before next: String? = nil, sense: String? = nil) -> Bool {
        guard let key, let pos = raw.pos[key] else { return false }
        if classifierHere(key, after: prev, before: next) { return false }
        var main = pos.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        if let sense, !sense.isEmpty {
            main = sense
        } else {
            if pos.contains("時間詞") { return true }
            // a one-syllable word that is both a 名詞 and a 動詞 (相): a 名詞 after 這 / 彼 / 一 / a number /
            // a 量詞 (這相, 一張相); otherwise a 動詞 (相厝宅, 相機會), which changes its tone
            if main.contains("名詞"), pos.contains("動詞"), !Dict.codesOf(key).contains(" ") {
                let pp = prev.flatMap { raw.pos[$0] } ?? ""
                let nounHere = pp.contains("代詞") || pp.contains("數詞") || pp.contains("量詞")
                if !nounHere { main = "動詞" }
            }
        }
        if main.contains("時間詞") { return true }
        if main.contains("名詞") { return true }
        if main.contains("動詞"), !Dict.notVerbWithNoun.contains(key) {
            let hs = Array(Dict.hanOf(key)), cs = Dict.codesOf(key).split(separator: " ").map(String.init)
            guard hs.count == cs.count, hs.count > 1 else { return false }
            for L in 1..<hs.count {
                let k = String(hs.suffix(L)) + "\t" + cs.suffix(L).joined(separator: " ")
                if let p = raw.pos[k], baseKeys.contains(k),
                   (p.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? "").contains("名詞") { return true }
            }
        }
        return false
    }

    /// a word's syllables as tone units, from its tokens ("--" marks the light tone)
    func toneUnits(tokens: [String], key: String?, after prev: String? = nil, before next: String? = nil) -> [ToneUnit] {
        var out: [ToneUnit] = []
        var lightNext = false
        for t in tokens {
            let c = t.hasPrefix("^") ? String(t.dropFirst()) : t
            if isCode(c) {
                out.append(ToneUnit(code: c, light: lightNext))
                // a light tone goes on through the syllables joined to it ("tshut--khì-lâi")
            } else if t == "--" {
                if !out.isEmpty { out[out.count - 1].beforeLight = true }
                lightNext = true
            } else if t == "_" {
                lightNext = false
            }
        }
        if keepsLastTone(key, after: prev, before: next), !out.isEmpty { out[out.count - 1].keep = true }
        // 仔 inside the word
        if let key {
            let hs = Array(Dict.hanOf(key))
            if hs.count == out.count { for i in out.indices.dropLast() where hs[i + 1] == "仔" { out[i].beforeA = true } }
        }
        return out
    }

    /// a word on its own (headword, card, list): its last syllable ends the phrase
    func wordTones(_ key: String, _ place: Int) -> [Int] {
        var u = toneUnits(tokens: tokensFor(key, place), key: key)
        if !u.isEmpty { u[u.count - 1].phraseEnd = true }
        return realizedTones(u, place)
    }

    /// a reading drawn syllable by syllable in its tone colours (same text as render)
    func toneText(_ tokens: [String], _ sys: Int, _ place: Int, tones: [Int], system: Int) -> AttributedString {
        var out = AttributedString()
        var prevCode = false, n = 0
        for t in tokens {
            let cap = t.hasPrefix("^"), c = cap ? String(t.dropFirst()) : t
            if isCode(c) {
                if sys != 3 && prevCode { out += AttributedString("-") }
                let shown = ToneColors.marks && n < tones.count ? sandhiCode(c, tones[n]) : c
                var s = syl(shown, sys, place)
                if cap && sys != 3 { s = s.prefix(1).uppercased() + s.dropFirst() }
                var a = AttributedString(s)
                if n < tones.count, let col = ToneColors.color(tones[n], system) { a.swiftUI.foregroundColor = col }
                out += a; n += 1; prevCode = true
            } else if t == "--" { if sys != 3 { out += AttributedString("--") }; prevCode = false }
            else if t == "_" { out += AttributedString(" "); prevCode = false }
            else if t.hasPrefix("~") { out += AttributedString(String(t.dropFirst())); prevCode = false }
            else { out += AttributedString(t); prevCode = false }
        }
        return out
    }

    /// 漢字 coloured one character per syllable (characters that aren't 漢字 keep the base colour)
    func hanToneText(_ han: String, tones: [Int], system: Int, base: Color? = nil) -> AttributedString {
        var out = AttributedString(), n = 0
        for ch in han {
            var a = AttributedString(String(ch))
            if ch.unicodeScalars.first.map({ ConvertEngine.isHan($0.value) }) == true {
                if n < tones.count, let col = ToneColors.color(tones[n], system) { a.swiftUI.foregroundColor = col }
                else if let base { a.swiftUI.foregroundColor = base }
                n += 1
            } else if let base { a.swiftUI.foregroundColor = base }
            out += a
        }
        return out
    }

    /// a word's reading in tone colours
    func wordToneText(_ key: String, _ sys: Int, _ place: Int, system: Int) -> AttributedString {
        toneText(tokensFor(key, place), sys, place, tones: wordTones(key, place), system: system)
    }
    /// a word's 漢字 in tone colours
    func wordHanToneText(_ key: String, _ place: Int, system: Int, base: Color? = nil) -> AttributedString {
        hanToneText(Dict.hanOf(key), tones: wordTones(key, place), system: system, base: base)
    }

    // MARK: example sentences

    /// an example as shown for the place (the place's own words swapped in, its readings), with the tone
    /// of every syllable: (漢字, template, tones)
    func exampleTones(_ han: String, _ tpl: String, place: Int, zh: String?) -> (han: String, tpl: String, tones: [Int]) {
        // the word this sentence is an example of, and the class of the meaning it's listed under
        let head = exampleHead(han, tpl)
        var h = han, t = tpl
        if place >= 0 {
            let loc = localizedExample(han, tpl, place, zh: zh)
            h = loc.han
            t = dialectTemplate(loc.han, loc.tpl, place)
        }
        // codes and what comes between them
        var codes: [String] = [], seps: [String] = []
        var i = t.startIndex, prevEnd = t.startIndex
        while let open = t[i...].firstIndex(of: "{"), let close = t[open...].firstIndex(of: "}") {
            var c = String(t[t.index(after: open)..<close])
            if c.hasPrefix("^") { c.removeFirst() }
            if c.hasPrefix("?") || c.hasPrefix("!") { c.removeFirst() }
            codes.append(c); seps.append(String(t[prevEnd..<open]))
            prevEnd = t.index(after: close); i = prevEnd
        }
        let tail = String(t[prevEnd...])
        guard !codes.isEmpty else { return (h, t, []) }
        // which word each syllable belongs to
        let clean = t.replacingOccurrences(of: "{?", with: "{").replacingOccurrences(of: "{!", with: "{")
            .replacingOccurrences(of: "{^?", with: "{^").replacingOccurrences(of: "{^!", with: "{^")
        var keepAt = Set<Int>()
        var n = 0
        // the words with 漢字, and whether punctuation comes before each (the word before / after across
        // punctuation doesn't count)
        var words: [(key: String?, count: Int, afterPunct: Bool)] = []
        var sawPunct = false
        for p in exampleWords(h, clean) {
            let count = p.text.unicodeScalars.filter { ConvertEngine.isHan($0.value) }.count
            if count == 0 {
                if p.text.unicodeScalars.contains(where: { CharacterSet.punctuationCharacters.contains($0) }) { sawPunct = true }
                continue
            }
            words.append((p.key, count, sawPunct)); sawPunct = false
        }
        for (w, word) in words.enumerated() {
            let prevKey = w > 0 && !word.afterPunct ? words[w - 1].key : nil
            let nextKey = w + 1 < words.count && !words[w + 1].afterPunct ? words[w + 1].key : nil
            let sense = word.key != nil && word.key == head?.entry ? head?.pos : nil
            if keepsLastTone(word.key, after: prevKey, before: nextKey, sense: sense) { keepAt.insert(n + word.count - 1) }
            n += word.count
        }
        let hanChars = h.filter { $0.unicodeScalars.first.map { ConvertEngine.isHan($0.value) } ?? false }.map { $0 }
        var units: [ToneUnit] = []
        for (j, c) in codes.enumerated() {
            var u = ToneUnit(code: c)
            let sep = seps[j]
            u.light = sep == "--" || (sep == "-" && (units.last?.light ?? false))
            let next = j + 1 < codes.count ? seps[j + 1] : tail
            u.beforeLight = next == "--"
            u.phraseEnd = j + 1 == codes.count || next.contains(where: { !" -".contains($0) })
            // joined to the next syllable with one "-" (lù-khuán): it always changes
            u.keep = keepAt.contains(j) && next != "-"
            u.beforeA = j + 1 < hanChars.count && hanChars[j + 1] == "仔"
            units.append(u)
        }
        return (h, t, realizedTones(units, place))
    }

    /// an example's 羅馬字 / 方音 in tone colours
    func sentenceToneText(_ han: String, _ tpl: String, _ sys: Int, place: Int, zh: String?, system: Int) -> AttributedString {
        let ex = exampleTones(han, tpl, place: place, zh: zh)
        var out = AttributedString()
        var rest = Substring(ex.tpl), n = 0
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            out += AttributedString(String(rest[..<open]))
            var c = String(rest[rest.index(after: open)..<close])
            let cap = c.hasPrefix("^")
            if cap { c.removeFirst() }
            if c.hasPrefix("?") || c.hasPrefix("!") { c.removeFirst() }
            if ToneColors.marks, n < ex.tones.count, isCode(c) { c = sandhiCode(c, ex.tones[n]) }
            var s = isCode(c) ? syl(c, sys, place) : c
            if cap { s = s.prefix(1).uppercased() + s.dropFirst() }
            var a = AttributedString(s)
            if n < ex.tones.count, let col = ToneColors.color(ex.tones[n], system) { a.swiftUI.foregroundColor = col }
            out += a; n += 1
            rest = rest[rest.index(after: close)...]
        }
        out += AttributedString(String(rest))
        return out
    }

    /// an example's 漢字 (the place's own words swapped in) in tone colours
    func sentenceHanToneText(_ han: String, _ tpl: String, place: Int, zh: String?, system: Int, base: Color? = nil) -> AttributedString {
        let ex = exampleTones(han, tpl, place: place, zh: zh)
        return hanToneText(ex.han, tones: ex.tones, system: system, base: base)
    }
}

/// 聲調 button (top bar, next to the 腔口): off / 七聲 / 五聲
struct ToneMenu: View {
    @AppStorage(ToneColors.key) private var system = 0
    @AppStorage(ToneColors.versionKey) private var colorVersion = 0
    @ObservedObject private var store = Store.shared
    @AppStorage(ToneColors.marksKey) private var marks = true
    @AppStorage(ToneColors.glowKey) private var glow = ToneColors.glowStandard
    private let glassOn = false   // the Liquid Glass look was taken out
    var body: some View {
        Menu {
            ToneMenuItems()
        } label: {
            label
        }
        .accessibilityLabel(tr("聲調顏色"))
        #if targetEnvironment(macCatalyst)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        #endif
    }

    private var dots: some View { ToneDots(system: system, word: true) }
}

/// the tone colour choices (in ToneMenu, and in the one menu of a narrow top bar)
struct ToneMenuItems: View {
    @AppStorage(ToneColors.key) private var system = 0
    @AppStorage(ToneColors.marksKey) private var marks = true
    @AppStorage(ToneColors.glowKey) private var glow = ToneColors.glowStandard
    @ObservedObject private var store = Store.shared
    var body: some View {
        // 七聲 / 五聲 and 變調 are 台語's; the other languages only turn the colours on and off
        if store.lang == 0 || store.lang == 3 {
            // (客語: 七聲 gives the 入聲 colours of their own, 五聲 the colour of the tone they sound like)
            Picker(tr("聲調顏色"), selection: $system) {
                Text(tr("關")).tag(0)
                Text(tr("七聲")).tag(7)
                Text(tr("五聲")).tag(5)
            }
            .pickerStyle(.inline)
            if system != 0 {
                if store.lang == 0 { Toggle(tr("聲調符號照變調寫"), isOn: $marks) }
                Toggle(tr("聲調光暈"), isOn: $glow)
            }
        } else {
            Picker(store.lang == 4 ? tr("文字顏色") : tr("聲調顏色"), selection: Binding(get: { system == 0 ? 0 : 1 }, set: { system = $0 == 0 ? 0 : (system == 0 ? 7 : system) })) {
                Text(tr("關")).tag(0)
                Text(tr("開")).tag(1)
            }
            .pickerStyle(.inline)
            if system != 0 {
                Toggle(tr("聲調光暈"), isOn: $glow)
            }
        }
    }
}

/// the language's tone colours as small dots (調 when they're off)
struct ToneDots: View {
    let system: Int
    /// 調 when off (else nothing)
    var word = false
    @ObservedObject private var store = Store.shared
    var body: some View {
        HStack(spacing: 2) {
            if system == 0 {
                if word {
                #if targetEnvironment(macCatalyst)
                Text(tr("聲調")).ffFont(.subheadline, .bold).foregroundStyle(T.glyph)
                #else
                Text(tr("調")).ffFont(.subheadline, .bold).foregroundStyle(T.muted)
                #endif
                }
            } else {
                if store.isHak {
                    ForEach(ToneColors.hakTones.filter { ToneColors.hakPitch[Lang.hakAccent][$0] != nil }, id: \.self) { t in
                        Circle().fill(ToneColors.hakColor(t) ?? T.muted).frame(width: 5, height: 5)
                    }
                } else if store.isYue {
                    ForEach([1, 2, 3, 4, 5, 6], id: \.self) { t in
                        Circle().fill(ToneColors.yueColor(t) ?? T.muted).frame(width: 5, height: 5)
                    }
                } else if store.isZh {
                    ForEach([1, 2, 3, 4], id: \.self) { t in
                        Circle().fill(ToneColors.zhColor(t) ?? T.muted).frame(width: 5, height: 5)
                    }
                } else {
                    ForEach(system == 5 ? [1, 2, 3, 5, 6, 7] : [1, 2, 3, 4, 5, 6, 7, 8], id: \.self) { t in
                        Circle().fill(ToneColors.color(t, system) ?? T.muted).frame(width: 5, height: 5)
                    }
                }
            }
        }
    }
}

extension ToneMenu {

    @ViewBuilder private var label: some View {
        #if targetEnvironment(macCatalyst)
        capsule
        #else
        if glassOn, #available(iOS 26.0, *) { dots } else { capsule }
        #endif
    }
    private var capsule: some View {
        dots
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(Capsule().fill(T.fn))
            .overlay(Capsule().stroke(T.fnEdge, lineWidth: 2))
    }
}


extension ToneColors {
    /// the glow around coloured letters (設定 → 顯示 → 聲調光暈). The Mac draws it without blur: there every blur
    /// is worked out again whenever anything on the page moves (a word swelling), which made hovering slow.
    static let glowKey = "toneGlow"
    #if targetEnvironment(macCatalyst)
    static let glowStandard = true      // the Mac has its own cheaper glow (no blur)
    #else
    static let glowStandard = true
    #endif
}

/// 聲調顏色 on: the coloured letters glow a little in their own colour
struct ToneGlow: ViewModifier {
    @AppStorage(ToneColors.key) private var system = 0
    @AppStorage(ToneColors.glowKey) private var glow = ToneColors.glowStandard
    @ViewBuilder func body(content: Content) -> some View {
        if system != 0 && glow {
            #if targetEnvironment(macCatalyst)
            // Mac: no blur (the Mac works every blur out again whenever anything on the page moves). A soft
            // halo instead: faint copies of the letters, a little to each side, in a ring of 8 and a wider
            // ring of 8. Drawing letters is cheap; only the colours spread out around them.
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let r: CGFloat = i < 8 ? 1.4 : 3.0
                    let a = Double(i % 8) * .pi / 4 + (i < 8 ? 0 : .pi / 8)
                    content
                        .offset(x: r * CGFloat(cos(a)), y: r * CGFloat(sin(a)))
                        .opacity(i < 8 ? 0.16 : 0.07)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                content
            }
            #else
            // a ZStack (not .background) so the blurred copies get the same width as the text and wrap the
            // same way; a background copy is laid out again at the text's measured size and can wrap differently
            ZStack {
                content.blur(radius: 5).opacity(0.9).allowsHitTesting(false).accessibilityHidden(true)
                content.blur(radius: 1.5).opacity(0.6).allowsHitTesting(false).accessibilityHidden(true)
                content
            }
            #endif
        } else {
            content
        }
    }
}
extension View {
    func toneGlow() -> some View { modifier(ToneGlow()) }
}


// MARK: which meaning an example sentence belongs to

private final class ExampleHeadIndex: @unchecked Sendable {
    static let shared = ExampleHeadIndex()
    let lock = NSLock()
    var map: [String: (entry: String, pos: String)]? = nil
}

extension Dict {
    /// the entry an example sentence is listed under, and the word class of that meaning (for the tone of
    /// the headword in its own examples: 相厝宅 is under 相's 動詞 meaning)
    func exampleHead(_ han: String, _ tpl: String) -> (entry: String, pos: String)? {
        let idx = ExampleHeadIndex.shared
        idx.lock.lock(); defer { idx.lock.unlock() }
        if idx.map == nil {
            var m: [String: (entry: String, pos: String)] = [:]
            for (entry, senses) in raw.ex {
                let pos = (raw.pos[entry] ?? "").components(separatedBy: "|")
                for (i, exs) in senses.enumerated() {
                    let p = i < pos.count ? pos[i] : ""
                    for e in exs where e.count > 1 { m[e[0] + "\u{1}" + e[1]] = (entry, p) }
                }
            }
            idx.map = m
        }
        return idx.map?[han + "\u{1}" + tpl]
    }
}


// MARK: - 客語 變調 (教育部《臺灣客語辭典》's 客語變調規則)

/// the pitches a 客語 word's syllables are said in: every syllable but the last one changes as its accent's rules say
/// (only the one before changes, never the one after):
///   四縣、南四縣  陰平 24 before 陰平, 去聲, 陽入 → 11
///   海陸        上聲 24 → 33; 陰入 5 → 2
///   大埔        陽平 113 before 陽平 → 33; 去聲 53 before 上聲, 去聲, 陰入, 陽入 → 55
///   饒平        上聲 53 before 陰平, 上聲 → 33, else → 11; 陰入 2 → 5; 陽平 55 before 陰平, 上聲, 陰入 → 53, else → 33;
///              陽去 24 → 33
///   詔安        上聲 31 before 上聲 → 55, else → 11; 陰入 24 → 5 (no b/d/g at the end: 55); 陽平 53 → 33;
///              陽去 55 → 33; 陽入 43 → 3
enum HakSandhi {
    /// for each syllable (category, ends in b/d/g): its pitch, and whether it's still short
    static func pitches(_ syl: [(cat: Int, stop: Bool)], accent: Int) -> [(pitch: String, short: Bool)?] {
        guard accent >= 0, accent < ToneColors.hakPitch.count else { return syl.map { _ in nil } }
        let table = ToneColors.hakPitch[accent]
        return syl.enumerated().map { i, s in
            guard let own = table[s.cat] else { return nil }
            let short = s.cat == 4 || s.cat == 8
            guard i + 1 < syl.count else { return (own, short) }
            let next = syl[i + 1].cat
            switch accent {
            case 0, 5:
                if s.cat == 1 && [1, 3, 8].contains(next) { return ("11", false) }
            case 1:
                if s.cat == 2 { return ("33", false) }
                if s.cat == 4 { return ("2", true) }
            case 2:
                if s.cat == 5 && next == 5 { return ("33", false) }
                if s.cat == 3 && [2, 3, 4, 8].contains(next) { return ("55", false) }
            case 3:
                if s.cat == 2 { return ([1, 2].contains(next) ? "33" : "11", false) }
                if s.cat == 4 { return ("5", true) }
                if s.cat == 5 { return ([1, 2, 4].contains(next) ? "53" : "33", false) }
                if s.cat == 7 { return ("33", false) }
            case 4:
                if s.cat == 2 { return (next == 2 ? "55" : "11", false) }
                if s.cat == 4 { return s.stop ? ("5", true) : ("55", false) }
                if s.cat == 5 || s.cat == 7 { return ("33", false) }
                if s.cat == 8 { return ("3", true) }
            default: break
            }
            return (own, short)
        }
    }
}
