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

    @Test("Accepts only multiples of 25 between 25 and 800", arguments: [25, 50, 100, 775, 800])
    func acceptsValidPercentages(percentage: Int) {
        #expect(PreviewZoom(percentage: percentage)?.percentage == percentage)
    }

    @Test("Rejects out-of-range values and values that are not multiples of 25", arguments: [0, -25, 30, 101, 799, 801])
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
        var steps: [Int] = []
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
}
