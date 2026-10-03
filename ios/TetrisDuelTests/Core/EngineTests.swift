import XCTest
#if SWIFT_PACKAGE
@testable import TetrisCore
#else
@testable import pt_TetrisDuel
#endif

final class EngineTests: XCTestCase {
    private func board() -> Board { Board(stream: PieceStream(seed: 42)) }
    
    private func well(_ board: Board, perfect: Bool = false) {
        var grid = [UInt8](repeating: 0, count: 220)
        for row in 18..<22 {
            for x in 0..<10 where x != 4 { grid[row*10+x] = Tetromino.j.rawValue }
        }
        if !perfect { grid[170] = Tetromino.t.rawValue }
        board.setFixture(grid: grid, piece: Piece(.i, x: 2, rotation: 1))
    }
    
    func testSevenBagAndSeedReproducibility() {
        let a = PieceStream(seed: 8), b = PieceStream(seed: 8)
        for bag in 0..<20 {
            let pieces = (0..<7).map { a.at(bag*7+$0) }
            XCTAssertEqual(Set(pieces).count, 7)
            XCTAssertEqual(pieces, (0..<7).map { b.at(bag*7+$0) })
        }
    }
    
    func testEqualPieceSequenceAtDifferentPlayerSpeeds() {
        let match = Match(seed: 85, players: 2)
        let left = match.boards[0], right = match.boards[1]
        var sequence: [Tetromino] = []
        for _ in 0..<20 {
            sequence.append(left.piece.kind)
            left.setFixture(grid: [UInt8](repeating: 0, count: 220), piece: left.piece)
            left.hardDrop()
        }
        for piece in sequence {
            XCTAssertEqual(right.piece.kind, piece)
            right.setFixture(grid: [UInt8](repeating: 0, count: 220), piece: right.piece)
            right.hardDrop()
        }
    }
    
    func testWallCollisionAndGhost() {
        let b = board()
        while b.move(-1) {}
        XCTAssertEqual(b.piece.cells().map(\.x).min(), 0)
        XCTAssertTrue(b.valid(dy: b.ghostDistance))
        XCTAssertFalse(b.valid(dy: b.ghostDistance + 1))
        while b.move(1) {}
        XCTAssertEqual(b.piece.cells().map(\.x).max(), 9)
    }
    
    func testFourRotationsRestoreShape() {
        let b = board()
        b.setFixture(grid: b.grid, piece: Piece(.t, y: 5))
        let before = Set(b.piece.cells())
        for _ in 0..<4 { XCTAssertTrue(b.rotate()) }
        XCTAssertEqual(Set(b.piece.cells()), before)
    }
    
    func testFloorAndIWallKicks() {
        let b = board()
        b.setFixture(grid: b.grid, piece: Piece(.t, y: 20))
        XCTAssertTrue(b.rotate()); XCTAssertTrue(b.valid()); XCTAssertLessThan(b.piece.y, 20)
        b.setFixture(grid: b.grid, piece: Piece(.i, x: -2, y: 5, rotation: 1))
        XCTAssertTrue(b.valid()); XCTAssertTrue(b.rotate(-1)); XCTAssertTrue(b.valid())
    }
    
    func testHoldOncePerPieceAndSwapPreservesQueue() {
        let b = board(), original = b.piece.kind
        XCTAssertTrue(b.hold()); XCTAssertFalse(b.hold()); XCTAssertEqual(b.held, original)
        b.hardDrop()
        let cursor = b.cursor
        XCTAssertTrue(b.hold()); XCTAssertEqual(b.cursor, cursor)
        XCTAssertEqual(b.piece.kind, original); XCTAssertEqual(b.piece.rotation, 0)
    }
    
    func testHardDropScoresAndLocks() {
        let b = board(), distance = b.ghostDistance
        b.hardDrop()
        XCTAssertEqual(b.placed, 1); XCTAssertEqual(b.score, distance*2)
        XCTAssertEqual(b.grid.filter { $0 != 0 }.count, 4)
    }
    
    func testTetrisClearAndAttack() {
        let b = board(); well(b)
        let dropScore = b.ghostDistance*2
        b.hardDrop()
        XCTAssertEqual(b.lines, 4); XCTAssertEqual(b.score, 800+dropScore)
        XCTAssertEqual(b.outgoing, 4); XCTAssertEqual(b.grid.filter { $0 != 0 }.count, 1)
    }
    
    func testPerfectClearAndBackToBack() {
        let b = board(); well(b, perfect: true); b.hardDrop()
        XCTAssertEqual(b.outgoing, 10); XCTAssertTrue(b.grid.allSatisfy { $0 == 0 })
        b.outgoing = 0; well(b); b.hardDrop()
        XCTAssertEqual(b.outgoing, 5)
    }
    
    func testGarbageCancellation() {
        let b = board(); well(b)
        b.receive(GarbagePacket(rows: 5, hole: 6, readyAt: 20)); b.hardDrop()
        XCTAssertEqual(b.incoming, 1); XCTAssertEqual(b.outgoing, 0)
    }
    
    func testGarbageDelayAndEightRowLimit() {
        let b = board()
        b.receive(GarbagePacket(rows: 12, hole: 7, readyAt: 1.5))
        b.now = 1.4; b.hardDrop(); XCTAssertEqual(b.incoming, 12)
        b.now = 1.5; b.hardDrop(); XCTAssertEqual(b.incoming, 4)
        for row in 14..<22 {
            XCTAssertEqual(b.grid[row*10+7], 0)
            XCTAssertEqual(b.grid[(row*10)..<(row*10+10)].filter { $0 == 0 }.count, 1)
        }
    }
    
    func testSimultaneousAttacksCancel() {
        let match = Match(seed: 1, players: 2)
        match.boards[0].outgoing = 4; match.boards[1].outgoing = 2
        match.tick(0.02, softDrop: [false, false])
        XCTAssertEqual(match.boards[0].incoming, 0); XCTAssertEqual(match.boards[1].incoming, 2)
    }
    
    func testSoftDropAndLockDelay() {
        let b = board()
        b.tick(0.2, softDrop: true)
        XCTAssertGreaterThan(b.piece.y, 0); XCTAssertGreaterThan(b.score, 0)
        b.setFixture(grid: b.grid, piece: Piece(.o, y: 20))
        b.tick(0.2); XCTAssertEqual(b.placed, 0)
        b.tick(0.2); b.tick(0.2); XCTAssertEqual(b.placed, 1)
    }
    
    func testHiddenLockoutAndSoloEnd() {
        let match = Match(seed: 42, players: 1), b = match.boards[0]
        var grid = b.grid; grid[24] = 8; grid[25] = 8
        b.setFixture(grid: grid, piece: Piece(.o)); b.hardDrop()
        match.tick(0.01, softDrop: [false])
        XCTAssertFalse(b.alive); XCTAssertTrue(match.finished); XCTAssertNil(match.winner)
        let elapsed = match.elapsed
        match.tick(0.05, softDrop: [true]); XCTAssertEqual(match.elapsed, elapsed)
    }
    
    func testWinnerAndSimultaneousDraw() {
        for seats in [[0], [0, 1]] {
            let match = Match(seed: 1, players: 2)
            for seat in seats {
                let b = match.boards[seat]
                var grid = b.grid; grid[24] = 8; grid[25] = 8
                b.setFixture(grid: grid, piece: Piece(.o)); b.hardDrop()
            }
            match.tick(0.01, softDrop: [false, false])
            XCTAssertTrue(match.finished)
            XCTAssertEqual(match.winner, seats.count == 1 ? 1 : nil)
        }
    }
    
    func testHeldInputDeduplicatesAndRepeats() {
        var input = HeldInput()
        XCTAssertEqual(input.set(.left, down: true), .left)
        XCTAssertNil(input.set(.left, down: true)); XCTAssertTrue(input.tick(0.1).isEmpty)
        XCTAssertFalse(input.tick(0.1).isEmpty)
        _ = input.set(.left, down: false); XCTAssertTrue(input.tick(1).isEmpty)
        _ = input.set(.softDrop, down: true); XCTAssertTrue(input.softDrop)
        input.clear(); XCTAssertFalse(input.softDrop)
    }
    
    func testRandomDuelsMaintainInvariants() {
        for seed in 0..<20 {
            let match = Match(seed: UInt64(seed), players: 2)
            var random = SeededRandom(seed: UInt64(seed))
            for _ in 0..<600 {
                for seat in 0..<2 { match.action(GameAction.allCases[random.index(7)], player: seat) }
                match.tick(0.05, softDrop: [false, true])
                for b in match.boards {
                    XCTAssertEqual(b.grid.count, 220)
                    if b.alive { XCTAssertTrue(b.valid()) }
                }
                if match.finished { break }
            }
            XCTAssertTrue(match.finished)
        }
    }
}
