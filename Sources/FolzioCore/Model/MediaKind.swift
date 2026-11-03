public enum MediaKind: String, CaseIterable, Sendable {
    case jpeg
    case png
    case gif
    case webp
    case mp4
    case mov

    public init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg":
            self = .jpeg
        case "png":
            self = .png
        case "gif":
            self = .gif
        case "webp":
            self = .webp
        case "mp4":
            self = .mp4
        case "mov":
            self = .mov
        default:
            return nil
        }
    }

    public var isVideo: Bool {
        switch self {
        case .mp4, .mov:
            return true
        case .jpeg, .png, .gif, .webp:
            return false
        }
    }
}

/// Color role of a file list row's leading icon (FR-269–271).
/// Core only decides the role; the app maps each role to a concrete `NSColor`.
public enum ListItemIconTone: Sendable, Hashable {
    /// Fixed blue used for folders and directories inside a zip
    case folderBlue
    /// Fixed yellow used for zip files
    case archiveYellow
    /// Secondary label color: the `..` row and the media fallback icons keep their existing look
    case secondary
}

/// Kind of a file list row (FR-068–070, 076, 077; ListItemKind in data-model.md). The type of `MediaFile.kind`.
public enum ListItemKind: Sendable, Hashable {
    /// Supported media file
    case media(MediaKind)
    /// Zip file in a regular folder
    case archive
    /// Subfolder of a regular folder (a target of file operations)
    case folder
    /// Directory inside a zip (read-only)
    case directory
    /// Leading `..` row (inside a zip, and in regular folders other than tree roots)
    case parent

    /// Color role of the row's leading icon (FR-269–271).
    public var iconTone: ListItemIconTone {
        switch self {
        case .folder, .directory:
            return .folderBlue
        case .archive:
            return .archiveYellow
        case .parent, .media:
            return .secondary
        }
    }

    public var isMedia: Bool {
        if case .media = self { return true }
        return false
    }

    /// Whether this row is a folder that the name sort groups first: a regular `.folder` or a `.directory` inside
    /// a zip. Zip files (`.archive`) and the `..` row (`.parent`) are not folder rows (FR-288).
    public var isFolderRow: Bool {
        switch self {
        case .folder, .directory:
            return true
        case .media, .archive, .parent:
            return false
        }
    }

    public var mediaKind: MediaKind? {
        if case .media(let kind) = self { return kind }
        return nil
    }

    /// Whether this is a video `.media` item.
    public var isVideo: Bool {
        mediaKind?.isVideo ?? false
    }

    /// Whether double-click opens the file in the app associated with it by the OS (FR-251).
    /// Only media files in the file system qualify. Media inside a zip has no real file (A-150).
    public func opensInDefaultApp(isBrowsingArchive: Bool) -> Bool {
        isMedia && !isBrowsingArchive
    }

    /// Whether double-click or ⌘↓ can open the row (`.archive`, `.folder`, `.directory`, `.parent`).
    public var opensAsContainer: Bool {
        switch self {
        case .media:
            return false
        case .archive, .folder, .directory, .parent:
            return true
        }
    }

    /// String used as the secondary sort key
    var sortKey: String {
        switch self {
        case .media(let kind): return kind.rawValue
        case .archive: return "archive"
        case .folder: return "folder"
        case .directory: return "directory"
        case .parent: return "parent"
        }
    }
}
