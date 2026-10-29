/// Pure computation that returns whether each command is available from the row kind, whether a zip is being
/// browsed, whether there is an enclosing level, and whether search results are shown
/// (FR-069, 073, 076, 077, 087; research.md R26, R30, R32, R38).
/// Unavailable commands appear dimmed in menus and do nothing for keyboard shortcuts and drags.
public struct ListItemCommands: Sendable, Equatable {
    /// Kind of the focused row. Nil when there is no row (nothing is selected).
    public let kind: ListItemKind?
    /// Whether a zip is being browsed.
    public let isBrowsingArchive: Bool
    /// Whether ⌘↑ has an enclosing level to return to (inside a zip, or a regular folder that is not a tree root).
    public let hasEnclosingLevel: Bool
    /// Whether search results are shown. Disables paste and ⌘↑ because there is no destination or enclosing folder
    /// (FR-087).
    public let isShowingSearchResults: Bool

    /// Omitting `hasEnclosingLevel` (nil) makes it equal to `isBrowsingArchive`.
    public init(
        kind: ListItemKind?,
        isBrowsingArchive: Bool,
        hasEnclosingLevel: Bool? = nil,
        isShowingSearchResults: Bool = false
    ) {
        self.kind = kind
        self.isBrowsingArchive = isBrowsingArchive
        self.hasEnclosingLevel = hasEnclosingLevel ?? isBrowsingArchive
        self.isShowingSearchResults = isShowingSearchResults
    }

    /// Opens the container (double-click, ⌘↓). Opens zip files, folders, and directories; `..` goes up.
    /// Does nothing for media files or no row.
    public var canOpenContainer: Bool {
        kind?.opensAsContainer ?? false
    }

    /// Goes to the enclosing level (⌘↑). Works regardless of the selected row when an enclosing level exists.
    public var canGoUp: Bool {
        hasEnclosingLevel && !isShowingSearchResults
    }

    /// Open (⌘O), copy, duplicate, rename, move to Trash, Reveal in Finder, and drag. A zip is read-only, and `..`
    /// is not a target.
    public var allowsFileOperations: Bool {
        !isBrowsingArchive && kind != .parent
    }

    /// Copy as Pathname. Needs exactly one selected row that is a file operation target, so a zip's contents and
    /// `..` are excluded (FR-073, FR-183).
    public func allowsCopyPathname(selectionCount: Int) -> Bool {
        allowsFileOperations && selectionCount == 1
    }

    /// Paste and Move Item Here into the list. Unavailable inside a zip and while showing search results.
    public var allowsPaste: Bool {
        !isBrowsingArchive && !isShowingSearchResults
    }
}
