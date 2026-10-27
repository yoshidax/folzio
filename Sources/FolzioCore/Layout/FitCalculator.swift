import CoreGraphics

public struct FitCalculator {
    public static func fit(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else {
            return .zero
        }

        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Scales the fitted rectangle by `zoom.scale` while keeping its center (FR-029, FR-133).
    /// The origin becomes negative when the result is larger than the container. Does not round.
    public static func frame(imageSize: CGSize, in container: CGSize, zoom: PreviewZoom) -> CGRect {
        let fitted = fit(imageSize: imageSize, in: container)
        guard fitted != .zero else { return .zero }
        guard zoom != .fit else { return fitted }

        let size = CGSize(width: fitted.width * zoom.scale, height: fitted.height * zoom.scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }
}
