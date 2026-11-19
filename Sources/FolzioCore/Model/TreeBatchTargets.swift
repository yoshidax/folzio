import Foundation

/// Targets of a directory tree command when the tree allows multiple selection (FR-217, FR-218).
///
/// The UI passes the roles of the selected rows and, for a context menu or a drag, the row where the command started.
/// This type decides which rows the command acts on and whether each command is available. It does not read the disk
/// (research.md R1, R2).
public struct TreeBatchTargets: Sendable, Equatable {
    /// Result of resolving the targets of Move to Trash.
    public enum TrashTargets: Sendable, Equatable {
        /// Every target is a regular folder that can be moved to the Trash (FR-079).
        case folders([URL])
        /// The targets are empty or include a row that is not a regular folder (FR-218).
        case unavailable
        /// The targets include a folder and one of its descendants (EC-146).
        case overlapping
    }

    /// Rows the command acts on, in selection order.
    public let targets: [TreeItemRole]

    /// Creates targets from the selected rows and the row where the command started.
    ///
    /// - Parameters:
    ///   - selection: Roles of the selected rows, in row order.
    ///   - origin: Row that was right-clicked or dragged. Nil for keyboard shortcuts and menu bar commands.
    ///   - originIsSelected: Whether `origin` is one of the selected rows.
    public init(selection: [TreeItemRole], origin: TreeItemRole? = nil, originIsSelected: Bool = false) {
        if let origin, !originIsSelected {
            targets = [origin]
        } else {
            targets = selection
        }
    }

    /// Whether the command acts on exactly one row. Commands that assume a single row (New Folder, rename, Copy as
    /// Pathname, Add to Favorites, Remove from Favorites, and paste) are available only in this case
    /// (FR-218).
    public var isSingle: Bool { targets.count == 1 }

    /// Whether the command acts on two or more rows.
    public var isMultiple: Bool { targets.count > 1 }

    /// The only target when `isSingle` is true; otherwise nil.
    public var singleTarget: TreeItemRole? { isSingle ? targets[0] : nil }

    /// Resolves the folders that Move to Trash acts on. A single target follows `FavoriteCommands.trashTarget`.
    /// Multiple targets are accepted only when all of them are regular folders, and are rejected as a whole when one
    /// contains another (FR-218, EC-146).
    public func trashTargets(roots: [URL]) -> TrashTargets {
        guard let urls = regularFolderURLs(roots: roots) else { return .unavailable }
        return Self.containsOverlap(urls) ? .overlapping : .folders(urls)
    }

    /// Returns the URLs to drag when every target is a regular folder, or nil to refuse the drag (FR-162, FR-218).
    /// Folders that contain one another are still returned; the drop validation rejects them (EC-121).
    public func dragURLs(roots: [URL]) -> [URL]? {
        regularFolderURLs(roots: roots)
    }

    /// Real folders for copy and Reveal in Finder, including roots. Rejects virtual rows as a whole.
    public var folderURLs: [URL]? {
        guard !targets.isEmpty else { return nil }
        var urls: [URL] = []
        for target in targets {
            guard case .folder(let url) = target else { return nil }
            urls.append(url)
        }
        return urls
    }

    /// Duplicate protects the same roots and out-of-root targets as rename and Trash.
    public func duplicateURLs(roots: [URL]) -> [URL]? {
        regularFolderURLs(roots: roots)
    }

    /// Multiple targets use the same operation order; each action validates the entire target set.
    public func contextMenu(roots: [URL]) -> [TreeContextMenuItem] {
        if let single = singleTarget {
            return FavoriteCommands.contextMenu(for: single, roots: roots)
        }
        return isMultiple ? FolderContextMenu.items(allowsModification: true) : []
    }

    /// Whether any URL equals another or is inside another. Compares path components of `standardizedFileURL` so
    /// that `/a/b2` is not treated as inside `/a/b` (EC-146).
    public static func containsOverlap(_ urls: [URL]) -> Bool {
        let paths = urls.map { $0.standardizedFileURL.pathComponents }
        for (index, path) in paths.enumerated() {
            for (otherIndex, other) in paths.enumerated() where otherIndex != index {
                if path.count >= other.count, path.starts(with: other) {
                    return true
                }
            }
        }
        return false
    }

    private func regularFolderURLs(roots: [URL]) -> [URL]? {
        guard !targets.isEmpty else { return nil }
        var urls: [URL] = []
        for target in targets {
            guard let url = FavoriteCommands.trashTarget(target, roots: roots) else { return nil }
            urls.append(url)
        }
        return urls
    }
}
