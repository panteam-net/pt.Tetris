import UIKit

enum MenuChoice { case solo, shared, host, join }
struct MenuItem {
    let choice: MenuChoice
    let title: String
    let symbol: String
}
protocol MenuViewing: AnyObject { func show(items: [MenuItem], name: String) }
protocol MenuPresenting: AnyObject {
    func load()
    func select(_ choice: MenuChoice, name: String)
}
protocol MenuInteracting: AnyObject {
    var name: String { get }
    var items: [MenuItem] { get }
    func saveName(_ name: String)
}
protocol MenuRouting: AnyObject {
    func game(_ mode: MatchMode)
    func lobby(_ role: NearbyRole, name: String)
}

final class MenuInteractor: MenuInteracting {
    private let defaults: UserDefaults
    private let isPad: Bool
    init(defaults: UserDefaults, isPad: Bool) { self.defaults = defaults; self.isPad = isPad }
    var name: String {
        defaults.string(forKey: "playerName") ?? L10n.text("player.default")
    }
    var items: [MenuItem] {
        var values = [MenuItem(
            choice: .solo,
            title: L10n.text("menu.solo"),
            symbol: "person.fill"
        )]
        if isPad {
            values.append(MenuItem(
                choice: .shared,
                title: L10n.text("menu.shared"),
                symbol: "person.2.fill"
            ))
        }

        values += [
            MenuItem(
                choice: .host,
                title: L10n.text("menu.host"),
                symbol: "wifi"
            ),
            MenuItem(
                choice: .join,
                title: L10n.text("menu.join"),
                symbol: "antenna.radiowaves.left.and.right"
            )
        ]
        return values
    }
    func saveName(_ name: String) {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.utf8.count > 60 { value.removeLast() }
        defaults.set(
            value.isEmpty ? L10n.text("player.default") : value,
            forKey: "playerName"
        )
    }
}

final class MenuPresenter: MenuPresenting {
    weak var view: MenuViewing?
    private let interactor: MenuInteracting
    private let router: MenuRouting
    init(interactor: MenuInteracting, router: MenuRouting) { self.interactor = interactor; self.router = router }
    func load() { view?.show(items: interactor.items, name: interactor.name) }
    func select(_ choice: MenuChoice, name: String) {
        interactor.saveName(name)
        switch choice {
        case .solo: router.game(.solo)
        case .shared:
            guard interactor.items.contains(where: { $0.choice == .shared }) else { return }
            router.game(.sharedDevice)
        case .host: router.lobby(.host, name: interactor.name)
        case .join: router.lobby(.guest, name: interactor.name)
        }
    }
}

final class MenuRouter: MenuRouting {
    weak var navigation: UINavigationController?
    private let gameFactory: (MatchMode) -> UIViewController
    private let lobbyFactory: (NearbyRole, String) -> UIViewController
    init(gameFactory: @escaping (MatchMode) -> UIViewController,
         lobbyFactory: @escaping (NearbyRole, String) -> UIViewController) {
        self.gameFactory = gameFactory; self.lobbyFactory = lobbyFactory
    }
    func game(_ mode: MatchMode) { navigation?.pushViewController(gameFactory(mode), animated: true) }
    func lobby(_ role: NearbyRole, name: String) { navigation?.pushViewController(lobbyFactory(role, name), animated: true) }
}
