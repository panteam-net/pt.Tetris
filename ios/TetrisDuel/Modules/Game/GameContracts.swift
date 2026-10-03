import Foundation

struct GameConfiguration {
    let mode: MatchMode
    let opponent: String?
}

struct GameViewModel {
    let snapshot: MatchSnapshot
    let mode: MatchMode
    let title: String
    let overlayTitle: String?
    let overlayDetail: String
    let primaryTitle: String?
    let soundEnabled: Bool
    let opponentName: String
}

protocol GameViewing: AnyObject {
    func render(_ model: GameViewModel)
    func showHelp()
}

protocol GamePresenting: AnyObject {
    func load()
    func input(_ action: GameAction, seat: Int, pressed: Bool)
    func pause()
    func primaryAction()
    func help()
    func toggleFeedback()
    func setAvailable(_ available: Bool)
    func exit()
}

protocol GameInteracting: AnyObject {
    var output: GameInteractorOutput? { get set }
    var configuration: GameConfiguration { get }
    var feedbackEnabled: Bool { get }
    func start()
    func input(_ action: GameAction, seat: Int, pressed: Bool)
    func setPaused(_ paused: Bool)
    func requestRematch()
    func toggleFeedback()
    func setAvailable(_ available: Bool)
    func stop()
}

protocol GameInteractorOutput: AnyObject {
    func gameUpdated(_ snapshot: MatchSnapshot, notice: String?)
}

protocol GameRouting: AnyObject { func closeGame() }
