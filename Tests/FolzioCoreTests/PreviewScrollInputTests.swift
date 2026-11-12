import Testing
@testable import FolzioCore

@Suite("Preview scroll input")
struct PreviewScrollInputTests {
    @Test("Repeated trackpad gestures without a second may-begin still pan")
    func repeatedTrackpadGestures() {
        var input = PreviewScrollInput()
        #expect(input.classify(phase: .mayBegin, isMomentum: false) == .pan)
        #expect(input.classify(phase: .began, isMomentum: false) == .pan)
        #expect(input.classify(phase: .changed, isMomentum: false) == .pan)
        #expect(input.classify(phase: .ended, isMomentum: false) == .pan)
        #expect(input.classify(phase: .none, isMomentum: true) == .pan)
        #expect(input.classify(phase: .began, isMomentum: false) == .pan)
        #expect(input.classify(phase: .changed, isMomentum: false) == .pan)
        #expect(input.classify(phase: .ended, isMomentum: false) == .pan)
        #expect(input.classify(phase: .none, isMomentum: true) == .pan)
    }

    @Test("Phase-less mouse wheel zooms, including after a trackpad gesture")
    func wheelAfterTrackpad() {
        var input = PreviewScrollInput()
        _ = input.classify(phase: .began, isMomentum: false)
        _ = input.classify(phase: .ended, isMomentum: false)
        #expect(input.classify(phase: .none, isMomentum: false) == .zoom)
        #expect(input.classify(phase: .none, isMomentum: false) == .zoom)
        #expect(input.classify(phase: .none, isMomentum: true) == .ignore)
    }

    @Test("Reset and cancellation discard gesture momentum")
    func reset() {
        var input = PreviewScrollInput()
        _ = input.classify(phase: .mayBegin, isMomentum: false)
        #expect(input.classify(phase: .cancelled, isMomentum: false) == .ignore)
        #expect(input.classify(phase: .none, isMomentum: true) == .ignore)
        _ = input.classify(phase: .began, isMomentum: false)
        input.reset()
        #expect(input.classify(phase: .none, isMomentum: false) == .zoom)
    }
}
