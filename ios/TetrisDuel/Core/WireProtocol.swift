import Foundation

public enum WireMessage: Equatable {
    case ready
    case snapshot(MatchSnapshot)
    case input(round: UInt32, sequence: UInt32, action: GameAction, pressed: Bool)
    case pause(round: UInt32, paused: Bool)
    case availability(Bool)
    case rematch(round: UInt32)
    case heartbeat, bye

    public var isSnapshot: Bool { if case .snapshot = self { return true }; return false }
}

public enum WireError: Error { case malformed, incompatibleVersion, oversized, queueFull }

/// Explicit byte order, bounded payloads, and four-bit cells: a two-board update
/// is under 320 bytes. Never decodes arbitrary objects from a nearby device.
public enum WireCodec {
    public static let version: UInt8 = 1
    public static let maxPayload = 1024

    public static func encode(_ message: WireMessage) throws -> Data {
        var w = ByteWriter()
        w.byte(version)
        switch message {
        case .ready: w.byte(3)
        case .snapshot(let state):
            guard (1...2).contains(state.boards.count), state.wins.count == 2 else { throw WireError.malformed }
            w.byte(4); w.u32(state.round); w.u32(state.revision); w.byte(state.phase.rawValue)
            w.u16(Int(max(0, state.countdown) * 1000)); w.u32(UInt32(clamping: Int(state.elapsed * 1000)))
            w.byte(state.winner.map { UInt8(clamping: $0) } ?? 255)
            w.u16(state.wins[0]); w.u16(state.wins[1]); w.byte(UInt8(state.boards.count))
            for board in state.boards {
                guard board.grid.count == 220, board.grid.allSatisfy({ $0 <= 8 }), board.next.count == 3 else {
                    throw WireError.malformed
                }
                for i in stride(from: 0, to: 220, by: 2) { w.byte(board.grid[i] | (board.grid[i+1] << 4)) }
                w.byte(board.piece.kind.rawValue); w.signed(board.piece.x); w.signed(board.piece.y)
                w.byte(UInt8(clamping: board.piece.rotation)); w.signed(board.ghostY)
                w.byte(board.held?.rawValue ?? 0); w.byte(board.holdUsed ? 1 : 0)
                board.next.forEach { w.byte($0.rawValue) }
                w.u32(UInt32(clamping: board.score)); w.u16(board.lines); w.u16(board.sent)
                w.u16(board.incoming); w.byte(board.alive ? 1 : 0)
            }
        case .input(let round, let sequence, let action, let pressed):
            w.byte(5); w.u32(round); w.u32(sequence); w.byte(action.rawValue); w.byte(pressed ? 1 : 0)
        case .pause(let round, let paused):
            w.byte(6); w.u32(round); w.byte(paused ? 1 : 0)
        case .availability(let value): w.byte(7); w.byte(value ? 1 : 0)
        case .rematch(let round): w.byte(8); w.u32(round)
        case .heartbeat: w.byte(9)
        case .bye: w.byte(10)
        }
        guard w.bytes.count <= maxPayload else { throw WireError.oversized }
        return Data(w.bytes)
    }

    public static func decode(_ data: Data) throws -> WireMessage {
        guard data.count <= maxPayload else { throw WireError.oversized }
        var r = ByteReader(bytes: Array(data))
        guard try r.byte() == version else { throw WireError.incompatibleVersion }
        let message: WireMessage
        switch try r.byte() {
        case 3: message = .ready
        case 4:
            let round = try r.u32(), revision = try r.u32()
            guard let phase = MatchPhase(rawValue: try r.byte()) else { throw WireError.malformed }
            let countdown = Double(try r.u16()) / 1000
            let elapsed = Double(try r.u32()) / 1000
            let winnerByte = try r.byte()
            let wins = [Int(try r.u16()), Int(try r.u16())]
            let count = Int(try r.byte())
            guard (1...2).contains(count), winnerByte == 255 || Int(winnerByte) < count else { throw WireError.malformed }
            var boards: [BoardSnapshot] = []
            for _ in 0..<count {
                let grid = try r.take(110).flatMap { [$0 & 15, $0 >> 4] }
                guard grid.allSatisfy({ $0 <= 8 }) else { throw WireError.malformed }
                let kind = try r.pieceKind()
                let x = try r.signed(), y = try r.signed(), rotation = Int(try r.byte()), ghostY = try r.signed()
                guard (-3...9).contains(x), (0...21).contains(y), (0...3).contains(rotation),
                      (y...21).contains(ghostY) else { throw WireError.malformed }
                let heldByte = try r.byte()
                guard heldByte <= 7 else { throw WireError.malformed }
                let held = Tetromino(rawValue: heldByte)
                let holdUsed = try r.boolean()
                let next = [try r.pieceKind(), try r.pieceKind(), try r.pieceKind()]
                let score = Int(try r.u32()), lines = Int(try r.u16()), sent = Int(try r.u16())
                let incoming = Int(try r.u16()), alive = try r.boolean()
                let piece = Piece(kind, x: x, y: y, rotation: rotation)
                guard piece.cells().allSatisfy({ (0..<10).contains($0.x) && (0..<22).contains($0.y) }),
                      piece.cells(dy: ghostY-y).allSatisfy({ (0..<22).contains($0.y) }) else { throw WireError.malformed }
                boards.append(BoardSnapshot(grid: grid, piece: piece, ghostY: ghostY, held: held,
                                            holdUsed: holdUsed, next: next, score: score, lines: lines,
                                            sent: sent, incoming: incoming, alive: alive))
            }
            message = .snapshot(MatchSnapshot(round: round, revision: revision, phase: phase, countdown: countdown,
                                             elapsed: elapsed, boards: boards, wins: wins,
                                             winner: winnerByte == 255 ? nil : Int(winnerByte)))
        case 5:
            let round = try r.u32(), sequence = try r.u32()
            guard let action = GameAction(rawValue: try r.byte()) else { throw WireError.malformed }
            message = .input(round: round, sequence: sequence, action: action, pressed: try r.boolean())
        case 6: message = .pause(round: try r.u32(), paused: try r.boolean())
        case 7: message = .availability(try r.boolean())
        case 8: message = .rematch(round: try r.u32())
        case 9: message = .heartbeat
        case 10: message = .bye
        default: throw WireError.malformed
        }
        guard r.offset == r.bytes.count else { throw WireError.malformed }
        return message
    }
}

private struct ByteWriter {
    var bytes: [UInt8] = []
    mutating func byte(_ value: UInt8) { bytes.append(value) }
    mutating func signed(_ value: Int) { byte(UInt8(bitPattern: Int8(clamping: value))) }
    mutating func u16(_ value: Int) {
        let v = UInt16(clamping: value)
        byte(UInt8(truncatingIfNeeded: v >> 8)); byte(UInt8(truncatingIfNeeded: v))
    }
    mutating func u32(_ value: UInt32) {
        for shift in [24, 16, 8, 0] { byte(UInt8(truncatingIfNeeded: value >> shift)) }
    }
}

private struct ByteReader {
    let bytes: [UInt8]
    var offset = 0
    mutating func byte() throws -> UInt8 {
        guard offset < bytes.count else { throw WireError.malformed }
        defer { offset += 1 }
        return bytes[offset]
    }
    mutating func take(_ count: Int) throws -> [UInt8] {
        guard count >= 0, count <= bytes.count - offset else { throw WireError.malformed }
        defer { offset += count }
        return Array(bytes[offset..<(offset + count)])
    }
    mutating func signed() throws -> Int { Int(Int8(bitPattern: try byte())) }
    mutating func u16() throws -> UInt16 { (UInt16(try byte()) << 8) | UInt16(try byte()) }
    mutating func u32() throws -> UInt32 { (UInt32(try u16()) << 16) | UInt32(try u16()) }
    mutating func boolean() throws -> Bool {
        let value = try byte()
        guard value < 2 else { throw WireError.malformed }
        return value == 1
    }
    mutating func pieceKind() throws -> Tetromino {
        guard let kind = Tetromino(rawValue: try byte()), kind != .garbage else { throw WireError.malformed }
        return kind
    }
}
