import Foundation

public func sorted(_ files: [MediaFile], by order: SortOrder) -> [MediaFile] {
    // `..` (.parent) is not sorted and is always kept first.
    let parents = files.filter { $0.kind == .parent }
    let rest = files.filter { $0.kind != .parent }
    let indexed = Array(rest.enumerated())

    return parents + indexed.sorted { lhs, rhs in
        if let result = precedes(lhs.element, rhs.element, by: order) {
            return result
        }
        return lhs.offset < rhs.offset
    }.map(\.element)
}

/// Builds an array in the same order as `sorted(existing + incoming, by: order)` from two sorted arrays in
/// a single pass. For ties, `existing` comes first (R36). Assumes `..` (.parent) rows are not passed in.
public func sortedMerge(_ existing: [MediaFile], _ incoming: [MediaFile], by order: SortOrder) -> [MediaFile] {
    guard !existing.isEmpty else { return incoming }
    guard !incoming.isEmpty else { return existing }

    var result: [MediaFile] = []
    result.reserveCapacity(existing.count + incoming.count)
    var i = 0
    var j = 0
    while i < existing.count, j < incoming.count {
        // Places incoming only when it comes strictly first (existing comes first on ties).
        if precedes(incoming[j], existing[i], by: order) == true {
            result.append(incoming[j])
            j += 1
        } else {
            result.append(existing[i])
            i += 1
        }
    }
    result.append(contentsOf: existing[i...])
    result.append(contentsOf: incoming[j...])
    return result
}

/// Returns true when `a` precedes `b`, false when it follows, and nil when they tie. A missing creation or
/// modification date sorts last regardless of direction; when column values are equal, the natural name order
/// (ascending) is the secondary key. Folders count as 0 bytes when sorting by size, as in Finder. When sorting by
/// name, folder rows always come before file rows in both directions, and each group is ordered by name (FR-288).
private func precedes(_ a: MediaFile, _ b: MediaFile, by order: SortOrder) -> Bool? {
    if order.column == .name, a.kind.isFolderRow != b.kind.isFolderRow {
        return a.kind.isFolderRow
    }

    if let dates = dateAccessor(for: order.column) {
        if dates(a) == nil, dates(b) != nil {
            return false
        }
        if dates(a) != nil, dates(b) == nil {
            return true
        }
    }

    let primary = comparePrimary(a, b, column: order.column)
    if primary != .orderedSame {
        return order.ascending ? primary == .orderedAscending : primary == .orderedDescending
    }

    let byName = a.name.localizedStandardCompare(b.name)
    if byName != .orderedSame {
        return byName == .orderedAscending
    }
    return nil
}

private func dateAccessor(for column: SortColumn) -> ((MediaFile) -> Date?)? {
    switch column {
    case .creationDate:
        return { $0.creationDate }
    case .modificationDate:
        return { $0.modificationDate }
    case .name, .kind, .size, .location:
        return nil
    }
}

private func compareDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
    switch (lhs, rhs) {
    case let (.some(lhs), .some(rhs)):
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    case (nil, nil):
        return .orderedSame
    case (nil, .some):
        return .orderedDescending
    case (.some, nil):
        return .orderedAscending
    }
}

private func comparePrimary(_ a: MediaFile, _ b: MediaFile, column: SortColumn) -> ComparisonResult {
    switch column {
    case .name:
        return a.name.localizedStandardCompare(b.name)
    case .creationDate:
        return compareDates(a.creationDate, b.creationDate)
    case .modificationDate:
        return compareDates(a.modificationDate, b.modificationDate)
    case .size:
        let lhs = a.hasFileSize ? a.fileSize : 0
        let rhs = b.hasFileSize ? b.fileSize : 0
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    case .kind:
        let lhs = a.typeDescription.localizedStandardCompare(b.typeDescription)
        if lhs != .orderedSame {
            return lhs
        }
        return a.kind.sortKey.localizedStandardCompare(b.kind.sortKey)
    case .location:
        // Used only while showing search results (FR-084). Not persisted.
        return a.url.deletingLastPathComponent().path
            .localizedStandardCompare(b.url.deletingLastPathComponent().path)
    }
}
