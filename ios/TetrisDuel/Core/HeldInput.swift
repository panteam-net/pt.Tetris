import Foundation

public struct HeldInput {
    private(set) var pressed = Set<GameAction>()
    private var direction = 0
    private var repeatTime = 0.0
    public init() {}
    public var softDrop: Bool { pressed.contains(.softDrop) }

    /// Returns an immediate action once per physical press.
    public mutating func set(_ action: GameAction, down: Bool) -> GameAction? {
        if !down { pressed.remove(action); return nil }
        guard pressed.insert(action).inserted else { return nil }
        if action == .left || action == .right {
            direction = action == .left ? -1 : 1
            repeatTime = -0.16
        }
        return action == .softDrop ? nil : action
    }

    public mutating func tick(_ dt: Double) -> [GameAction] {
        let next = (pressed.contains(.right) ? 1 : 0) - (pressed.contains(.left) ? 1 : 0)
        if direction != next {
            direction = next; repeatTime = -0.16
            return next == 0 ? [] : [next < 0 ? .left : .right]
        }
        guard next != 0 else { return [] }
        repeatTime += dt
        var result: [GameAction] = []
        while repeatTime >= 0 { result.append(next < 0 ? .left : .right); repeatTime -= 0.045 }
        return result
    }

    public mutating func clear() { self = HeldInput() }
}
