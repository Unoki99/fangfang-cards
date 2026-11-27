import SwiftUI
import MultipeerConnectivity
import CryptoKit

// MARK: - the people playing together (一起玩, 詞龍): nearby, or over the internet
//
// 附近: the same Wi-Fi, or Bluetooth (MultipeerConnectivity, encrypted). Everyone on the game's page both looks for
// the others and can be found; the one whose name sorts first asks, so two don't ask each other at the same time.
// 網路: a room on the relay (the project's relay folder: a small server on your own free Cloudflare account,
// 設定 → 一起玩 → 連線伺服器), the same as the Android and computer versions', so all of them play together. The room's
// name on the relay is a hash of the room code, and every message is encrypted with a key made from the code
// (AES-GCM: base64 of nonce + ciphertext + tag), so the relay passes on bytes it can't read. Each message is an
// envelope {"n": the sender's name, "h": 1 for "I'm here", "d": the game's own JSON}.
// Each game has its own service (its own lobby) and its own messages (JSON): a game's link is a subclass that reads
// them (received), and hears who joined and left.

enum RoomCrypto {
    private static let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static func norm(_ code: String) -> String { String(code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }) }
    private static func sha256(_ s: String) -> Data { Data(SHA256.hash(data: Data(s.utf8))) }
    /// the room's name on the relay (the code never leaves the app)
    static func roomId(_ code: String) -> String { String(sha256("fangfang-room:" + norm(code)).map { String(format: "%02x", $0) }.joined().prefix(32)) }
    static func key(_ code: String) -> SymmetricKey { SymmetricKey(data: sha256("fangfang-key:" + norm(code))) }
    /// a new room code: 8 letters and digits that can't be mixed up (XXXX-XXXX)
    static func newCode() -> String {
        let s = String((0..<8).map { _ in letters.randomElement()! })
        return String(s.prefix(4)) + "-" + String(s.suffix(4))
    }
    static func seal(_ key: SymmetricKey, _ plain: Data) -> String? {
        guard let box = try? AES.GCM.seal(plain, using: key), let c = box.combined else { return nil }
        return c.base64EncodedString()
    }
    static func open(_ key: SymmetricKey, _ b64: String) -> Data? {
        guard let d = Data(base64Encoded: b64), let box = try? AES.GCM.SealedBox(combined: d) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }
}

@MainActor
class NearbyLink: NSObject, ObservableObject {
    enum Via: Int { case nearby, internet }
    /// how the players are found (chosen before going in)
    @Published private(set) var via: Via = .nearby
    let myName: String
    /// the others connected now: an id (the device nearby, or the relay's) → their name
    @Published var players: [String: String] = [:]
    /// 網路: 0 not in a room, 1 connecting, 2 in the room, 3 failed
    @Published var status = 0
    @Published var error: String?
    @Published var code = ""

    /// everyone here (me and the ones connected)
    var everyone: Set<String> { Set([myName] + Array(players.values)) }
    var connected: Bool { via == .nearby ? true : status == 2 }

    // 附近
    private let me: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private var nearbyOn = false
    // 網路
    private var task: URLSessionWebSocketTask?
    private var key: SymmetricKey?
    private var pinger: Timer?

    /// `service`: the game's own (1–15 letters, digits and "-"; listed in Info.plist's NSBonjourServices)
    init(name: String, service: String) {
        myName = String(name.prefix(40))
        me = MCPeerID(displayName: myName)
        session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: service)
        browser = MCNearbyServiceBrowser(peer: me, serviceType: service)
        super.init()
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
    }

    /// 附近: look for the others and be found
    func open() {
        closeRoom()
        via = .nearby
        guard !nearbyOn else { return }
        nearbyOn = true
        advertiser.startAdvertisingPeer(); browser.startBrowsingForPeers()
    }

    /// 網路: into the room `code` on the relay at `server` (https://…workers.dev)
    func openRoom(server: String, code: String) {
        closeNearby()
        closeRoom()
        via = .internet
        let s = server.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if s.isEmpty { status = 3; error = tr("還沒有連線伺服器：設定 → 一起玩 → 連線伺服器。"); return }
        if RoomCrypto.norm(code).count < 6 { status = 3; error = tr("房間代碼太短了。"); return }
        let ws: String
        if s.hasPrefix("https://") { ws = "wss://" + s.dropFirst(8) }
        else if s.hasPrefix("http://") { ws = "ws://" + s.dropFirst(7) }
        else if s.hasPrefix("ws") { ws = s } else { ws = "wss://" + s }
        guard let url = URL(string: ws + "/room/" + RoomCrypto.roomId(code)) else { status = 3; error = tr("連線伺服器的網址不對。"); return }
        self.code = code
        key = RoomCrypto.key(code)
        status = 1; error = nil
        let t = URLSession.shared.webSocketTask(with: url)
        task = t
        t.resume()
        listen(t)
        pinger = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.task?.sendPing { _ in } }
        }
    }

    func close() { closeNearby(); closeRoom() }

    private func closeNearby() {
        guard nearbyOn else { return }
        nearbyOn = false
        advertiser.stopAdvertisingPeer(); browser.stopBrowsingForPeers(); session.disconnect()
        dropAll()
    }

    private func closeRoom() {
        pinger?.invalidate(); pinger = nil
        if let t = task { t.cancel(with: .normalClosure, reason: nil); task = nil; dropAll() }
        status = 0
    }

    private func dropAll() {
        let gone = Array(players.values)
        players = [:]
        for n in gone { left(n) }
    }

    /// to everyone else (the sender handles its own message itself)
    func sendData(_ d: Data) {
        if via == .internet { envelope(String(decoding: d, as: UTF8.self), hello: false); return }
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(d, toPeers: session.connectedPeers, with: .reliable)
    }

    // (for the games)
    func received(_ d: Data) {}
    func joined(_ name: String) {}
    func left(_ name: String) {}

    // MARK: 網路

    private func envelope(_ d: String, hello: Bool) {
        guard let k = key, let t = task,
              let plain = try? JSONSerialization.data(withJSONObject: ["n": myName, "h": hello ? 1 : 0, "d": d] as [String: Any]),
              let sealed = RoomCrypto.seal(k, plain) else { return }
        t.send(.string(sealed)) { _ in }
    }

    private func listen(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] r in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch r {
                case .success(let m):
                    switch m {
                    case .string(let s): self.frame(s)
                    case .data(let d): self.frame(String(decoding: d, as: UTF8.self))
                    @unknown default: break
                    }
                    self.listen(t)
                case .failure(let e):
                    self.status = 3
                    self.error = tr("連不上伺服器：") + e.localizedDescription
                    self.pinger?.invalidate(); self.pinger = nil
                    self.task = nil
                    self.dropAll()
                }
            }
        }
    }

    private func frame(_ text: String) {
        guard let o = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] else { return }
        switch o["sys"] as? String {
        case "welcome": status = 2; envelope("", hello: true)
        case "join": envelope("", hello: true)
        case "leave":
            if let id = o["id"] as? String, let n = players.removeValue(forKey: id) { left(n) }
        case "msg":
            guard let id = o["from"] as? String, let k = key, let data = o["data"] as? String, let plain = RoomCrypto.open(k, data),
                  let e = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any],
                  let name = e["n"] as? String, !name.isEmpty else { return }
            if players[id] != name { players[id] = name; joined(name) }
            if (e["h"] as? Int ?? 0) == 1 { return }
            if let d = e["d"] as? String { received(Data(d.utf8)) }
        default: break
        }
    }
}

extension NearbyLink: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated private static func id(_ p: MCPeerID) -> String { "mc\(p.hash)" }

    nonisolated func session(_ s: MCSession, peer p: MCPeerID, didChange state: MCSessionState) {
        let name = p.displayName, id = Self.id(p)
        Task { @MainActor in
            guard self.via == .nearby else { return }
            if state == .connected { self.players[id] = name; self.joined(name) }
            else if state == .notConnected, self.players[id] != nil { self.players[id] = nil; self.left(name) }
        }
    }
    nonisolated func session(_ s: MCSession, didReceive data: Data, fromPeer p: MCPeerID) {
        Task { @MainActor in if self.via == .nearby { self.received(data) } }
    }
    nonisolated func session(_ s: MCSession, didReceive stream: InputStream, withName n: String, fromPeer p: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName n: String, fromPeer p: MCPeerID, with progress: Foundation.Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName n: String, fromPeer p: MCPeerID, at u: URL?, withError e: Error?) {}

    nonisolated func advertiser(_ a: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer p: MCPeerID, withContext c: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        let handler = invitationHandler
        Task { @MainActor in handler(true, self.session) }
    }
    nonisolated func browser(_ b: MCNearbyServiceBrowser, foundPeer p: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard !self.session.connectedPeers.contains(p),
                  self.me.displayName < p.displayName || (self.me.displayName == p.displayName && self.me.hash < p.hash) else { return }
            b.invitePeer(p, to: self.session, withContext: nil, timeout: 20)
        }
    }
    nonisolated func browser(_ b: MCNearbyServiceBrowser, lostPeer p: MCPeerID) {}
}

// MARK: - 附近 or 網路, and the room

/// the way to find the others (附近 / 網路), and, over the internet, the room code; who's here is the game's own
struct RoomBar: View {
    @ObservedObject var link: NearbyLink
    /// a game is on: the way can't be changed
    var locked = false
    @AppStorage("relayServer") private var server = ""
    @AppStorage("coopVia") private var via = 0
    @State private var code = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $via) {
                Text(tr("附近的人")).tag(0)
                Text(tr("透過網路")).tag(1)
            }
            .pickerStyle(.segmented)
            .disabled(locked)
            if via == 1 {
                if link.status == 2 {
                    HStack(spacing: 8) {
                        Text(tr("房間")).ffFont(.caption).foregroundStyle(T.muted)
                        Text(link.code).latFont(18).foregroundStyle(T.glyph).textSelection(.enabled)
                        Spacer()
                        if !locked { Button(tr("離開房間"), role: .destructive) { link.close() } }
                    }
                    Text(tr("請其他人在「一起玩」輸入同一個代碼。訊息在 App 裡就加密了，伺服器看不懂。")).ffFont(.caption).foregroundStyle(T.muted)
                } else {
                    Text(tr("用同一個房間代碼和別人連線（透過網路；iPhone、Android、電腦都可以一起玩）。")).ffFont(.footnote).foregroundStyle(T.muted)
                    TextField(tr("房間代碼，例如 KX7P-2MQA"), text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .latFont(18).textFieldStyle(.roundedBorder)
                        .onSubmit { link.openRoom(server: server, code: code) }
                    HStack(spacing: 10) {
                        Button { code = RoomCrypto.newCode(); link.openRoom(server: server, code: code) } label: {
                            Text(tr("開一個新房間")).frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .buttonStyle(.bordered)
                        Button { link.openRoom(server: server, code: code) } label: {
                            Text(link.status == 1 ? tr("連線中…") : tr("進房間")).frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .prominentButton(T.blueEdge)
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || link.status == 1)
                    }
                    if let e = link.error { Text(e).ffFont(.footnote).foregroundStyle(T.rustInk) }
                    if server.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(tr("還沒有連線伺服器：設定 → 一起玩 → 連線伺服器（專案的 relay 資料夾說明怎麼免費放一個）。")).ffFont(.caption).foregroundStyle(T.muted)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.fn.opacity(0.55)))
        .onAppear { if code.isEmpty { code = link.code }; apply() }
        .onChange(of: via) { apply() }
    }

    /// 附近: looking at once; 網路: once a room is chosen
    private func apply() {
        if via == 0 { link.open() }
        else if link.via == .nearby { link.close() }
    }
}

/// 設定 → 一起玩
struct CoopSettingsSection: View {
    @AppStorage("relayServer") private var server = ""
    @AppStorage("coopName") private var name = ""
    var body: some View {
        Section {
            TextField(UIDevice.current.name, text: $name)
            TextField(tr("連線伺服器，例如 https://fangfang-relay.你的帳號.workers.dev"), text: $server)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        } header: {
            Text(tr("一起玩"))
        } footer: {
            Text(tr("在不同地方的人透過網路一起玩（一起玩、詞龍）：用專案 relay 資料夾裡的說明，免費放一個自己的連線伺服器，再把網址貼在這裡。一起玩的每個人都要填同一個網址。訊息在 App 裡用房間代碼加密，伺服器只轉送、看不懂內容。"))
        }
    }
}
