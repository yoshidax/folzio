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
