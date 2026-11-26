import CoreGraphics

/// Rules for the badge that marks a video on its representative frame (FR-415–FR-418, FR-421).
/// Decides only from the item kind and the rectangle the frame is drawn in, and reads no files.
public enum VideoBadgeLayout {
    /// Size rules relative to the drawn frame. Lengths are in points.
    public struct Metrics: Sendable, Equatable {
        /// Diameter as a fraction of the long side of the drawn frame
        public var diameterRatio: Double
        public var minDiameter: Double
        public var maxDiameter: Double
        /// Margin from the right and bottom edges as a fraction of the long side
        public var marginRatio: Double
        public var minMargin: Double
        public var maxMargin: Double

        public init(
            diameterRatio: Double,
            minDiameter: Double,
            maxDiameter: Double,
            marginRatio: Double,
            minMargin: Double,
            maxMargin: Double
        ) {
            self.diameterRatio = diameterRatio
            self.minDiameter = minDiameter
            self.maxDiameter = maxDiameter
            self.marginRatio = marginRatio
            self.minMargin = minMargin
            self.maxMargin = maxMargin
        }

        /// Thumbnail mode: 0.2 of the long side within 10–40 pt.
        public static let thumbnail = Metrics(
            diameterRatio: 0.2, minDiameter: 10, maxDiameter: 40,
            marginRatio: 0.04, minMargin: 2, maxMargin: 8
        )

        /// Leading icon of the list mode (16 pt): 0.5 of the long side, at most 8 pt, no margin.
        public static let listIcon = Metrics(
            diameterRatio: 0.5, minDiameter: 0, maxDiameter: 8,
            marginRatio: 0, minMargin: 0, maxMargin: 0
        )
    }

    /// Thumbnail mode: 0.2 of the long side within 10–40 pt.
    public static let thumbnail = Metrics.thumbnail

    /// Leading icon of the list mode (16 pt): 0.5 of the long side, at most 8 pt, no margin.
    public static let listIcon = Metrics.listIcon

    /// Whether the item gets a badge: a video showing its generated frame, not a generic icon (FR-417).
    public static func isShown(kind: ListItemKind, showingRepresentativeFrame: Bool) -> Bool {
        kind.isVideo && showingRepresentativeFrame
    }

    /// The rectangle an image is drawn in, scaled proportionally and centered. Without upscaling, an image smaller
    /// than the container keeps its size, like an image view with `scaleProportionallyDown`.
    public static func imageRect(imageSize: CGSize, in container: CGSize, allowsUpscaling: Bool) -> CGRect {
        let fitted = FitCalculator.fit(imageSize: imageSize, in: container)
        guard !allowsUpscaling, fitted.width > imageSize.width else { return fitted }
        return CGRect(
            x: (container.width - imageSize.width) / 2,
            y: (container.height - imageSize.height) / 2,
            width: imageSize.width,
            height: imageSize.height
        )
    }

    /// The badge frame at the bottom-right corner of `imageRect`, or nil for an empty or non-finite rectangle.
    /// `flipped` tells whether the origin is at the top, so that the badge stays at the bottom either way.
    /// The diameter never exceeds half of the short side, which takes precedence over the minimum (EC-286).
    public static func badgeFrame(imageRect rect: CGRect, metrics: Metrics, flipped: Bool) -> CGRect? {
        // Check the stored size: `width` and `height` return absolute values, so a negative size would pass.
        let values = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        guard values.allSatisfy({ $0.isFinite }), rect.size.width > 0, rect.size.height > 0 else { return nil }

        let long = Double(max(rect.width, rect.height))
        let short = Double(min(rect.width, rect.height))
        let diameter = min(clamp(long * metrics.diameterRatio, metrics.minDiameter, metrics.maxDiameter), short * 0.5)
        let margin = min(clamp(long * metrics.marginRatio, metrics.minMargin, metrics.maxMargin), short * 0.25)

        let x = Double(rect.maxX) - margin - diameter
        let y = flipped ? Double(rect.maxY) - margin - diameter : Double(rect.minY) + margin
        return CGRect(x: x, y: y, width: diameter, height: diameter)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}
