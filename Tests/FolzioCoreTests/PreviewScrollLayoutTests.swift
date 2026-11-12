import CoreGraphics
import Testing
@testable import FolzioCore

@Suite("Preview scroll layout")
struct PreviewScrollLayoutTests {
    @Test("Zoom preserves the anchor and clamps at image edges")
    func anchoredZoom() {
        let viewport = CGSize(width: 200, height: 200)
        let original = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 400), viewport: viewport, center: CGPoint(x: 0.5, y: 0.5))
        let anchor = CGPoint(x: 40, y: 150)
        let enlarged = original.zoomed(to: CGSize(width: 600, height: 600), viewport: viewport, anchor: anchor)
        #expect(abs((anchor.x - original.frame.minX) / original.frame.width - (anchor.x - enlarged.frame.minX) / enlarged.frame.width) < 0.0001)
        #expect(abs((anchor.y - original.frame.minY) / original.frame.height - (anchor.y - enlarged.frame.minY) / enlarged.frame.height) < 0.0001)
        let edge = original.zoomed(to: CGSize(width: 250, height: 250), viewport: viewport, anchor: CGPoint(x: 0, y: 200))
        #expect(edge.frame.origin == CGPoint(x: -50, y: 0))
        let smaller = enlarged.zoomed(to: CGSize(width: 100, height: 100), viewport: viewport, anchor: anchor)
        #expect(smaller.frame == CGRect(x: 50, y: 50, width: 100, height: 100))
        #expect(original.zoomed(to: CGSize(width: CGFloat.infinity, height: 10), viewport: viewport, anchor: anchor).frame == original.frame)
        #expect(original.zoomed(to: CGSize(width: 600, height: 600), viewport: viewport, anchor: CGPoint(x: CGFloat.nan, y: 0)).frame == original.frame)
    }

    @Test("Movement follows the input and clamps at the image edge")
    func movement() {
        let viewport = CGSize(width: 200, height: 200)
        let layout = PreviewScrollLayout(imageSize: CGSize(width: 400, height: 400), viewport: viewport, center: CGPoint(x: 0.5, y: 0.5))
        let moved = layout.moved(x: 40, y: -30, viewport: viewport)
        #expect(abs(moved.frame.minX + 140) < 0.001)
        #expect(abs(moved.frame.minY + 70) < 0.001)
        let edge = moved.moved(x: 1000, y: -1000, viewport: viewport)
        #expect(edge.frame.origin == CGPoint(x: -200, y: 0))
        #expect(layout.moved(x: CGFloat.nan, y: 0, viewport: viewport).frame == layout.frame)
    }

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
