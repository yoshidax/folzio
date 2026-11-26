import AppKit
import FolzioCore

/// Image view that overlays the video badge at the bottom-right corner of the drawn image (FR-415, FR-418).
/// The badge is a subview placed by frame in `layout()`, so it adds no constraints and leaves the image untouched.
@MainActor
final class VideoBadgeImageView: NSImageView {
    private let badgeView = VideoBadgeView()

    /// Whether to show the badge. Callers set it only while the image is a generated frame of a video (FR-417).
    var showsVideoBadge = false {
        didSet {
            guard showsVideoBadge != oldValue else { return }
            needsLayout = true
            updateBadgeFrame()
        }
    }

    var badgeMetrics: VideoBadgeLayout.Metrics = VideoBadgeLayout.thumbnail {
        didSet { needsLayout = true }
    }

    /// The badge view. Read by tests.
    var videoBadgeView: NSView { badgeView }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        badgeView.isHidden = true
        addSubview(badgeView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var image: NSImage? {
        didSet { needsLayout = true }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        // Thumbnail size and pane width changes resize this view through Auto Layout (FR-416).
        if changed { needsLayout = true }
    }

    override func layout() {
        super.layout()
        updateBadgeFrame()
    }

    private func updateBadgeFrame() {
        guard showsVideoBadge, let image else {
            badgeView.isHidden = true
            return
        }
        // Match how the image view draws: `scaleProportionallyDown` never enlarges the image (research.md R2).
        let drawn = VideoBadgeLayout.imageRect(
            imageSize: image.size,
            in: bounds.size,
            allowsUpscaling: imageScaling != .scaleProportionallyDown
        )
        guard let frame = VideoBadgeLayout.badgeFrame(imageRect: drawn, metrics: badgeMetrics, flipped: isFlipped) else {
            badgeView.isHidden = true
            return
        }
        // Align to device pixels so the outline and the symbol stay sharp on Retina displays.
        let aligned = backingAlignedRect(frame, options: .alignAllEdgesNearest)
        if badgeView.frame != aligned {
            badgeView.frame = aligned
            badgeView.needsDisplay = true
        }
        badgeView.isHidden = false
    }
}

/// Translucent circle with a play symbol. It takes no clicks and is not an accessibility element, so the item under
/// it behaves as before (FR-420, EC-290).
@MainActor
final class VideoBadgeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height)
        guard diameter > 0 else { return }

        // The same look in light and dark appearances and in every selection state (EC-288).
        let lineWidth = max(0.75, diameter * 0.06)
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
        circle.lineWidth = lineWidth
        NSColor.black.withAlphaComponent(0.45).setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.7).setStroke()
        circle.stroke()

        let configuration = NSImage.SymbolConfiguration(pointSize: diameter * 0.45, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let symbol = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return }
        let size = symbol.size
        // Shift right a little so the triangle looks centered.
        let symbolRect = NSRect(
            x: bounds.midX - size.width / 2 + diameter * 0.04,
            y: bounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}
