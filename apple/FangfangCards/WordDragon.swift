import SwiftUI
import PencilKit
import Vision

// MARK: - 詞龍 (詞語接龍)
//
// A word is given; the next word must start with its last character (瑞典語: its last letter), and so on. Every
// word must be in the dictionary of the language shown, and no word twice.
// 一個人: you and the app take turns, and it never ends by itself: the app always answers (with a common word if it
// has one, else any word of the dictionary; if no word at all starts with that character, it starts again with a
// new word). You can only lose: when the time for a turn runs out (時間, if set) or you give up (認輸).
// 和附近的人: two or more players nearby (Wi-Fi / Bluetooth) take turns; the app doesn't play. Whoever runs out of
// time or gives up is out; the last one left wins.
// 手寫: write the word in squares (the same as the other games', with the same pen); iOS reads each square
// (Vision), and you tap what it read to put it in.

/// what's sent between the players (JSON)
struct DragonMsg: Codable {
    enum Kind: String, Codable { case ready, start, word, out }
    var kind: Kind
    var name: String
    /// ready: on or off; start: the players in turn order, the first word, the seconds a turn (0: no limit)
    var on = false
    var order: [String] = []
    var word = ""
    var seconds = 0
}

@MainActor
final class DragonLink: NearbyLink {
    @Published var ready: Set<String> = []
    private var meReady = false
    // the game, the same on every device
    @Published var playing = false
    @Published var order: [String] = []
    @Published var alive: [String] = []
    @Published var turn = 0
    @Published var chain: [(word: String, who: String)] = []
    @Published var seconds = 0
    @Published var game = 0
    @Published var outs: [String] = []

    init(name: String) { super.init(name: name, service: "ff-dragon") }

    var current: String? { alive.isEmpty ? nil : alive[turn % alive.count] }
    var myTurn: Bool { playing && current == myName }
    var winner: String? { order.count > 1 && alive.count == 1 && !playing ? alive.first : nil }

    func send(_ m: DragonMsg) {
        handle(m)
        if let d = try? JSONEncoder().encode(m) { sendData(d) }
    }
    override func received(_ d: Data) { if let m = try? JSONDecoder().decode(DragonMsg.self, from: d) { handle(m) } }
    override func joined(_ name: String) { if meReady { send(DragonMsg(kind: .ready, name: myName, on: true)) } }
    override func left(_ name: String) {
        ready.remove(name)
        if playing, alive.contains(name) { out(name) }
    }

    func setReady(_ on: Bool) { meReady = on; send(DragonMsg(kind: .ready, name: myName, on: on)) }

    /// everyone ready: the first of them (by name) starts it, with its first word and its time
    var allReady: Bool { everyone.count >= 2 && everyone.isSubset(of: ready) && !playing }
    var iStart: Bool { allReady && everyone.sorted().first == myName }

    private func out(_ name: String) {
        guard let i = alive.firstIndex(of: name) else { return }
        let cur = turn % max(alive.count, 1)
        alive.remove(at: i)
        outs.append(name)
        // (the turn stays with the same player; theirs, when it's the one who's out, goes to the next)
        if alive.isEmpty { turn = 0 } else if i < cur { turn = cur - 1 } else { turn = cur % alive.count }
        if alive.count <= 1 { playing = false; ready = []; meReady = false }
    }

    fileprivate func handle(_ m: DragonMsg) {
        switch m.kind {
        case .ready:
            if m.on { ready.insert(m.name) } else { ready.remove(m.name) }
        case .start:
            order = m.order; alive = m.order; turn = 0; outs = []
            chain = [(m.word, "")]
            seconds = m.seconds
            playing = true
            game += 1
        case .word:
            guard playing, current == m.name else { return }
            chain.append((m.word, m.name))
            turn = (turn + 1) % max(alive.count, 1)
        case .out:
            out(m.name)
        }
    }
}

struct WordDragonView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("coopName") private var name = ""
    /// seconds a turn (0: no limit)
    @AppStorage("dragonSeconds") private var seconds = 0
    @AppStorage("dragonHand") private var hand = false
    @State private var best = UserDefaults.standard.integer(forKey: "dragonBest")

    /// 0 一個人, 1 和附近的人
    @State private var together = false
    @StateObject private var link = DragonLink(name: UserDefaults.standard.string(forKey: "coopName").flatMap { $0.isEmpty ? nil : $0 } ?? UIDevice.current.name)

    // 一個人
    private struct Link: Identifiable { let id = UUID(); let word: String; let who: String }
    @State private var solo: [Link] = []
    @State private var lost = false
    @State private var note: String?
    // both
    @State private var typed = ""
    @State private var said: String?
    @State private var left = 0
    @State private var turnStart = Date()
    @FocusState private var focused: Bool
    /// 手寫: the squares, their side, what iOS read
    @State private var drawings = [PKDrawing()]
    @State private var side: CGFloat = 0
    @State private var resetN = 0
    @State private var read: [String] = []
    /// the words the app may answer with, by their first unit: the common ones (the cards) first, then the dictionary's
    @State private var byFirst: [String: [String]] = [:]
    @State private var anyFirst: [String: [String]] = [:]

    private var sv: Bool { store.isSv }
    private var words: [(word: String, who: String)] {
        if together { return link.chain }
        return solo.map { (word: $0.word, who: $0.who) }
    }
    private var used: Set<String> { Set(words.map { norm($0.word) }) }
    private var mineCount: Int { words.filter { $0.who == link.myName }.count }
    private var myTurn: Bool { together ? link.myTurn : !lost }
    private var need: String? { words.last.flatMap { last($0.word) } }
    private static let times = [0, 15, 30, 60]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $together) {
                    Text(tr("一個人")).tag(false)
                    Text(tr("和附近的人")).tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.top, 8)
                .disabled(link.playing)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if together { players }
                            ForEach(Array(words.enumerated()), id: \.offset) { i, w in row(w.word, w.who).id(i) }
                            if let note { Text(note).ffFont(.footnote).foregroundStyle(T.muted) }
                            if !together && lost { lostView }
                            if together { togetherState }
                        }
                        .padding()
                        .frame(maxWidth: 680, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: words.count) { withAnimation { proxy.scrollTo(words.count - 1, anchor: .bottom) } }
                }
                if myTurn && (!together || link.playing) { input }
            }
            .appBackground()
            .navigationTitle(tr("詞龍"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { link.close(); dismiss() } }
                if hand { ToolbarItem(placement: .topBarTrailing) { PenTools() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(tr("手寫"), isOn: $hand)
                        Picker(tr("每一輪的時間"), selection: $seconds) {
                            ForEach(Self.times, id: \.self) { t in Text(t == 0 ? tr("不限時間") : tr("\(t) 秒")).tag(t) }
                        }
                    } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel(tr("設定"))
                }
                if !sv { ToolbarItem(placement: .topBarTrailing) { RomButton() } }
            }
        }
        .onAppear { if byFirst.isEmpty { build() }; if solo.isEmpty { startSolo() } }
        .onChange(of: together) { if together { link.open() } else { link.close() } }
        .onDisappear { link.close() }
        .onChange(of: link.allReady) { if link.iStart { startTogether() } }
        .onChange(of: link.game) { newTurn() }
        .onChange(of: link.turn) { newTurn() }
        .onChange(of: link.chain.count) { newTurn() }
        // (the time left of this turn)
        .task(id: "\(turnKey)") {
            let limit = together ? link.seconds : seconds
            guard limit > 0, myTurn, !together || link.playing else { left = 0; return }
            left = limit
            while left > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                left -= 1
            }
            timeUp()
        }
        // (手寫: read a moment after the last stroke)
        .task(id: drawings.map(\.strokes.count).reduce(0, +)) {
            guard hand, drawings.contains(where: { !$0.strokes.isEmpty }) else { read = []; return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            read = await readSquares()
        }
    }

    /// changes at each new turn (restarts the clock)
    private var turnKey: String { "\(together)-\(link.game)-\(link.turn)-\(words.count)-\(lost)" }

    // MARK: parts

    private func row(_ w: String, _ who: String) -> some View {
        let mine = who == link.myName
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            if who.isEmpty || who == "app" {
                Image(systemName: "sparkles").ffFont(.caption).foregroundStyle(T.oliveInk)
            } else {
                Text(mine ? tr("你") : who).ffFont(.caption, .semibold).foregroundStyle(mine ? T.blueInk : T.greenInk)
            }
            Text(w).scaledFont(26, weight: .semibold).foregroundStyle(T.glyph)
            if let r = reading(w) { Text(r).latFont(16).foregroundStyle(T.greenInk) }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private var input: some View {
        VStack(spacing: 8) {
            if let said { Text(said).ffFont(.footnote).foregroundStyle(T.rustInk).frame(maxWidth: .infinity, alignment: .leading) }
            if hand {
                GameWriteSquares(drawings: $drawings, side: $side, reset: resetN)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if read.isEmpty {
                            Text(drawings.allSatisfy { $0.strokes.isEmpty } ? tr("一格寫一個字") : tr("看不出來，再寫清楚一點")).ffFont(.caption).foregroundStyle(T.muted)
                        }
                        ForEach(read, id: \.self) { w in
                            Button { typed = w } label: {
                                Text(w).scaledFont(22, weight: .semibold).foregroundStyle(T.glyph)
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(Capsule().fill(T.fn))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                if let need { Text(need).scaledFont(24, weight: .bold).foregroundStyle(T.btnInk).frame(minWidth: 34) }
                TextField(sv ? tr("打一個瑞典文的詞") : tr("打一個詞"), text: $typed)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { submit() }
                    .scaledFont(20)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(T.fn.opacity(0.75)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.fnEdge, lineWidth: 1))
                Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 34)) }
                    .buttonStyle(.plain).foregroundStyle(T.btnInk)
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                if left > 0 { Label(tr("\(left) 秒"), systemImage: "timer").ffFont(.caption, .semibold).foregroundStyle(left <= 5 ? T.rustInk : T.muted) }
                Text(together ? tr("接了 \(mineCount) 個") : tr("接了 \(mineCount) 個・最多 \(best) 個")).ffFont(.caption).foregroundStyle(T.muted)
                Spacer()
                Button(tr("認輸")) { giveUp() }.ffFont(.caption).foregroundStyle(T.rustInk)
            }
        }
        .padding()
        .background(T.fn.opacity(0.35))
    }

    private var lostView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("接了 \(mineCount) 個詞。")).ffFont(.headline).foregroundStyle(T.glyph)
            Button { startSolo() } label: { Text(tr("再玩一次")).frame(maxWidth: .infinity, minHeight: 30) }
                .prominentButton(T.blueEdge)
        }
        .padding(.top, 6)
    }

    private var players: some View {
        VStack(alignment: .leading, spacing: 6) {
            let names = link.playing ? link.order : Array(link.everyone).sorted()
            ForEach(names, id: \.self) { n in
                HStack(spacing: 8) {
                    if link.playing && link.current == n { Image(systemName: "arrowtriangle.right.fill").ffFont(.caption).foregroundStyle(T.blueInk) }
                    Text(n + (n == link.myName ? tr("（你）") : "")).ffFont(.subheadline, .semibold)
                        .foregroundStyle(link.outs.contains(n) ? T.muted : T.glyph)
                        .strikethrough(link.outs.contains(n))
                    Spacer()
                    if !link.playing {
                        Text(link.ready.contains(n) ? tr("準備好了") : tr("還沒準備好")).ffFont(.caption)
                            .foregroundStyle(link.ready.contains(n) ? T.greenInk : T.muted)
                    }
                }
            }
            if link.players.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(tr("找附近的人中…請其他人也打開詞龍的「和附近的人」（同一個 Wi-Fi，或打開藍牙）。")).ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    @ViewBuilder private var togetherState: some View {
        if let w = link.winner {
            Text(w == link.myName ? tr("你贏了！") : tr("\(w) 贏了！")).ffFont(.title3, .bold).foregroundStyle(T.blueInk)
        }
        if !link.playing {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("你的名字")).ffFont(.subheadline, .semibold).foregroundStyle(T.muted)
                TextField(UIDevice.current.name, text: $name).textFieldStyle(.roundedBorder).disabled(link.ready.contains(link.myName))
                Text(tr("輪流接；時間到或認輸就出局，最後留下來的人贏。每一輪的時間照第一個人（名字排最前面）的設定。")).ffFont(.caption).foregroundStyle(T.muted)
                let on = link.ready.contains(link.myName)
                Button { link.setReady(!on) } label: {
                    Text(on ? tr("不要了，先等一下") : tr("準備好了")).ffFont(.headline).frame(maxWidth: .infinity, minHeight: 34)
                }
                .prominentButton(on ? T.rustEdge : T.blueEdge)
                .disabled(link.players.isEmpty)
            }
        } else if !link.myTurn, let c = link.current {
            HStack(spacing: 8) { ProgressView(); Text(tr("輪到 \(c)…")).foregroundStyle(T.muted) }
        }
    }

    // MARK: words

    private func norm(_ w: String) -> String { sv ? w.lowercased() : w }
    private func first(_ w: String) -> String? { (sv ? w.lowercased() : w).first.map(String.init) }
    private func last(_ w: String) -> String? {
        if sv { return w.lowercased().last(where: { $0.isLetter }).map(String.init) }
        return w.last(where: { $0.unicodeScalars.first.map(Zhuyin.isHan) ?? false }).map(String.init) ?? w.last.map(String.init)
    }

    /// a word of the language shown (in its dictionary)
    private func isWord(_ w: String) -> Bool {
        if !store.isZh { return store.dict?.hanMap[w] != nil }
        guard let z = store.zh else { return false }
        if z.isSv { return !z.svIndices(w).isEmpty }
        return z.byHan[w] != nil
    }

    private func reading(_ w: String) -> String? {
        if sv { return nil }
        guard let c = store.cards.first(where: { $0.h == w }) else { return nil }
        return String(store.cardRom(c, rom, place).characters)
    }

    /// the app's words: the cards (most common first), then the whole dictionary's
    private func build() {
        var m: [String: [String]] = [:]
        for c in store.cards where Lang.charOf(c.k) == nil {
            let w = c.h
            guard (sv ? w.count >= 3 : w.count >= 2), !w.contains(" "), let f = first(w) else { continue }
            m[f, default: []].append(w)
        }
        byFirst = m
        var a: [String: [String]] = [:]
        let all: [String]
        if !store.isZh { all = store.dict.map { Array($0.hanMap.keys) } ?? [] }
        else if let z = store.zh { all = z.isSv ? z.entries.map(\.h) : Array(z.byHan.keys) } else { all = [] }
        for w in all where (sv ? w.count >= 3 : w.count >= 2) && !w.contains(" ") {
            if let f = first(w) { a[f, default: []].append(w) }
        }
        anyFirst = a
    }

    /// a word to start with (a common one that can be followed)
    private func opening() -> String? {
        let pool = byFirst.values.flatMap { $0.prefix(30) }.filter { w in last(w).map { byFirst[$0] != nil } ?? false }
        return pool.randomElement() ?? byFirst.values.first?.first
    }

    private func startSolo() {
        typed = ""; said = nil; lost = false; note = nil; clearSquares()
        solo = opening().map { [Link(word: $0, who: "app")] } ?? []
        focused = !hand
    }

    private func startTogether() {
        guard let w = opening() else { return }
        link.send(DragonMsg(kind: .start, name: link.myName, order: link.everyone.sorted(), word: w, seconds: seconds))
    }

    private func newTurn() {
        typed = ""; said = nil; clearSquares()
        if together && link.myTurn { focused = !hand }
    }

    private func clearSquares() { drawings = [PKDrawing()]; resetN += 1; read = [] }

    private func submit() {
        let w = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty, myTurn else { return }
        if let n = need, first(w) != n { said = tr("要用「\(n)」開頭。"); return }
        if used.contains(norm(w)) { said = tr("這個詞用過了。"); return }
        if !isWord(w) { said = tr("詞典裡沒有「\(w)」。"); return }
        said = nil; typed = ""; clearSquares()
        if together { link.send(DragonMsg(kind: .word, name: link.myName, word: w)); return }
        solo.append(Link(word: w, who: link.myName))
        if mineCount > best { best = mineCount; UserDefaults.standard.set(best, forKey: "dragonBest") }
        reply(to: w)
        focused = !hand
    }

    /// the app always answers: a common word, else any of the dictionary's, else a new start
    private func reply(to w: String) {
        note = nil
        let u = used
        guard let l = last(w) else { return }
        if let r = (byFirst[l] ?? []).first(where: { !u.contains(norm($0)) }) ?? (anyFirst[l] ?? []).first(where: { !u.contains(norm($0)) }) {
            solo.append(Link(word: r, who: "app"))
        } else if let n = opening(), !u.contains(norm(n)) {
            note = tr("詞典裡沒有「\(l)」開頭的詞了，換一個詞開始：")
            solo.append(Link(word: n, who: "app"))
        }
    }

    private func timeUp() {
        if together { if link.myTurn { link.send(DragonMsg(kind: .out, name: link.myName)) } }
        else { lost = true; said = tr("時間到了。") }
    }

    private func giveUp() {
        if together { link.send(DragonMsg(kind: .out, name: link.myName)) } else { lost = true }
    }

    /// 手寫: each square read by iOS; one square: its guesses, more: the word from each square's best guess
    private func readSquares() async -> [String] {
        let langs = sv ? ["sv-SE", "en-US"] : (Simp.on ? ["zh-Hans", "zh-Hant"] : ["zh-Hant", "zh-Hans"])
        let filled = drawings.filter { !$0.strokes.isEmpty }
        if filled.count == 1 { return await InkReader.read(filled[0], langs: langs) }
        var guesses: [[String]] = []
        for d in filled { guesses.append(await InkReader.read(d, langs: langs)) }
        let best = guesses.compactMap { $0.first.map { String($0.prefix(1)) } }.joined()
        var out = best.isEmpty ? [] : [best]
        // (the second guess of each square, one at a time)
        for (i, g) in guesses.enumerated() where g.count > 1 {
            var w = guesses.map { $0.first.map { String($0.prefix(1)) } ?? "" }
            w[i] = String(g[1].prefix(1))
            let s = w.joined()
            if !s.isEmpty && !out.contains(s) { out.append(s) }
        }
        return out
    }
}

// MARK: - reading writing with Vision

enum InkReader {
    /// what the drawing says, the likeliest first (a few guesses)
    @MainActor static func read(_ d: PKDrawing, langs: [String]) async -> [String] {
        guard !d.strokes.isEmpty else { return [] }
        let box = d.bounds.insetBy(dx: -24, dy: -24)
        // (black ink on white: Vision reads an opaque picture)
        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent { ink = d.image(from: box, scale: 2) }
        let img = UIGraphicsImageRenderer(size: box.size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 2; f.opaque = true; return f }()).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: box.size))
            ink.draw(in: CGRect(origin: .zero, size: box.size))
        }
        guard let cg = img.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) { () -> [String] in
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = false
            if let ok = try? req.supportedRecognitionLanguages() {
                let use = langs.filter { ok.contains($0) }
                if !use.isEmpty { req.recognitionLanguages = use }
            }
            try? VNImageRequestHandler(cgImage: cg).perform([req])
            let obs = (req.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            guard !obs.isEmpty else { return [] }
            var out: [String] = []
            if obs.count == 1 {
                out = obs[0].topCandidates(5).map(\.string)
            } else {
                out = [obs.compactMap { $0.topCandidates(1).first?.string }.joined()]
            }
            var seen = Set<String>()
            return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "") }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }.value
    }
}
