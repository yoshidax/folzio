import Foundation

/// History location (FR-108): the folder shown in the file list and the position inside a zip (R69).
public struct HistoryLocation: Sendable, Equatable {
    public var folder: URL
    public var archive: ArchiveLocation?

    public init(folder: URL, archive: ArchiveLocation? = nil) {
        self.folder = folder
        self.archive = archive
    }

    public static func == (lhs: HistoryLocation, rhs: HistoryLocation) -> Bool {
        HistoryPath.normalized(lhs.folder.path) == HistoryPath.normalized(rhs.folder.path)
            && lhs.archive?.directory == rhs.archive?.directory
            && lhs.archive.map { HistoryPath.normalized($0.archive.path) }
                == rhs.archive.map { HistoryPath.normalized($0.archive.path) }
    }

    /// Whether this location is `url` itself or is inside it. For a zip, uses the zip file location (R73).
    public func isWithin(_ url: URL) -> Bool {
        if let archive {
            return HistoryPath.isWithin(archive.archive.path, url.path)
        }
        return HistoryPath.isWithin(folder.path, url.path)
    }

    /// Returns the new location when it relates to a renamed folder; otherwise nil (R69, R75).
    public func rebased(by renamed: RenamedFolder) -> HistoryLocation? {
        let newFolder = renamed.rebase(folder)
        if let archive {
            guard let newArchive = renamed.rebase(archive.archive) else { return nil }
            return HistoryLocation(
                folder: newFolder ?? folder,
                archive: ArchiveLocation(archive: newArchive, directory: archive.directory)
            )
        }
        guard let newFolder else { return nil }
        return HistoryLocation(folder: newFolder)
    }
}

/// Part of the history presentation state owned by the app (R74).
public struct HistoryPresentation: Sendable, Equatable {
    public var displayMode: DisplayMode
    public var thumbnailSize: Double
    public var paneLayout: PaneLayout

    public init(displayMode: DisplayMode, thumbnailSize: Double, paneLayout: PaneLayout) {
        self.displayMode = displayMode
        self.thumbnailSize = thumbnailSize
        self.paneLayout = paneLayout
    }
}

/// History presentation state (FR-108). `BrowserModel` owns the media type filter and zip file visibility.
public struct HistoryViewState: Sendable, Equatable {
    public var presentation: HistoryPresentation
    public var mediaTypeFilter: MediaTypeFilter
    public var showsZipFiles: Bool

    public init(
        presentation: HistoryPresentation,
        mediaTypeFilter: MediaTypeFilter,
        showsZipFiles: Bool
    ) {
        self.presentation = presentation
        self.mediaTypeFilter = mediaTypeFilter
        self.showsZipFiles = showsZipFiles
    }
}

/// One history entry. `focusedItem` is the row focused when leaving this entry (FR-108).
public struct HistoryEntry: Sendable, Equatable {
    public var location: HistoryLocation
    public var viewState: HistoryViewState
    public var focusedItem: URL?

    public init(location: HistoryLocation, viewState: HistoryViewState, focusedItem: URL? = nil) {
        self.location = location
        self.viewState = viewState
        self.focusedItem = focusedItem
    }

    /// Compares only the location and presentation state (the "same state" in FR-107; EC-59).
    public func hasSameState(as other: HistoryEntry) -> Bool {
        location == other.location && viewState == other.viewState
    }
}

public enum HistoryRecordKind: Sendable, Equatable {
    case navigation
    case viewChange
    case thumbnailSize
}

public enum HistoryDirection: Sendable, Equatable {
    case back
    case forward
}

/// Compares locations using paths with `.` and `..` removed (R69). The same rule as `RenamedFolder`.
private enum HistoryPath {
    static func normalized(_ path: String) -> String {
        var contiguous = path
        contiguous.makeContiguousUTF8()
        let hasDotComponent = contiguous.withUTF8 { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            return memmem(base, bytes.count, "/.", 2) != nil
        }
        guard hasDotComponent else { return contiguous }

        var parts: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !parts.isEmpty { parts.removeLast() }
            default:
                parts.append(component)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    static func components(_ path: String) -> [Substring] {
        normalized(path).split(separator: "/", omittingEmptySubsequences: true)
    }

    static func isWithin(_ path: String, _ base: String) -> Bool {
        let pathComponents = components(path)
        let baseComponents = components(base)
        guard !baseComponents.isEmpty else { return true }
        guard pathComponents.count >= baseComponents.count else { return false }
        return pathComponents.prefix(baseComponents.count).elementsEqual(baseComponents)
    }
}
