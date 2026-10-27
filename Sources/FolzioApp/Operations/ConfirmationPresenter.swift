import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
final class ConfirmationPresenter {
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// When `includesFolders` is true, notes that folders are processed with their contents (R32). When `location` is
    /// present, includes the target's absolute path (R58). `ConfirmationPolicy` decides whether confirmation can be
    /// skipped. Confirmations that cannot be skipped (rename, move, and Trash from the tree) always appear regardless
    /// of the setting and do not show "Don't ask again" (FR-024, FR-079).
    func confirm(
        _ operation: FileOperation,
        includesFolders: Bool = false,
        origin: OperationOrigin = .fileList,
        location: String? = nil
    ) async -> Bool {
        let isSkippable = ConfirmationPolicy.isSkippable(operation.kind, origin: origin)
        if isSkippable, !settings.confirmation.confirmBeforeFileOperations {
            return true
        }
        return await present(
            messageText: { self.messageText(for: operation.kind, count: operation.sources.count) },
            informativeText: {
                var text = self.informativeText(for: operation, includesFolders: includesFolders)
                if let location { text += "\n" + l10n.text(.dialogConfirmLocation, .text(location)) }
                return text
            },
            confirmTitle: { l10n.text(.dialogConfirmContinue) },
            allowsSuppression: isSkippable
        )
    }

    func confirmRemovingFavorite(named name: String, path: String) async -> Bool {
        guard settings.confirmation.confirmBeforeFileOperations else {
            return true
        }
        return await present(
            messageText: { l10n.text(.dialogFavoriteRemoveTitle) },
            informativeText: { [
                l10n.text(.dialogFavoriteRemoveItems, .text(name)),
                l10n.text(.dialogConfirmLocation, .text(path)),
                l10n.text(.dialogFavoriteRemoveNote),
            ].joined(separator: "\n") },
            confirmTitle: { l10n.text(.dialogFavoriteRemoveConfirm) },
            allowsSuppression: true
        )
    }

    private func present(
        messageText: @escaping @MainActor () -> String,
        informativeText: @escaping @MainActor () -> String,
        confirmTitle: @escaping @MainActor () -> String,
        allowsSuppression: Bool
    ) async -> Bool {

        let alert = NSAlert()
        alert.messageText = messageText()
        alert.informativeText = informativeText()
        alert.addButton(withTitle: confirmTitle())
        alert.addButton(withTitle: l10n.text(.dialogCancel))
        alert.buttons[1].keyEquivalent = "\u{1b}"
        if allowsSuppression {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = l10n.text(.dialogConfirmDontAsk)
        }

        let languageObserver = LanguageChangeObserver {
            alert.messageText = messageText()
            alert.informativeText = informativeText()
            alert.buttons[0].title = confirmTitle()
            alert.buttons[1].title = l10n.text(.dialogCancel)
            alert.suppressionButton?.title = l10n.text(.dialogConfirmDontAsk)
        }

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            }
        } else if allowsSuppression {
            return true
        } else {
            // Operations that always confirm are not executed without confirmation even when there is no sheet parent.
            response = alert.runModal()
        }

        withExtendedLifetime(languageObserver) {}
        if allowsSuppression, alert.suppressionButton?.state == .on {
            settings.confirmation = ConfirmationOptions(confirmBeforeFileOperations: false)
        }

        return response == .alertFirstButtonReturn
    }

    private func messageText(for kind: FileOperation.Kind, count: Int) -> String {
        switch kind {
        case .copy:
            return l10n.text(.dialogConfirmCopy, .count(count))
        case .move:
            return l10n.text(.dialogConfirmMove, .count(count))
        case .rename:
            return l10n.text(.dialogConfirmRename)
        case .trash:
            return l10n.text(.dialogConfirmTrash)
        }
    }

    private func informativeText(for operation: FileOperation, includesFolders: Bool) -> String {
        let sources = operation.sources
        var lines = [l10n.text(.dialogConfirmItems, .number(sources.count))]
        lines.append(contentsOf: sources.prefix(5).map { l10n.text(.dialogConfirmBullet, .text($0.lastPathComponent)) })
        if sources.count > 5 {
            lines.append(l10n.text(.dialogConfirmMore, .number(sources.count - 5)))
        }
        if includesFolders {
            switch operation.kind {
            case .trash:
                lines.append(l10n.text(.dialogConfirmFolderTrash))
            case .copy, .move, .rename:
                lines.append(l10n.text(.dialogConfirmFolderProcess))
            }
        }
        switch operation.kind {
        case .copy, .move:
            if let destination = operation.destination {
                lines.append(l10n.text(.dialogConfirmDestination, .text(destination.path)))
            }
        case .rename, .trash:
            break
        }
        return lines.joined(separator: "\n")
    }
}
