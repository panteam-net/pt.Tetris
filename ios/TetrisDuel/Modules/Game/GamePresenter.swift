import Foundation

final class GamePresenter: GamePresenting, GameInteractorOutput {
    weak var view: GameViewing?
    private let interactor: GameInteracting
    private let router: GameRouting
    private var phase: MatchPhase = .waiting

    init(interactor: GameInteracting, router: GameRouting) {
        self.interactor = interactor; self.router = router
    }
    func load() { interactor.start() }
    func input(_ action: GameAction, seat: Int, pressed: Bool) { interactor.input(action, seat: seat, pressed: pressed) }
    func pause() { interactor.setPaused(phase != .paused) }
    func primaryAction() {
        switch phase {
        case .paused: interactor.setPaused(false)
        case .finished: interactor.requestRematch()
        case .disconnected: exit(); router.closeGame()
        default: break
        }
    }
    func help() { interactor.setPaused(true); view?.showHelp() }
    func toggleFeedback() { interactor.toggleFeedback() }
    func setAvailable(_ available: Bool) { interactor.setAvailable(available) }
    func exit() { interactor.stop() }

    func gameUpdated(_ snapshot: MatchSnapshot, notice: String?) {
        phase = snapshot.phase
        let mode = interactor.configuration.mode
        let heading: String?
        var detail = notice ?? ""
        var button: String?
        switch phase {
        case .waiting:
            heading = "GET READY"
            detail = "Waiting for both devices…"
        case .countdown: heading = "\(max(1, Int(ceil(snapshot.countdown))))"; detail = "Same pieces. Your own pace."
        case .playing: heading = nil
        case .paused:
            heading = "PAUSED"; button = "Resume"
            if detail.isEmpty { detail = "Both boards and the timer are paused." }
        case .finished:
            if mode == .solo { heading = "GAME OVER" }
            else if let winner = snapshot.winner {
                heading = mode == .sharedDevice ? "PLAYER \(winner + 1) WINS" : (winner == mode.localSeat ? "YOU WIN" : "YOU LOSE")
            } else { heading = "DRAW" }
            button = "Rematch"
            if detail.isEmpty {
                detail = mode == .solo ? "\(snapshot.boards[0].score) POINTS  •  \(snapshot.boards[0].lines) LINES"
                    : "\(snapshot.wins[0]) : \(snapshot.wins[1])  •  MATCH WINS"
            }
        case .disconnected: heading = "CONNECTION LOST"; button = "Back to menu"
        }
        view?.render(GameViewModel(snapshot: snapshot, mode: mode,
                     title: mode == .solo ? "SOLO" : (mode == .sharedDevice ? "LOCAL DUEL" : "NEARBY DUEL"),
                     overlayTitle: heading, overlayDetail: detail, primaryTitle: button,
                     soundEnabled: interactor.feedbackEnabled, opponentName: interactor.configuration.opponent ?? "Opponent"))
    }
}
