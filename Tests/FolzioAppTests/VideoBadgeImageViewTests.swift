import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Video badge image view", .serialized)
@MainActor
struct VideoBadgeImageViewTests {
    /// Puts an image view of the given side in a window and lays it out.
    private func withImageView(
        side: CGFloat,
        imageSize: NSSize,
        body: (VideoBadgeImageView, NSWindow) throws -> Void
    ) rethrows {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let imageView = VideoBadgeImageView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = NSImage(size: imageSize)
        window.contentView?.addSubview(imageView)
        try body(imageView, window)
    }

    private func expectedFrame(of imageView: VideoBadgeImageView) throws -> NSRect {
        let image = try #require(imageView.image)
        let drawn = VideoBadgeLayout.imageRect(
            imageSize: image.size,
            in: imageView.bounds.size,
            allowsUpscaling: imageView.imageScaling != .scaleProportionallyDown
        )
        let frame = try #require(
            VideoBadgeLayout.badgeFrame(imageRect: drawn, metrics: imageView.badgeMetrics, flipped: imageView.isFlipped)
        )
        return imageView.backingAlignedRect(frame, options: .alignAllEdgesNearest)
    }

    /// Whether the badge sits in the bottom half of the drawn image, in the view's own orientation.
    private func isInBottomHalf(_ badge: NSRect, of imageView: VideoBadgeImageView) throws -> Bool {
        let image = try #require(imageView.image)
        let drawn = VideoBadgeLayout.imageRect(imageSize: image.size, in: imageView.bounds.size, allowsUpscaling: true)
        return imageView.isFlipped ? badge.midY > drawn.midY : badge.midY < drawn.midY
    }

    @Test("The badge is placed at the bottom-right of the drawn image (FR-415)")
    func placement() throws {
        try withImageView(side: 120, imageSize: NSSize(width: 160, height: 90)) { imageView, _ in
            imageView.showsVideoBadge = true
            imageView.layoutSubtreeIfNeeded()
            let badge = imageView.videoBadgeView
            let expected = try expectedFrame(of: imageView)
            let inBottomHalf = try isInBottomHalf(badge.frame, of: imageView)
            #expect(!badge.isHidden)
            #expect(badge.frame == expected)
            #expect(inBottomHalf)
            #expect(badge.frame.midX > imageView.bounds.midX)
        }
    }

    @Test("The badge is hidden when turned off or without an image (FR-417)")
    func hidden() {
        withImageView(side: 120, imageSize: NSSize(width: 160, height: 90)) { imageView, _ in
            imageView.layoutSubtreeIfNeeded()
            #expect(imageView.videoBadgeView.isHidden)

            imageView.showsVideoBadge = true
            imageView.layoutSubtreeIfNeeded()
            #expect(!imageView.videoBadgeView.isHidden)

            imageView.image = nil
            imageView.layoutSubtreeIfNeeded()
            #expect(imageView.videoBadgeView.isHidden)
        }
    }

    @Test("The badge takes no clicks or drops and is not an accessibility element (FR-420, EC-290)")
    func passive() {
        withImageView(side: 120, imageSize: NSSize(width: 160, height: 90)) { imageView, _ in
            imageView.showsVideoBadge = true
            imageView.layoutSubtreeIfNeeded()
            let badge = imageView.videoBadgeView
            let center = NSPoint(x: badge.frame.midX, y: badge.frame.midY)
            #expect(badge.hitTest(center) == nil)
            #expect(imageView.hitTest(center) !== badge)
            #expect(!badge.isAccessibilityElement())
            #expect(badge.registeredDraggedTypes.isEmpty)
        }
    }

    @Test("The badge follows size changes of the image view (FR-416, US95-AS6–AS8)")
    func followsResize() throws {
        try withImageView(side: 40, imageSize: NSSize(width: 160, height: 90)) { imageView, _ in
            imageView.showsVideoBadge = true
            for side: CGFloat in [40, 120, 504] {
                imageView.setFrameSize(NSSize(width: side, height: side))
                imageView.layoutSubtreeIfNeeded()
                let expected = try expectedFrame(of: imageView)
                #expect(imageView.videoBadgeView.frame == expected, "side \(side)")
            }
        }
    }

    @Test("A portrait video keeps the badge off the side margins (US95-AS3)")
    func portrait() throws {
        try withImageView(side: 120, imageSize: NSSize(width: 90, height: 160)) { imageView, _ in
            imageView.showsVideoBadge = true
            imageView.layoutSubtreeIfNeeded()
            let image = try #require(imageView.image)
            let drawn = VideoBadgeLayout.imageRect(
                imageSize: image.size,
                in: imageView.bounds.size,
                allowsUpscaling: true
            )
            #expect(imageView.videoBadgeView.frame.maxX <= drawn.maxX + 0.5)
            #expect(imageView.videoBadgeView.frame.minX >= drawn.minX - 0.5)
        }
    }
}
