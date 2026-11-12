import CoreGraphics

public enum PreviewPanKey: Hashable, Sendable {
    case left, right, up, down
}

/// Tracks held arrow keys and provides a normalized direction for keyboard panning.
public struct PreviewPanKeys: Sendable {
    private var held: Set<PreviewPanKey> = []

    public init() {}

    public mutating func press(_ key: PreviewPanKey) { held.insert(key) }
    public mutating func release(_ key: PreviewPanKey) { held.remove(key) }
    public mutating func reset() { held.removeAll() }

    public var direction: CGPoint {
        let x = (held.contains(.right) ? 1.0 : 0.0) - (held.contains(.left) ? 1.0 : 0.0)
        let y = (held.contains(.up) ? 1.0 : 0.0) - (held.contains(.down) ? 1.0 : 0.0)
        let magnitude = (x * x + y * y).squareRoot()
        guard magnitude > 0 else { return .zero }
        return CGPoint(x: x / magnitude, y: y / magnitude)
    }
}
