import Foundation

public struct FolderListing: Sendable {
    public enum State: Sendable, Equatable {
        case loading
        case loaded
        case empty
        case noMatches
        case denied
        case failed(ListingFailure)
    }

    public var folder: URL
    public var files: [MediaFile]
    public var state: State
    /// The zip and hierarchy when browsing a zip; nil for a regular folder (`folder` remains the folder containing
    /// the zip).
    public var archive: ArchiveLocation?
    /// Search criteria and progress when showing search results. While showing results, `folder` remains the
    /// pre-search folder and `archive` is nil (FR-084, FR-085).
    public var search: SearchListing?

    public init(
        folder: URL,
        files: [MediaFile] = [],
        state: State = .empty,
        archive: ArchiveLocation? = nil,
        search: SearchListing? = nil
    ) {
        self.folder = folder
        self.files = files
        self.state = state
        self.archive = archive
        self.search = search
    }
}

/// Request that tells the tree about navigation in the file list (FR-078, research.md R31). Exposed as
/// `BrowserModel.treeSyncRequest`.
public struct TreeSyncRequest: Sendable, Equatable {
    /// Folder to select in the tree (the folder shown in the file list)
    public let folder: URL
    /// Incremented for every request. The tree applies only the result with the latest `id` to the selection.
    public let id: Int

    public init(folder: URL, id: Int) {
        self.folder = folder
        self.id = id
    }
}

public struct SelectionState: Sendable {
    public var selected: Set<URL>
    public var focused: URL?

    public init(selected: Set<URL> = [], focused: URL? = nil) {
        self.selected = selected
        self.focused = focused
    }
}

extension SelectionState {
    /// Restricts the selection to visible URLs, preserving the listing order.
    public func restricted(toVisible orderedURLs: [URL]) -> SelectionState {
        let visible = Set(orderedURLs)
        let kept = selected.intersection(visible)

        let newFocused: URL?
        if let focused {
            if visible.contains(focused) {
                newFocused = focused
            } else {
                newFocused = orderedURLs.last { kept.contains($0) }
            }
        } else {
            newFocused = nil
        }
        return SelectionState(selected: kept, focused: newFocused)
    }
}

public enum PreviewContent {
    case empty
    case loading(URL)
    case image(DecodedImage)
    case animatedImage(URL)
    /// Animated image inside a zip. `Data` is the entry content read from the zip (discarded when leaving the preview).
    case animatedImageData(URL, Data)
    case video(URL)
    case unavailable(name: String, reason: PreviewFailure)
}

/// Reason a folder listing could not be read (a value independent of the display language).
public enum ListingFailure: Error, Sendable, Equatable {
    case folderNotFound
    /// Reason returned by the OS. Do not re-translate (EC-111).
    case systemFailure(systemReason: String)
    case archive(ArchiveError)
}

/// Reason the preview cannot be displayed (a value independent of the display language).
public enum PreviewFailure: Error, Sendable, Equatable {
    case unreadable
    case unsupportedFormat
    case corrupted
    case archive(ArchiveError)
}

public enum FocusDirection: Sendable {
    case previous
    case next
}
