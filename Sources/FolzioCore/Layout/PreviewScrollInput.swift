/// Routes phased scroll gestures and their momentum to panning; phase-less wheel events zoom.
public struct PreviewScrollInput: Sendable {
    public enum Phase: Sendable {
        case none, mayBegin, began, changed, ended, cancelled
    }

    public enum Action: Sendable {
        case pan, zoom, ignore
    }

    private var gestureSequence = false

    public init() {}

    public mutating func reset() {
        gestureSequence = false
    }

    public mutating func classify(phase: Phase, isMomentum: Bool) -> Action {
        if isMomentum { return gestureSequence ? .pan : .ignore }
        switch phase {
        case .mayBegin, .began, .changed, .ended:
            gestureSequence = true
            return .pan
        case .cancelled:
            reset()
            return .ignore
        case .none:
            reset()
            return .zoom
        }
    }
}
