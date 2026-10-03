import XCTest
@testable import pt_TetrisDuel

private final class TestClock: GameClock {
    var onTick: ((Double) -> Void)?
    var now: TimeInterval = 0
    func start() {}
    func stop() { onTick = nil }
    func advance(_ seconds: Double) { now += seconds; onTick?(seconds) }
}
private struct TestSeed: SeedProviding { func next() -> UInt64 { 42 } }
private final class TestFeedback: FeedbackServing {
    var isEnabled = true
    func play(_ effect: GameEffect) {}
}
private final class TestTransport: NearbyTransport {
    var onEvent: ((NearbyEvent) -> Void)?
    var onMessage: ((WireMessage) -> Void)?
    var isConnected = true
    var messages: [WireMessage] = []
    var deliver: ((WireMessage) -> Void)?
    func host() {}
    func browse() {}
    func invite(_ peer: NearbyPeer) {}
    func send(_ message: WireMessage) throws { messages.append(message); deliver?(message) }
    func disconnect() { isConnected = false }
}
private final class GameOutputSpy: GameInteractorOutput {
    var state: MatchSnapshot?
    var notice: String?
    func gameUpdated(_ snapshot: MatchSnapshot, notice: String?) { state = snapshot; self.notice = notice }
}

final class GameInteractorTests: XCTestCase {
    private func make(_ mode: MatchMode) -> (GameInteractor, TestClock, TestTransport, GameOutputSpy) {
        let clock = TestClock(), transport = TestTransport(), output = GameOutputSpy()
        let interactor = GameInteractor(configuration: GameConfiguration(mode: mode, opponent: "Peer"),
                                        clock: clock, transport: mode.isNearby ? transport : nil,
                                        feedback: TestFeedback(), seeds: TestSeed())
        interactor.output = output; interactor.start()
        return (interactor, clock, transport, output)
    }
    func testLocalCountdownPauseAndResume() {
        let (game, clock, _, output) = make(.solo)
        XCTAssertEqual(output.state?.phase, .countdown)
        for _ in 0..<61 { clock.advance(0.05) }
        XCTAssertEqual(output.state?.phase, .playing)
        game.setPaused(true)
        let elapsed = output.state?.elapsed
        clock.advance(0.05); XCTAssertEqual(output.state?.elapsed, elapsed)
        game.setPaused(false); clock.advance(0.05)
        XCTAssertEqual(output.state?.phase, .playing)
    }
    func testHostWaitsForGuestReady() {
        let (game, clock, transport, output) = make(.nearbyHost)
        clock.advance(0.05); XCTAssertEqual(output.state?.phase, .waiting)
        transport.onMessage?(.ready); XCTAssertEqual(output.state?.phase, .countdown)
        game.stop()
    }
    func testGuestSendsInputButNeverSimulates() {
        let (game, clock, transport, output) = make(.nearbyGuest)
        XCTAssertEqual(transport.messages.first, .ready)
        let match = Match(seed: 1, players: 2)
        let state = MatchSnapshot(round: 1, revision: 1, phase: .playing, countdown: 0, elapsed: 0,
                                  boards: match.boards.map { $0.snapshot }, wins: [0,0], winner: nil)
        transport.onMessage?(.snapshot(state))
        game.input(.hardDrop, seat: 1, pressed: true); clock.advance(0.05)
        XCTAssertEqual(output.state, state)
        XCTAssertTrue(transport.messages.contains(.input(round: 1, sequence: 1, action: .hardDrop, pressed: true)))
        let count = transport.messages.count
        game.input(.hardDrop, seat: 0, pressed: true)
        XCTAssertEqual(transport.messages.count, count)
    }
    func testGuestIgnoresReorderedSnapshots() {
        let (game, _, transport, output) = make(.nearbyGuest)
        let match = Match(seed: 1, players: 2)
        var state = MatchSnapshot(round: 2, revision: 30, phase: .playing, countdown: 0, elapsed: 20,
                                  boards: match.boards.map { $0.snapshot }, wins: [0,0], winner: nil)
        transport.onMessage?(.snapshot(state))
        state.revision = 29; state.elapsed = 19
        transport.onMessage?(.snapshot(state)); XCTAssertEqual(output.state?.elapsed, 20)
        state.round = 1; state.revision = 900
        transport.onMessage?(.snapshot(state)); XCTAssertEqual(output.state?.round, 2)
        game.stop()
    }
    func testDisconnectFreezesMatchWithoutAwardingWinner() {
        let (game, clock, transport, output) = make(.nearbyHost)
        transport.onMessage?(.ready)
        clock.advance(9)
        XCTAssertEqual(output.state?.phase, .disconnected)
        XCTAssertEqual(output.state?.wins, [0,0]); XCTAssertNil(output.state?.winner)
        XCTAssertFalse(transport.isConnected)
        game.stop()
    }
    func testUnavailablePeerPreventsResume() {
        let (game, _, transport, output) = make(.nearbyHost)
        transport.onMessage?(.ready)
        transport.onMessage?(.availability(false)); game.setPaused(false)
        XCTAssertEqual(output.state?.phase, .paused)
        transport.onMessage?(.availability(true)); game.setPaused(false)
        XCTAssertEqual(output.state?.phase, .countdown)
        game.stop()
    }
    func testSharedDeviceInputsAreIndependent() {
        let (game, clock, _, output) = make(.sharedDevice)
        for _ in 0..<61 { clock.advance(0.05) }
        game.input(.left, seat: 0, pressed: true)
        game.input(.right, seat: 1, pressed: true)
        clock.advance(0.01)
        XCTAssertEqual(output.state?.boards.map { $0.piece.x }, [2, 4])
        game.input(.left, seat: 0, pressed: false)
        clock.advance(0.2)
        XCTAssertEqual(output.state?.boards[0].piece.x, 2)
        XCTAssertGreaterThan(output.state?.boards[1].piece.x ?? 0, 4)
        game.stop()
    }
    func testHostRejectsOldRoundAndDuplicateInputs() {
        let (game, clock, transport, output) = make(.nearbyHost)
        transport.onMessage?(.ready)
        for _ in 0..<61 { clock.advance(0.05) }
        transport.onMessage?(.input(round: 2, sequence: 1, action: .left, pressed: true))
        clock.advance(0.01)
        XCTAssertEqual(output.state?.boards[1].piece.x, 3)
        transport.onMessage?(.input(round: 1, sequence: 2, action: .left, pressed: true))
        transport.onMessage?(.input(round: 1, sequence: 2, action: .right, pressed: true))
        clock.advance(0.01)
        XCTAssertEqual(output.state?.boards[1].piece.x, 2)
        game.stop()
    }
    func testNearbyRematchRequiresBothVotesAndKeepsWins() {
        let (host, hostClock, hostTransport, hostOutput) = make(.nearbyHost)
        let (guest, guestClock, guestTransport, guestOutput) = make(.nearbyGuest)
        hostTransport.deliver = guestTransport.onMessage
        guestTransport.deliver = hostTransport.onMessage
        hostTransport.onMessage?(.ready)
        for _ in 0..<61 { hostClock.advance(0.05); guestClock.advance(0.05) }
        for _ in 0..<40 where hostOutput.state?.phase == .playing {
            host.input(.hardDrop, seat: 0, pressed: true)
            host.input(.hardDrop, seat: 0, pressed: false)
            hostClock.advance(0.02); guestClock.advance(0.02)
        }
        hostClock.advance(0.1)
        XCTAssertEqual(hostOutput.state?.phase, .finished)
        XCTAssertEqual(guestOutput.state?.phase, .finished)
        let wins = hostOutput.state?.wins
        guest.requestRematch()
        XCTAssertEqual(hostOutput.state?.phase, .finished)
        host.requestRematch()
        XCTAssertEqual(hostOutput.state?.round, 2)
        XCTAssertEqual(guestOutput.state?.round, 2)
        XCTAssertEqual(guestOutput.state?.phase, .countdown)
        XCTAssertEqual(hostOutput.state?.wins, wins)
        host.stop(); guest.stop()
    }
}
