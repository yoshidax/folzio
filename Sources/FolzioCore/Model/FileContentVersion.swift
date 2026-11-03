import Foundation

/// Values that identify the content of a file at a path (research.md R1, A-141).
/// Two different values mean that the content at the same path was replaced. Not persisted.
public struct FileContentVersion: Hashable, Sendable {
    public var fileSize: Int64
    public var modificationDate: Date?
    /// Inode of the item. Not stable on every file system, so it is used only for comparison.
    public var fileIdentifier: UInt64?

    public init(fileSize: Int64, modificationDate: Date?, fileIdentifier: UInt64?) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.fileIdentifier = fileIdentifier
    }

    /// Builds the value from resource values fetched with `resourceKeys`.
    /// Returns nil when none of the values are available.
    public init?(resourceValues values: URLResourceValues?) {
        guard let values else { return nil }
        let size = values.fileSize
        let date = values.contentModificationDate
        let identifier = values.fileIdentifier
        guard size != nil || date != nil || identifier != nil else { return nil }
        self.init(fileSize: Int64(size ?? 0), modificationDate: date, fileIdentifier: identifier)
    }

    /// Builds the value for entries inside a zip from the identity of the zip file itself (research.md R7).
    public init(archiveIdentity identity: ArchiveIdentity) {
        self.init(
            fileSize: Int64(clamping: identity.fileSize),
            modificationDate: identity.modificationDate,
            fileIdentifier: identity.inode
        )
    }

    /// Resource keys needed by `init(resourceValues:)`.
    public static let resourceKeys: Set<URLResourceKey> = [
        .fileSizeKey,
        .contentModificationDateKey,
        .fileIdentifierKey,
    ]

    /// Reads the current value of a file. Performs file system access; do not call on the main thread.
    /// A URL object caches resource values once read, so a URL kept from an earlier listing (such as a search result)
    /// would return the values from before the replacement. Reads through a new URL with an empty cache instead.
    public static func current(of url: URL) -> FileContentVersion? {
        var fresh = URL(fileURLWithPath: url.path)
        fresh.removeAllCachedResourceValues()
        return FileContentVersion(resourceValues: try? fresh.resourceValues(forKeys: resourceKeys))
    }
}
