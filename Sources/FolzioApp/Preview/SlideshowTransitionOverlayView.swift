import AppKit
import QuartzCore

/// Snapshot of the previous media item. Input and accessibility pass through to the real view below.
@MainActor
final class SlideshowTransitionOverlayView: NSView {
    private let snapshotLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(snapshotLayer)
        setAccessibilityElement(false)
        setAccessibilityChildren([])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(image: CGImage?, frame: CGRect, gravity: CALayerContentsGravity) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = NSColor.black.cgColor
        snapshotLayer.frame = frame
        snapshotLayer.contents = image
        snapshotLayer.contentsGravity = gravity
        snapshotLayer.contentsScale = window?.backingScaleFactor ?? 2
        isHidden = false
        CATransaction.commit()
    }

    func clear() {
        isHidden = true
        snapshotLayer.contents = nil
    }
}
