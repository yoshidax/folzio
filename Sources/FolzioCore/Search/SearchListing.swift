import Foundation

/// Criteria and progress of the displayed search (FR-084, 085; research.md R37). Stored in
/// `FolderListing.search` and not persisted.
public struct SearchListing: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case searching
        case finished
    }

    /// `SearchPattern.keyword` (shown in the search bar)
    public var keyword: String
    /// Search root directory that was validated
    public var root: URL
    public var phase: Phase
    /// Number of matches (before applying the media type filter). While searching, the count so far.
    public var totalCount: Int

    public init(keyword: String, root: URL, phase: Phase, totalCount: Int) {
        self.keyword = keyword
        self.root = root
        self.phase = phase
        self.totalCount = totalCount
    }

    /// String for the Location column and thumbnail tooltips. Joins the root folder name with the relative path
    /// to the folder containing the file, separated by `/`. When the root is `/`, returns the absolute path of the
    /// folder containing the file.
    public func location(of fileURL: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let folder = fileURL.deletingLastPathComponent().standardizedFileURL
        if rootComponents == ["/"] {
            return folder.path
        }

        let folderComponents = folder.pathComponents
        let relative: ArraySlice<String>
        if folderComponents.starts(with: rootComponents) {
            relative = folderComponents.dropFirst(rootComponents.count)
        } else {
            relative = []
        }
        return ([root.standardizedFileURL.lastPathComponent] + relative).joined(separator: "/")
    }
}
