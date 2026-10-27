import AppKit
import FolzioCore

extension BrowserModel {
    /// Returns command availability from the focused row kind, whether a zip is being browsed, whether an enclosing
    /// level exists, and whether search results are shown. Menus, keys, and drags use the same decision
    /// (FR-069, 073, 077, 087; research.md R26, R30, R38).
    var focusedItemCommands: ListItemCommands {
        ListItemCommands(
            kind: focusedKind,
            isBrowsingArchive: isBrowsingArchive,
            hasEnclosingLevel: hasEnclosingLevel,
            isShowingSearchResults: isShowingSearchResults
        )
    }

    /// Availability of file operations for the selection (copy, Trash, and so on). Because `operableSelection` excludes
    /// `..`, other selected rows can be operated on even when the focus is on `..` (R30).
    var selectionItemCommands: ListItemCommands {
        let kind = focusedKind == .parent && !operableSelection.isEmpty ? nil : focusedKind
        return ListItemCommands(
            kind: kind,
            isBrowsingArchive: isBrowsingArchive,
            hasEnclosingLevel: hasEnclosingLevel,
            isShowingSearchResults: isShowingSearchResults
        )
    }

    private var focusedKind: ListItemKind? {
        selection.focused.flatMap { focused in
            listing.files.first { $0.url == focused }?.kind
        }
    }

    /// Availability for the kind of the given row. Treats out-of-range rows as a nil kind.
    func itemCommands(forRowAt index: Int) -> ListItemCommands {
        let files = listing.files
        let kind = files.indices.contains(index) ? files[index].kind : nil
        return ListItemCommands(
            kind: kind,
            isBrowsingArchive: isBrowsingArchive,
            hasEnclosingLevel: hasEnclosingLevel,
            isShowingSearchResults: isShowingSearchResults
        )
    }
}

extension NSEvent {
    /// Whether this is Esc with no modifier keys.
    var isPlainEscape: Bool {
        guard charactersIgnoringModifiers == "\u{1b}" else { return false }
        let relevant = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        return relevant.isEmpty
    }

    /// Whether this is ↓ or ↑ with only Command. Used to avoid passing to the default NSTableView or
    /// NSCollectionView action (such as moving to the end) when the menu item is disabled (R26).
    var isCommandOnlyVerticalArrow: Bool {
        guard specialKey == .downArrow || specialKey == .upArrow else { return false }
        let relevant = modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        return relevant == [.command]
    }
}
