import Foundation

/// Keeps the displayed order and selection until a file-list Move to Trash finishes.
public struct PostTrashSelection: Sendable {
    let orderedFiles: [MediaFile]
    let lastTarget: Int
    let targets: Set<URL>
    let selection: SelectionState
    let navigationGeneration: Int
    let intentGeneration: Int

    init?(orderedFiles: [MediaFile], targets: Set<URL>, selection: SelectionState,
          navigationGeneration: Int, intentGeneration: Int) {
        guard !targets.isEmpty, targets.isSubset(of: selection.selected) else { return nil }
        var unseen = targets
        var lastTarget = 0
        for index in orderedFiles.indices where unseen.remove(orderedFiles[index].url) != nil {
            lastTarget = index
            if unseen.isEmpty { break }
        }
        guard unseen.isEmpty else { return nil }
        // Array value semantics retain the original order without copying every URL before confirmation.
        self.orderedFiles = orderedFiles
        self.lastTarget = lastTarget
        self.targets = targets
        self.selection = selection
        self.navigationGeneration = navigationGeneration
        self.intentGeneration = intentGeneration
    }

    private init(_ snapshot: Self, intentGeneration: Int) {
        orderedFiles = snapshot.orderedFiles
        lastTarget = snapshot.lastTarget
        targets = snapshot.targets
        selection = snapshot.selection
        navigationGeneration = snapshot.navigationGeneration
        self.intentGeneration = intentGeneration
    }

    /// Allows the same original candidates to be checked again after asynchronous search pruning.
    func continuing(withIntentGeneration generation: Int) -> Self {
        Self(self, intentGeneration: generation)
    }

    /// Returns nil when nothing succeeded; an empty selection means there is no following survivor.
    func selection(afterRemoving removed: Set<URL>, remainingURLs: [URL]) -> SelectionState? {
        guard !targets.isDisjoint(with: removed) else { return nil }
        let removedPaths = Set(removed.map { $0.standardizedFileURL.path })
        func survives(_ url: URL) -> Bool {
            !SearchRemovalScope.contains(url, in: removedPaths)
        }
        let available = Set(remainingURLs)
        // The parent link navigates; it is never a failed trash target or a surviving real selection.
        let kept = selection.selected.filter { !ParentLink.isParentLink($0) && available.contains($0) && survives($0) }
        if !kept.isEmpty {
            let focused = selection.focused.flatMap { kept.contains($0) ? $0 : nil }
                ?? remainingURLs.last { kept.contains($0) }
            return SelectionState(selected: kept, focused: focused)
        }
        let next = orderedFiles.dropFirst(lastTarget + 1).lazy.map(\.url).first { available.contains($0) && survives($0) }
        return SelectionState(selected: Set(next.map { [$0] } ?? []), focused: next)
    }
}
