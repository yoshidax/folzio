import Foundation

/// Where a drop on the file list goes, for drags inside the app and from other apps alike (FR-163, FR-349).
public enum FileListDropTarget: Sendable, Equatable {
    /// The folder item at this index of the listing.
    case folder(Int)
    /// The displayed folder: empty space, the gaps between rows, or an item that is not a folder (A-207).
    case displayedFolder

    /// - Parameters:
    ///   - kind: The kind of the item under the pointer, or nil for empty space and the gaps between rows.
    ///   - index: The index of that item in the listing.
    ///   - isBrowsingArchive: A zip's contents are read-only, so nothing in it takes drops (FR-073).
    ///   - isShowingSearchResults: Search results have no single displayed folder; only their folder rows take drops
    ///     (FR-087).
    ///   - state: A folder that cannot be read or was not found takes no drops, the same as New Folder (FR-212).
    /// - Returns: The destination, or nil when the drop is not accepted there.
    public static func resolve(
        kind: ListItemKind?,
        index: Int?,
        isBrowsingArchive: Bool,
        isShowingSearchResults: Bool,
        state: FolderListing.State
    ) -> FileListDropTarget? {
        guard !isBrowsingArchive else { return nil }
        switch kind {
        case .folder:
            guard let index else { return nil }
            return .folder(index)
        case .parent, .directory:
            return nil
        case .media, .archive, nil:
            guard !isShowingSearchResults else { return nil }
            switch state {
            case .denied, .failed:
                return nil
            case .loading, .loaded, .empty, .noMatches:
                return .displayedFolder
            }
        }
    }
}
