import CoreGraphics

/// Maintains the relative center within the image and clamps the position on overflowing axes to the visible
/// range.
public struct PreviewScrollLayout: Sendable {
    public let frame: CGRect
    public let center: CGPoint
    public let horizontal: Bool
    public let vertical: Bool

    public func resized(imageSize: CGSize, viewport: CGSize, anchoredAt point: CGPoint) -> PreviewScrollLayout {
        guard [frame.width, frame.height, imageSize.width, imageSize.height, viewport.width, viewport.height]
            .allSatisfy({ $0.isFinite && $0 > 0 }),
              point.x.isFinite, point.y.isFinite else {
            return self
        }
        let relative = CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
        let nextCenter = CGPoint(
            x: relative.x + (viewport.width / 2 - point.x) / imageSize.width,
            y: relative.y + (viewport.height / 2 - point.y) / imageSize.height
        )
        guard nextCenter.x.isFinite, nextCenter.y.isFinite else { return self }
        return PreviewScrollLayout(imageSize: imageSize, viewport: viewport, center: nextCenter)
    }

    public func moved(x: CGFloat, y: CGFloat, viewport: CGSize) -> PreviewScrollLayout {
        guard x.isFinite, y.isFinite,
              [frame.width, frame.height, viewport.width, viewport.height].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return self
        }
        let nextCenter = CGPoint(x: center.x + x / frame.width, y: center.y + y / frame.height)
        guard nextCenter.x.isFinite, nextCenter.y.isFinite else { return self }
        return PreviewScrollLayout(imageSize: frame.size, viewport: viewport, center: nextCenter)
    }

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
}
