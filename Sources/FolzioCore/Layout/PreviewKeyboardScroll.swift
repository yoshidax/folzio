import CoreGraphics

/// Tracks held directions independently of key-repeat events.
public struct PreviewKeyboardScroll: Sendable {
    public enum Direction: Sendable, Hashable {
        case left, right, up, down
    }

    private var directions: Set<Direction> = []

    public init() {}

    public var isEmpty: Bool { directions.isEmpty }

    public func contains(_ direction: Direction) -> Bool { directions.contains(direction) }

    public mutating func press(_ direction: Direction) {
        directions.insert(direction)
    }

    public mutating func release(_ direction: Direction) {
        directions.remove(direction)
    }

    public mutating func reset() {
        directions.removeAll()
    }

    public func movement(step: CGFloat) -> CGPoint {
        let x = CGFloat((directions.contains(.right) ? 1 : 0) - (directions.contains(.left) ? 1 : 0))
        let y = CGFloat((directions.contains(.up) ? 1 : 0) - (directions.contains(.down) ? 1 : 0))
        let length = hypot(x, y)
        guard length > 0, step.isFinite else { return .zero }
        return CGPoint(x: step * x / length, y: step * y / length)
    }
}
