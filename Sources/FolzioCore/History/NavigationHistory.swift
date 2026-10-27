import Foundation

/// History sequence (FR-107–111). All recording, navigation, branching, capacity, and consolidation rules live
/// in this value type (R68).
public struct NavigationHistory: Sendable {
    public static let capacity = 100

    public private(set) var backEntries: [HistoryEntry]
    public private(set) var current: HistoryEntry?
    public private(set) var forwardEntries: [HistoryEntry]
    public private(set) var version: Int

    private var lastRecordKind: HistoryRecordKind?

    public init() {
        self.backEntries = []
        self.current = nil
        self.forwardEntries = []
        self.version = 0
        self.lastRecordKind = nil
    }

    public var count: Int {
        backEntries.count + (current == nil ? 0 : 1) + forwardEntries.count
    }

    public var canGoBack: Bool { !backEntries.isEmpty }
    public var canGoForward: Bool { !forwardEntries.isEmpty }

    /// Back entries, current, and forward entries in one sequence (used for existence checks)
    public var allEntries: [HistoryEntry] {
        var entries = backEntries
        if let current { entries.append(current) }
        entries.append(contentsOf: forwardEntries)
        return entries
    }

    /// Records the state after an operation as one history entry. Does nothing and returns false for the same state
    /// (FR-107, R71).
    @discardableResult
    public mutating func record(
        location: HistoryLocation,
        viewState: HistoryViewState,
        kind: HistoryRecordKind,
        leavingFocus: URL?
    ) -> Bool {
        if kind == .thumbnailSize, lastRecordKind == .thumbnailSize, var merged = current {
            guard merged.viewState != viewState else { return false }
            merged.viewState = viewState
            current = merged
            let didConsolidate = consolidate()
            lastRecordKind = didConsolidate ? nil : .thumbnailSize
            version += 1
            return true
        }

        let entry = HistoryEntry(location: location, viewState: viewState)
        if let current, current.hasSameState(as: entry) {
            return false
        }

        if var leaving = current {
            leaving.focusedItem = leavingFocus
            backEntries.append(leaving)
        }
        current = entry
        forwardEntries.removeAll()

        if count > Self.capacity {
            let overflow = count - Self.capacity
            backEntries.removeFirst(min(overflow, backEntries.count))
        }

        lastRecordKind = kind
        version += 1
        return true
    }

    public func candidate(_ direction: HistoryDirection) -> HistoryEntry? {
        switch direction {
        case .back:
            return backEntries.last
        case .forward:
            return forwardEntries.first
        }
    }

    /// Removes a candidate that could not be found (FR-109, EC-54).
    public mutating func dropCandidate(_ direction: HistoryDirection) {
        switch direction {
        case .back:
            guard !backEntries.isEmpty else { return }
            backEntries.removeLast()
        case .forward:
            guard !forwardEntries.isEmpty else { return }
            forwardEntries.removeFirst()
        }
        _ = consolidate()
        version += 1
    }

    /// Moves to the previous or next history entry. Records the focused row on the entry being left (FR-108).
    @discardableResult
    public mutating func move(_ direction: HistoryDirection, leavingFocus: URL?) -> HistoryEntry? {
        guard let target = candidate(direction) else { return nil }

        switch direction {
        case .back:
            backEntries.removeLast()
            if var leaving = current {
                leaving.focusedItem = leavingFocus
                forwardEntries.insert(leaving, at: 0)
            }
        case .forward:
            forwardEntries.removeFirst()
            if var leaving = current {
                leaving.focusedItem = leavingFocus
                backEntries.append(leaving)
            }
        }

        current = target
        lastRecordKind = nil
        version += 1
        return target
    }

    /// Replaces the current presentation state (when search results end; R76).
    public mutating func updateCurrentViewState(_ viewState: HistoryViewState) {
        guard var entry = current, entry.viewState != viewState else { return }
        entry.viewState = viewState
        current = entry
        _ = consolidate()
        lastRecordKind = nil
        version += 1
    }

    /// Replaces the current location (EC-60). Does not change the presentation state or forward entries.
    public mutating func replaceCurrentLocation(_ location: HistoryLocation) {
        guard var entry = current, entry.location != location else { return }
        entry.location = location
        current = entry
        _ = consolidate()
        version += 1
    }

    /// Moves the current entry to the end of the back entries and sets current to nil (EC-62).
    public mutating func detachCurrent() {
        guard let entry = current else { return }
        backEntries.append(entry)
        current = nil
        lastRecordKind = nil
        version += 1
    }

    /// Removes the current entry and sets it to nil (EC-65).
    public mutating func removeCurrent() {
        guard current != nil else { return }
        current = nil
        lastRecordKind = nil
        _ = consolidate()
        version += 1
    }

    /// Removes entries at or below any of `urls` (FR-109).
    public mutating func removeEntries(within urls: [URL], keepingCurrent: Bool) {
        guard !urls.isEmpty else { return }
        var changed = false

        if !keepingCurrent, let current, urls.contains(where: { current.location.isWithin($0) }) {
            self.current = nil
            changed = true
        }
        backEntries.removeAll { entry in
            guard urls.contains(where: { entry.location.isWithin($0) }) else { return false }
            changed = true
            return true
        }
        forwardEntries.removeAll { entry in
            guard urls.contains(where: { entry.location.isWithin($0) }) else { return false }
            changed = true
            return true
        }
        if changed {
            _ = consolidate()
            version += 1
        }
    }

    /// Removes entries at the given `allEntries` positions (external changes; may include the current entry).
    public mutating func removeEntries(at positions: Set<Int>) {
        guard !positions.isEmpty else { return }
        let entries = allEntries
        guard positions.contains(where: { entries.indices.contains($0) }) else { return }

        let boundary = backEntries.count
        let currentIndex = current == nil ? nil : boundary
        var newBack: [HistoryEntry] = []
        var newCurrent: HistoryEntry?
        var newForward: [HistoryEntry] = []

        for (index, entry) in entries.enumerated() where !positions.contains(index) {
            if let currentIndex, index == currentIndex {
                newCurrent = entry
            } else if index < boundary {
                newBack.append(entry)
            } else {
                newForward.append(entry)
            }
        }

        backEntries = newBack
        current = newCurrent
        forwardEntries = newForward
        _ = consolidate()
        version += 1
    }

    /// Updates history for a renamed folder. Replaces the current location with the new one and removes other
    /// entries (FR-109, R75).
    public mutating func renameFolder(_ renamed: RenamedFolder) {
        var changed = false

        if var entry = current, entry.location.isWithin(renamed.from),
           let rebased = entry.location.rebased(by: renamed) {
            entry.location = rebased
            current = entry
            changed = true
        }

        backEntries.removeAll { entry in
            guard entry.location.isWithin(renamed.from) else { return false }
            changed = true
            return true
        }
        forwardEntries.removeAll { entry in
            guard entry.location.isWithin(renamed.from) else { return false }
            changed = true
            return true
        }

        guard changed else { return }
        _ = consolidate()
        version += 1
    }

    /// Consolidates adjacent entries with the same state (EC-59). Keeps the current entry when the group contains it;
    /// otherwise keeps the newer entry.
    @discardableResult
    private mutating func consolidate() -> Bool {
        let entries = allEntries
        guard entries.count > 1 else { return false }

        let boundary = backEntries.count
        let currentIndex = current == nil ? nil : boundary
        var keptIndices: [Int] = []
        var index = 0

        while index < entries.count {
            var end = index + 1
            while end < entries.count, entries[end].hasSameState(as: entries[index]) {
                end += 1
            }
            if end - index == 1 {
                keptIndices.append(index)
            } else if let currentIndex, currentIndex >= index, currentIndex < end {
                keptIndices.append(currentIndex)
            } else {
                keptIndices.append(end - 1)
            }
            index = end
        }

        guard keptIndices.count != entries.count else { return false }

        var newBack: [HistoryEntry] = []
        var newCurrent: HistoryEntry?
        var newForward: [HistoryEntry] = []
        for index in keptIndices {
            if let currentIndex, index == currentIndex {
                newCurrent = entries[index]
            } else if index < boundary {
                newBack.append(entries[index])
            } else {
                newForward.append(entries[index])
            }
        }

        backEntries = newBack
        current = newCurrent
        forwardEntries = newForward
        return true
    }
}
