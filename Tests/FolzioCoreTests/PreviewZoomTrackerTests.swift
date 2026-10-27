import Foundation
import Testing
@testable import FolzioCore

// Cannot call a mutating method inside #expect, so store the result in a variable first.
@Suite("PreviewZoomTracker")
struct PreviewZoomTrackerTests {
    private let urlA = URL(fileURLWithPath: "/tmp/zoom/a.jpg")
    private let urlB = URL(fileURLWithPath: "/tmp/zoom/b.jpg")

    @Test("Starts at 100% with no image")
    func initialState() {
        let tracker = PreviewZoomTracker()
        #expect(tracker.level == .fit)
        #expect(tracker.imageIdentity == nil)
    }

    @Test("Re-presenting the same image keeps the zoom; a different image resets to 100%")
    func presentKeepsOrResets() {
        var tracker = PreviewZoomTracker()
        let presentedA = tracker.present(urlA)
        #expect(presentedA)
        #expect(tracker.imageIdentity == urlA)
        let presentedAgain = tracker.present(urlA)
        #expect(presentedAgain == false)

        let zoomed = tracker.zoomIn()
        #expect(zoomed)
        let presentedSame = tracker.present(urlA)
        #expect(presentedSame == false)
        #expect(tracker.level.percentage == 125)

        let presentedB = tracker.present(urlB)
        #expect(presentedB)
        #expect(tracker.level == .fit)
        #expect(tracker.imageIdentity == urlB)
    }

    @Test("Resets to 100% when there is no image (empty, video, or unavailable)")
    func presentNilResets() {
        var tracker = PreviewZoomTracker()
        tracker.present(urlA)
        tracker.zoomIn()

        let cleared = tracker.present(nil)
        #expect(cleared)
        #expect(tracker.level == .fit)
        #expect(tracker.imageIdentity == nil)
        let clearedAgain = tracker.present(nil)
        #expect(clearedAgain == false)
    }

    @Test("reset returns to 100% for the same image (for history navigation)")
    func resetKeepsIdentity() {
        var tracker = PreviewZoomTracker()
        tracker.present(urlA)
        tracker.zoomIn()

        let reset = tracker.reset()
        #expect(reset)
        #expect(tracker.level == .fit)
        #expect(tracker.imageIdentity == urlA)
        let resetAgain = tracker.reset()
        #expect(resetAgain == false)
        #expect(tracker.imageIdentity == urlA)
    }

    @Test("Zooming at the limits leaves the value unchanged and returns false")
    func clampsAtLimits() {
        var tracker = PreviewZoomTracker()
        tracker.present(urlA)
        var zoomInCount = 0
        while tracker.zoomIn() {
            zoomInCount += 1
        }
        #expect(zoomInCount == 28)
        #expect(tracker.level.percentage == 800)
        let zoomedPastMaximum = tracker.zoomIn()
        #expect(zoomedPastMaximum == false)
        #expect(tracker.level.percentage == 800)

        tracker.fit()
        var zoomOutCount = 0
        while tracker.zoomOut() {
            zoomOutCount += 1
        }
        #expect(zoomOutCount == 3)
        #expect(tracker.level.percentage == 25)
        let zoomedPastMinimum = tracker.zoomOut()
        #expect(zoomedPastMinimum == false)
        #expect(tracker.level.percentage == 25)
    }

    @Test("fit returns true only when returning from a value other than 100%")
    func fitReportsChange() {
        var tracker = PreviewZoomTracker()
        tracker.present(urlA)
        tracker.zoomIn()
        let fitted = tracker.fit()
        #expect(fitted)
        #expect(tracker.level == .fit)
        let fittedAgain = tracker.fit()
        #expect(fittedAgain == false)
    }
}
