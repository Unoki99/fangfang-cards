import Foundation

/// The app's own language, for buttons, menus and explanations: 中文 (as the code is written) or English (from
/// ui_en.json, keyed by the Chinese text). The dictionaries' content (meanings, examples) stays as it is.
enum UILang {
    /// 0 = 中文, 1 = English
    static let key = "uiLanguage"
    /// (read each time: it changes as soon as 設定 changes it)
    static var english: Bool { UserDefaults.standard.integer(forKey: key) == 1 }
    nonisolated(unsafe) private static var table: [String: String]?

    /// the English for a piece of text (with {0} {1}… where the values go), or nil
    static func english(for key: String) -> String? {
        if table == nil {
            if let u = Bundle.main.url(forResource: "ui_en", withExtension: "json"),
               let d = try? Data(contentsOf: u),
               let t = try? JSONDecoder().decode([String: String].self, from: d) { table = t } else { table = [:] }
        }
        return table?[key]
    }
}

/// a piece of the app's text, with the values put into it (`tr("有「\(ch)」的詞")`); in English it's looked up
/// with {0} {1}… in place of the values
struct TR: ExpressibleByStringInterpolation {
    var key = ""
    var args: [String] = []
    /// which values are text of the app's own (those are translated too)
    var own: [Bool] = []

    init(stringLiteral v: String) { key = v }
    init(stringInterpolation i: Interp) { key = i.key; args = i.args; own = i.own }

    struct Interp: StringInterpolationProtocol {
        var key = "", args: [String] = [], own: [Bool] = []
        init(literalCapacity: Int, interpolationCount: Int) {}
        mutating func appendLiteral(_ s: String) { key += s }
        private mutating func put(_ s: String, _ o: Bool) { key += "{\(args.count)}"; args.append(s); own.append(o) }
        /// (a value that's the app's own text is translated where it's made: `trs("…")`; values aren't looked up,
        /// so a word or character from the dictionary never turns into English by accident)
        mutating func appendInterpolation(_ v: String) { put(v, false) }
        mutating func appendInterpolation<T: BinaryInteger>(_ v: T) { put(Int(v).formatted(), false) }
        mutating func appendInterpolation<T>(_ v: T) { put("\(v)", false) }
    }

    var text: String {
        let en = UILang.english
        var s = (en ? UILang.english(for: key) : nil) ?? key
        for (i, a) in args.enumerated() {
            let v = en && own[i] ? (UILang.english(for: a) ?? a) : a
            s = s.replacingOccurrences(of: "{\(i)}", with: v)
        }
        return s
    }
}

/// the app's text in the language chosen (設定 → 介面語言)
func tr(_ t: TR) -> String { t.text }

/// a piece of the app's text that isn't written out where it's shown (a title passed along, a name from a list)
func trs(_ s: String) -> String { UILang.english ? (UILang.english(for: s) ?? s) : s }

extension UILang {
    /// a name the app puts together (the 新詞 groups, the HSK/TOCFL levels), in the app's language
    static func label(_ s: String) -> String {
        guard english else { return s }
        if let e = english(for: s) { return e }
        var t = s
        for (a, b) in parts { t = t.replacingOccurrences(of: a, with: b) }
        return t
    }
    private static let parts: [(String, String)] = [
        ("漢字・更多常用字", "Characters · more common ones"), ("漢字・", "Characters · "),
        ("常用字 ", "Common characters "), ("常用詞 ", "Common words "),
        ("準備一級", "Novice 1"), ("準備二級", "Novice 2"), ("入門級", "Level 1"), ("基礎級", "Level 2"),
        ("進階級", "Level 3"), ("高階級", "Level 4"), ("流利級", "Level 5"),
    ]
}
