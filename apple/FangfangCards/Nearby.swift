import SwiftUI
import MultipeerConnectivity

// MARK: - the people nearby (一起玩, 詞龍): the same Wi-Fi, or Bluetooth (MultipeerConnectivity, encrypted)
//
// Everyone on the game's page both looks for the others and can be found; the one whose name sorts first asks,
// so two don't ask each other at the same time. Each game has its own service (its own lobby) and its own
// messages (JSON): a game's link is a subclass that reads them (received), and hears who joined and left.
// (Over the internet: later, see docs/PENDING-other-versions.md.)

@MainActor
class NearbyLink: NSObject, ObservableObject {
    let me: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    /// the others connected now, by their names
    @Published var players: [MCPeerID: String] = [:]

    var myName: String { me.displayName }
    /// everyone here (me and the ones connected)
    var everyone: Set<String> { Set([myName] + Array(players.values)) }

    /// `service`: the game's own (1–15 letters, digits and "-"; listed in Info.plist's NSBonjourServices)
    init(name: String, service: String) {
        me = MCPeerID(displayName: String(name.prefix(40)))
        session = MCSession(peer: me, securityIdentity: nil, encryptionPreference: .required)
        advertiser = MCNearbyServiceAdvertiser(peer: me, discoveryInfo: nil, serviceType: service)
        browser = MCNearbyServiceBrowser(peer: me, serviceType: service)
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

    /// to everyone else (the sender handles its own message itself)
    func sendData(_ d: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        try? session.send(d, toPeers: session.connectedPeers, with: .reliable)
    }

    // (for the games)
    func received(_ d: Data) {}
    func joined(_ name: String) {}
    func left(_ name: String) {}
}

extension NearbyLink: MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    nonisolated func session(_ s: MCSession, peer p: MCPeerID, didChange state: MCSessionState) {
        let name = p.displayName
        Task { @MainActor in
            if state == .connected { self.players[p] = name; self.joined(name) }
            else if state == .notConnected, self.players[p] != nil { self.players[p] = nil; self.left(name) }
        }
    }
    nonisolated func session(_ s: MCSession, didReceive data: Data, fromPeer p: MCPeerID) {
        Task { @MainActor in self.received(data) }
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
