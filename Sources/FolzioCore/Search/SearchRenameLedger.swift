import Foundation

/// Renames of folders during a search and the match records for each enumeration (EC-52, EC-94; research.md R2, R3;
/// data-model.md §3).
///
/// Results from an enumeration started before a rename carry URLs from the old location, so the ledger applies
/// renames recorded after that enumeration began and rebases them to the new location. When the renamed folder
/// itself had not been matched at the time of the rename (its old location had not been visited yet), the ledger
/// drops the row for the old location and uses the row that a subsequent enumeration emits under the new name.
/// It does not read the disk and compares paths with `SearchPath.normalized` (it does not use
/// `standardizedFileURL`, which removes `/private` and changes the form relative to enumeration records).
public struct SearchRenameLedger: Sendable {
    private struct Stream: Sendable {
        /// Directories matched by that enumeration
        var visits: SearchVisitLog
        /// Number of entries in `renames` when that enumeration started
        var renameCount: Int
    }

    /// Renames during the current search (oldest first)
    private var renames: [RenamedFolder] = []
    /// Per-enumeration records and the rename count at start
    private var streams: [Stream] = []
    /// Rename index treated as unmatched → normalized path of the original location
    private var rejudged: [Int: String] = [:]

    public init() {}

    /// Whether there are no renames (the ledger is empty).
    public var isEmpty: Bool { renames.isEmpty }

    /// Registers an enumeration and returns its index (0, 1, ...).
    public mutating func addStream(visits: SearchVisitLog) -> Int {
        streams.append(Stream(visits: visits, renameCount: renames.count))
        return streams.count - 1
    }

    /// Records a rename. `visited == false` means the folder had not been matched yet at the time of the rename.
    public mutating func recordRename(_ renamed: RenamedFolder, visited: Bool) {
        if !visited {
            rejudged[renames.count] = SearchPath.normalized(renamed.from)
        }
        renames.append(renamed)
    }

    /// Rewinds the folder to its location when each enumeration matched and checks the record. Returns true when any
    /// enumeration has a record.
    public func hasVisited(_ folder: URL) -> Bool {
        for stream in streams {
            var location = folder
            for renamed in renames[stream.renameCount...].reversed() {
                guard let reversed = renamed.reversed.rebase(location) else { continue }
                location = reversed
            }
            if stream.visits.contains(SearchPath.normalized(location)) {
                return true
            }
        }
        return false
    }

    /// Applies renames recorded after enumeration `index` started to a result from it. Returns nil (drops the result)
    /// for a row at the original location at the time of a rename treated as unmatched (the renamed folder itself).
    /// For folder rows, also changes `name` to the new name when the last URL component changes (FR-105).
    public func place(_ file: MediaFile, fromStream index: Int) -> MediaFile? {
        guard streams.indices.contains(index) else { return file }
        let stream = streams[index]
        var placed = file
        for offset in 0..<(renames.count - stream.renameCount) {
            let renameIndex = stream.renameCount + offset
            let renamed = renames[renameIndex]
            if rejudged[renameIndex] == SearchPath.normalized(placed.url) {
                return nil
            }
            guard let rebased = renamed.rebase(placed.url) else { continue }
            if placed.kind == .folder, rebased.lastPathComponent != placed.url.lastPathComponent {
                placed.name = rebased.lastPathComponent
            }
            placed.url = rebased
        }
        return placed
    }
}
