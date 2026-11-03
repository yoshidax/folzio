import Foundation

/// A list view column that the user can show or hide from the column header menu (TAK-47).
///
/// The name column is not listed: like the Name column in Finder, it is always shown and has no menu item. The
/// location column is not listed either, because it appears automatically while search results are displayed
/// (FR-084). The declaration order is the order of the menu items and of the columns.
public enum ListColumn: String, Sendable, CaseIterable, Hashable {
    case creationDate
    case kind
    case size
    case modificationDate

    /// Columns shown when the user has not changed the setting: Date Created and Kind.
    public static let defaultVisible: Set<ListColumn> = [.creationDate, .kind]

    /// Reads the saved raw values. Unknown values are ignored, and a value of an unexpected type, or no value,
    /// gives the default.
    public static func visibleColumns(fromStored stored: Any?) -> Set<ListColumn> {
        guard let rawValues = stored as? [String] else { return defaultVisible }
        return Set(rawValues.compactMap(ListColumn.init(rawValue:)))
    }

    /// Raw values for saving, in column order.
    public static func storedValue(of columns: Set<ListColumn>) -> [String] {
        allCases.filter(columns.contains).map(\.rawValue)
    }
}

extension SortColumn {
    /// The toggleable column that shows this sort key, or nil for name and location, which are not toggleable.
    public var listColumn: ListColumn? {
        switch self {
        case .name, .location: return nil
        case .creationDate: return .creationDate
        case .kind: return .kind
        case .size: return .size
        case .modificationDate: return .modificationDate
        }
    }
}

extension MediaFile {
    /// Whether the size column shows a size for this row. Folders (including folders inside a zip) and `..` have none
    /// and show `--`; they count as 0 bytes when sorting by size, as in Finder.
    public var hasFileSize: Bool {
        switch kind {
        case .media, .archive: return true
        case .folder, .directory, .parent: return false
        }
    }
}
