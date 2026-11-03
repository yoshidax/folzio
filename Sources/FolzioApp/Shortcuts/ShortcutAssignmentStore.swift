import AppKit
import FolzioCore
import FolzioLocalization

extension Notification.Name {
    /// Posted after the current shortcut assignments change (FR-261).
    static let shortcutAssignmentsDidChange = Notification.Name("FolzioShortcutAssignmentsDidChange")
}

/// Holds the current shortcut assignments, saves them, and tells every display to refresh.
///
/// Every menu, tooltip, and reference reads its keys from here, so that they cannot disagree (FR-261).
@MainActor
final class ShortcutAssignmentStore {
    static let shared = ShortcutAssignmentStore()

    private let settings: SettingsStore
    private(set) var assignments: ShortcutAssignments

    init(settings: SettingsStore = SettingsStore(defaults: .standard)) {
        self.settings = settings
        assignments = ShortcutAssignments(storedOverrides: settings.shortcutOverrides)
    }

    /// Assigns a combination and returns the reason it was refused, or nil on success.
    @discardableResult
    func assign(_ combination: KeyCombination, to command: ShortcutCommandID) -> ShortcutAssignmentError? {
        switch assignments.assigning(combination, to: command) {
        case let .success(updated):
            commit(updated)
            return nil
        case let .failure(error):
            return error
        }
    }

    /// Returns one command to its default and reports the command that blocks it, if any.
    @discardableResult
    func reset(_ command: ShortcutCommandID) -> ShortcutAssignmentError? {
        switch assignments.resetting(command) {
        case let .success(updated):
            commit(updated)
            return nil
        case let .failure(error):
            return error
        }
    }

    /// Removes the command's key (FR-268).
    func unset(_ command: ShortcutCommandID) {
        commit(assignments.unsetting(command))
    }

    func resetAll() {
        commit(assignments.resettingAll())
    }

    /// The display text of one command's current key, such as `⇧⌘N`, or "Not Set" when the command has none.
    func keyText(_ command: ShortcutCommandID) -> String {
        assignments.combination(for: command)?.displayText ?? l10n.text(.settingsShortcutsUnset)
    }

    /// The display text of several commands' current keys, joined with " / ".
    func keyText(_ commands: [ShortcutCommandID]) -> String {
        commands.map(keyText).joined(separator: " / ")
    }

    private func commit(_ updated: ShortcutAssignments) {
        guard updated != assignments else { return }
        assignments = updated
        settings.shortcutOverrides = updated.storedOverrides
        MenuShortcutApplier.shared.applyAll()
        NotificationCenter.default.post(name: .shortcutAssignmentsDidChange, object: nil)
    }
}

/// Runs an update on the main actor whenever the shortcut assignments change.
@MainActor
final class ShortcutAssignmentObserver: NSObject {
    private let update: @MainActor () -> Void

    init(update: @escaping @MainActor () -> Void) {
        self.update = update
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(assignmentsDidChange), name: .shortcutAssignmentsDidChange, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func assignmentsDidChange() { update() }
}
