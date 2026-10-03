import Foundation

public enum Rules {
    public static let width = 10
    public static let height = 22
    public static let hidden = 2
    public static let lockDelay = 0.5
    public static let lockResetLimit = 15
}

public enum Tetromino: UInt8, CaseIterable, Equatable {
    case i = 1, j, l, o, s, t, z, garbage

    public var cells: [[Cell]] {
        let rows: [String]
        switch self {
        case .i: rows = ["....", "####", "....", "...."]
        case .j: rows = ["#..", "###", "..."]
        case .l: rows = ["..#", "###", "..."]
        case .o: rows = [".##.", ".##.", "....", "...."]
        case .s: rows = [".##", "##.", "..."]
        case .t: rows = [".#.", "###", "..."]
        case .z: rows = ["##.", ".##", "..."]
        case .garbage: return [[], [], [], []]
        }
        var state = rows.enumerated().flatMap { y, row in
            row.enumerated().compactMap { x, value in value == "#" ? Cell(x, y) : nil }
        }
        var result: [[Cell]] = []
        for _ in 0..<4 {
            result.append(state)
            if self != .o { state = state.map { Cell(rows.count - 1 - $0.y, $0.x) } }
        }
        return result
    }

    // Cached once, so the 60 Hz engine does not rebuild rotation matrices.
    static let rotations = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.cells) })
}

public struct Cell: Equatable, Hashable {
    public var x: Int
    public var y: Int
    public init(_ x: Int, _ y: Int) { self.x = x; self.y = y }
}

public struct Piece: Equatable {
    public var kind: Tetromino
    public var x: Int = 3
    public var y: Int = 0
    public var rotation: Int = 0

    public init(_ kind: Tetromino, x: Int = 3, y: Int = 0, rotation: Int = 0) {
        self.kind = kind; self.x = x; self.y = y; self.rotation = rotation
    }

    public func cells(dx: Int = 0, dy: Int = 0, rotation: Int? = nil) -> [Cell] {
        (Tetromino.rotations[kind]?[rotation ?? self.rotation] ?? []).map {
            Cell(x + $0.x + dx, y + $0.y + dy)
        }
    }
}

public enum GameAction: UInt8, CaseIterable {
    case left, right, softDrop, rotate, reverse, hardDrop, hold
    public var repeats: Bool { self == .left || self == .right || self == .softDrop }
}

public enum MatchMode: Equatable {
    case solo, sharedDevice, nearbyHost, nearbyGuest
    public var isNearby: Bool { self == .nearbyHost || self == .nearbyGuest }
    public var localSeat: Int { self == .nearbyGuest ? 1 : 0 }
    public var playerCount: Int { self == .solo ? 1 : 2 }
}

public enum MatchPhase: UInt8 {
    case waiting, countdown, playing, paused, finished, disconnected
}

public struct BoardSnapshot: Equatable {
    public var grid: [UInt8]
    public var piece: Piece
    public var ghostY: Int
    public var held: Tetromino?
    public var holdUsed: Bool
    public var next: [Tetromino]
    public var score: Int
    public var lines: Int
    public var sent: Int
    public var incoming: Int
    public var alive: Bool
    public var level: Int { 1 + lines / 10 }
}

public struct MatchSnapshot: Equatable {
    public var round: UInt32
    public var revision: UInt32
    public var phase: MatchPhase
    public var countdown: Double
    public var elapsed: Double
    public var boards: [BoardSnapshot]
    public var wins: [Int]
    public var winner: Int?
}

public enum GameEffect { case lock, clear, hold, garbage, win }

public struct GarbagePacket {
    public var rows: Int
    public let hole: Int
    public let readyAt: Double
    public init(rows: Int, hole: Int, readyAt: Double) {
        self.rows = rows; self.hole = hole; self.readyAt = readyAt
    }
}
