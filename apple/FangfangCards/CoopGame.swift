import SwiftUI
import MultipeerConnectivity
import PencilKit

// MARK: - 一起玩 (two or more players nearby, taking turns)
//
// Each player picks how they answer (手寫, 八選一 or 打字) and how many words, and presses 準備好了; the game
// starts once everyone has. The players take turns. On your turn, a word from your own 練習範圍 (in your own language) is picked, but it's
// shown only on the others' screens, never on yours: they see its clues one at a time and read them to you
// (first its reading; then, if you ask for more, its meaning; then its radicals), and they see the answer.
// You answer on your own screen — write it (手寫), pick it out of eight words that sound alike (八選一) or type it
// (打字) — and press 完成. Your answer appears on their screens, and one of them presses 對 or 錯. Then it's the next
// player's turn. Each extra clue costs points; the one with the most points wins. Your answers count for 不熟 /
// 複習 as in the other practice. A word is shown in the list at the bottom only once it has been answered.
// (Over the internet, and with the other versions: later, see docs/PENDING-other-versions.md.)

/// what's sent between the players (JSON)
struct CoopMsg: Codable {
    enum Kind: String, Codable { case hello, ready, question, hint, submit, judge }
    var kind: Kind
    var name: String
    /// ready: the way this player answers, and how many words they get (`right`: ready or not)
    var mode = 0
    var rounds = 0
    /// question: the word, its reading, and its clues (reading, meaning, radicals)
    var word = ""
    var reading = ""
    var clues: [String] = []
    /// what each clue is ("reading", "meaning", "radicals", "letters"), so each screen labels it in its own language
    var clueKinds: [String] = []
    /// the meaning in English too: each screen shows the one its own 設定 → 主要解釋 says
    var english = ""
    var lang = 0
    /// hint: how many clues are shown now
    var hints = 1
    /// submit: what was typed or picked, or the writing (squares)
    var text = ""
    /// the writing: each square a list of strokes (InkLine: the same as the Android and computer versions')
    var squares: [[InkLine]] = []
    /// judge
    var right = false

    init(kind: Kind, name: String, mode: Int = 0, rounds: Int = 0, word: String = "", reading: String = "", clues: [String] = [],
         lang: Int = 0, hints: Int = 1, text: String = "", right: Bool = false) {
        self.kind = kind; self.name = name; self.mode = mode; self.rounds = rounds; self.word = word; self.reading = reading
        self.clues = clues; self.lang = lang; self.hints = hints; self.text = text; self.right = right
    }
    // (read leniently: a message from another version may leave some out)
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        mode = (try? c.decodeIfPresent(Int.self, forKey: .mode)) ?? 0
        rounds = (try? c.decodeIfPresent(Int.self, forKey: .rounds)) ?? 0
        word = (try? c.decodeIfPresent(String.self, forKey: .word)) ?? ""
        reading = (try? c.decodeIfPresent(String.self, forKey: .reading)) ?? ""
        clues = (try? c.decodeIfPresent([String].self, forKey: .clues)) ?? []
        clueKinds = (try? c.decodeIfPresent([String].self, forKey: .clueKinds)) ?? []
        english = (try? c.decodeIfPresent(String.self, forKey: .english)) ?? ""
        lang = (try? c.decodeIfPresent(Int.self, forKey: .lang)) ?? 0
        hints = (try? c.decodeIfPresent(Int.self, forKey: .hints)) ?? 1
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        squares = (try? c.decodeIfPresent([[InkLine]].self, forKey: .squares)) ?? []
        right = (try? c.decodeIfPresent(Bool.self, forKey: .right)) ?? false
    }
}

/// the question of the turn, as everyone knows it
struct CoopQuestion {
    let from: String
    let word: String
    let reading: String
    let clues: [String]
    var clueKinds: [String] = []
    var english = ""
    let lang: Int
    var shown = 1
    var text = ""
    var squares: [[InkLine]] = []
    var submitted = false
}

/// a word that has been answered (for the list at the bottom)
struct CoopResult: Identifiable {
    let id = UUID()
    let who: String
    let word: String
    let reading: String
    let right: Bool
    let points: Int
}

@MainActor
final class CoopLink: NearbyLink {

    /// who has pressed 準備好了, with their way of answering and how many words; the game starts once everyone has
    @Published var ready: [String: (mode: Int, rounds: Int)] = [:]
    /// mine, sent again to anyone who joins
    private var mine: (mode: Int, rounds: Int)?

    // the game, the same on every device
    @Published var playing = false
    /// the players (by name) and each one's way of answering
    @Published var order: [String] = []
    @Published var modes: [String: Int] = [:]
    /// whose turn each turn is: round and round, a player left out once they've had all their words
    @Published var schedule: [String] = []
    @Published var turn = 0
    @Published var question: CoopQuestion?
    @Published var scores: [String: Int] = [:]
    @Published var results: [CoopResult] = []
    /// (one more each time a game starts)
    @Published var game = 0

    var over: Bool { playing && turn >= schedule.count }
    /// whose turn it is
    var answerer: String? { turn < schedule.count ? schedule[turn] : nil }
    var myTurn: Bool { answerer == myName }
    /// how many of my turns came before this one
    var myTurnsBefore: Int { schedule.prefix(turn).filter { $0 == myName }.count }

    /// 準備好了 (or not any more)
    func setReady(_ on: Bool, mode: Int, rounds: Int) {
        mine = on ? (mode, rounds) : nil
        send(CoopMsg(kind: .ready, name: myName, mode: mode, rounds: rounds, right: on))
    }

    /// a player who left: their turns are passed over
    fileprivate func skipGone() {
        let here = everyone
        while playing, let a = answerer, !here.contains(a) {
            if question?.from == a { question = nil }
            turn += 1
        }
    }

    /// everyone (two or more) ready: the game starts, on every device the same way
    private func startIfReady() {
        guard !playing || over else { return }
        let all = everyone
        guard all.count >= 2, all.isSubset(of: Set(ready.keys)) else { return }
        order = all.sorted()
        modes = Dictionary(uniqueKeysWithValues: order.map { ($0, ready[$0]?.mode ?? 0) })
        var left = Dictionary(uniqueKeysWithValues: order.map { ($0, max(1, ready[$0]?.rounds ?? 5)) })
        var s: [String] = []
        while left.values.contains(where: { $0 > 0 }) {
            for n in order where (left[n] ?? 0) > 0 { s.append(n); left[n]! -= 1 }
        }
        schedule = s
        turn = 0; question = nil; results = []
        scores = Dictionary(uniqueKeysWithValues: order.map { ($0, 0) })
        ready = [:]; mine = nil
        playing = true
        game += 1
    }

    init(name: String) { super.init(name: name, service: "ff-coop") }

    func send(_ m: CoopMsg) {
        handle(m)
        if let d = try? JSONEncoder().encode(m) { sendData(d) }
    }
    override func received(_ d: Data) {
        if let m = try? JSONDecoder().decode(CoopMsg.self, from: d) { handle(m) }
    }
    override func joined(_ name: String) {
        // (someone joined: they're told I'm ready, if I am)
        if let r = mine { send(CoopMsg(kind: .ready, name: myName, mode: r.mode, rounds: r.rounds, right: true)) }
        startIfReady()
    }
    override func left(_ name: String) {
        ready[name] = nil
        skipGone()
        startIfReady()
    }

    /// the points a right answer gets: fewer for each clue after the first
    static func points(_ shown: Int) -> Int { max(1, 10 - 3 * (shown - 1)) }

    fileprivate func handle(_ m: CoopMsg) {
        switch m.kind {
        case .hello: break
        case .ready:
            if m.right { ready[m.name] = (m.mode, m.rounds) } else { ready[m.name] = nil }
            startIfReady()
        case .question:
            question = CoopQuestion(from: m.name, word: m.word, reading: m.reading, clues: m.clues, clueKinds: m.clueKinds, english: m.english, lang: m.lang)
        case .hint:
            if question?.from == m.name { question?.shown = max(question?.shown ?? 1, m.hints) }
        case .submit:
            guard question?.from == m.name else { return }
            question?.text = m.text
            question?.squares = m.squares
            question?.submitted = true
        case .judge:
            // (the first one to judge counts)
            guard let q = question, q.submitted else { return }
            let pts = m.right ? Self.points(q.shown) : 0
            scores[q.from, default: 0] += pts
            results.append(CoopResult(who: q.from, word: q.word, reading: q.reading, right: m.right, points: pts))
            question = nil
            turn += 1
            skipGone()
        }
    }
}

// MARK: the page

struct CoopView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("coopName") private var name = ""
    @AppStorage("coopMode") private var mode = 0
    @AppStorage("coopRounds") private var rounds = 5
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("goal") private var goal = 3
    @StateObject private var link = CoopLink(name: UserDefaults.standard.string(forKey: "coopName").flatMap { $0.isEmpty ? nil : $0 } ?? UIDevice.current.name)

    // my turns: my words, and the one being asked now (never shown here until it's been judged)
    @State private var queue: [Card] = []
    @State private var mine: Card?
    @State private var options: [Card] = []
    @State private var picked: String?
    @State private var typed = ""
    /// 手寫: the squares (the same as the other games') and their side
    @State private var drawings = [PKDrawing()]
    @State private var side: CGFloat = 0
    @State private var resetN = 0
    @State private var hints = 1
    @State private var sent = false
    @FocusState private var focused: Bool

    private static let modes = ["手寫", "八選一", "打字"]
    /// the way I answer in this game (the one I chose when I pressed 準備好了)
    private var myMode: Int { link.modes[link.myName] ?? mode }
    private var iAmReady: Bool { link.ready[link.myName] != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RoomBar(link: link, locked: link.playing && !link.over)
                    scoreboard
                    if !link.playing { lobby }
                    else if link.over { finished; lobby }
                    else if link.myTurn { myTurnView }
                    else { theirTurnView }
                    answered
                }
                .padding()
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .appBackground()
            .navigationTitle(tr("一起玩"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { link.close(); dismiss() } }
                // (手寫 on my turn: the pen's settings, as in the other games)
                if link.playing && link.myTurn && myMode == 0 { ToolbarItem(placement: .topBarTrailing) { PenTools() } }
                ToolbarItem(placement: .topBarTrailing) { RomButton() }
            }
        }
        .onDisappear { link.close() }
        .onChange(of: link.game) { begin() }
        .onChange(of: link.turn) { turnChanged() }
        .onChange(of: link.results.count) { learned() }
    }

    /// my answer was judged (on another device): it counts for 不熟 / 複習
    private func learned() {
        guard let r = link.results.last, r.who == link.myName, let c = queue.first(where: { $0.h == r.word }) else { return }
        _ = store.answer(c, correct: r.right, goal: goal)
    }

    // MARK: parts

    private var scoreboard: some View {
        VStack(alignment: .leading, spacing: 8) {
            let names = link.playing ? link.order : [link.myName] + Array(link.players.values).sorted()
            ForEach(names, id: \.self) { n in
                HStack(spacing: 8) {
                    if link.playing && link.answerer == n { Image(systemName: "arrowtriangle.right.fill").foregroundStyle(T.blueInk).ffFont(.caption) }
                    Text(n + (n == link.myName ? tr("（你）") : "")).ffFont(.subheadline, .semibold).foregroundStyle(T.glyph)
                    if link.playing, let m = link.modes[n] { Text(trs(Self.modes[min(max(m, 0), 2)])).ffFont(.caption).foregroundStyle(T.muted) }
                    Spacer()
                    if !link.playing || link.over {
                        if let r = link.ready[n] {
                            Label(tr("準備好了") + "・" + trs(Self.modes[min(max(r.mode, 0), 2)]) + "・" + tr("\(r.rounds) 題"), systemImage: "checkmark.circle.fill")
                                .ffFont(.caption).foregroundStyle(T.greenInk)
                        } else {
                            Text(tr("還沒準備好")).ffFont(.caption).foregroundStyle(T.muted)
                        }
                    }
                    if link.playing { Text("\(link.scores[n] ?? 0)").scaledFont(22, weight: .bold).foregroundStyle(T.blueInk) }
                }
            }
            if link.players.isEmpty && (link.via == .nearby || link.status == 2) {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(link.via == .nearby ? tr("找附近的人中…請其他人也打開「一起玩」（同一個 Wi-Fi，或打開藍牙）。")
                         : tr("等其他人進房間…")).ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    private var lobby: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("你的名字")).ffFont(.subheadline, .semibold).foregroundStyle(T.muted)
            TextField(UIDevice.current.name, text: $name).textFieldStyle(.roundedBorder)
            Text(tr("（改名字要重新打開「一起玩」才會用上）")).ffFont(.caption2).foregroundStyle(T.muted)
            Picker(tr("你怎麼答"), selection: $mode) {
                ForEach(Self.modes.indices, id: \.self) { Text(trs(Self.modes[$0])).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(iAmReady)
            Stepper(tr("你答 \(rounds) 題"), value: $rounds, in: 1...20).disabled(iAmReady)
            Text(tr("輪流答題，每個人用自己選的方式答。輪到你的時候，詞只會出現在別人的畫面上：他們一次給你一個提示（先是讀音，要的話再給意思、部首），你在自己的畫面上答，按「完成」，他們再按對或錯。每個人的詞都從自己的練習範圍（\(store.practiceName)）出，用自己的語言。答對 10 分，每多要一個提示少 3 分。"))
                .ffFont(.footnote).foregroundStyle(T.muted)
            Button { toggleReady() } label: {
                Text(iAmReady ? tr("不要了，先等一下") : tr("準備好了")).ffFont(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .prominentButton(iAmReady ? T.rustEdge : T.blueEdge)
            .disabled(link.players.isEmpty)
            Text(iAmReady ? tr("等其他人也按「準備好了」，大家都準備好就開始。") : tr("每個人選自己怎麼答，大家都按「準備好了」才會開始。"))
                .ffFont(.caption).foregroundStyle(T.muted)
        }
    }

    /// my turn: the clues are on the others' screens; I answer here
    private var myTurnView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("輪到你了")).ffFont(.title3, .bold).foregroundStyle(T.blueInk)
            if mine == nil {
                Text(tr("你的練習範圍沒有詞可以問了。")).foregroundStyle(T.muted)
                Button(tr("跳過")) { skip() }
            } else if sent {
                HStack(spacing: 8) { ProgressView(); Text(tr("等對方看你的答案…")).foregroundStyle(T.muted) }
            } else {
                Text(tr("請對方唸提示給你聽（第 \(hints) 個提示）。")).ffFont(.footnote).foregroundStyle(T.muted)
                switch myMode {
                case 0:
                    // (one square a character: add one with 加一個格子; the pen as chosen with 筆 / 顏色 at the top)
                    GameWriteSquares(drawings: $drawings, side: $side, reset: resetN)
                case 1:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(options, id: \.k) { o in
                            Button { picked = o.h } label: {
                                Text(o.h).scaledFont(22, weight: .semibold).foregroundStyle(T.glyph)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(picked == o.h ? T.blue : T.fn))
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(picked == o.h ? T.blueEdge : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                default:
                    TextField(store.isSv ? tr("打這個詞") : tr("打這個詞的字"), text: $typed)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused).scaledFont(22).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button(tr("再給一個提示")) { moreHint() }
                        .disabled(hints >= (link.question?.clues.count ?? 1))
                    Spacer()
                    Button { submit() } label: { Text(tr("完成")).ffFont(.headline).frame(minWidth: 90, minHeight: 30) }
                        .prominentButton(T.blueEdge)
                        .disabled(!canSubmit)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    private var canSubmit: Bool {
        switch myMode {
        case 0: return drawings.contains { !$0.strokes.isEmpty }
        case 1: return picked != nil
        default: return !typed.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// someone else's turn: their word, its clues so far, and, once they've answered, 對 / 錯
    private var theirTurnView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let q = link.question {
                Text(tr("輪到 \(q.from)：唸提示給他聽")).ffFont(.title3, .bold).foregroundStyle(T.blueInk)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(q.clues.prefix(q.shown).enumerated()), id: \.offset) { i, _ in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(i + 1)").ffFont(.caption, .bold).foregroundStyle(T.muted).frame(width: 18)
                            Text(clueText(q, i)).ffFont(.title3).foregroundStyle(T.glyph).textSelection(.enabled)
                        }
                    }
                    if q.shown < q.clues.count {
                        Text(tr("（還有 \(q.clues.count - q.shown) 個提示，他要的時候才會出現）")).ffFont(.caption).foregroundStyle(T.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("答案（不要給 \(q.from) 看）")).ffFont(.caption).foregroundStyle(T.muted)
                    Text(q.word).scaledFont(36, weight: .bold).foregroundStyle(T.glyph)
                    if !q.reading.isEmpty { Text(q.reading).latFont(18).foregroundStyle(T.greenInk) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(T.fn))
                if q.submitted {
                    Text(tr("\(q.from) 的答案")).ffFont(.subheadline, .semibold).foregroundStyle(T.muted)
                    if !q.squares.isEmpty {
                        WrittenSquares(squares: q.squares, size: 130)
                    } else {
                        Text(q.text).scaledFont(32, weight: .semibold).foregroundStyle(T.glyph)
                    }
                    HStack(spacing: 12) {
                        Button { judge(true) } label: { Label(tr("對"), systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 34) }
                            .prominentButton(T.greenEdge)
                        Button { judge(false) } label: { Label(tr("錯"), systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 34) }
                            .prominentButton(T.rustEdge)
                    }
                } else {
                    HStack(spacing: 8) { ProgressView(); Text(tr("\(q.from) 正在答…")).foregroundStyle(T.muted) }
                }
            } else {
                HStack(spacing: 8) { ProgressView(); Text(tr("等 \(link.answerer ?? "") 的題目…")).foregroundStyle(T.muted) }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    /// a clue as this screen shows it: labelled in this app's language; the meaning in the language this app's
    /// 設定 → 主要解釋 says for the word's language (華語 or English)
    private func clueText(_ q: CoopQuestion, _ i: Int) -> String {
        let v = q.clues[i]
        let kind = i < q.clueKinds.count ? q.clueKinds[i] : ""
        switch kind {
        case "reading": return tr("讀音：") + v
        case "meaning":
            let en = !q.english.isEmpty && (ZhMeaning.english(q.lang) || v.isEmpty)
            return tr("意思：") + (en ? q.english : v)
        case "radicals": return v.isEmpty ? "" : tr("部首：") + v
        case "letters": return tr("\(q.word.count) 個字母，開頭是「\(String(q.word.prefix(1)))」")
        case "count": return tr("\(q.word.count) 個字")
        default: return v
        }
    }

    private var finished: some View {
        VStack(alignment: .leading, spacing: 10) {
            let best = link.scores.values.max() ?? 0
            let winners = link.order.filter { (link.scores[$0] ?? 0) == best }
            Text(winners.count == 1 ? tr("\(winners[0]) 贏了！") : tr("平手！")).ffFont(.title2, .bold).foregroundStyle(T.blueInk)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    /// the words answered so far (only once answered: never the one being asked)
    private var answered: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !link.results.isEmpty { Text(tr("答過的詞")).ffFont(.subheadline, .semibold).foregroundStyle(T.muted) }
            ForEach(link.results.reversed()) { r in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: r.right ? "checkmark.circle.fill" : "xmark.circle.fill").foregroundStyle(r.right ? T.greenInk : T.rustInk)
                    Text(r.word).scaledFont(20, weight: .semibold).foregroundStyle(T.glyph)
                    if !r.reading.isEmpty { Text(r.reading).latFont(14).foregroundStyle(T.greenInk) }
                    Spacer()
                    Text(r.who + (r.right ? "　+\(r.points)" : "")).ffFont(.caption).foregroundStyle(T.muted)
                }
            }
        }
    }

    // MARK: the game

    /// 準備好了 / 不要了
    private func toggleReady() { link.setReady(!iAmReady, mode: mode, rounds: rounds) }

    /// a game started: my words for it (the ones due for 複習 first, then the practice scope's)
    private func begin() {
        var seen = Set<String>()
        let pool = (store.dueCards.shuffled() + store.practiceCards.shuffled())
            .filter { seen.insert($0.k).inserted && (myMode != 0 || store.isSv || Store.canWrite($0.h)) }
        queue = Array(pool.prefix(link.schedule.filter { $0 == link.myName }.count))
        mine = nil
        turnChanged()
    }

    private func turnChanged() {
        guard link.playing, !link.over, link.myTurn else { return }
        ask()
    }

    /// my turn: the next of my words, sent to the others (not shown here)
    private func ask() {
        let k = link.myTurnsBefore
        sent = false; picked = nil; typed = ""; drawings = [PKDrawing()]; resetN += 1; hints = 1
        guard k < queue.count else { mine = nil; return }
        let c = queue[k]
        mine = c
        options = (soundAlike(c) + [c]).shuffled()
        let reading = store.isSv ? "" : String(store.cardRom(c, rom, place).characters)
        let m = meanings(c)
        var clues: [String], kinds: [String]
        if store.isSv {
            clues = [m.zh, ""]; kinds = ["meaning", "letters"]
        } else {
            let r = radicals(c.h)
            clues = [reading, m.zh, r]; kinds = ["reading", "meaning", r.isEmpty ? "count" : "radicals"]
        }
        var q = CoopMsg(kind: .question, name: link.myName, word: c.h, reading: reading, clues: clues, lang: Lang.kind(c.k))
        q.clueKinds = kinds
        q.english = m.en
        link.send(q)
        focused = myMode == 2
    }

    /// seven words that sound like it (the same number of syllables, as much of the reading the same as can be)
    private func soundAlike(_ c: Card) -> [Card] {
        func plain(_ s: String) -> String { (s.applyingTransform(.stripDiacritics, reverse: false) ?? s).lowercased().filter { $0.isLetter || $0 == " " || $0 == "-" } }
        let me = plain(c.r.first ?? ""), n = c.syllables
        let first = me.split(whereSeparator: { $0 == " " || $0 == "-" }).first.map(String.init) ?? me
        var scored: [(Int, Card)] = []
        for x in store.cards.prefix(8000) where x.k != c.k && x.h != c.h && x.syllables == n {
            let p = plain(x.r.first ?? "")
            var same = zip(p, me).prefix { $0 == $1 }.count
            if p.hasPrefix(first) { same += 3 }
            if same > 0 { scored.append((same, x)) }
        }
        var out: [Card] = []
        var used: Set<String> = [c.h]
        for (_, x) in scored.sorted(by: { $0.0 > $1.0 }).prefix(30).shuffled() where !used.contains(x.h) {
            used.insert(x.h); out.append(x)
            if out.count == 7 { break }
        }
        if out.count < 7 { out += store.distractors(for: c, count: 7 - out.count).filter { !used.contains($0.h) } }
        return Array(out.prefix(7))
    }

    /// 部首 of each character (the 華語 dictionary's), "" when it hasn't any of them
    private func radicals(_ h: String) -> String {
        guard let z = store.zh else { return "" }
        let rs = h.map(String.init).map { ch in z.charIndex[ch].flatMap { z.chars[$0].radical } ?? "？" }
        return rs.contains(where: { $0 != "？" }) ? rs.joined(separator: "、") : ""
    }

    /// the word's meaning in 中文 and in English (either can be ""), for the others' screens to pick from
    private func meanings(_ c: Card) -> (zh: String, en: String) {
        let kind = Lang.kind(c.k)
        let first = c.d.prefix(2).map(\.t).joined(separator: "；")
        var en: [String] = []
        if kind == 0 { en = TwEnglish.meanings(c.k) }
        else if let d = store.zh, d.lang == kind, let e = d.entry(c.k) {
            en = e.enList
            if kind == 5 {
                let e3 = en.prefix(3).joined(separator: "; ")
                return (e.svZhAll.prefix(2).joined(separator: "；"), e3.isEmpty ? first : e3)
            }
        }
        // (粵語, 日語: the meanings are English already)
        if kind == 2 || kind == 4 { return (first, first) }
        return (first, en.prefix(3).joined(separator: "; "))
    }

    private func moreHint() {
        hints += 1
        link.send(CoopMsg(kind: .hint, name: link.myName, hints: hints))
    }

    private func submit() {
        var m = CoopMsg(kind: .submit, name: link.myName)
        switch myMode {
        case 0: m.squares = drawings.map { InkLine.from($0, side: side) }
        case 1: m.text = picked ?? ""
        default: m.text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        sent = true
        focused = false
        link.send(m)
    }

    private func judge(_ right: Bool) {
        link.send(CoopMsg(kind: .judge, name: link.myName, right: right))
    }

    private func skip() {
        // (no word: the turn passes as a wrong answer with nothing asked)
        link.send(CoopMsg(kind: .question, name: link.myName, word: "—", clues: ["—"]))
        link.send(CoopMsg(kind: .submit, name: link.myName, text: "—"))
        link.send(CoopMsg(kind: .judge, name: link.myName, right: false))
    }
}
