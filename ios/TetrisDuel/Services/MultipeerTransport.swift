import Foundation
import MultipeerConnectivity

enum TransportError: Error { case notConnected }

/// Nearby Wi-Fi only. No CoreBluetooth APIs or Bluetooth permission are used.
/// All service state is confined to main; MCSession delegates arrive on a
/// private framework queue and are explicitly marshalled to main.
final class MultipeerTransport: NSObject, NearbyTransport {
    private static let serviceType = "tetris-duel"
    private let identity: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var discovered: [String: MCPeerID] = [:]
    private var candidate: MCPeerID?
    private var connectedPeer: MCPeerID?
    private var invitationPending = false
    private var closed = false
    private var role: NearbyRole?
    private var connectionTimeout: DispatchWorkItem?
    var onEvent: ((NearbyEvent) -> Void)?
    var onMessage: ((WireMessage) -> Void)?
    var isConnected: Bool { connectedPeer != nil && !closed }

    init(displayName: String) {
        var name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.utf8.count > 60 { name.removeLast() }
        identity = MCPeerID(
            displayName: name.isEmpty ? L10n.text("player.nearbyDefault") : name
        )
        super.init()
        session = MCSession(
            peer: identity,
            securityIdentity: nil,
            encryptionPreference: .required)
        session.delegate = self
    }

    func host() {
        guard !closed else { return }
        role = .host
        let service = MCNearbyServiceAdvertiser(
            peer: identity,
            discoveryInfo: ["version": String(WireCodec.version)],
            serviceType: Self.serviceType)
        advertiser = service
        service.delegate = self
        service.startAdvertisingPeer()
        onEvent?(.status(L10n.text("nearby.status.waiting")))
    }

    func browse() {
        guard !closed else { return }
        role = .guest
        let service = MCNearbyServiceBrowser(peer: identity, serviceType: Self.serviceType)
        browser = service; service.delegate = self; service.startBrowsingForPeers()
        onEvent?(.status(L10n.text("nearby.status.searching")))
    }

    func invite(_ peer: NearbyPeer) {
        guard !closed, candidate == nil, connectedPeer == nil, let remote = discovered[peer.id] else { return }
        candidate = remote
        browser?.stopBrowsingForPeers()
        browser?.invitePeer(remote, to: session, withContext: Data([WireCodec.version]), timeout: 20)
        onEvent?(.status(L10n.format(
            "nearby.status.invitation",
            remote.displayName
        )))
        scheduleTimeout()
    }

    private func scheduleTimeout() {
        connectionTimeout?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isConnected, !self.closed else { return }
            self.disconnect()
            self.onEvent?(.failure(L10n.text("nearby.error.invitation")))
        }
        connectionTimeout = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 22, execute: task)
    }

    func send(_ message: WireMessage) throws {
        guard !closed, let peer = connectedPeer else { throw TransportError.notConnected }
        let data = try WireCodec.encode(message)
        let delivery: MCSessionSendDataMode
        if case .snapshot(let state) = message, state.phase == .playing { delivery = .unreliable }
        else { delivery = .reliable }
        try session.send(data, toPeers: [peer], with: delivery)
    }

    func disconnect() {
        guard !closed else { return }
        closed = true
        connectionTimeout?.cancel(); connectionTimeout = nil
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        advertiser?.delegate = nil; browser?.delegate = nil
        session.delegate = nil; session.disconnect()
        candidate = nil; connectedPeer = nil; discovered.removeAll()
    }

    private func emitPeers() {
        onEvent?(.peers(discovered.map { NearbyPeer(id: $0.key, name: $0.value.displayName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }))
    }

    private func connectionChanged(_ peer: MCPeerID, state: MCSessionState) {
        guard !closed else { return }
        switch state {
        case .connected:
            guard peer == candidate, connectedPeer == nil || connectedPeer == peer else {
                disconnect()
                onEvent?(.failure(L10n.text("nearby.error.extraPeer")))
                return
            }

            connectedPeer = peer
            connectionTimeout?.cancel(); connectionTimeout = nil
            advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
            onEvent?(.connected(name: peer.displayName))
        case .notConnected:
            guard peer == candidate || peer == connectedPeer else { return }
            disconnect()
            onEvent?(.disconnected(L10n.text("nearby.error.disconnected")))
        case .connecting:
            onEvent?(.status(L10n.text("nearby.status.connecting")))
        @unknown default: break
        }
    }

    deinit {
        connectionTimeout?.cancel()
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers()
        session?.disconnect()
    }
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(.failure(L10n.format(
                "nearby.error.host",
                error.localizedDescription
            )))
        }
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.closed, self.role == .host,
                  self.connectedPeer == nil, self.candidate == nil, !self.invitationPending,
                  context == Data([WireCodec.version]) else { invitationHandler(false, nil); return }
            self.invitationPending = true
            var answered = false
            let answer: (Bool) -> Void = { [weak self] accepted in
                guard !answered else { return }
                answered = true
                guard let self = self, !self.closed else { invitationHandler(false, nil); return }
                self.invitationPending = false
                if accepted {
                    self.candidate = peerID
                    self.advertiser?.stopAdvertisingPeer()
                    self.scheduleTimeout()
                }
                invitationHandler(accepted, accepted ? self.session : nil)
            }
            self.onEvent?(.invitation(name: peerID.displayName, answer: answer))
            DispatchQueue.main.asyncAfter(deadline: .now() + 18) { answer(false) }
        }
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.closed, info?["version"] == String(WireCodec.version) else { return }
            // MCPeerID equality is authoritative; display names are not identifiers.
            if !self.discovered.values.contains(peerID) { self.discovered[UUID().uuidString] = peerID }
            self.emitPeers()
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.discovered = self.discovered.filter { $0.value != peerID }
            self.emitPeers()
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(.failure(L10n.format(
                "nearby.error.search",
                error.localizedDescription
            )))
        }
    }
}

extension MultipeerTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in self?.connectionChanged(peerID, state: state) }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard data.count <= WireCodec.maxPayload else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.closed, peerID == self.connectedPeer else { return }
            do { self.onMessage?(try WireCodec.decode(data)) }
            catch {
                self.disconnect()
                self.onEvent?(.failure(L10n.text("nearby.error.incompatible")))
            }
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close()
    }
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) { progress.cancel() }
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
