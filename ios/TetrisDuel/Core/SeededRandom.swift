import Foundation

/// SplitMix64 has specified wrapping arithmetic, unlike system RNG algorithms.
public struct SeededRandom {
    private var state: UInt64
    
    public init(seed: UInt64) { state = seed }
    
    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    
    public mutating func index(_ upper: Int) -> Int {
        precondition(upper > 0)
        // Reject the short tail rather than introducing modulo bias.
        let bound = UInt64(upper)
        let threshold = (0 &- bound) % bound
        var value = next()
        while value < threshold { value = next() }
        return Int(value % bound)
    }
}

public final class PieceStream {
    private var random: SeededRandom
    private var sequence: [Tetromino] = []
    
    public init(seed: UInt64) { random = SeededRandom(seed: seed) }
    
    public func at(_ index: Int) -> Tetromino {
        precondition(index >= 0)
        while sequence.count <= index {
            var bag = Tetromino.allCases.filter { $0 != .garbage }
            for i in stride(from: bag.count - 1, through: 1, by: -1) {
                bag.swapAt(i, random.index(i + 1))
            }
            sequence.append(contentsOf: bag)
        }
        return sequence[index]
    }
}
