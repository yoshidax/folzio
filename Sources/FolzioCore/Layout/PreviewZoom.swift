import CoreGraphics
import Foundation

/// Preview zoom level (FR-133). 100% is the fit-to-window display from FR-028, not actual size (A-62).
/// Supports continuous scaling between 25% and 800%.
public struct PreviewZoom: Sendable, Equatable, Comparable {
    public static let step = 25
    public static let minimum = 25
    public static let maximum = 800
    public static let fit = PreviewZoom(percentage: 100)!

    public let scale: CGFloat
    public var percentage: Int { Int((scale * 100).rounded()) }

    public init?(percentage: Int) {
        guard (Self.minimum...Self.maximum).contains(percentage),
              percentage % Self.step == 0 else { return nil }
        self.scale = CGFloat(percentage) / 100
    }

    private init(scale: CGFloat) { self.scale = scale }

    public func scaled(by factor: CGFloat) -> PreviewZoom {
        guard factor.isFinite, factor > 0 else { return self }
        return PreviewZoom(scale: min(8, max(0.25, scale * factor)))
    }

    public var canZoomIn: Bool { scale < 8 }
    public var canZoomOut: Bool { scale > 0.25 }

    public func zoomedIn() -> PreviewZoom {
        PreviewZoom(scale: min(8, scale + 0.25))
    }

    public func zoomedOut() -> PreviewZoom {
        PreviewZoom(scale: max(0.25, scale - 0.25))
    }

    public static func < (lhs: PreviewZoom, rhs: PreviewZoom) -> Bool {
        lhs.scale < rhs.scale
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
    public mutating func scale(by factor: CGFloat) -> Bool {
        update(level.scaled(by: factor))
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
