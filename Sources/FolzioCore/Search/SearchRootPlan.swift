import Foundation

/// Queue of search roots that have not started enumerating yet (FR-438, FR-440; research.md R3, R4;
/// data-model.md 5).
///
/// Roots are enumerated one at a time from the top. A folder rename only rewrites a waiting root's path: its
/// enumeration has not started, so it will see the new name by itself, and starting an additional enumeration for it
/// would visit the same place twice.
public struct SearchRootPlan: Sendable, Equatable {
    /// Roots waiting to be enumerated, next first.
    public private(set) var pending: [URL]

    public init(pending: [URL] = []) {
        self.pending = pending
    }

    public var isEmpty: Bool { pending.isEmpty }

    /// Removes and returns the next root.
    public mutating func next() -> URL? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    /// Replaces waiting roots that are the renamed folder or inside it. Returns true when any root changed.
    @discardableResult
    public mutating func rebase(_ renamed: RenamedFolder) -> Bool {
        var changed = false
        for index in pending.indices {
            guard let rebased = renamed.rebase(pending[index]) else { continue }
            pending[index] = rebased
            changed = true
        }
        return changed
    }

    /// Whether `url` is a waiting root or inside one.
    public func contains(_ url: URL) -> Bool {
        let path = SearchPath.normalized(url)
        return pending.contains { SearchPath.isSameOrWithin(path, SearchPath.normalized($0)) }
    }

    /// Drops every waiting root (the search stopped).
    public mutating func removeAll() {
        pending.removeAll()
    }
}
