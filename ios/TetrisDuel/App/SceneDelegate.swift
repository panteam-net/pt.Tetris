import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var container: AppContainer?
    
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let container = AppContainer(
            defaults: .standard,
            seeds: SystemSeedProvider(),
            clockFactory: { DisplayLinkClock() },
            transportFactory: { MultipeerTransport(displayName: $0) })
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = container.makeRoot()
        self.window = window; self.container = container
        window.makeKeyAndVisible()
    }
}
