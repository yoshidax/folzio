import Foundation

/// Pure computation that determines the enclosing folder of a regular folder from the tree roots
/// (FR-077, research.md R30).
public enum FolderNavigation {
    /// Returns nil when `folder` is a root or is not inside any root.
    /// Returns the parent within the deepest containing root (the home folder when the folder is inside both the home
    /// folder and the boot volume). Compares path components of `standardizedFileURL` so that `/Users/me2` is not
    /// mistaken for a child of `/Users/me`.
    public static func enclosingFolder(of folder: URL, roots: [URL]) -> URL? {
        let target = folder.standardizedFileURL
        let components = target.pathComponents

        var deepest: [String]?
        for root in roots {
            let rootComponents = root.standardizedFileURL.pathComponents
            if rootComponents == components {
                return nil
            }
            guard components.count > rootComponents.count,
                  components.starts(with: rootComponents) else { continue }
            if rootComponents.count > (deepest?.count ?? -1) {
                deepest = rootComponents
            }
        }

        guard deepest != nil else { return nil }
        return target.deletingLastPathComponent()
    }

    /// Folder to show after moving folders to the Trash in the tree (FR-079, research.md R33).
    /// When `showing` (the folder being displayed, or the folder containing the zip when inside a zip) is one of
    /// `trashed` or is inside one, returns the `enclosingFolder` of the shallowest matching folder. Returns nil when
    /// it has no ancestor/descendant relationship with any entry, when the matching folder is a root, or when
    /// `trashed` is empty. Compares path components of `standardizedFileURL` so that `/a/b2` is not mistaken for a
    /// child of `/a/b`.
    public static func folderToShow(afterTrashing trashed: [URL], showing: URL, roots: [URL]) -> URL? {
        let showingComponents = pathComponents(of: showing)

        var shallowest: String?
        var shallowestCount = Int.max
        for url in trashed {
            let components = pathComponents(of: url)
            guard showingComponents.starts(with: components),
                  components.count < shallowestCount else { continue }
            shallowest = NSString.path(withComponents: components)
            shallowestCount = components.count
        }

        guard let shallowest else { return nil }
        return enclosingFolder(of: URL(fileURLWithPath: shallowest, isDirectory: true), roots: roots)
    }

    /// Whether `folders` contains `folder` itself or one of its ancestors (FR-042, EC-13). The file system watcher
    /// reports a renamed, moved, or deleted folder as a change to its parent, so a vanished displayed folder or
    /// ancestor arrives only as one of these folders. Compares path components so that `/a/b2` is not mistaken for a
    /// child of `/a/b`.
    public static func containsFolderOrAncestor(of folder: URL, in folders: Set<URL>) -> Bool {
        let target = pathComponents(of: folder)
        return folders.contains { target.starts(with: pathComponents(of: $0)) }
    }

    /// Returns the nearest ancestor of a vanished `folder` for which `isFolder` is true, together with the shallowest
    /// vanished folder on the way (the folder itself or an ancestor). Returns nil when no ancestor is a folder.
    /// `isFolder` reads the disk, so call this off the main thread.
    public static func nearestExistingAncestor(
        of folder: URL,
        isFolder: (URL) -> Bool
    ) -> (folder: URL, vanished: URL)? {
        var vanished = folder
        var candidate = folder.deletingLastPathComponent()
        while candidate.standardizedFileURL.path != vanished.standardizedFileURL.path {
            if isFolder(candidate) {
                return (candidate, vanished)
            }
            vanished = candidate
            candidate = candidate.deletingLastPathComponent()
        }
        return nil
    }

    /// Whether `candidate` is inside, or is, the deepest root in `roots` that contains `folder`. Returns true when no
    /// root contains `folder`. Used to keep a vanished folder from being replaced by a folder outside its volume, such
    /// as `/Volumes` after the volume is removed (EC-18). Compares path components.
    public static func staysInsideRoot(from folder: URL, to candidate: URL, roots: some Sequence<URL>) -> Bool {
        let folderComponents = pathComponents(of: folder)
        let deepest = roots
            .map { pathComponents(of: $0) }
            .filter { folderComponents.starts(with: $0) }
            .max { $0.count < $1.count }
        guard let deepest else { return true }
        return pathComponents(of: candidate).starts(with: deepest)
    }

    /// Path components of `standardizedFileURL`. Because `standardizedFileURL` removes `/private` from paths such as
    /// `/private/var` only for existing paths, this normalizes the form so a folder moved to the Trash still matches
    /// the roots.
    private static func pathComponents(of url: URL) -> [String] {
        var components = url.standardizedFileURL.pathComponents
        if components.count > 2, components[1] == "private", ["var", "tmp", "etc"].contains(components[2]) {
            components.remove(at: 1)
        }
        return components
    }
}
