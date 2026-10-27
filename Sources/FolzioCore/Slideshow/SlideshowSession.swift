import Foundation

/// Core runtime state with the deadline, cancellation generation, and pending automatic advance.
/// Time is supplied by the caller as a monotonic clock Instant; this type never sleeps.
/// Changing settings does not rewrite a `deadline` that has already been set.
/// A new interval is used only when creating the next deadline in start, arrow, or commit.
public struct SlideshowSession: Sendable {
    public enum Phase: Sendable, Equatable {
        case idle
        /// Waiting for the next regular transition.
        case running
        /// Waiting after the last accepted arrow. This is not a separate paused state.
        case waitingAfterArrow
    }

    public struct PendingDue: Sendable, Equatable {
        public let generation: Int
        public let deadline: ContinuousClock.Instant
    }

    public private(set) var phase: Phase = .idle
    public private(set) var deadline: ContinuousClock.Instant?
    public private(set) var generation = 0
    /// Pending item held after a timeout until commit following the app's input dispatch. At most one.
    public private(set) var pendingDue: PendingDue?

    public init() {}

    public var isActive: Bool { phase != .idle }

    /// Starts from idle. Restarting while active does not change the selection or deadline.
    @discardableResult
    public mutating func start(now: ContinuousClock.Instant, interval: Duration) -> Bool {
        guard phase == .idle else { return false }
        generation &+= 1
        phase = .running
        deadline = now.advanced(by: interval)
        pendingDue = nil
        return true
    }

    /// Stops execution and invalidates the wait and any pending due. Does nothing when not active.
    @discardableResult
    public mutating func stop() -> Bool {
        guard phase != .idle else { return false }
        generation &+= 1
        phase = .idle
        deadline = nil
        pendingDue = nil
        return true
    }

    /// Accepts an arrow. Regardless of whether navigation succeeds, invalidates the old deadline and pending due and
    /// moves to now + interval.
    @discardableResult
    public mutating func arrow(now: ContinuousClock.Instant, interval: Duration) -> Bool {
        guard phase != .idle else { return false }
        generation &+= 1
        pendingDue = nil
        phase = .waitingAfterArrow
        deadline = now.advanced(by: interval)
        return true
    }

    /// Holds the fact that the deadline has arrived. Does not change the selection or the deadline yet.
    /// Returns true when a pending item for the same generation already exists.
    @discardableResult
    public mutating func timeout(now: ContinuousClock.Instant) -> Bool {
        guard phase != .idle, let deadline, now >= deadline else { return false }
        if pendingDue?.generation == generation {
            return true
        }
        pendingDue = PendingDue(generation: generation, deadline: deadline)
        return true
    }

    /// Commits the pending automatic advance. Allows only the pending item for the current generation once, and sets
    /// the phase to running and the deadline to the commit time + interval.
    @discardableResult
    public mutating func commit(now: ContinuousClock.Instant, interval: Duration) -> Bool {
        guard phase != .idle,
              let pending = pendingDue,
              pending.generation == generation else {
            return false
        }
        pendingDue = nil
        phase = .running
        deadline = now.advanced(by: interval)
        return true
    }

    public func hasPendingDue(for generation: Int) -> Bool {
        pendingDue?.generation == generation
    }

    /// Time remaining until the next deadline. Zero once the deadline has passed. Nil when idle.
    public func remaining(at now: ContinuousClock.Instant) -> Duration? {
        guard let deadline else { return nil }
        let remaining = now.duration(to: deadline)
        return remaining > .zero ? remaining : .zero
    }
}
