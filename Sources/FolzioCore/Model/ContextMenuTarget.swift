/// What the file list context menu acts on. Like the tree (A-21), a context click does not change the selection
/// (FR-397).
public enum ContextMenuTarget: Equatable, Sendable {
    /// The displayed folder: the click hit no item (FR-213).
    case background
    /// The whole selection: the clicked item is selected.
    case selection
    /// Only the clicked item, at this index of the listing: it is not selected.
    case item(Int)

    /// - Parameters:
    ///   - clicked: The index of the item under the pointer, or nil for the background.
    ///   - selected: The indices of the items selected now.
    ///   - itemCount: The number of items in the listing. An index outside it counts as the background.
    public static func resolve(clicked: Int?, selected: Set<Int>, itemCount: Int) -> ContextMenuTarget {
        guard let clicked, clicked >= 0, clicked < itemCount else { return .background }
        return selected.contains(clicked) ? .selection : .item(clicked)
    }
}
