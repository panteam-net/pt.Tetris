import UIKit

final class GameRouter: GameRouting {
    weak var navigation: UINavigationController?
    func closeGame() { navigation?.popToRootViewController(animated: true) }
}
