import Foundation

/// Narrows the displayed file list to the rows whose names match the text in the toolbar search field (FR-381).
///
/// Matching uses the same rules as the search modal (`SearchPattern`, FR-082): a substring match without
/// wildcards, a whole-name match with `*` or `?`, ignoring letter case and Unicode normalization differences.
/// Every row kind passed in is matched by its name, including folders, zip files, and directories inside a zip.
/// The `..` row is not part of the rows the model filters, so it always stays (FR-381).
public struct NameFilter: Sendable, Equatable {
    /// The text as typed, including leading and trailing whitespace, so the field can be compared with it.
    public let text: String
    /// Nil when the text is empty after removing leading and trailing whitespace. Such text does not filter.
    public let pattern: SearchPattern?

    public init(text: String = "") {
        self.text = text
        self.pattern = SearchPattern(keyword: text)
    }

    public var isFiltering: Bool {
        pattern != nil
    }

    public func apply(to files: [MediaFile]) -> [MediaFile] {
        guard let pattern else { return files }
        return files.filter { pattern.matches(fileName: $0.name) }
    }

    public static func == (lhs: NameFilter, rhs: NameFilter) -> Bool {
        lhs.text == rhs.text
    }
}
