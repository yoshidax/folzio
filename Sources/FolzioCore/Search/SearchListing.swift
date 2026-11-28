import Foundation

/// Criteria and progress of the displayed search (FR-084, 085, 439; research.md R37). Stored in
/// `FolderListing.search` and not persisted.
public struct SearchListing: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case searching
        case finished
    }

    /// How the search bar names the roots (FR-439).
    public enum RootSummary: Sendable, Equatable {
        /// One root: its folder name (`/` for the filesystem root).
        case single(String)
        /// Two or more roots: the first root's folder name and the number of other roots.
        case multiple(first: String, others: Int)
    }

    /// `SearchPattern.keyword` (shown in the search bar)
    public var keyword: String
    /// Validated and organized search roots in the order they are searched (FR-437). Never empty.
    public var roots: [URL]
    public var phase: Phase
    /// Number of matches (before applying the media type filter). While searching, the count so far.
    public var totalCount: Int

    public init(keyword: String, roots: [URL], phase: Phase, totalCount: Int) {
        precondition(!roots.isEmpty, "A search has at least one root")
        self.keyword = keyword
        self.roots = roots
        self.phase = phase
        self.totalCount = totalCount
    }

    public init(keyword: String, root: URL, phase: Phase, totalCount: Int) {
        self.init(keyword: keyword, roots: [root], phase: phase, totalCount: totalCount)
    }

    /// The first root.
    public var root: URL {
        roots[0]
    }

    /// Search bar summary of the roots (FR-439).
    public var rootSummary: RootSummary {
        let first = Self.displayName(of: roots[0])
        return roots.count == 1 ? .single(first) : .multiple(first: first, others: roots.count - 1)
    }

    /// Absolute paths of every root in search order, for the search bar tooltip (FR-439).
    public var rootPaths: [String] {
        roots.map { $0.standardizedFileURL.path }
    }

    /// The root that contains the item: the containing root with the longest path, so that a root nested behind a
    /// hidden folder of another root wins (EC-302, research.md R5).
    public func root(containing url: URL) -> URL? {
        let path = url.standardizedFileURL.path
        return roots
            .filter { SearchPath.isSameOrWithin(path, $0.standardizedFileURL.path) }
            .max { $0.standardizedFileURL.path.count < $1.standardizedFileURL.path.count }
    }

    /// String for the Location column and thumbnail tooltips. Joins the containing root's folder name with the
    /// relative path to the folder containing the file, separated by `/`. When the containing root is `/`, or another
    /// root has the same folder name (compared case-insensitively; EC-305), starts from the root's absolute path.
    public func location(of fileURL: URL) -> String {
        let folder = fileURL.deletingLastPathComponent().standardizedFileURL
        // With one root, skip the containment search so sorting 10,000 rows by Location costs what it did before.
        let root = (roots.count == 1 ? roots[0] : root(containing: folder) ?? roots[0]).standardizedFileURL
        let rootComponents = root.pathComponents
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
        let base = hasSharedName(root) ? root.path : root.lastPathComponent
        return ([base] + relative).joined(separator: "/")
    }

    /// Whether another root has the same folder name as `root`, ignoring case.
    private func hasSharedName(_ root: URL) -> Bool {
        guard roots.count > 1 else { return false }
        let path = root.path
        let name = root.lastPathComponent
        return roots.contains { other in
            let standardized = other.standardizedFileURL
            return standardized.path != path
                && standardized.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    private static func displayName(of root: URL) -> String {
        let standardized = root.standardizedFileURL
        return standardized.path == "/" ? "/" : standardized.lastPathComponent
    }
}
