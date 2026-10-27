import Foundation

/// Role of a directory tree row. The UI creates it from the row and lets FavoriteCommands decide favorite actions.
public enum TreeItemRole: Sendable, Equatable {
    case favoritesHeader
    case favorite(URL)
    /// A regular folder, including the home and volume roots
    case folder(URL)
}

public enum TreeContextMenuItem: Sendable, Equatable {
    case pasteHere, movePasteHere, addToFavorites, revealInFinder, removeFromFavorites
    /// Moves a tree folder to the Trash (FR-079)
    case moveToTrash
    /// Renames a favorite item (FR-099)
    case renameFavorite
    /// Renames a regular folder in the tree (FR-103)
    case renameFolder
    case separator
}

/// Target of Rename in the tree (research.md R59).
public enum TreeRenameTarget: Sendable, Equatable {
    /// Renames the favorite's display name. Does not change the actual folder (FR-099).
    case favorite(URL)
    /// Renames a regular folder in the tree. Excludes roots (FR-103).
    case folder(URL)
}

public enum FavoriteCommands {
    /// ⌃⌘T and Add to Favorites. True only for `.folder` URLs that are not registered.
    public static func canAdd(_ role: TreeItemRole?, favorites: FavoriteFolders) -> Bool {
        guard case .folder(let url) = role else { return false }
        return !favorites.contains(url)
    }

    /// Target of ⌘⌫ and Remove from Favorites. Returns a URL only for `.favorite`.
    public static func removalTarget(_ role: TreeItemRole?) -> URL? {
        guard case .favorite(let url) = role else { return nil }
        return url
    }

    /// Target of Return, Edit > Rename, and Rename in the context menu. `.favorite` renames the display name;
    /// a non-root `.folder` renames the actual folder (the same scope as `trashTarget`).
    /// Returns nil for roots, `.favoritesHeader`, and nil (FR-099, FR-103, R59).
    public static func renameTarget(_ role: TreeItemRole?, roots: [URL]) -> TreeRenameTarget? {
        switch role {
        case .favorite(let url):
            return .favorite(url)
        case .folder:
            return trashTarget(role, roots: roots).map(TreeRenameTarget.folder)
        case .favoritesHeader, nil:
            return nil
        }
    }

    /// Target of ⌘⌫ and Move to Trash in the context menu (FR-079). Returns a URL only for a `.folder` that is
    /// not a root (`FolderNavigation.enclosingFolder` returns nil). Returns nil for `.favorite`, `.favoritesHeader`,
    /// and nil
    /// (FR-064).
    public static func trashTarget(_ role: TreeItemRole?, roots: [URL]) -> URL? {
        guard case .folder(let url) = role,
              FolderNavigation.enclosingFolder(of: url, roots: roots) != nil else { return nil }
        return url
    }

    /// Context menu items and their order. `.favoritesHeader` returns an empty array (no menu).
    /// For rows where `trashTarget` returns a URL, places `.moveToTrash` and `.renameFolder` first, each followed by
    /// a separator (A-37). The default value of `roots` is empty, which omits `.moveToTrash` and `.renameFolder`.
    public static func contextMenu(for role: TreeItemRole, roots: [URL] = []) -> [TreeContextMenuItem] {
        switch role {
        case .folder:
            let items: [TreeContextMenuItem] =
                [.pasteHere, .movePasteHere, .separator, .addToFavorites, .separator, .revealInFinder]
            return trashTarget(role, roots: roots) != nil
                ? [.moveToTrash, .separator, .renameFolder, .separator] + items
                : items
        case .favorite:
            return [.renameFavorite, .removeFromFavorites]
        case .favoritesHeader:
            return []
        }
    }

    /// Folder whose contents are shown when selected. `.favoritesHeader` returns nil (FR-065).
    public static func folderToShow(for role: TreeItemRole) -> URL? {
        switch role {
        case .folder(let url), .favorite(let url):
            url
        case .favoritesHeader:
            nil
        }
    }

    /// Whether the row accepts drops and pastes. True only for `.folder` (the UI still checks accessibility).
    public static func acceptsFiles(_ role: TreeItemRole) -> Bool {
        if case .folder = role { return true }
        return false
    }
}
