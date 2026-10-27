import CoreGraphics
import Testing
@testable import FolzioCore

@Suite("Preview scroll layout")
struct PreviewScrollLayoutTests {
    @Test("Centers a single axis and clamps an overflowing axis to both ends")
    func singleAxis() {
        let left = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 100), viewport: CGSize(width: 200, height: 200), center: CGPoint(x: 0, y: 0))
        #expect(left.frame == CGRect(x: 0, y: 50, width: 400, height: 100))
        #expect(left.center == CGPoint(x: 0.25, y: 0.5))
        #expect(left.horizontal && !left.vertical)
        let right = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 100), viewport: CGSize(width: 200, height: 200), center: CGPoint(x: 1, y: 1))
        #expect(right.frame.origin == CGPoint(x: -200, y: 50))
    }

    @Test("Relative center at the four corners of both axes and after resizing")
    func bothAxes() {
        let a = PreviewScrollLayout(imageSize: CGSize(width: 800, height: 600), viewport: CGSize(width: 200, height: 200), center: CGPoint(x: 0.7, y: 0.6))
        #expect(a.horizontal && a.vertical)
        #expect(abs(a.center.x - 0.7) < 0.0001 && abs(a.center.y - 0.6) < 0.0001)
        let b = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 300), viewport: CGSize(width: 200, height: 200), center: a.center)
        #expect(abs(b.center.x - 0.7) < 0.0001 && abs(b.center.y - 0.6) < 0.0001)
        let edge = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 300), viewport: CGSize(width: 200, height: 200), center: CGPoint(x: 1, y: 1))
        #expect(abs(edge.frame.minX + 200) < 0.0001 && abs(edge.frame.minY + 100) < 0.0001)
    }

    @Test("Handles equal and invalid dimensions safely")
    func invalidAndFit() {
        let fit = PreviewScrollLayout(imageSize: CGSize(width: 200, height: 100), viewport: CGSize(width: 200, height: 200), center: CGPoint(x: 0, y: 0))
        #expect(!fit.horizontal && !fit.vertical && fit.center == CGPoint(x: 0.5, y: 0.5))
        for width in [CGFloat.zero, -1, .infinity, .nan] {
            let invalid = PreviewScrollLayout(imageSize: CGSize(width: width, height: 100), viewport: CGSize(width: 200, height: 200), center: .zero)
            #expect(invalid.frame == .zero && !invalid.horizontal && !invalid.vertical)
        }
    }
}
