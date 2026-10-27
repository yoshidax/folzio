import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
final class ConflictPrompt {
    struct Choice {
        let resolution: ConflictResolution
        let applyToAll: Bool
    }

    init() {}

    func resolve(conflictingNames: [String], destination: URL?, allowReplace: Bool = true) async -> Choice {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return Choice(resolution: .abort, applyToAll: false)
        }

        let alert = NSAlert()
        alert.messageText = l10n.text(.dialogConflictTitle)
        alert.informativeText = informativeText(for: conflictingNames, destination: destination)
        alert.addButton(withTitle: l10n.text(.dialogConflictReplace))
        alert.addButton(withTitle: l10n.text(.dialogConflictKeepBoth))
        alert.addButton(withTitle: l10n.text(.dialogConflictStop))
        alert.buttons[0].isEnabled = allowReplace
        alert.buttons[2].keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = l10n.text(.dialogConflictApplyAll)

        let languageObserver = LanguageChangeObserver {
            alert.messageText = l10n.text(.dialogConflictTitle)
            alert.informativeText = self.informativeText(for: conflictingNames, destination: destination)
            alert.buttons[0].title = l10n.text(.dialogConflictReplace)
            alert.buttons[1].title = l10n.text(.dialogConflictKeepBoth)
            alert.buttons[2].title = l10n.text(.dialogConflictStop)
            alert.suppressionButton?.title = l10n.text(.dialogConflictApplyAll)
        }

        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }

        withExtendedLifetime(languageObserver) {}

        let resolution: ConflictResolution
        switch response {
        case .alertFirstButtonReturn:
            resolution = .replace
        case .alertSecondButtonReturn:
            resolution = .keepBoth
        default:
            resolution = .abort
        }
        return Choice(resolution: resolution, applyToAll: alert.suppressionButton?.state == .on)
    }

    private func informativeText(for names: [String], destination: URL?) -> String {
        var lines = [l10n.text(.dialogConflictItems, .number(names.count))]
        lines.append(contentsOf: names.prefix(5).map { l10n.text(.dialogConfirmBullet, .text($0)) })
        if names.count > 5 {
            lines.append(l10n.text(.dialogConfirmMore, .number(names.count - 5)))
        }
        if let destination {
            lines.append(l10n.text(.dialogConfirmDestination, .text(destination.path)))
        }
        return lines.joined(separator: "\n")
    }
}
