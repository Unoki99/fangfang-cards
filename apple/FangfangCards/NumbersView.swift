import SwiftUI

// MARK: - 台語 數字練習
//
// Taiwanese numbers have two sets of readings: 白 (counting, amounts; 一 and 二 before a 量詞 are 一 tsi̍t and 兩 nn̄g)
// and 文 (phone numbers, ages, fixed expressions like 四季). Two games, everything in the spelling chosen (皓羅, 台羅,
// 白話字, 方音):
//  - 算數: a sum written out in spelling; type the answer in spelling (tone marks or not, spaces or not)
//  - 白還是文: a number in a setting (a 量詞, a phone number, an age, a fixed expression); pick how it's said
// Rules (from the user, 2026-11-27): 10–19 are always 十…, never 一十… (also after 百: 一百十一); a 3-digit number
// with no units may drop its 十 (110 一百一, 120 一百二; 一百十, 一百二十 also right); a zero inside is 空 once
// (2002 兩千空二, 101 一百空一); 一, 二 before 百 / 千 / 萬 are 一 tsi̍t, 兩 nn̄g; above ten a 量詞 still takes 二.

/// one syllable, as 台羅 (the key to the dictionary's spellings)
typealias TL = String

enum TwNumbers {
    static let bai: [TL] = ["khòng", "it", "jī", "sann", "sì", "gōo", "la̍k", "tshit", "peh", "káu"]
    static let bun: [TL] = ["khòng", "it", "jī", "sam", "sù", "ngóo", "lio̍k", "tshit", "pat", "kiú"]
    static let ten: TL = "tsa̍p", tenBun: TL = "si̍p"
    static let hundred: TL = "pah", thousand: TL = "tshing", tenThousand: TL = "bān"
    /// 一 / 二 before a 量詞 or 百 千 萬
    static let tsit: TL = "tsi̍t", nng: TL = "nn̄g"

    /// before a 量詞 / 百 千 萬: 1 tsi̍t, 2 nn̄g, the rest as they count
    private static func lead(_ d: Int) -> TL { d == 1 ? tsit : (d == 2 ? nng : bai[d]) }

    /// 1–99 in 白 (10–19: 十…; 20 and up: 二十…)
    private static func underHundred(_ n: Int) -> [TL] {
        if n < 10 { return [bai[n]] }
        let t = n / 10, u = n % 10
        var out: [TL] = t == 1 ? [ten] : [bai[t], ten]
        if u > 0 { out.append(bai[u]) }
        return out
    }

    /// a number 0–99 999 in 白 (counting); short: a 3-digit number with no units drops its 十 (110 一百一)
    static func say(_ n: Int, short: Bool = true) -> [TL] {
        if n == 0 { return [bai[0]] }
        var out: [TL] = []
        var zero = false             // a zero passed since the last digit said (空 once)
        let w = n / 10000, th = (n / 1000) % 10, h = (n / 100) % 10, rest = n % 100
        if w > 0 {
            out += w >= 10 ? underHundred(w) : [lead(w)]
            out.append(tenThousand)
        }
        func digitPlace(_ d: Int, _ unit: TL, _ higher: Bool) {
            if d > 0 {
                if zero { out.append(bai[0]); zero = false }
                out += [lead(d), unit]
            } else if higher { zero = true }
        }
        digitPlace(th, thousand, w > 0)
        digitPlace(h, hundred, !out.isEmpty)
        if rest > 0 {
            // (空 for the place left empty: 101 一百空一, 2202 兩千兩百空二, 2020 兩千空二十, 10 001 一萬空一)
            if !out.isEmpty && (rest < 10 || h == 0) { out.append(bai[0]) }
            if short && rest % 10 == 0 && rest >= 10 && !out.isEmpty && h > 0 && n < 1000 {
                // 110 一百一, 120 一百二
                out.append(bai[rest / 10])
            } else {
                out += underHundred(rest)
            }
        }
        return out
    }

    /// every way that's right for n (the short and the long 一百一 / 一百十 / 一百一十 not: 一十 is never said)
    static func accepted(_ n: Int) -> [[TL]] {
        let a = [say(n, short: true), say(n, short: false)]
        return a[0] == a[1] ? [a[0]] : a
    }

    /// the same syllables read 文 (三 sam, 十 si̍p…)
    static func toBun(_ w: [TL]) -> [TL] {
        w.map { t in
            if t == ten { return tenBun }
            if let i = bai.firstIndex(of: t) { return bun[i] }
            return t
        }
    }

    /// a phone number's digits in 文
    static func digitsBun(_ s: String) -> [TL] { s.compactMap { $0.wholeNumberValue }.map { bun[$0] } }
    /// an age (文): 1–99
    static func ageBun(_ n: Int) -> [TL] {
        if n < 10 { return [bun[n]] }
        let t = n / 10, u = n % 10
        var out: [TL] = t == 1 ? [tenBun] : [bun[t], tenBun]
        if u > 0 { out.append(bun[u]) }
        return out
    }
}

/// the spellings of the 台語 syllables the game uses, from the dictionary (台羅 → its code)
@MainActor
final class TwSpell {
    static let shared = TwSpell()
    private var byTL: [String: String] = [:]
    private func norm(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.lowercased() }

    /// the syllable in the spelling chosen (0 皓羅, 1 台羅, 2 白話字, 3 方音); 台羅 when the dictionary hasn't it
    func spell(_ tl: String, _ rom: Int) -> String {
        let store = Store.shared
        if byTL.isEmpty {
            for (c, s) in store.syl where s.count >= 2 { byTL[norm(s[1]), default: c] = byTL[norm(s[1])] ?? c }
        }
        guard let c = byTL[norm(tl)] else { return tl }
        if rom == 3, let d = store.dict { return d.syl(c, 3, -1) }
        if let d = store.dict { return d.syl(c, min(max(rom, 0), 2), -1) }
        return store.syl[c].map { $0[min(max(rom, 0), 2)] } ?? tl
    }
    func spell(_ tls: [String], _ rom: Int) -> String { tls.map { spell($0, rom) }.joined(separator: " ") }

    /// a typed answer, ready to compare: no tone marks or numbers, no spaces or dashes, ⁿ / nn as n
    static func plain(_ s: String) -> String {
        let d = s.decomposedStringWithCompatibilityMapping.lowercased()
        var out = String.UnicodeScalarView()
        for u in d.unicodeScalars {
            if (0x0300...0x036F).contains(u.value) { continue }                    // the marks over letters
            if "ˉˊˇˋ˪˫˙·'ʼ- ".unicodeScalars.contains(u) || u.properties.isWhitespace { continue }
            if CharacterSet.decimalDigits.contains(u) { continue }
            if (0xA700...0xA71F).contains(u.value) { continue }                    // 方音's tone letters
            out.append(u)
        }
        return String(out).replacingOccurrences(of: "nn", with: "n")
    }
}

struct NumbersView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("numbersMode") private var mode = 0          // 0 算數, 1 白還是文
    @AppStorage("numbersLevel") private var level = 1        // 算數: 0 up to 20, 1 up to 100, 2 up to 1000, 3 up to 10 000

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    Text(tr("算數")).tag(0)
                    Text(tr("白還是文")).tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.top, 8)
                if mode == 0 {
                    Picker("", selection: $level) {
                        Text("≤ 20").tag(0); Text("≤ 100").tag(1); Text("≤ 1000").tag(2); Text("≤ 10 000").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal).padding(.top, 6)
                    MathGame(level: level, rom: rom).id("\(level)-\(rom)")
                } else {
                    BaiBunGame(rom: rom).id(rom)
                }
            }
            .appBackground()
            .navigationTitle(tr("數字練習"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { RomButton() }
            }
        }
    }
}

/// 算數: "sann ka gōo ＝ ?", the answer typed in spelling
private struct MathGame: View {
    let level: Int
    let rom: Int
    @State private var a = 0, b = 0, op = 0
    @State private var typed = ""
    @State private var result: Bool?
    @State private var right = 0, wrong = 0
    @FocusState private var focused: Bool

    private static let ops: [(TL, String)] = [("ka", "+"), ("kiám", "−"), ("sîng", "×"), ("tû", "÷")]
    private var answer: Int {
        switch op { case 0: return a + b; case 1: return a - b; case 2: return a * b; default: return b == 0 ? 0 : a / b }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("\(right)", systemImage: "checkmark").foregroundStyle(T.blueInk)
                    Label("\(wrong)", systemImage: "xmark").foregroundStyle(T.rustInk)
                    Spacer()
                }
                .ffFont(.subheadline, .semibold)
                // the sum, all in spelling (the digits only after answering)
                VStack(alignment: .leading, spacing: 8) {
                    Text(TwSpell.shared.spell(TwNumbers.say(a), rom)).latFont(24).foregroundStyle(T.greenInk)
                    Text(TwSpell.shared.spell(Self.ops[op].0, rom)).latFont(20).foregroundStyle(T.muted)
                    Text(TwSpell.shared.spell(TwNumbers.say(b), rom)).latFont(24).foregroundStyle(T.greenInk)
                    Text("＝ ?").ffFont(.title2, .bold).foregroundStyle(T.glyph)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
                TextField(tr("用拼音寫答案（聲調符號可有可無）"), text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit { check() }
                    .latFont(20)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.7)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                    .disabled(result != nil)
                if let result {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result ? tr("答對了！") : tr("不對。")).ffFont(.headline).foregroundStyle(result ? T.blueInk : T.rustInk)
                        Text("\(a) \(Self.ops[op].1) \(b) ＝ \(answer)").ffFont(.subheadline, mono: true).foregroundStyle(T.muted)
                        Text(TwSpell.shared.spell(TwNumbers.say(answer), rom)).latFont(22).foregroundStyle(T.greenInk)
                    }
                    Button { next() } label: {
                        Text(tr("下一題")).ffFont(.headline).frame(maxWidth: .infinity, minHeight: 46)
                            .background(Capsule().fill(T.btn)).foregroundStyle(T.btnInk)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { check() } label: {
                        Text(tr("確認答案")).ffFont(.headline).frame(maxWidth: .infinity, minHeight: 46)
                            .background(Capsule().fill(T.btn)).foregroundStyle(T.btnInk)
                    }
                    .buttonStyle(.plain)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(tr("算數：加 ka、減 kiám、乘 sîng、除 tû。答案用上面選的拼音打，可以不打聲調、不分開音節。")).ffFont(.caption).foregroundStyle(T.muted)
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if a == 0 && b == 0 { next() } }
    }

    private func next() {
        typed = ""; result = nil
        let top = [20, 100, 1000, 10000][min(max(level, 0), 3)]
        op = Int.random(in: 0...(level == 0 ? 1 : 3))
        switch op {
        case 0: a = Int.random(in: 0...top / 2); b = Int.random(in: 0...(top - a))
        case 1: a = Int.random(in: 0...top); b = Int.random(in: 0...a)
        case 2:
            let lim = max(2, Int(Double(top).squareRoot()))
            a = Int.random(in: 1...lim); b = Int.random(in: 1...max(1, top / max(a, 1)))
            b = min(b, lim * 2)
        default:
            b = Int.random(in: 1...max(1, min(12, top / 10))); a = b * Int.random(in: 0...max(1, top / b))
        }
        focused = true
    }

    private func check() {
        guard result == nil else { return }
        let mine = TwSpell.plain(typed)
        // (the chosen spelling, or 台羅; any of the right ways)
        let ok = TwNumbers.accepted(answer).contains { w in
            TwSpell.plain(TwSpell.shared.spell(w, rom)) == mine || TwSpell.plain(w.joined()) == mine
        }
        result = ok
        if ok { right += 1 } else { wrong += 1 }
    }
}

/// 白還是文: a number in a setting; pick how it's said there
private struct BaiBunGame: View {
    let rom: Int
    private struct Q { let prompt: String; let why: String; let right: [TL]; let other: [TL] }
    @State private var q: Q?
    @State private var choices: [[TL]] = []
    @State private var picked: Int?
    @State private var right = 0, wrong = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("\(right)", systemImage: "checkmark").foregroundStyle(T.blueInk)
                    Label("\(wrong)", systemImage: "xmark").foregroundStyle(T.rustInk)
                    Spacer()
                }
                .ffFont(.subheadline, .semibold)
                if let q {
                    Text(q.prompt).ffFont(.title2, .semibold).foregroundStyle(T.glyph)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(T.fn.opacity(0.7)))
                    Text(tr("這裡要怎麼講？")).ffFont(.subheadline).foregroundStyle(T.muted)
                    ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                        Button { pick(i) } label: {
                            Text(TwSpell.shared.spell(c, rom)).latFont(20)
                                .foregroundStyle(color(i))
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                                .padding(.horizontal, 14)
                                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.75)))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(border(i), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                    }
                    if picked != nil {
                        Text(q.why).ffFont(.subheadline).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                        Button { next() } label: {
                            Text(tr("下一題")).ffFont(.headline).frame(maxWidth: .infinity, minHeight: 46)
                                .background(Capsule().fill(T.btn)).foregroundStyle(T.btnInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text(tr("白：算數、數量；一、二在量詞和百、千、萬前面講「一 tsi̍t」「兩 nn̄g」（十以上還是講二）。文：電話號碼、年紀、固定的講法（四季）。")).ffFont(.caption).foregroundStyle(T.muted)
            }
            .padding()
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if q == nil { next() } }
    }

    private func color(_ i: Int) -> Color {
        guard let p = picked else { return T.greenInk }
        if choices[i] == q?.right { return T.blueInk }
        return i == p ? T.rustInk : T.muted
    }
    private func border(_ i: Int) -> Color {
        guard let p = picked else { return T.fnEdge }
        if choices[i] == q?.right { return T.blueEdge }
        return i == p ? T.rustEdge : T.fnEdge
    }

    private func pick(_ i: Int) {
        guard picked == nil, let q else { return }
        picked = i
        if choices[i] == q.right { right += 1 } else { wrong += 1 }
    }

    private func next() {
        picked = nil
        let made = make()
        q = made
        choices = [made.right, made.other].shuffled()
    }

    private func make() -> Q {
        switch Int.random(in: 0...3) {
        case 0:
            // 量詞: 一個、兩隻 (白, 一 tsi̍t / 兩 nn̄g); 十二個 (白, still 二)
            let units: [(String, TL)] = [("個", "ê"), ("隻", "tsiah"), ("本", "pún"), ("張", "tiunn"), ("杯", "pue")]
            let u = units.randomElement()!
            let n = [1, 2, 1, 2, 3, 12, 21][Int.random(in: 0...6)]
            let said = TwNumbers.say(n)
            let right: [TL] = n == 1 ? [TwNumbers.tsit, u.1] : (n == 2 ? [TwNumbers.nng, u.1] : said + [u.1])
            var other: [TL]
            if n <= 2 { other = [TwNumbers.bai[n], u.1] }
            else if said.contains(TwNumbers.bai[2]) { other = said.map { $0 == TwNumbers.bai[2] ? TwNumbers.nng : $0 } + [u.1] }
            else { other = TwNumbers.toBun(said) + [u.1] }
            return Q(prompt: "\(n)\(u.0)", why: n <= 2 ? trs("量詞前面：一講 tsi̍t、二講 nn̄g（白）。") : trs("數量用白的讀音；十以上，量詞前面還是講二，不講兩。"), right: right, other: other)
        case 1:
            // a phone number (文)
            let num = "09" + String((0..<8).map { _ in Character(String(Int.random(in: 0...9))) })
            let shown = String(num.prefix(4)) + " " + String(num.dropFirst(4).prefix(3)) + " " + String(num.suffix(3))
            return Q(prompt: tr("電話：\(shown)"), why: trs("電話號碼一個數字一個數字講，用文的讀音。"),
                     right: TwNumbers.digitsBun(num), other: num.compactMap { $0.wholeNumberValue }.map { TwNumbers.bai[$0] })
        case 2:
            // an age (文)
            let n = Int.random(in: 13...89)
            return Q(prompt: tr("\(n) 歲"), why: trs("年紀用文的讀音。"), right: TwNumbers.ageBun(n) + ["huè"], other: TwNumbers.say(n) + ["huè"])
        default:
            // counting (白)
            let n = Int.random(in: 3...99)
            let bunForm = TwNumbers.toBun(TwNumbers.say(n))
            return Q(prompt: tr("算數：\(n)"), why: trs("算數、數量用白的讀音。"), right: TwNumbers.say(n), other: bunForm == TwNumbers.say(n) ? TwNumbers.say(n + 1) : bunForm)
        }
    }
}
