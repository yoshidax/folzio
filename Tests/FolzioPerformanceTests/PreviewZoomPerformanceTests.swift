import CoreGraphics
import Foundation
import Testing
@testable import FolzioCore

// Add to the existing PerformanceBaseline suite (.serialized).
// A separate suite would run in parallel with the existing performance tests, and CPU contention could exceed the
// thresholds.
extension PerformanceBaselineTests {
    @Test("Computes 32 zoom levels 1,000 times each for a 24 MP image within 1 second")
    func previewZoomFrameCalculationWithinBudget() throws {
        let imageSize = CGSize(width: 6000, height: 4000)
        let container = CGSize(width: 1600, height: 1200)
        let levels = stride(from: PreviewZoom.minimum, through: PreviewZoom.maximum, by: PreviewZoom.step)
            .compactMap { PreviewZoom(percentage: $0) }
        #expect(levels.count == 32)

        var checksum: CGFloat = 0
        let start = ContinuousClock.now
        for zoom in levels {
            for _ in 0..<1000 {
                checksum += FitCalculator.frame(imageSize: imageSize, in: container, zoom: zoom).width
            }
        }
        let elapsed = ContinuousClock.now - start

        #expect(checksum > 0)
        #expect(
            elapsed < .seconds(1),
            "32,000 zoom rectangle calculations must take at most one second (measured: \(elapsed))"
        )
    }
}
