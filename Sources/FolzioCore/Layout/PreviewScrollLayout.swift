import CoreGraphics

/// Maintains the relative center within the image and clamps the position on overflowing axes to the visible
/// range.
public struct PreviewScrollLayout: Sendable {
    public let frame: CGRect
    public let center: CGPoint
    public let horizontal: Bool
    public let vertical: Bool

    public init(imageSize: CGSize, viewport: CGSize, center: CGPoint) {
        guard [imageSize.width, imageSize.height, viewport.width, viewport.height].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            frame = .zero
            self.center = CGPoint(x: 0.5, y: 0.5)
            horizontal = false
            vertical = false
            return
        }
        func axis(_ image: CGFloat, _ view: CGFloat, _ requested: CGFloat) -> (CGFloat, CGFloat, Bool) {
            guard image > view else { return ((view - image) / 2, 0.5, false) }
            let minimum = view / (2 * image)
            let position = min(1 - minimum, max(minimum, requested.isFinite ? requested : 0.5))
            return (view / 2 - image * position, position, true)
        }
        let x = axis(imageSize.width, viewport.width, center.x)
        let y = axis(imageSize.height, viewport.height, center.y)
        frame = CGRect(x: x.0, y: y.0, width: imageSize.width, height: imageSize.height)
        self.center = CGPoint(x: x.1, y: y.1)
        horizontal = x.2
        vertical = y.2
    }
    /// Returns a new layout after moving the viewport center in image coordinates.
    public func moved(x: CGFloat, y: CGFloat, viewport: CGSize) -> PreviewScrollLayout {
        guard frame.width > 0, frame.height > 0, x.isFinite, y.isFinite else { return self }
        return PreviewScrollLayout(
            imageSize: frame.size, viewport: viewport,
            center: CGPoint(x: center.x + x / frame.width, y: center.y + y / frame.height)
        )
    }

    /// Keeps the image point under the anchor fixed when possible, clamping at the image edges.
    public func zoomed(to imageSize: CGSize, viewport: CGSize, anchor: CGPoint) -> PreviewScrollLayout {
        guard frame.width > 0, frame.height > 0,
              [imageSize.width, imageSize.height, viewport.width, viewport.height].allSatisfy({ $0.isFinite && $0 > 0 }),
              anchor.x.isFinite, anchor.y.isFinite else { return self }
        let imageX = (anchor.x - frame.minX) / frame.width
        let imageY = (anchor.y - frame.minY) / frame.height
        let newCenter = CGPoint(
            x: imageX + (viewport.width / 2 - anchor.x) / imageSize.width,
            y: imageY + (viewport.height / 2 - anchor.y) / imageSize.height
        )
        return PreviewScrollLayout(imageSize: imageSize, viewport: viewport, center: newCenter)
    }

}
