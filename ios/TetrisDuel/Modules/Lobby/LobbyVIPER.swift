import UIKit

protocol LobbyViewing: AnyObject {
    func showStatus(_ text: String, failed: Bool)
    func showPeers(_ peers: [NearbyPeer])
    func showInvitation(name: String, answer: @escaping (Bool) -> Void)
}
protocol LobbyPresenting: AnyObject {
    func load()
    func select(_ peer: NearbyPeer)
    func leave()
}
protocol LobbyInteracting: AnyObject {
    var output: LobbyInteractorOutput? { get set }
    func start()
    func invite(_ peer: NearbyPeer)
    func stop()
}
protocol LobbyInteractorOutput: AnyObject {
    func lobbyEvent(_ event: NearbyEvent)
    func lobbyConnected(name: String, transport: NearbyTransport)
}
protocol LobbyRouting: AnyObject {
    func game(mode: MatchMode, name: String, transport: NearbyTransport)
}

final class LobbyInteractor: LobbyInteracting {
    weak var output: LobbyInteractorOutput?
    private let role: NearbyRole
    private let transport: NearbyTransport
    private var handedOff = false
    init(role: NearbyRole, transport: NearbyTransport) { self.role = role; self.transport = transport }
    func start() {
        transport.onEvent = { [weak self] event in
            guard let self = self, !self.handedOff else { return }
            if case .connected(let name) = event {
                self.handedOff = true
                self.output?.lobbyConnected(name: name, transport: self.transport)
            } else { self.output?.lobbyEvent(event) }
        }
        if role == .host { transport.host() } else { transport.browse() }
    }
    func invite(_ peer: NearbyPeer) { transport.invite(peer) }
    func stop() { if !handedOff { transport.disconnect(); transport.onEvent = nil } }
    deinit { if !handedOff { transport.disconnect() } }
}

final class LobbyPresenter: LobbyPresenting, LobbyInteractorOutput {
    weak var view: LobbyViewing?
    private let interactor: LobbyInteracting
    private let router: LobbyRouting
    private let role: NearbyRole
    init(interactor: LobbyInteracting, router: LobbyRouting, role: NearbyRole) {
        self.interactor = interactor; self.router = router; self.role = role
    }
    func load() { interactor.start() }
    func select(_ peer: NearbyPeer) { interactor.invite(peer) }
    func leave() { interactor.stop() }
    func lobbyEvent(_ event: NearbyEvent) {
        switch event {
        case .status(let text): view?.showStatus(text, failed: false)
        case .failure(let text), .disconnected(let text): view?.showStatus(text, failed: true)
        case .peers(let peers): view?.showPeers(peers)
        case .invitation(let name, let answer): view?.showInvitation(name: name, answer: answer)
        case .connected: break
        }
    }
    func lobbyConnected(name: String, transport: NearbyTransport) {
        router.game(mode: role == .host ? .nearbyHost : .nearbyGuest, name: name, transport: transport)
    }
}

final class LobbyRouter: LobbyRouting {
    weak var navigation: UINavigationController?
    private let factory: (MatchMode, String, NearbyTransport) -> UIViewController
    init(factory: @escaping (MatchMode, String, NearbyTransport) -> UIViewController) { self.factory = factory }
    func game(mode: MatchMode, name: String, transport: NearbyTransport) {
        guard let navigation = navigation, let root = navigation.viewControllers.first else { return }
        navigation.presentedViewController?.dismiss(animated: false)
        navigation.setViewControllers([root, factory(mode, name, transport)], animated: true)
    }
}
