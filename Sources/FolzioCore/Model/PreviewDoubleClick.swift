import Foundation

extension PreviewContent {
    /// Whether the preview is showing a selected media file, including while it loads or when it cannot be displayed.
    /// Only `.empty` (no selection, or a folder, zip file, directory inside a zip, or `..` row) returns false (EC-149).
    public var hasMedia: Bool {
        switch self {
        case .empty:
            false
        case .loading, .image, .animatedImage, .animatedImageData, .video, .unavailable:
            true
        }
    }
}

/// Decides whether a double-click in the preview toggles full screen (FR-035, FR-220, EC-149, EC-150).
/// The keyboard shortcut, the menu item, and Esc do not use this rule (A-135).
public enum PreviewDoubleClick {
    /// Returns whether a double-click toggles full screen.
    ///
    /// - Parameters:
    ///   - isFullScreen: Whether the window is in the full-screen presentation.
    ///   - hasMedia: Whether the preview shows a media file (`PreviewContent.hasMedia`).
    ///   - isOverControl: Whether the double-click is on a control, such as the video playback controls
    ///     or the image scroll bars.
    /// - Returns: False on a control. In full screen, true anywhere else regardless of the content.
    ///   Otherwise, true only when the preview shows a media file.
    public static func togglesFullScreen(isFullScreen: Bool, hasMedia: Bool, isOverControl: Bool) -> Bool {
        guard !isOverControl else { return false }
        return isFullScreen || hasMedia
    }
}
