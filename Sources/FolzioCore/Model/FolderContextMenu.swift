import Foundation

/// Shared folder menu order and targets. Uses only the current in-memory listing (FR-409–412).
public struct FolderContextMenu: Sendable {
    public let items: [MediaFile]
    public let hasMissingTargets: Bool
    public let isBrowsingArchive: Bool
    public let containsProtectedFolder: Bool

    public init(files: [MediaFile], targets: Set<URL>, isBrowsingArchive: Bool, roots: [URL]) {
        items = files.filter { targets.contains($0.url) }
        hasMissingTargets = items.count != targets.count
        self.isBrowsingArchive = isBrowsingArchive
        containsProtectedFolder = items.contains {
            $0.kind == .folder && FavoriteCommands.trashTarget(.folder($0.url), roots: roots) == nil
        }
    }

    public var containsFolder: Bool { items.contains { $0.kind == .folder } }
    public var onlyFolders: Bool {
        !isBrowsingArchive && !hasMissingTargets && !items.isEmpty && items.allSatisfy { $0.kind == .folder }
    }
    public var singleFolder: URL? { onlyFolders && items.count == 1 ? items[0].url : nil }

    /// A failed or ambiguous item target must never fall back to the displayed folder (FR-411).
    public func pasteDestination(isItemMenu: Bool, displayedFolder: URL, isShowingSearchResults: Bool) -> URL? {
        guard !isBrowsingArchive else { return nil }
        if isItemMenu && (containsFolder || hasMissingTargets) { return singleFolder }
        return isShowingSearchResults ? nil : displayedFolder
    }

    public static func items(allowsModification: Bool) -> [TreeContextMenuItem] {
        var result: [TreeContextMenuItem] = [.pasteHere, .movePasteHere, .separator]
        if allowsModification { result += [.moveToTrash, .separator, .renameFolder] }
        result += [.duplicate, .separator, .copy, .copyPathname, .separator, .addToFavorites, .separator, .revealInFinder]
        return result
    }
}
