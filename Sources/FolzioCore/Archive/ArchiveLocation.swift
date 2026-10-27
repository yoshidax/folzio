import Foundation

/// Currently displayed zip and the directory inside it (FR-069, FR-070; ArchiveLocation in data-model.md).
public struct ArchiveLocation: Sendable, Hashable {
    /// File URL of the zip
    public var archive: URL
    /// Directory path inside the zip. The root is an empty string; other paths end with `/`, as in `a/b/`.
    public var directory: String

    public init(archive: URL, directory: String) {
        self.archive = archive
        self.directory = directory
    }

    /// Parent directory. Nil at the root (returns to the folder containing the zip).
    public var parent: ArchiveLocation? {
        guard !directory.isEmpty else { return nil }
        let trimmed = directory.hasSuffix("/") ? String(directory.dropLast()) : directory
        guard let slash = trimmed.lastIndex(of: "/") else {
            return ArchiveLocation(archive: archive, directory: "")
        }
        return ArchiveLocation(archive: archive, directory: String(trimmed[...slash]))
    }
}
