import UIKit

/// Composition root. Constructors receive explicit protocol dependencies;
/// no module resolves services from a singleton or a global service locator.
final class AppContainer {
    private let defaults: UserDefaults
    private let seeds: SeedProviding
    private let clockFactory: () -> GameClock
    private let transportFactory: (String) -> NearbyTransport
    private let feedback: FeedbackServing
    private let navigation = UINavigationController()

    init(defaults: UserDefaults, seeds: SeedProviding, clockFactory: @escaping () -> GameClock,
         transportFactory: @escaping (String) -> NearbyTransport) {
        self.defaults = defaults; self.seeds = seeds; self.clockFactory = clockFactory
        self.transportFactory = transportFactory
        feedback = FeedbackService(defaults: defaults)
    }

    func makeRoot() -> UIViewController {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground(); appearance.backgroundColor = Theme.background
        appearance.titleTextAttributes = [.foregroundColor: Theme.text]
        appearance.shadowColor = .clear
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.compactAppearance = appearance
        navigation.navigationBar.tintColor = Theme.mint
        let router = MenuRouter(gameFactory: { [unowned self] in self.makeGame(mode: $0) },
                                lobbyFactory: { [unowned self] in self.makeLobby(role: $0, name: $1) })
        router.navigation = navigation
        let interactor = MenuInteractor(defaults: defaults, isPad: UIDevice.current.userInterfaceIdiom == .pad)
        let presenter = MenuPresenter(interactor: interactor, router: router)
        let view = MenuViewController(presenter: presenter)
        presenter.view = view
        navigation.setViewControllers([view], animated: false)
        return navigation
    }

    private func makeGame(mode: MatchMode, name: String? = nil, transport: NearbyTransport? = nil) -> UIViewController {
        let router = GameRouter(); router.navigation = navigation
        let interactor = GameInteractor(configuration: GameConfiguration(mode: mode, opponent: name),
                                        clock: clockFactory(), transport: transport, feedback: feedback, seeds: seeds)
        let presenter = GamePresenter(interactor: interactor, router: router)
        let view = GameViewController(presenter: presenter, mode: mode)
        presenter.view = view; interactor.output = presenter
        return view
    }

    private func makeLobby(role: NearbyRole, name: String) -> UIViewController {
        let router = LobbyRouter { [unowned self] mode, opponent, transport in
            self.makeGame(mode: mode, name: opponent, transport: transport)
        }
        router.navigation = navigation
        let interactor = LobbyInteractor(role: role, transport: transportFactory(name))
        let presenter = LobbyPresenter(interactor: interactor, router: router, role: role)
        let view = LobbyViewController(presenter: presenter, role: role, name: name)
        presenter.view = view; interactor.output = presenter
        return view
    }
}
