import Foundation

public final class Board {
    public private(set) var grid = [UInt8](repeating: 0, count: Rules.width * Rules.height)
    public private(set) var piece = Piece(.t)
    public private(set) var cursor = 0
    public private(set) var held: Tetromino?
    public private(set) var holdUsed = false
    public private(set) var alive = true
    public private(set) var score = 0
    public private(set) var lines = 0
    public private(set) var sent = 0
    public private(set) var placed = 0
    public private(set) var combo = -1
    private var backToBack = false
    public private(set) var pending: [GarbagePacket] = []
    public var outgoing = 0
    public var effects: [GameEffect] = []
    public var now = 0.0
    private var gravityTime = 0.0
    private var lockTime = 0.0
    private var lockResets = 0
    private let stream: PieceStream

    public init(stream: PieceStream) { self.stream = stream; spawn() }
    public var level: Int { 1 + lines / 10 }
    public var gravityInterval: Double { max(0.07, 0.8 * pow(0.82, Double(level - 1))) }
    public var incoming: Int { pending.reduce(0) { $0 + $1.rows } }
    public var preview: [Tetromino] { (0..<3).map { stream.at(cursor + $0) } }

    private func spawn(_ replacement: Tetromino? = nil) {
        let kind = replacement ?? stream.at(cursor)
        if replacement == nil { cursor += 1 }
        piece = Piece(kind)
        gravityTime = 0; lockTime = 0; lockResets = 0
        if !valid() { alive = false }
    }

    public func valid(dx: Int = 0, dy: Int = 0, rotation: Int? = nil) -> Bool {
        piece.cells(dx: dx, dy: dy, rotation: rotation).allSatisfy {
            (0..<Rules.width).contains($0.x) && (0..<Rules.height).contains($0.y)
                && grid[$0.y * Rules.width + $0.x] == 0
        }
    }
    public var grounded: Bool { !valid(dy: 1) }

    private func resetLock(_ wasGrounded: Bool) {
        if wasGrounded && lockResets < Rules.lockResetLimit { lockTime = 0; lockResets += 1 }
    }

    @discardableResult public func move(_ dx: Int) -> Bool {
        guard alive, valid(dx: dx) else { return false }
        let wasGrounded = grounded
        piece.x += dx
        resetLock(wasGrounded)
        return true
    }

    @discardableResult public func rotate(_ direction: Int = 1) -> Bool {
        guard alive, piece.kind != .o, direction == 1 || direction == -1 else { return false }
        let next = (piece.rotation + direction + 4) % 4
        let key = piece.rotation * 4 + next
        let wasGrounded = grounded
        let offsets = (piece.kind == .i ? Self.iKicks : Self.kicks)[key] ?? [Cell(0, 0)]
        for offset in offsets where valid(dx: offset.x, dy: offset.y, rotation: next) {
            piece.x += offset.x; piece.y += offset.y; piece.rotation = next
            resetLock(wasGrounded)
            return true
        }
        
        return false
    }

    @discardableResult public func hold() -> Bool {
        guard alive, !holdUsed else { return false }
        let replacement = held
        held = piece.kind
        spawn(replacement)
        holdUsed = true
        effects.append(.hold)
        return true
    }

    public var ghostDistance: Int {
        var distance = 0
        while valid(dy: distance + 1) { distance += 1 }
        return distance
    }

    public func hardDrop() {
        guard alive else { return }
        let distance = ghostDistance
        piece.y += distance
        score += distance * 2
        lock()
    }

    public func receive(_ packet: GarbagePacket) {
        guard packet.rows > 0, (0..<Rules.width).contains(packet.hole) else { return }
        pending.append(packet)
    }

    private func cancelIncoming(_ amount: Int) -> Int {
        var remaining = amount
        while remaining > 0 && !pending.isEmpty {
            let cancelled = min(remaining, pending[0].rows)
            remaining -= cancelled
            pending[0].rows -= cancelled
            if pending[0].rows == 0 { pending.removeFirst() }
        }
        
        return remaining
    }

    private func applyGarbage() {
        var budget = 8
        while let first = pending.first, first.readyAt <= now, budget > 0 {
            let count = min(first.rows, budget)
            if grid.prefix(count * Rules.width).contains(where: { $0 != 0 }) { alive = false }
            grid.removeFirst(count * Rules.width)
            for _ in 0..<count {
                grid.append(contentsOf: (0..<Rules.width).map { $0 == first.hole ? 0 : Tetromino.garbage.rawValue })
            }
            
            pending[0].rows -= count
            budget -= count
            if pending[0].rows == 0 { pending.removeFirst() }
        }
        
        if budget < 8 { effects.append(.garbage) }
    }

    private func lock() {
        let cells = piece.cells()
        for cell in cells { grid[cell.y * Rules.width + cell.x] = piece.kind.rawValue }
        placed += 1
        let full = (0..<Rules.height).filter { row in
            grid[(row * Rules.width)..<((row + 1) * Rules.width)].allSatisfy { $0 != 0 }
        }
        if !full.isEmpty {
            let count = full.count
            let oldLevel = level
            var remainder: [UInt8] = []
            for row in 0..<Rules.height where !full.contains(row) {
                remainder.append(contentsOf: grid[(row * Rules.width)..<((row + 1) * Rules.width)])
            }
            
            grid = [UInt8](repeating: 0, count: count * Rules.width) + remainder
            combo += 1
            let bonus = backToBack && count == 4
            var points = [0, 100, 300, 500, 800][count]
            if bonus { points = points * 3 / 2 }
            score += (points + 50 * max(0, combo)) * oldLevel
            lines += count
            backToBack = count == 4
            var attack = [0, 0, 1, 2, 4][count] + (bonus ? 1 : 0) + min(4, combo / 2)
            if grid.allSatisfy({ $0 == 0 }) {
                score += 2000 * oldLevel
                attack += 6
            }
            
            attack = cancelIncoming(attack)
            outgoing += attack; sent += attack
            effects.append(.clear)
        } else {
            combo = -1
            effects.append(.lock)
            applyGarbage()
            if cells.allSatisfy({ $0.y < Rules.hidden }) { alive = false }
        }
        
        holdUsed = false
        if alive { spawn() }
    }

    public func tick(_ dt: Double, softDrop: Bool = false) {
        guard alive, dt.isFinite, dt >= 0 else { return }
        let interval = softDrop
            ? min(0.035, gravityInterval)
            : gravityInterval
        gravityTime += min(dt, 0.25)
        while gravityTime >= interval {
            gravityTime -= interval
            if valid(dy: 1) {
                piece.y += 1
                if softDrop {
                    score += 1 }
            }
            else {
                gravityTime = 0
                break
            }
        }
        
        if grounded {
            lockTime += min(dt, 0.25)
            if lockTime >= Rules.lockDelay {
                lock()
            }
        } else if lockResets < Rules.lockResetLimit {
            lockTime = 0
        }
    }

    public var snapshot: BoardSnapshot {
        BoardSnapshot(
            grid: grid,
            piece: piece,
            ghostY: piece.y + ghostDistance,
            held: held,
            holdUsed: holdUsed,
            next: preview,
            score: score,
            lines: lines,
            sent: sent,
            incoming: incoming,
            alive: alive)
    }

    // Internal fixture seam available to @testable tests; the UI cannot edit a board.
    func setFixture(grid: [UInt8], piece: Piece) {
        precondition(grid.count == Rules.width * Rules.height)
        self.grid = grid; self.piece = piece
    }

    private static let kicks: [Int: [Cell]] = [
        1: [Cell(0,0),Cell(-1,0),Cell(-1,-1),Cell(0,2),Cell(-1,2)],
        4: [Cell(0,0),Cell(1,0),Cell(1,1),Cell(0,-2),Cell(1,-2)],
        6: [Cell(0,0),Cell(1,0),Cell(1,1),Cell(0,-2),Cell(1,-2)],
        9: [Cell(0,0),Cell(-1,0),Cell(-1,-1),Cell(0,2),Cell(-1,2)],
        11: [Cell(0,0),Cell(1,0),Cell(1,-1),Cell(0,2),Cell(1,2)],
        14: [Cell(0,0),Cell(-1,0),Cell(-1,1),Cell(0,-2),Cell(-1,-2)],
        12: [Cell(0,0),Cell(-1,0),Cell(-1,1),Cell(0,-2),Cell(-1,-2)],
        3: [Cell(0,0),Cell(1,0),Cell(1,-1),Cell(0,2),Cell(1,2)]
    ]
    private static let iKicks: [Int: [Cell]] = [
        1: [Cell(0,0),Cell(-2,0),Cell(1,0),Cell(-2,1),Cell(1,-2)],
        4: [Cell(0,0),Cell(2,0),Cell(-1,0),Cell(2,-1),Cell(-1,2)],
        6: [Cell(0,0),Cell(-1,0),Cell(2,0),Cell(-1,-2),Cell(2,1)],
        9: [Cell(0,0),Cell(1,0),Cell(-2,0),Cell(1,2),Cell(-2,-1)],
        11: [Cell(0,0),Cell(2,0),Cell(-1,0),Cell(2,-1),Cell(-1,2)],
        14: [Cell(0,0),Cell(-2,0),Cell(1,0),Cell(-2,1),Cell(1,-2)],
        12: [Cell(0,0),Cell(1,0),Cell(-2,0),Cell(1,2),Cell(-2,-1)],
        3: [Cell(0,0),Cell(-1,0),Cell(2,0),Cell(-1,-2),Cell(2,1)]
    ]
}
