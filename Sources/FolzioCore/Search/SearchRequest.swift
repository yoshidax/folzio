import Foundation

/// Request for a name search (FR-083, 105; research.md R2, R3).
public struct SearchRequest: Sendable {
    /// Folder where enumeration starts
    public var root: URL
    /// Keyword
    public var pattern: SearchPattern
    /// Whether `root` itself is matched as a folder. False when starting a search and when the search root or an
    /// ancestor is renamed. True only for the additional enumeration after renaming an unmatched folder (R3).
    public var matchesRoot: Bool
    /// Log where directories are recorded immediately before enumeration matches them
    public var visits: SearchVisitLog

    public init(
        root: URL,
        pattern: SearchPattern,
        matchesRoot: Bool = false,
        visits: SearchVisitLog = SearchVisitLog()
    ) {
        self.root = root
        self.pattern = pattern
        self.matchesRoot = matchesRoot
        self.visits = visits
    }
}

/// Path normalization used for search records and matching (EC-94).
public enum SearchPath {
    /// Removes a trailing `/` and `.` and `..` components. Does not use `standardizedFileURL`, which on macOS
    /// removes `/private` and produces `/var/...`; this preserves the form of the URL passed by the caller so paths
    /// compare in the same form as URLs from history, watching, and listings.
    public static func normalized(_ url: URL) -> String {
        var path = url.path
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        guard path.contains("/.") else { return path }
        var parts: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !parts.isEmpty { parts.removeLast() }
            default:
                parts.append(component)
            }
        }
        return "/" + parts.joined(separator: "/")
    }

    /// Whether `path` equals `base` or is inside it (compares through the `/` separator).
    public static func isSameOrWithin(_ path: String, _ base: String) -> Bool {
        let target = normalized(URL(fileURLWithPath: path))
        let root = normalized(URL(fileURLWithPath: base))
        if target == root { return true }
        if root == "/" { return true }
        return target.hasPrefix(root + "/")
    }
}

/// Record of directories matched by a search enumeration (EC-94, research.md R2).
///
/// Enumeration runs on another thread, so a lock allows `record` from the enumeration and `contains` from the
/// main actor. Only directories are recorded (normalized paths rebased to the root form); files are not recorded.
/// The record lasts only for the current search and is discarded when the search stops.
public final class SearchVisitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var paths: Set<String> = []

    public init() {}

    /// Records a directory's normalized path immediately before matching. Called from the enumeration thread.
    public func record(_ path: String) {
        _ = lock.withLock { paths.insert(path) }
    }

    /// Whether a record exists. Called from the main actor.
    public func contains(_ path: String) -> Bool {
        lock.withLock { paths.contains(path) }
    }
}
