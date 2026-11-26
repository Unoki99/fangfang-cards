import SwiftUI
import MultipeerConnectivity
import PencilKit

// MARK: - 一起玩 (co-op, nearby)
//
// Two or more people on the same Wi-Fi or near each other (Bluetooth), each with the app open on 一起玩. Each
// person gets questions from their own 練習範圍, in their own language (one can do 台語 while another does 華語);
// the points go into one team score. Everyone sees what the others are asked and how they did.
// Ways to answer: 八選一 (eight words, the wrong ones sounding alike), 打字 (type the word), 手寫 (write it; iOS reads
// the writing). 提示 shows one more character of the answer and costs points. After each question the one asked sees
// the right answer; every answer counts for 不熟 / 複習 as in the other practice.
// (Over the internet, and with the other versions: later, see docs/PENDING-other-versions.md.)

/// what's sent between the players (JSON)
struct CoopMsg: Codable {
    enum Kind: String, Codable { case hello, start, asked, answered, finished }
    var kind: Kind
    var name: String
    var lang: Int = 0
    var mode: Int = 0
    var rounds: Int = 0
    /// asked: what the question shows (the reading and the meaning); answered: the word
    var text: String = ""
    var right: Bool = false
    var points: Int = 0
}

@MainActor
final class CoopLink: NSObject, ObservableObject {
    static let service = "ff-coop"
    let me: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    @Published var players: [MCPeerID: String] = [:]
    @Published var feed: [(id: UUID, text: String, good: Bool?)] = []
    @Published var teamPoints = 0
    /// a game started (by anyone): its way of answering and how many questions
    @Published var started: (mode: Int, rounds: Int)?
    /// (one more each time a game starts)
    @Published var game = 0
    @Published var finished: Set<String> = []

    init(name: String) {
        me = MCPeerID(displayName: String(name.prefix(40)))
        session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: Self.service)
        browser = MCNearbyServiceBrowser(peer: me, serviceType: Self.service)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    func open() { advertiser.startAdvertisingPeer(); browser.startBrowsingForPeers() }
    func close() {
        advertiser.stopAdvertisingPeer(); browser.stopBrowsingForPeers(); session.disconnect()
        players = [:]
    }

    func send(_ m: CoopMsg) {
        handle(m, local: true)
        guard !session.connectedPeers.isEmpty, let d = try? JSONEncoder().encode(m) else { return }
        try? session.send(d, toPeers: session.connectedPeers, with: .reliable)
    }

    fileprivate func handle(_ m: CoopMsg, local: Bool) {
        let who = local ? tr("你") : m.name
        switch m.kind {
        case .hello: break
        case .start:
            started = (m.mode, m.rounds)
            game += 1
            finished = []
            teamPoints = 0
            feed.append((UUID(), tr("\(who) 開始了一局（\(m.rounds) 題）"), nil))
        case .asked:
            if !local { feed.append((UUID(), tr("\(who)（\(trs(Lang.names[min(max(m.lang, 0), 5)]))）正在答：") + m.text, nil)) }
        case .answered:
            teamPoints += m.points
            feed.append((UUID(), "\(who)：\(m.text)　" + (m.right ? "+\(m.points)" : tr("答錯")), m.right))
        case .finished:
            finished.insert(local ? me.displayName : m.name)
            feed.append((UUID(), tr("\(who) 答完了"), nil))
        }
        if feed.count > 200 { feed.removeFirst(feed.count - 200) }
    }
}

extension CoopLink: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ s: MCSession, peer p: MCPeerID, didChange state: MCSessionState) {
        let name = p.displayName
        Task { @MainActor in
            if state == .connected { self.players[p] = name; self.send(CoopMsg(kind: .hello, name: self.me.displayName)) }
            else if state == .notConnected { self.players[p] = nil }
        }
    }
    nonisolated func session(_ s: MCSession, didReceive data: Data, fromPeer p: MCPeerID) {
        guard let m = try? JSONDecoder().decode(CoopMsg.self, from: data) else { return }
        Task { @MainActor in self.handle(m, local: false) }
    }
    nonisolated func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Foundation.Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at u: URL?, withError e: Error?) {}

    // (everyone looks and is seen; the one whose name sorts first asks, so two don't ask each other at once)
    nonisolated func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer p: MCPeerID, withContext c: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let handler = invitationHandler
        Task { @MainActor in handler(true, self.session) }
    }
    nonisolated func browser(_ b: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !self.session.connectedPeers.contains(p), self.me.displayName < p.displayName || self.me.displayName == p.displayName && self.me.hash < p.hash else { return }
            b.invitePeer(p, to: self.session, withContext: nil, timeout: 20)
        }
    }
    nonisolated func browser(_ b: MCNearbyServiceBrowser, lostPeer p: MCPeerID) {}
}

// MARK: the page

struct CoopView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("coopName") private var name = ""
    @AppStorage("coopMode") private var mode = 0
    @AppStorage("coopRounds") private var rounds = 10
    @AppStorage("rom") private var rom = 0
    @AppStorage("place") private var place = -1
    @AppStorage("goal") private var goal = 3
    @StateObject private var link = CoopLink(name: UserDefaults.standard.string(forKey: "coopName").flatMap { $0.isEmpty ? nil : $0 } ?? UIDevice.current.name)

    // the game on this device
    @State private var queue: [Card] = []
    @State private var n = 0
    @State private var card: Card?
    @State private var options: [Card] = []
    @State private var typed = ""
    @State private var hints = 0
    @State private var result: Bool?
    @State private var myPoints = 0
    @State private var drawing = PKDrawing()
    @State private var clearN = 0
    @State private var read: [String] = []
    @FocusState private var focused: Bool

    private static let modes = ["八選一", "打字", "手寫"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    players
                    if link.started == nil { lobby } else if let c = card { question(c) } else { done }
                    feed
                }
                .padding()
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .appBackground()
            .navigationTitle(tr("一起玩"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button(tr("完成")) { link.close(); dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { RomButton() }
            }
        }
        .onAppear { link.open() }
        .onDisappear { link.close() }
        .onChange(of: link.game) { begin() }
        .task(id: drawing.strokes.count) {
            guard mode == 2, !drawing.strokes.isEmpty else { read = []; return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            read = await InkReader.read(drawing, langs: store.isSv ? ["sv-SE", "en-US"] : (Simp.on ? ["zh-Hans", "zh-Hant"] : ["zh-Hant", "zh-Hans"]))
        }
    }

    // MARK: parts

    private var players: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tr("隊伍分數")).ffFont(.headline).foregroundStyle(T.glyph)
                Spacer()
                Text("\(link.teamPoints)").scaledFont(28, weight: .bold).foregroundStyle(T.blueInk)
            }
            FlowLayout(spacing: 6) {
                chip(link.me.displayName + tr("（你）"), T.blue)
                ForEach(Array(link.players.values).sorted(), id: \.self) { chip($0, T.green) }
            }
            if link.players.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(tr("找附近的人中…請其他人也打開「一起玩」（同一個 Wi-Fi，或打開藍牙）。")).ffFont(.footnote).foregroundStyle(T.muted)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    private func chip(_ t: String, _ fill: Color) -> some View {
        Text(t).ffFont(.subheadline, .semibold).foregroundStyle(T.glyph)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(fill.opacity(0.7)))
    }

    private var lobby: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("你的名字")).ffFont(.subheadline, .semibold).foregroundStyle(T.muted)
            TextField(UIDevice.current.name, text: $name).textFieldStyle(.roundedBorder)
            Text(tr("（改名字要重新打開「一起玩」才會用上）")).ffFont(.caption2).foregroundStyle(T.muted)
            Picker(tr("怎麼答"), selection: $mode) {
                ForEach(Self.modes.indices, id: \.self) { Text(trs(Self.modes[$0])).tag($0) }
            }
            .pickerStyle(.segmented)
            Stepper(tr("每個人 \(rounds) 題"), value: $rounds, in: 5...30, step: 5)
            Text(tr("每個人的題目都從自己的練習範圍（\(store.practiceName)）出，用自己的語言。答對 +10，用一次提示 −3。"))
                .ffFont(.footnote).foregroundStyle(T.muted)
            Button { link.send(CoopMsg(kind: .start, name: link.me.displayName, mode: mode, rounds: rounds)) } label: {
                Text(tr("開始")).ffFont(.headline).frame(maxWidth: .infinity, minHeight: 34)
            }
            .prominentButton(T.blueEdge)
        }
    }

    private func question(_ c: Card) -> some View {
        let m = link.started?.mode ?? mode
        return VStack(alignment: .leading, spacing: 12) {
            Text(tr("第 \(n + 1)／\(queue.count) 題・你的分數 \(myPoints)")).ffFont(.caption).foregroundStyle(T.muted)
            VStack(alignment: .leading, spacing: 6) {
                if !store.isSv { Text(store.cardRom(c, rom, place)).latFont(24).foregroundStyle(T.greenInk) }
                Text(store.practiceMeaning(c).t).ffFont(.title3).foregroundStyle(T.glyph)
                if hints > 0 {
                    Text(tr("提示：") + String(c.h.prefix(hints)) + String(repeating: "＿", count: max(0, c.h.count - hints)))
                        .scaledFont(22, weight: .semibold).foregroundStyle(T.oliveInk)
                }
            }
            if let r = result {
                VStack(alignment: .leading, spacing: 6) {
                    Label(r ? tr("答對了") : tr("答錯了"), systemImage: r ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(r ? T.greenInk : T.rustInk).ffFont(.headline)
                    Text(c.h).scaledFont(40, weight: .bold).foregroundStyle(T.glyph)
                    Text(store.cardRom(c, rom, place)).latFont(18).foregroundStyle(T.greenInk)
                    Button { next() } label: { Text(n + 1 < queue.count ? tr("下一題") : tr("看結果")).frame(maxWidth: .infinity, minHeight: 30) }
                        .prominentButton(T.blueEdge)
                }
            } else {
                switch m {
                case 0:
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(options, id: \.k) { o in
                            Button { answer(c, o.k == c.k, o.h) } label: {
                                Text(o.h).scaledFont(22, weight: .semibold).foregroundStyle(T.glyph)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(T.fn))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                case 1:
                    HStack {
                        TextField(store.isSv ? tr("打這個詞") : tr("打這個詞的字"), text: $typed)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($focused).submitLabel(.done).onSubmit { check(c, typed) }
                            .scaledFont(22).textFieldStyle(.roundedBorder)
                        Button(tr("確認答案")) { check(c, typed) }.disabled(typed.isEmpty)
                    }
                default:
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.97))
                        InkPad(drawing: $drawing, clear: clearN)
                        Button { clearN += 1; read = [] } label: { Image(systemName: "eraser").padding(10) }
                            .buttonStyle(.plain).foregroundStyle(Color(white: 0.35))
                    }
                    .frame(height: 200)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.fnEdge, lineWidth: 1))
                    HStack(spacing: 8) {
                        ForEach(read, id: \.self) { w in
                            Button { check(c, w) } label: {
                                Text(w).scaledFont(22, weight: .semibold).foregroundStyle(T.glyph)
                                    .padding(.horizontal, 12).padding(.vertical, 4).background(Capsule().fill(T.fn))
                            }
                            .buttonStyle(.plain)
                        }
                        if read.isEmpty { Text(tr("寫好以後點 iOS 認出來的字")).ffFont(.caption).foregroundStyle(T.muted) }
                    }
                }
                HStack {
                    Button(tr("提示（−3）")) { hints += 1 }.disabled(hints >= c.h.count - 1 || m == 0 && hints >= 1)
                    Spacer()
                    Button(tr("不知道")) { answer(c, false, "—") }.foregroundStyle(T.rustInk)
                }
                .ffFont(.subheadline)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("你答完了：\(myPoints) 分")).ffFont(.headline).foregroundStyle(T.glyph)
            let all = link.players.count + 1
            Text(tr("\(link.finished.count)／\(all) 個人答完了")).ffFont(.footnote).foregroundStyle(T.muted)
            Button { link.send(CoopMsg(kind: .start, name: link.me.displayName, mode: mode, rounds: rounds)) } label: {
                Text(tr("再玩一局")).frame(maxWidth: .infinity, minHeight: 30)
            }
            .prominentButton(T.blueEdge)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(link.feed.reversed().prefix(40), id: \.id) { f in
                Text(f.text).ffFont(.footnote)
                    .foregroundStyle(f.good == true ? T.greenInk : (f.good == false ? T.rustInk : T.muted))
            }
        }
    }

    // MARK: the game

    private func begin() {
        guard let s = link.started else { return }
        // (the words due for 複習 first, then the practice scope's)
        var pool = store.dueCards.shuffled() + store.practiceCards.shuffled()
        var seen = Set<String>()
        pool = pool.filter { seen.insert($0.k).inserted && (s.mode != 2 || store.isSv || Store.canWrite($0.h)) }
        queue = Array(pool.prefix(s.rounds))
        n = 0; myPoints = 0
        ask()
    }

    private func ask() {
        guard n < queue.count else {
            card = nil
            if link.started != nil { link.send(CoopMsg(kind: .finished, name: link.me.displayName)) }
            return
        }
        let c = queue[n]
        card = c; hints = 0; result = nil; typed = ""; clearN += 1; read = []
        options = (store.distractors(for: c, count: 7) + [c]).shuffled()
        let prompt = (store.isSv ? "" : String(store.cardRom(c, rom, place).characters) + "　") + store.practiceMeaning(c).t
        link.send(CoopMsg(kind: .asked, name: link.me.displayName, lang: Lang.kind(c.k), text: prompt))
        focused = (link.started?.mode ?? mode) == 1
    }

    private func norm(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.isSv ? t.lowercased() : Simp.convert(t)
    }

    private func check(_ c: Card, _ given: String) {
        guard !given.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        answer(c, norm(given) == norm(c.h), given)
    }

    private func answer(_ c: Card, _ ok: Bool, _ given: String) {
        guard result == nil else { return }
        result = ok
        let pts = ok ? max(1, 10 - 3 * hints) : 0
        myPoints += pts
        _ = store.answer(c, correct: ok, goal: goal)
        link.send(CoopMsg(kind: .answered, name: link.me.displayName, lang: Lang.kind(c.k), text: c.h, right: ok, points: pts))
        focused = false
    }

    private func next() { n += 1; ask() }
}
