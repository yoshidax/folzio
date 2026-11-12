import CoreGraphics
import Testing
@testable import FolzioCore

@Suite("PreviewZoom")
struct PreviewZoomTests {
    @Test("Step, limits, and fit constants")
    func constants() {
        #expect(PreviewZoom.step == 25)
        #expect(PreviewZoom.minimum == 25)
        #expect(PreviewZoom.maximum == 800)
        #expect(PreviewZoom.fit.percentage == 100)
    }

    @Test("Accepts valid percentages", arguments: [25, 50, 100, 775, 800])
    func acceptsValidPercentages(percentage: Int) {
        #expect(PreviewZoom(percentage: percentage)?.percentage == Double(percentage))
    }

    @Test("Rejects out-of-range values", arguments: [0, -25, 801])
    func rejectsInvalidPercentages(percentage: Int) {
        #expect(PreviewZoom(percentage: percentage) == nil)
    }

    @Test("scale is the percentage divided by 100")
    func scale() throws {
        #expect(try #require(PreviewZoom(percentage: 25)).scale == 0.25)
        #expect(PreviewZoom.fit.scale == 1.0)
        #expect(try #require(PreviewZoom(percentage: 800)).scale == 8.0)
    }

    @Test("Zoom in adds 25 points and stops at 800%")
    func zoomsIn() throws {
        let first = PreviewZoom.fit.zoomedIn()
        #expect(first.percentage == 125)
        #expect(first.zoomedIn().percentage == 150)

        let maximum = try #require(PreviewZoom(percentage: 800))
        #expect(maximum.zoomedIn() == maximum)
    }

    @Test("Zoom out subtracts 25 points and stops at 25%")
    func zoomsOut() throws {
        var zoom = try #require(PreviewZoom(percentage: 150))
        var steps: [Double] = []
        for _ in 0..<5 {
            zoom = zoom.zoomedOut()
            steps.append(zoom.percentage)
        }
        #expect(steps == [125, 100, 75, 50, 25])
        #expect(zoom.zoomedOut() == zoom)
    }

    @Test("28 zoom-in steps from 100% reach 800% and further steps do not change it")
    func reachesMaximumAfterTwentyEightSteps() {
        var zoom = PreviewZoom.fit
        for _ in 0..<28 {
            zoom = zoom.zoomedIn()
        }
        #expect(zoom.percentage == 800)
        #expect(zoom.zoomedIn().percentage == 800)
    }

    @Test("Availability at the upper and lower limits")
    func canZoom() throws {
        #expect(try #require(PreviewZoom(percentage: 800)).canZoomIn == false)
        #expect(try #require(PreviewZoom(percentage: 775)).canZoomIn)
        #expect(try #require(PreviewZoom(percentage: 25)).canZoomOut == false)
        #expect(try #require(PreviewZoom(percentage: 50)).canZoomOut)
    }

    @Test("Compares in percentage order")
    func comparable() throws {
        let small = try #require(PreviewZoom(percentage: 75))
        let large = try #require(PreviewZoom(percentage: 125))
        #expect(small < .fit)
        #expect(PreviewZoom.fit < large)
        #expect(!(large < small))
    }
    @Test("Wheel zoom is reversible and clamps at bounds")
    func wheelZoom() throws {
        let initial = try #require(PreviewZoom(percentage: 110.5))
        let enlarged = initial.scaled(by: 1.1)
        #expect(abs(enlarged.percentage - 121.55) < 0.0001)
        #expect(abs(enlarged.scaled(by: 1 / 1.1).percentage - initial.percentage) < 0.0001)
        #expect(initial.scaled(by: 100).percentage == 800)
        #expect(initial.scaled(by: 0.01).percentage == 25)
        #expect(initial.zoomedIn().percentage == 135.5)
        #expect(PreviewZoom(percentage: Double.nan) == nil)
    }

    @Test("Reversing a continuous pinch at either limit immediately moves away without a jump")
    func pinchReversesAtLimits() throws {
        var zoom = PreviewZoom.fit
        for _ in 0..<100 { zoom = zoom.pinched(by: -0.05) }
        #expect(zoom.percentage == 25)
        let aboveMinimum = zoom.pinched(by: 0.05)
        #expect(abs(aboveMinimum.percentage - 26.25) < 0.0001)

        zoom = PreviewZoom.fit
        for _ in 0..<100 { zoom = zoom.pinched(by: 0.05) }
        #expect(zoom.percentage == 800)
        let belowMaximum = zoom.pinched(by: -0.05)
        #expect(abs(belowMaximum.percentage - 760) < 0.0001)
        #expect(zoom.pinched(by: .nan) == zoom)
    }
}
