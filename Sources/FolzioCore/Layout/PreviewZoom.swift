import CoreGraphics
import Foundation

/// Preview zoom level (FR-133). 100% is the fit-to-window display from FR-028, not actual size (A-62).
/// Accepts finite values between 25% and 800% and does not change at the limits.
public struct PreviewZoom: Sendable, Equatable, Comparable {
    public static let step = 25
    public static let minimum = 25
    public static let maximum = 800
    public static let fit = PreviewZoom(percentage: 100)!

    public let percentage: Double

    public init?(percentage: Int) {
        self.init(percentage: Double(percentage))
    }

    public init?(percentage: Double) {
        guard percentage.isFinite, percentage >= Double(Self.minimum), percentage <= Double(Self.maximum) else { return nil }
        self.percentage = percentage
    }

    /// Scale applied to the fitted rectangle
    public var scale: CGFloat { CGFloat(percentage) / 100 }

    public var canZoomIn: Bool { percentage < Double(Self.maximum) }
    public var canZoomOut: Bool { percentage > Double(Self.minimum) }

    public func zoomedIn() -> PreviewZoom {
        PreviewZoom(percentage: min(Double(Self.maximum), percentage + Double(Self.step)))!
    }

    public func zoomedOut() -> PreviewZoom {
        PreviewZoom(percentage: max(Double(Self.minimum), percentage - Double(Self.step)))!
    }

    public func scaled(by factor: Double) -> PreviewZoom {
        guard factor.isFinite, factor > 0 else { return self }
        return PreviewZoom(percentage: min(Double(Self.maximum), max(Double(Self.minimum), percentage * factor)))!
    }

    public static func pinchFactor(for magnification: Double) -> Double {
        guard magnification.isFinite else { return 1 }
        return max(0.001, 1 + magnification)
    }

    public func pinched(by magnification: Double) -> PreviewZoom {
        scaled(by: Self.pinchFactor(for: magnification))
    }

    public static func < (lhs: PreviewZoom, rhs: PreviewZoom) -> Bool {
        lhs.percentage < rhs.percentage
    }
}

/// Tracks the zoom level for the displayed image (FR-137). Resets to 100% only when the image changes.
/// Neither persists nor records in history.
public struct PreviewZoomTracker: Sendable, Equatable {
    public private(set) var level: PreviewZoom = .fit
    /// Identity of the displayed image. Nil for empty, video, or unavailable content.
    public private(set) var imageIdentity: URL?

    public init() {}

    /// Reports the displayed content. Resets to 100% and returns true only when the identity changes.
    @discardableResult
    public mutating func present(_ identity: URL?) -> Bool {
        guard identity != imageIdentity else { return false }
        imageIdentity = identity
        level = .fit
        return true
    }

    /// Resets to 100% while keeping the same image (for history navigation). Returns true when the level changes.
    @discardableResult
    public mutating func reset() -> Bool {
        fit()
    }

    @discardableResult
    public mutating func zoomIn() -> Bool {
        update(level.zoomedIn())
    }

    @discardableResult
    public mutating func zoomOut() -> Bool {
        update(level.zoomedOut())
    }

    @discardableResult
    public mutating func fit() -> Bool {
        update(.fit)
    }

    @discardableResult
    public mutating func setLevel(_ newLevel: PreviewZoom) -> Bool {
        update(newLevel)
    }

    private mutating func update(_ newLevel: PreviewZoom) -> Bool {
        guard newLevel != level else { return false }
        level = newLevel
        return true
    }
}

/// Availability of zoom in, zoom out, and Zoom to Fit (FR-134, FR-136).
/// Does not include sheets, renaming, or the Settings window being key in the conditions (A-73).
public struct PreviewZoomAvailability: Sendable, Equatable {
    /// Whether the preview is actually displaying an image (false while waiting for the first animation frame)
    public var isImageDisplayed: Bool
    /// Whether the preview is visible in the three-pane layout, preview-only, or full screen
    public var isPreviewVisible: Bool
    public var level: PreviewZoom

    public init(isImageDisplayed: Bool, isPreviewVisible: Bool, level: PreviewZoom) {
        self.isImageDisplayed = isImageDisplayed
        self.isPreviewVisible = isPreviewVisible
        self.level = level
    }

    public var isAvailable: Bool { isImageDisplayed && isPreviewVisible }
    public var canZoomIn: Bool { isAvailable && level.canZoomIn }
    public var canZoomOut: Bool { isAvailable && level.canZoomOut }
    public var canFit: Bool { isAvailable }
}
