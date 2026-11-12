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
    @Test("Zoom preserves the image point under the pointer when unclamped")
    func anchor() {
        let old = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 400), viewport: CGSize(width: 200, height: 200), center: CGPoint(x: 0.5, y: 0.5))
        let point = CGPoint(x: 150, y: 75)
        let next = old.resized(imageSize: CGSize(width: 600, height: 600), viewport: CGSize(width: 200, height: 200), anchoredAt: point)
        let before = CGPoint(x: (point.x - old.frame.minX) / old.frame.width, y: (point.y - old.frame.minY) / old.frame.height)
        let after = CGPoint(x: (point.x - next.frame.minX) / next.frame.width, y: (point.y - next.frame.minY) / next.frame.height)
        #expect(abs(before.x - after.x) < 0.0001 && abs(before.y - after.y) < 0.0001)
    }

    @Test("Movement follows deltas, clamps at the edges, and rejects nonfinite values")
    func movement() {
        let viewport = CGSize(width: 200, height: 200)
        let old = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 400), viewport: viewport, center: CGPoint(x: 0.5, y: 0.5))
        let moved = old.moved(x: 30, y: -20, viewport: viewport)
        #expect(abs(moved.frame.minX + 130) < 0.0001 && abs(moved.frame.minY + 80) < 0.0001)
        let edge = moved.moved(x: 1000, y: -1000, viewport: viewport)
        #expect(edge.frame.origin == CGPoint(x: -200, y: 0))
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            #expect(old.moved(x: invalid, y: 10, viewport: viewport).frame == old.frame)
            #expect(old.moved(x: 10, y: invalid, viewport: viewport).center == old.center)
        }
    }

    @Test("Anchored resize clamps, centers small images, and rejects invalid inputs")
    func anchoredResizeEdges() {
        let viewport = CGSize(width: 200, height: 200)
        let old = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 400), viewport: viewport, center: CGPoint(x: 0.25, y: 0.25))
        let fitted = PreviewScrollLayout(imageSize: CGSize(width: 100, height: 100), viewport: viewport, center: CGPoint(x: 0.5, y: 0.5))
        let enlarged = fitted.resized(imageSize: CGSize(width: 400, height: 400), viewport: viewport, anchoredAt: CGPoint(x: 10, y: 10))
        #expect(enlarged.frame.origin == .zero)
        let small = old.resized(imageSize: CGSize(width: 100, height: 100), viewport: viewport, anchoredAt: CGPoint(x: 20, y: 20))
        #expect(small.frame == CGRect(x: 50, y: 50, width: 100, height: 100))
        for invalid in [CGFloat.nan, .infinity, -.infinity] {
            let invalidAnchor = old.resized(imageSize: CGSize(width: 600, height: 600), viewport: viewport, anchoredAt: CGPoint(x: invalid, y: 10))
            let invalidSize = old.resized(imageSize: CGSize(width: invalid, height: 600), viewport: viewport, anchoredAt: .zero)
            #expect(invalidAnchor.frame == old.frame && invalidAnchor.center == old.center)
            #expect(invalidSize.frame == old.frame && invalidSize.center == old.center)
        }
    }
}
