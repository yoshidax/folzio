import FolzioCore
import FolzioLocalization

/// Builds the toolbar tooltips and accessibility texts, inserting the current key of each command (FR-261).
@MainActor
enum ToolbarShortcutText {
    /// The text for one of the toolbar keys whose translation takes the shortcut as its argument.
    static func text(_ key: TextKey) -> String {
        l10n.text(key, .text(ShortcutAssignmentStore.shared.keyText(commands(for: key))))
    }

    /// The commands whose keys the text shows, in display order.
    static func commands(for key: TextKey) -> [ShortcutCommandID] {
        switch key {
        case .toolbarGoBackHelp: return [.back]
        case .toolbarGoForwardHelp: return [.forward]
        case .toolbarShowFileListOnlyHelp: return [.fileListOnly]
        case .toolbarShowPreviewOnlyHelp: return [.previewOnly]
        case .toolbarShowImagesOnlyHelp: return [.imagesOnly]
        case .toolbarShowVideosOnlyHelp: return [.videosOnly]
        case .toolbarZipFilesHelp: return [.zipVisibility]
        case .toolbarStartSlideshowHelp: return [.startSlideshow]
        case .toolbarZoomInHelp: return [.zoomIn]
        case .toolbarZoomToFitHelp: return [.zoomToFit]
        case .toolbarZoomOutHelp: return [.zoomOut]
        case .toolbarThumbnails: return [.thumbnails]
        case .toolbarList: return [.list]
        case .toolbarThumbnailSize: return [.largerThumbnails, .smallerThumbnails]
        default: return []
        }
    }
}
