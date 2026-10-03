import Foundation

public final class Match {
    public let boards: [Board]
    public private(set) var elapsed = 0.0
    public private(set) var finished = false
    public private(set) var winner: Int?
    private var random: [SeededRandom]

    public init(seed: UInt64, players: Int) {
        precondition(players == 1 || players == 2)
        let stream = PieceStream(seed: seed)
        boards = (0..<players).map { _ in Board(stream: stream) }
        random = (0..<players).map { _ in SeededRandom(seed: seed ^ 0xD0E1) }
    }

    public func action(_ action: GameAction, player: Int) {
        guard !finished, boards.indices.contains(player) else { return }
        let board = boards[player]
        switch action {
        case .left: board.move(-1)
        case .right: board.move(1)
        case .rotate: board.rotate()
        case .reverse: board.rotate(-1)
        case .hardDrop: board.hardDrop()
        case .hold: board.hold()
        case .softDrop: break
        }
    }

    public func tick(_ dt: Double, softDrop: [Bool]) {
        guard !finished, dt.isFinite, dt >= 0 else { return }
        let step = min(dt, 0.05)
        elapsed += step
        for (seat, board) in boards.enumerated() {
            board.now = elapsed
            board.tick(step, softDrop: softDrop.indices.contains(seat) && softDrop[seat])
        }
        if boards.count == 2 {
            let mutual = min(boards[0].outgoing, boards[1].outgoing)
            for seat in 0..<2 {
                let attack = boards[seat].outgoing - mutual
                if attack > 0 {
                    boards[1-seat].receive(GarbagePacket(rows: attack, hole: random[seat].index(Rules.width),
                                                        readyAt: elapsed + 1.5))
                }
            }
        }
        boards.forEach { $0.outgoing = 0 }
        if boards.contains(where: { !$0.alive }) {
            finished = true
            winner = boards.count == 2 ? boards.firstIndex(where: { $0.alive }) : nil
        }
    }
}
