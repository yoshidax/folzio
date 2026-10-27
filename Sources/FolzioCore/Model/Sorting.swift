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

/// Returns true when `a` precedes `b`, false when it follows, and nil when they tie. A nil creation date sorts
/// last regardless of direction; when column values are equal, the natural name order (ascending) is the secondary
/// key.
private func precedes(_ a: MediaFile, _ b: MediaFile, by order: SortOrder) -> Bool? {
    if order.column == .creationDate {
        if a.creationDate == nil, b.creationDate != nil {
            return false
        }
        if a.creationDate != nil, b.creationDate == nil {
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

private func comparePrimary(_ a: MediaFile, _ b: MediaFile, column: SortColumn) -> ComparisonResult {
    switch column {
    case .name:
        return a.name.localizedStandardCompare(b.name)
    case .creationDate:
        switch (a.creationDate, b.creationDate) {
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
