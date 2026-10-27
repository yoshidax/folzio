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

    public var isMedia: Bool {
        if case .media = self { return true }
        return false
    }

    public var mediaKind: MediaKind? {
        if case .media(let kind) = self { return kind }
        return nil
    }

    /// Whether this is a video `.media` item.
    public var isVideo: Bool {
        mediaKind?.isVideo ?? false
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
