import Foundation

/// Finds what to record when a search result disappears outside the app, so that late results from the same old
/// location stay hidden (EC-236). A whole folder moved away hides its other files that have not arrived yet, the same
/// as a move inside the app (`BrowserModel.didMoveSearchItems`).
enum SearchRemovalScope {
    /// The topmost missing item on the way from `url` up to the search root: the missing ancestor whose parent still
    /// exists, the root itself when the root is gone, or `url` when only that item is gone. Never goes above `root`.
    /// - Parameters:
    ///   - url: A search result that no longer exists.
    ///   - root: The search root. When nil, stops at the first existing parent.
    ///   - known: Existence already checked during this call, keyed by standardized path, so a folder is checked once.
    ///   - exists: Checks whether a path exists. Reads the file system; call off the UI thread.
    static func topmostMissing(
        _ url: URL,
        root: URL?,
        known: inout [String: Bool],
        exists: (URL) -> Bool
    ) -> URL {
        let rootPath = root?.standardizedFileURL.path
        var current = url.standardizedFileURL
        while true {
            if let rootPath, current.path == rootPath { return current }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path else { return current }
            if let rootPath, !isSameOrInside(parent.path, rootPath) { return current }
            let parentExists: Bool
            if let cached = known[parent.path] {
                parentExists = cached
            } else {
                parentExists = exists(parent)
                known[parent.path] = parentExists
            }
            if parentExists { return current }
            current = parent
        }
    }

    private static func isSameOrInside(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }
}
