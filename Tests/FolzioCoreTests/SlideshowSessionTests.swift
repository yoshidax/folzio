import Foundation
import Testing
@testable import FolzioCore

@Suite("SlideshowSession")
struct SlideshowSessionTests {
    private let clock = ContinuousClock()
    private var t0: ContinuousClock.Instant { clock.now }

    @Test("Starting sets running with a deadline three seconds after now; starting again while running changes nothing")
    func starts() {
        var session = SlideshowSession()
        let now = t0

        #expect(session.phase == .idle)
        #expect(!session.isActive)

        let started = session.start(now: now, interval: .seconds(3))
        #expect(started)
        #expect(session.phase == .running)
        #expect(session.deadline == now.advanced(by: .seconds(3)))
        #expect(session.generation == 1)

        let deadline = session.deadline
        let restarted = session.start(now: now.advanced(by: .seconds(1)), interval: .seconds(3))
        #expect(!restarted)
        #expect(session.deadline == deadline)
        #expect(session.generation == 1)
    }

    @Test("timeout is false before the deadline, becomes pending afterward, and commit advances to the next deadline")
    func timeoutThenCommit() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(3))

        let early = session.timeout(now: now.advanced(by: .seconds(2.999)))
        #expect(!early)
        let earlyCommit = session.commit(now: now.advanced(by: .seconds(2.999)), interval: .seconds(3))
        #expect(!earlyCommit)

        let due = session.timeout(now: now.advanced(by: .seconds(3)))
        #expect(due)
        #expect(session.pendingDue?.generation == session.generation)
        #expect(session.phase == .running)

        let commitTime = now.advanced(by: .seconds(3.2))
        let committed = session.commit(now: commitTime, interval: .seconds(3))
        #expect(committed)
        #expect(session.pendingDue == nil)
        #expect(session.phase == .running)
        #expect(session.deadline == commitTime.advanced(by: .seconds(3)))

        let secondCommit = session.commit(now: commitTime.advanced(by: .seconds(1)), interval: .seconds(3))
        #expect(!secondCommit)
    }

    @Test("An arrow after timeout cancels pending work and takes priority with its own deadline")
    func arrowCancelsPendingDue() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(3))

        let due = session.timeout(now: now.advanced(by: .seconds(3)))
        #expect(due)
        let arrowTime = now.advanced(by: .seconds(3.1))
        let arrowed = session.arrow(now: arrowTime, interval: .seconds(3))
        #expect(arrowed)

        #expect(session.pendingDue == nil)
        #expect(session.phase == .waitingAfterArrow)
        #expect(session.deadline == arrowTime.advanced(by: .seconds(3)))
        let committed = session.commit(now: arrowTime.advanced(by: .seconds(0.1)), interval: .seconds(3))
        #expect(!committed)
    }

    @Test("A deadline after an arrow allows commit to perform the next advance")
    func dueAfterArrowCommits() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(3))

        let arrowTime = now.advanced(by: .seconds(1))
        let arrowed = session.arrow(now: arrowTime, interval: .seconds(3))
        #expect(arrowed)
        let early = session.timeout(now: arrowTime.advanced(by: .seconds(2.999)))
        #expect(!early)

        let dueTime = arrowTime.advanced(by: .seconds(3))
        let due = session.timeout(now: dueTime)
        #expect(due)
        #expect(session.hasPendingDue(for: session.generation))
        let committed = session.commit(now: dueTime.advanced(by: .seconds(0.01)), interval: .seconds(3))
        #expect(committed)
        #expect(session.phase == .running)
    }

    @Test("Stopping invalidates waits and pending work; restarting advances the generation")
    func stopInvalidates() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(3))
        let due = session.timeout(now: now.advanced(by: .seconds(3)))
        #expect(due)

        let stopped = session.stop()
        #expect(stopped)
        #expect(session.phase == .idle)
        #expect(session.deadline == nil)
        #expect(session.pendingDue == nil)
        let committed = session.commit(now: now.advanced(by: .seconds(3.1)), interval: .seconds(3))
        #expect(!committed)
        let stoppedAgain = session.stop()
        #expect(!stoppedAgain)

        let generation = session.generation
        let restarted = session.start(now: now.advanced(by: .seconds(4)), interval: .seconds(3))
        #expect(restarted)
        #expect(session.generation == generation + 1)
    }

    @Test("Arrows, timeout, and commit do nothing while idle")
    func idleIgnoresInputs() {
        var session = SlideshowSession()
        let now = t0

        let arrowed = session.arrow(now: now, interval: .seconds(3))
        #expect(!arrowed)
        let due = session.timeout(now: now.advanced(by: .seconds(10)))
        #expect(!due)
        let committed = session.commit(now: now.advanced(by: .seconds(10)), interval: .seconds(3))
        #expect(!committed)
        #expect(session.phase == .idle)
    }

    @Test("remaining returns time until the deadline, zero after it, and nil while idle")
    func remaining() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(2.5))

        #expect(session.remaining(at: now) == .seconds(2.5))
        #expect(session.remaining(at: now.advanced(by: .seconds(1))) == .seconds(1.5))
        #expect(session.remaining(at: now.advanced(by: .seconds(3))) == Duration.zero)

        session.stop()
        #expect(session.remaining(at: now) == nil)
    }

    @Test("Cannot commit pending work from a different generation")
    func stalePendingCannotCommit() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(3))
        let due = session.timeout(now: now.advanced(by: .seconds(3)))
        #expect(due)
        let oldGeneration = session.generation

        session.arrow(now: now.advanced(by: .seconds(3.1)), interval: .seconds(3))
        #expect(session.generation != oldGeneration)
        #expect(!session.hasPendingDue(for: oldGeneration))
    }

    @Test("Advances once only at the configured deadline and measures the next interval from commit time after a delay", arguments: [1, 3, 10])
    func configurableIntervals(seconds: Int) {
        var session = SlideshowSession()
        let now = t0
        let interval = Duration.seconds(seconds)
        let started = session.start(now: now, interval: interval)
        #expect(started)
        let deadline = now.advanced(by: interval)
        let early = session.timeout(now: deadline.advanced(by: .milliseconds(-1)))
        #expect(!early)
        let earlyCommit = session.commit(now: deadline.advanced(by: .milliseconds(-1)), interval: interval)
        #expect(!earlyCommit)
        #expect(session.deadline == deadline)
        let due = session.timeout(now: deadline)
        #expect(due)
        let committed = session.commit(now: deadline, interval: interval)
        #expect(committed)
        let secondCommit = session.commit(now: deadline, interval: interval)
        #expect(!secondCommit)
        #expect(session.deadline == deadline.advanced(by: interval))

        let late = deadline.advanced(by: interval * 10)
        let lateDue = session.timeout(now: late)
        #expect(lateDue)
        let lateCommit = session.commit(now: late, interval: interval)
        #expect(lateCommit)
        let secondLateCommit = session.commit(now: late, interval: interval)
        #expect(!secondLateCommit)
        #expect(session.deadline == late.advanced(by: interval))
    }

    @Test("Changing the interval preserves the scheduled deadline and uses the new interval after the next commit")
    func intervalChangesAfterCommit() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(5))
        let deadline = now.advanced(by: .seconds(5))
        let earlyCommit = session.commit(now: now.advanced(by: .seconds(2)), interval: .seconds(2))
        #expect(!earlyCommit)
        #expect(session.deadline == deadline)
        #expect(session.remaining(at: now.advanced(by: .seconds(2))) == .seconds(3))
        let early = session.timeout(now: deadline.advanced(by: .milliseconds(-1)))
        #expect(!early)
        let due = session.timeout(now: deadline)
        #expect(due)
        #expect(session.deadline == deadline)
        let committed = session.commit(now: deadline, interval: .seconds(2))
        #expect(committed)
        #expect(session.deadline == deadline.advanced(by: .seconds(2)))
    }

    @Test("Arrows wait using the latest interval; changes during the wait apply to the cycle after it")
    func intervalChangesWhileWaitingAfterArrow() {
        var session = SlideshowSession()
        let now = t0
        session.start(now: now, interval: .seconds(3))
        let arrowTime = now.advanced(by: .seconds(1))
        let arrowed = session.arrow(now: arrowTime, interval: .seconds(5))
        #expect(arrowed)
        let deadline = arrowTime.advanced(by: .seconds(5))
        #expect(session.phase == .waitingAfterArrow)
        #expect(session.deadline == deadline)
        let earlyCommit = session.commit(now: arrowTime.advanced(by: .seconds(2)), interval: .seconds(2))
        #expect(!earlyCommit)
        #expect(session.deadline == deadline)
        let early = session.timeout(now: deadline.advanced(by: .milliseconds(-1)))
        #expect(!early)
        let due = session.timeout(now: deadline)
        #expect(due)
        let committed = session.commit(now: deadline, interval: .seconds(2))
        #expect(committed)
        #expect(session.phase == .running)
        #expect(session.deadline == deadline.advanced(by: .seconds(2)))
    }
}
