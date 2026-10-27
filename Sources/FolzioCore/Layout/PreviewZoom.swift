import CoreGraphics
import Foundation

/// Preview zoom level (FR-133). 100% is the fit-to-window display from FR-028, not actual size (A-62).
/// Accepts only multiples of 25% between 25% and 800% and does not change at the limits.
public struct PreviewZoom: Sendable, Equatable, Comparable {
    public static let step = 25
    public static let minimum = 25
    public static let maximum = 800
    public static let fit = PreviewZoom(percentage: 100)!

    public let percentage: Int

    public init?(percentage: Int) {
        guard (Self.minimum...Self.maximum).contains(percentage),
              percentage % Self.step == 0 else { return nil }
        self.percentage = percentage
    }

    /// Scale applied to the fitted rectangle
    public var scale: CGFloat { CGFloat(percentage) / 100 }

    public var canZoomIn: Bool { percentage < Self.maximum }
    public var canZoomOut: Bool { percentage > Self.minimum }

    public func zoomedIn() -> PreviewZoom {
        PreviewZoom(percentage: percentage + Self.step) ?? self
    }

    public func zoomedOut() -> PreviewZoom {
        PreviewZoom(percentage: percentage - Self.step) ?? self
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
