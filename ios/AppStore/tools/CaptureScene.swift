import UIKit

// A standalone, simulator-only capture host. It links the app's production
// views, presenter, localization and engine; it is not part of the app target.
@main
final class CaptureAppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Capture", sessionRole: session.role)
        configuration.delegateClass = CaptureSceneDelegate.self
        return configuration
    }
}

final class CaptureSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let navigation = UINavigationController()
    private var interactor: CaptureGameInteractor?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) {
        guard let scene = scene as? UIWindowScene else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Theme.background
        appearance.titleTextAttributes = [.foregroundColor: Theme.text]
        appearance.shadowColor = .clear
        navigation.navigationBar.standardAppearance = appearance
        navigation.navigationBar.scrollEdgeAppearance = appearance
        navigation.navigationBar.compactAppearance = appearance
        navigation.navigationBar.tintColor = Theme.mint

        let menuRouter = MenuRouter(
            gameFactory: { [unowned self] in self.game(mode: $0, scene: "solo") },
            lobbyFactory: { [unowned self] _, _ in self.game(mode: .nearbyHost, scene: "nearby") }
        )
        menuRouter.navigation = navigation
        let menuPresenter = MenuPresenter(
            interactor: MenuInteractor(defaults: .standard, isPad: UIDevice.current.userInterfaceIdiom == .pad),
            router: menuRouter
        )
        let menu = MenuViewController(presenter: menuPresenter)
        menuPresenter.view = menu

        let arguments = ProcessInfo.processInfo.arguments
        let captureScene = arguments.firstIndex(of: "--scene").flatMap {
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        } ?? "solo"
        if captureScene == "menu" {
            navigation.setViewControllers([menu], animated: false)
        } else {
            let mode: MatchMode = captureScene == "duel" ? .sharedDevice
                : (captureScene == "nearby" ? .nearbyHost : .solo)
            navigation.setViewControllers([menu, game(mode: mode, scene: captureScene)], animated: false)
        }

        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = navigation
        self.window = window
        window.makeKeyAndVisible()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.markReady(scene: captureScene)
        }
    }

    private func game(mode: MatchMode, scene: String) -> UIViewController {
        let interactor = CaptureGameInteractor(mode: mode, scene: scene)
        self.interactor = interactor
        let router = GameRouter()
        router.navigation = navigation
        let presenter = GamePresenter(interactor: interactor, router: router)
        let controller = GameViewController(presenter: presenter, mode: mode)
        presenter.view = controller
        interactor.output = presenter
        return controller
    }

    private func markReady(scene: String) {
        guard let window = window else { return }
        window.layoutIfNeeded()
        var regions: [[String: Any]] = []
        func visit(_ view: UIView) {
            if view is CubeBoardView || view is TouchControls || view is PlayerPanel {
                let frame = view.convert(view.bounds, to: window)
                regions.append([
                    "type": String(describing: type(of: view)),
                    "x": frame.minX, "y": frame.minY,
                    "width": frame.width, "height": frame.height
                ])
            }
            view.subviews.forEach(visit)
        }
        visit(window)
        var metadata: [String: Any] = [
            "scene": scene, "scale": window.screen.scale,
            "width": window.bounds.width, "height": window.bounds.height,
            "regions": regions
        ]
        if let snapshot = interactor?.snapshot {
            metadata["elapsed"] = snapshot.elapsed
            metadata["boards"] = snapshot.boards.map {
                ["score": $0.score, "lines": $0.lines, "level": $0.level, "sent": $0.sent, "incoming": $0.incoming]
            }
        }
        let destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("capture.json")
        do {
            try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
                .write(to: destination, options: .atomic)
        } catch {
            fatalError("Unable to mark capture ready: \(error)")
        }
    }
}

final class CaptureGameInteractor: GameInteracting {
    weak var output: GameInteractorOutput?
    let configuration: GameConfiguration
    var feedbackEnabled = true
    private(set) var snapshot: MatchSnapshot

    init(mode: MatchMode, scene: String) {
        configuration = GameConfiguration(mode: mode, opponent: "Alex")
        snapshot = CaptureReplay.snapshot(mode: mode, scene: scene)
    }
    func start() { output?.gameUpdated(snapshot, notice: nil) }
    func input(_ action: GameAction, seat: Int, pressed: Bool) {}
    func setPaused(_ paused: Bool) {
        snapshot.phase = paused ? .paused : .playing
        start()
    }
    func requestRematch() {}
    func toggleFeedback() { feedbackEnabled.toggle(); start() }
    func setAvailable(_ available: Bool) {}
    func stop() {}
}

// All scores, levels, previews, garbage and grid cells come from legal engine
// actions. A fixed seed and virtual time make every localized capture repeatable.
private enum CaptureReplay {
    private struct Placement {
        let rotation: Int
        let x: Int
        let cost: Double
    }

    static func snapshot(mode: MatchMode, scene: String) -> MatchSnapshot {
        let seed: UInt64 = scene == "strategy" ? 0xC0FFEE : 0xD0E1
        let match = Match(seed: seed, players: mode.playerCount)
        var random = SeededRandom(seed: seed ^ 0xA551)
        let rounds = scene == "speed" ? 150 : (scene == "strategy" ? 64 : 44)
        match.boards.forEach { _ = $0.hold() }
        for round in 0..<rounds {
            for (seat, board) in match.boards.enumerated() {
                guard board.alive, let move = placement(board, random: &random) else {
                    preconditionFailure("Capture replay topped out at round \(round)")
                }
                for _ in 0..<((move.rotation - board.piece.rotation + 4) % 4) { _ = board.rotate() }
                while board.piece.x != move.x {
                    guard board.move(board.piece.x < move.x ? 1 : -1) else {
                        preconditionFailure("Unreachable capture placement")
                    }
                }
                match.action(.hardDrop, player: seat)
                match.tick(0.05, softDrop: [])
            }
            for _ in 0..<18 { match.tick(0.05, softDrop: []) }
        }
        // Leave the falling piece visible above its real landing outline.
        for _ in 0..<28 { match.tick(0.05, softDrop: []) }
        precondition(!match.finished, "Capture requires a playing match")
        return MatchSnapshot(
            round: 1, revision: 1, phase: .playing, countdown: 0,
            elapsed: match.elapsed, boards: match.boards.map(\.snapshot),
            wins: [0, 0], winner: nil
        )
    }

    private static func placement(_ board: Board, random: inout SeededRandom) -> Placement? {
        var candidates: [Placement] = []
        for rotation in 0..<4 {
            for x in -3..<Rules.width {
                var piece = Piece(board.piece.kind, x: x, y: board.piece.y, rotation: rotation)
                func valid(_ piece: Piece) -> Bool {
                    piece.cells().allSatisfy {
                        (0..<Rules.width).contains($0.x) && (0..<Rules.height).contains($0.y)
                            && board.grid[$0.y * Rules.width + $0.x] == 0
                    }
                }
                guard valid(piece) else { continue }
                while valid(Piece(piece.kind, x: x, y: piece.y + 1, rotation: rotation)) { piece.y += 1 }
                var grid = board.grid
                piece.cells().forEach { grid[$0.y * Rules.width + $0.x] = piece.kind.rawValue }
                let rows = stride(from: 0, to: grid.count, by: Rules.width).map {
                    Array(grid[$0..<($0 + Rules.width)])
                }
                let remaining = rows.filter { $0.contains(0) }
                let cleared = Rules.height - remaining.count
                grid = Array(repeating: 0, count: cleared * Rules.width) + remaining.flatMap { $0 }
                var holes = 0
                let heights = (0..<Rules.width).map { column -> Int in
                    var first = Rules.height
                    for row in 0..<Rules.height {
                        if grid[row * Rules.width + column] != 0 { first = min(first, row) }
                        else if first < row { holes += 1 }
                    }
                    return Rules.height - first
                }
                let bumpiness = zip(heights, heights.dropFirst()).reduce(0) { $0 + abs($1.0 - $1.1) }
                let tallest = heights.max() ?? 0
                let variation = Double(random.index(1000)) / 1000 * 3.2
                let cost = Double(heights.reduce(0, +)) * 0.48 + Double(holes) * 6
                    + Double(bumpiness) * 0.5 + Double(max(0, tallest - 10)) * 5
                    - Double(cleared) * 4 + variation
                candidates.append(Placement(rotation: rotation, x: x, cost: cost))
            }
        }
        return candidates.min { $0.cost < $1.cost }
    }
}
