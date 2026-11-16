import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Confirmation presenter", .serialized)
@MainActor
struct ConfirmationPresenterTests {
    private static let source = URL(fileURLWithPath: "/tmp/folzio-confirm/a.jpg")
    private static let destination = URL(fileURLWithPath: "/tmp/folzio-confirm/dest", isDirectory: true)

    /// Runs the operation that `target` governs and returns whether a modal was shown.
    private func runOperation(
        _ target: ConfirmationTarget,
        on presenter: ConfirmationPresenter
    ) async -> Bool {
        switch target {
        case .copy:
            return await presenter.confirm(
                FileOperation(kind: .copy, sources: [Self.source], destination: Self.destination))
        case .move:
            return await presenter.confirm(
                FileOperation(kind: .move, sources: [Self.source], destination: Self.destination), origin: .tree)
        case .rename:
            return await presenter.confirm(
                FileOperation(kind: .rename(newName: "b.jpg"), sources: [Self.source]), origin: .tree)
        case .removeFavorite:
            return await presenter.confirmRemovingFavorite(named: "a", path: Self.destination.path)
        case .trash:
            return await presenter.confirm(FileOperation(kind: .trash, sources: [Self.source]))
        }
    }

    @Test("Turning off one operation skips only that operation's modal (SC-216)",
          arguments: ConfirmationTarget.allCases)
    func skipsOnlyTheTurnedOffOperation(_ turnedOff: ConfirmationTarget) async throws {
        try await withPresenter { settings, presenter, recorder in
            var options = ConfirmationOptions()
            options.setEnabled(false, for: turnedOff)
            settings.confirmation = options
            for target in ConfirmationTarget.allCases {
                recorder.alerts.removeAll()
                let confirmed = await runOperation(target, on: presenter)
                #expect(confirmed, "\(target)")
                #expect(recorder.alerts.count == (target == turnedOff ? 0 : 1), "\(turnedOff) off → \(target)")
            }
        }
    }

    @Test("Trash from the tree follows the Trash setting like the file list (FR-079, US85-AS5, US85-AS10)",
          arguments: [true, false])
    func treeTrashFollowsTheTrashSetting(_ trashConfirms: Bool) async throws {
        try await withPresenter { settings, presenter, recorder in
            // Every other setting is the opposite, so only the Trash setting can explain the result.
            settings.confirmation = ConfirmationOptions(
                copy: !trashConfirms, move: !trashConfirms, rename: !trashConfirms,
                removeFavorite: !trashConfirms, trash: trashConfirms)
            let confirmed = await presenter.confirm(
                FileOperation(kind: .trash, sources: [Self.source]), origin: .tree)
            #expect(confirmed)
            #expect(recorder.alerts.count == (trashConfirms ? 1 : 0))
            if trashConfirms {
                #expect(recorder.alerts.first?.showsSuppressionButton == true)
            }
        }
    }

    @Test("\"Don't ask again\" on Trash from the tree turns off only the Trash confirmation (FR-395, SC-218)")
    func dontAskAgainOnTreeTrash() async throws {
        try await withPresenter(checksSuppression: true) { settings, presenter, _ in
            settings.confirmation = ConfirmationOptions()
            _ = await presenter.confirm(FileOperation(kind: .trash, sources: [Self.source]), origin: .tree)
            let options = settings.confirmation
            for target in ConfirmationTarget.allCases {
                #expect(options.isEnabled(target) == (target != .trash), "\(target)")
            }
        }
    }

    @Test("\"Don't ask again\" turns off only that operation (FR-395, SC-218)", arguments: ConfirmationTarget.allCases)
    func dontAskAgainTurnsOffOnlyThatOperation(_ target: ConfirmationTarget) async throws {
        try await withPresenter(checksSuppression: true) { settings, presenter, recorder in
            settings.confirmation = ConfirmationOptions()
            _ = await runOperation(target, on: presenter)
            #expect(recorder.alerts.first?.showsSuppressionButton == true)
            let options = settings.confirmation
            for other in ConfirmationTarget.allCases {
                #expect(options.isEnabled(other) == (other != target), "\(target) → \(other)")
            }
        }
    }

    @Test("\"Don't ask again\" also applies when the modal is cancelled (EC-262)")
    func dontAskAgainAppliesOnCancel() async throws {
        try await withPresenter(checksSuppression: true, response: .alertSecondButtonReturn) { settings, presenter, _ in
            let confirmed = await runOperation(.move, on: presenter)
            #expect(!confirmed)
            #expect(!settings.confirmation.move)
            #expect(settings.confirmation.copy)
        }
    }

    @Test("Without a window, every operation whose confirmation is on asks with an app-modal alert (EC-263)",
          arguments: ConfirmationTarget.allCases)
    func noWindowStillConfirms(_ target: ConfirmationTarget) async throws {
        try await withPresenter { settings, presenter, recorder in
            presenter.fallbackWindow = { nil }
            var modals: [NSAlert] = []
            presenter.runModal = { alert in
                modals.append(alert)
                return .alertSecondButtonReturn
            }
            // Bind the result first: Xcode 16.0 on CI rejects effect markers combined with `!` inside `#expect`.
            let cancelled = await runOperation(target, on: presenter)
            #expect(!cancelled, "\(target)")
            #expect(modals.count == 1, "\(target)")
            #expect(modals.first?.showsSuppressionButton == true, "\(target)")
            #expect(recorder.alerts.isEmpty)
        }
    }

    @Test("Without a window, Trash from the tree asks while the Trash confirmation is on (EC-263)")
    func noWindowTreeTrash() async throws {
        try await withPresenter { settings, presenter, _ in
            presenter.fallbackWindow = { nil }
            var modals = 0
            presenter.runModal = { _ in
                modals += 1
                return .alertSecondButtonReturn
            }
            let trash = FileOperation(kind: .trash, sources: [Self.source])
            let cancelled = await presenter.confirm(trash, origin: .tree)
            #expect(!cancelled)
            #expect(modals == 1)

            settings.confirmation = ConfirmationOptions(trash: false)
            let skipped = await presenter.confirm(trash, origin: .tree)
            #expect(skipped)
            #expect(modals == 1)
        }
    }

    @Test("Without a window, an operation whose confirmation is off runs without any alert (FR-024)",
          arguments: ConfirmationTarget.allCases)
    func noWindowSkipsWhenTurnedOff(_ target: ConfirmationTarget) async throws {
        try await withPresenter { settings, presenter, recorder in
            presenter.fallbackWindow = { nil }
            presenter.runModal = { _ in
                Issue.record("A turned-off confirmation must not show an alert")
                return .alertSecondButtonReturn
            }
            var options = ConfirmationOptions()
            options.setEnabled(false, for: target)
            settings.confirmation = options
            let confirmed = await runOperation(target, on: presenter)
            #expect(confirmed, "\(target)")
            #expect(recorder.alerts.isEmpty)
        }
    }

    private func withPresenter(
        checksSuppression: Bool = false,
        response: NSApplication.ModalResponse = .alertFirstButtonReturn,
        _ body: @MainActor (SettingsStore, ConfirmationPresenter, AlertRecorder) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        let suite = "Folzio.Confirmation.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let presenter = ConfirmationPresenter(settings: settings)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        presenter.fallbackWindow = { window }
        presenter.runModal = { _ in
            Issue.record("An app-modal alert must not appear while a window is available")
            return .alertSecondButtonReturn
        }
        let recorder = AlertRecorder()
        presenter.presentSheet = { alert, _ in
            recorder.alerts.append(alert)
            if checksSuppression { alert.suppressionButton?.state = .on }
            return response
        }
        try await body(settings, presenter, recorder)
    }
}

@MainActor
private final class AlertRecorder {
    var alerts: [NSAlert] = []
}
