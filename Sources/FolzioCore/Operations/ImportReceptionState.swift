public struct ImportReceptionState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable { case receiving, checking, confirming, saving, finished, failed, cancelled }
    public enum Event: Sendable, Equatable {
        case received(id: String), receptionCompleted, checked, confirmed, saved, failed, cancelled
    }
    public private(set) var phase: Phase
    private var receivedIDs: Set<String> = []
    public var receivedCount: Int { receivedIDs.count }
    public init(hasPromises: Bool) { phase = hasPromises ? .receiving : .checking }

    @discardableResult
    public mutating func apply(_ event: Event) -> Bool {
        guard ![Phase.finished, .failed, .cancelled].contains(phase) else { return false }
        switch event {
        case let .received(id) where phase == .receiving:
            return receivedIDs.insert(id).inserted
        case .receptionCompleted where phase == .receiving: phase = .checking
        case .checked where phase == .checking: phase = .confirming
        case .confirmed where phase == .confirming: phase = .saving
        case .saved where phase == .saving: phase = .finished
        case .failed: phase = .failed
        case .cancelled where phase != .saving: phase = .cancelled
        default: return false
        }
        return true
    }
}
