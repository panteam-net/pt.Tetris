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
            heading = L10n.text("game.ready")
            detail = L10n.text("game.waiting")
        case .countdown:
            heading = "\(max(1, Int(ceil(snapshot.countdown))))"
            detail = L10n.text("game.countdown")
        case .playing: heading = nil
        case .paused:
            heading = L10n.text("game.paused")
            button = L10n.text("common.resume")
            if detail.isEmpty { detail = L10n.text("game.paused.detail") }

        case .finished:
            if mode == .solo { heading = L10n.text("game.gameOver") }
            else if let winner = snapshot.winner {
                heading = mode == .sharedDevice
                    ? L10n.format("game.playerWins", winner + 1)
                    : L10n.text(
                        winner == mode.localSeat
                            ? "game.youWin" : "game.youLose"
                    )
            } else { heading = L10n.text("game.draw") }

            button = L10n.text("common.rematch")
            if detail.isEmpty {
                detail = mode == .solo ? L10n.format(
                    "game.solo.result",
                    snapshot.boards[0].score,
                    snapshot.boards[0].lines
                ) : L10n.format(
                    "game.matchWins",
                    snapshot.wins[0],
                    snapshot.wins[1]
                )
            }

        case .disconnected:
            heading = L10n.text("game.disconnected")
            button = L10n.text("common.backToMenu")
        }

        let title: String
        switch mode {
        case .solo: title = L10n.text("game.mode.solo")
        case .sharedDevice: title = L10n.text("game.mode.shared")
        case .nearbyHost, .nearbyGuest: title = L10n.text("game.mode.nearby")
        }
        view?.render(GameViewModel(
            snapshot: snapshot,
            mode: mode,
            title: title,
            overlayTitle: heading,
            overlayDetail: detail,
            primaryTitle: button,
            soundEnabled: interactor.feedbackEnabled,
            opponentName: interactor.configuration.opponent
                ?? L10n.text("player.opponent")
        ))
    }
}
