import Foundation

/// The host is the only writer of competitive game state. Guests submit input
/// transitions; snapshots are read-only and carry round + revision ordering.
final class GameInteractor: GameInteracting {
    weak var output: GameInteractorOutput?
    let configuration: GameConfiguration
    private let clock: GameClock
    private let transport: NearbyTransport?
    private let feedback: FeedbackServing
    private let seeds: SeedProviding
    private var match: Match
    private var phase: MatchPhase = .waiting
    private var resumePhase: MatchPhase = .playing
    private var countdown = 3.0
    private var wins = [0, 0]
    private var round: UInt32 = 1
    private var revision: UInt32 = 0
    private var inputs = [HeldInput(), HeldInput()]
    private var sequence: UInt32 = 0
    private var lastRemoteSequence: UInt32 = 0
    private var remoteSnapshot: MatchSnapshot?
    private var snapshotTimer = 0.0
    private var heartbeatTimer = 0.0
    private var lastReceived = 0.0
    private var unavailable = Set<Int>()
    private var rematchVotes = Set<Int>()
    private var started = false
    private var stopped = false
    private var notice: String?
    private var inputWindowStart = 0.0
    private var remoteInputCount = 0
    var feedbackEnabled: Bool { feedback.isEnabled }

    init(configuration: GameConfiguration, clock: GameClock, transport: NearbyTransport?,
         feedback: FeedbackServing, seeds: SeedProviding) {
        self.configuration = configuration; self.clock = clock; self.transport = transport
        self.feedback = feedback; self.seeds = seeds
        match = Match(seed: seeds.next(), players: configuration.mode.playerCount)
    }

    func start() {
        guard !started else { return }
        started = true
        lastReceived = clock.now
        transport?.onMessage = { [weak self] in self?.receive($0) }
        transport?.onEvent = { [weak self] event in
            switch event {
            case .disconnected(let text), .failure(let text): self?.connectionLost(text)
            default: break
            }
        }
        clock.onTick = { [weak self] in self?.tick($0) }
        if !configuration.mode.isNearby { phase = .countdown }
        if configuration.mode == .nearbyGuest { send(.ready) }
        clock.start()
        publish()
    }

    func input(_ action: GameAction, seat: Int, pressed: Bool) {
        guard !stopped, currentPhase == .playing, (0..<configuration.mode.playerCount).contains(seat),
              configuration.mode == .sharedDevice || seat == configuration.mode.localSeat else { return }
        if configuration.mode == .nearbyGuest {
            sequence &+= 1
            send(.input(round: remoteSnapshot?.round ?? round, sequence: sequence, action: action, pressed: pressed))
        } else {
            applyInput(action, seat: seat, pressed: pressed)
            publish()
        }
    }

    private func applyInput(_ action: GameAction, seat: Int, pressed: Bool) {
        if let immediate = inputs[seat].set(action, down: pressed) { match.action(immediate, player: seat) }
    }

    private var currentPhase: MatchPhase { remoteSnapshot?.phase ?? phase }

    private func tick(_ dt: Double) {
        guard !stopped else { return }
        if configuration.mode.isNearby && phase != .disconnected {
            if clock.now - lastReceived > 8 {
                connectionLost("Connection lost. The match is stopped; no winner is awarded.")
                return
            }
            heartbeatTimer += dt
            if heartbeatTimer >= 1 {
                heartbeatTimer = 0
                send(configuration.mode == .nearbyGuest && remoteSnapshot == nil ? .ready : .heartbeat)
            }
        }
        guard configuration.mode != .nearbyGuest else { return }
        if phase == .countdown {
            countdown -= dt
            if countdown <= 0 { countdown = 0; phase = .playing; clearInputs() }
        } else if phase == .playing {
            for seat in match.boards.indices {
                for action in inputs[seat].tick(dt) { match.action(action, player: seat) }
            }
            match.tick(dt, softDrop: inputs.map { $0.softDrop })
            for (seat, board) in match.boards.enumerated() {
                if configuration.mode == .sharedDevice || seat == configuration.mode.localSeat {
                    board.effects.forEach { feedback.play($0) }
                }
                board.effects.removeAll(keepingCapacity: true)
            }
            if match.finished {
                phase = .finished
                clearInputs()
                if let winner = match.winner { wins[winner] += 1 }
                feedback.play(.win)
            }
        }
        publish()
        if configuration.mode == .nearbyHost {
            snapshotTimer += dt
            if snapshotTimer >= 1.0 / 12 { snapshotTimer = 0; send(.snapshot(snapshot)) }
        }
    }

    private var snapshot: MatchSnapshot {
        MatchSnapshot(round: round, revision: revision, phase: phase, countdown: countdown,
                      elapsed: match.elapsed, boards: match.boards.map { $0.snapshot }, wins: wins, winner: match.winner)
    }

    private func publish() {
        guard !stopped else { return }
        revision &+= 1
        output?.gameUpdated(remoteSnapshot ?? snapshot, notice: notice)
    }

    func setPaused(_ paused: Bool) {
        guard !stopped else { return }
        if configuration.mode == .nearbyGuest {
            send(.pause(round: remoteSnapshot?.round ?? round, paused: paused))
        } else { applyPause(paused) }
    }

    private func applyPause(_ paused: Bool) {
        if paused && (phase == .playing || phase == .countdown) {
            resumePhase = phase; phase = .paused; clearInputs()
        } else if !paused && phase == .paused {
            guard unavailable.isEmpty else { notice = "Both players must return to the game before resuming."; publish(); return }
            phase = resumePhase; notice = nil; clearInputs()
        }
        publish()
        // Send critical state immediately, before iOS suspends a backgrounded host.
        if configuration.mode == .nearbyHost { send(.snapshot(snapshot)) }
    }

    func setAvailable(_ available: Bool) {
        guard !stopped else { return }
        if configuration.mode.isNearby { send(.availability(available)) }
        let seat = configuration.mode.localSeat
        if available { unavailable.remove(seat) }
        else { unavailable.insert(seat); setPaused(true); clearInputs() }
    }

    func requestRematch() {
        guard currentPhase == .finished else { return }
        if configuration.mode == .nearbyGuest {
            send(.rematch(round: remoteSnapshot?.round ?? round))
            notice = "Rematch requested. Waiting for the other player."
            publish()
        } else if configuration.mode == .nearbyHost {
            rematchVotes.insert(0)
            tryRematch()
        } else { restart() }
    }

    private func tryRematch() {
        if rematchVotes.count == 2 { restart() }
        else { notice = "Rematch requested. Both players must choose Rematch."; publish() }
    }

    private func restart() {
        round &+= 1; revision = 0; countdown = 3; phase = .countdown
        match = Match(seed: seeds.next(), players: configuration.mode.playerCount)
        rematchVotes.removeAll(); clearInputs(); notice = nil
        lastRemoteSequence = 0
        publish()
        if configuration.mode == .nearbyHost { send(.snapshot(snapshot)) }
    }

    private func receive(_ message: WireMessage) {
        guard !stopped, phase != .disconnected else { return }
        lastReceived = clock.now
        switch message {
        case .ready where configuration.mode == .nearbyHost:
            if phase == .waiting { phase = .countdown; countdown = 3; publish() }
            send(.snapshot(snapshot))
        case .snapshot(let state) where configuration.mode == .nearbyGuest:
            guard state.boards.count == 2 else { connectionLost("Invalid match received."); return }
            if let old = remoteSnapshot {
                guard state.round > old.round || (state.round == old.round && state.revision > old.revision) else { return }
                if state.boards[1].lines > old.boards[1].lines { feedback.play(.clear) }
                if state.phase == .finished && old.phase != .finished { feedback.play(.win) }
                if state.round > old.round { notice = nil; sequence = 0; clearInputs() }
            }
            remoteSnapshot = state; phase = state.phase; round = state.round
            output?.gameUpdated(state, notice: notice)
        case .input(let epoch, let serial, let action, let pressed) where configuration.mode == .nearbyHost:
            guard epoch == round, serial > lastRemoteSequence, phase == .playing else { return }
            if clock.now - inputWindowStart >= 1 { inputWindowStart = clock.now; remoteInputCount = 0 }
            remoteInputCount += 1
            guard remoteInputCount <= 160 else { connectionLost("The peer sent too many inputs."); return }
            lastRemoteSequence = serial
            applyInput(action, seat: 1, pressed: pressed)
        case .pause(let epoch, let paused) where configuration.mode == .nearbyHost:
            if epoch == round { applyPause(paused) }
        case .availability(let available):
            let seat = 1 - configuration.mode.localSeat
            if available { unavailable.remove(seat) }
            else { unavailable.insert(seat); if configuration.mode == .nearbyHost { applyPause(true) } }
        case .rematch(let epoch) where configuration.mode == .nearbyHost:
            if epoch == round && phase == .finished { rematchVotes.insert(1); tryRematch() }
        case .bye: connectionLost("The other player left the match.")
        default: break
        }
    }

    private func send(_ message: WireMessage) {
        guard let transport = transport, !stopped, phase != .disconnected else { return }
        do { try transport.send(message) }
        catch { connectionLost("Connection interrupted. Return to the menu and join a new game.") }
    }

    private func connectionLost(_ text: String) {
        guard phase != .disconnected, !stopped else { return }
        phase = .disconnected; notice = text; clearInputs()
        if var state = remoteSnapshot { state.phase = .disconnected; remoteSnapshot = state }
        transport?.disconnect()
        publish()
    }

    private func clearInputs() { inputs = [HeldInput(), HeldInput()] }
    func toggleFeedback() { feedback.isEnabled.toggle(); publish() }
    func stop() {
        guard !stopped else { return }
        if transport?.isConnected == true { try? transport?.send(.bye) }
        stopped = true; clock.stop(); clock.onTick = nil
        transport?.onMessage = nil; transport?.onEvent = nil; transport?.disconnect()
        clearInputs()
    }
    deinit { clock.stop() }
}
