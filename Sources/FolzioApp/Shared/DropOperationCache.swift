import AppKit
import FolzioCore

/// Caches the operation chosen for each drop target during one drag session, so hovering never touches the file
/// system on the UI thread. The decision runs in a detached task; until it finishes, the target is not valid. Drags
/// inside the app and drags from other apps share this mechanism and differ only in how they decide (TAK-74).
@MainActor
final class DropOperationCache {
    /// What the hovered target accepts, as decided off the UI thread.
    enum Outcome: Sendable, Equatable {
        case accepted(InternalDropValidation.Kind)
        case rejected
    }

    /// The inputs of one decision. `command` and `mask` are only part of the key when the decision depends on them.
    struct Context: Hashable, Sendable {
        let urls: [URL]
        let destination: URL
        let option: Bool
        let command: Bool
        let mask: UInt
    }

    typealias Decide = @Sendable (Context) -> Outcome

    private var sequence: Int?
    private var urls: [URL]?
    private var outcomes: [Context: Outcome] = [:]
    private var pending: Set<Context> = []

    /// Called after a decision is stored. Used by tests to wait for the detached task.
    var onOutcomeStored: ((Context) -> Void)?

    /// The URLs of the drag session `sequence`. Reads them once per session instead of on every drag update.
    func urls(sequence: Int, read: () -> [URL]) -> [URL] {
        begin(sequence)
        if let urls { return urls }
        let read = read()
        urls = read
        return read
    }

    /// The stored decision for `context`, or nil while it is being decided. Starts the decision when it is missing.
    func outcome(sequence: Int, context: Context, decide: @escaping Decide) -> Outcome? {
        begin(sequence)
        if let outcome = outcomes[context] { return outcome }
        if pending.insert(context).inserted {
            Task { @MainActor [weak self] in
                let outcome = await Task.detached(priority: .userInitiated) { decide(context) }.value
                guard let self, self.sequence == sequence else { return }
                self.outcomes[context] = outcome
                self.pending.remove(context)
                self.onOutcomeStored?(context)
            }
        }
        return nil
    }

    /// The stored decision for `context`, without starting one. A drop uses this because it must answer at once and
    /// cannot read the file system on the UI thread; a missing decision rejects the drop.
    func cachedOutcome(sequence: Int, context: Context) -> Outcome? {
        guard self.sequence == sequence else { return nil }
        return outcomes[context]
    }

    /// Forgets everything from the previous drag session when a new one starts.
    private func begin(_ sequence: Int) {
        guard self.sequence != sequence else { return }
        self.sequence = sequence
        urls = nil
        outcomes.removeAll()
        pending.removeAll()
    }
}
