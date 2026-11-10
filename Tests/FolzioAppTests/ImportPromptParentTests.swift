import AppKit
import FolzioCore
import FolzioLocalization
import Testing
@testable import FolzioApp

enum ImportCollisionChoice: CaseIterable, Sendable, Equatable {
    case replace, keepBoth, abort

    var response: NSApplication.ModalResponse {
        switch self {
        case .replace: .alertFirstButtonReturn
        case .keepBoth: .alertSecondButtonReturn
        case .abort: .alertThirdButtonReturn
        }
    }
}

@Suite("Import prompt parent", .serialized)
@MainActor
struct ImportPromptParentTests {
    @Test("Inactive imports show collisions on the receiving window", arguments: ImportCollisionChoice.allCases, [true, false])
    func collisionWithoutActiveWindow(choice: ImportCollisionChoice, sameVolume: Bool) async throws {
        try await withFixture(confirms: false) { fixture in
            var shown = 0
            fixture.conflict.presentSheet = { alert, window in
                shown += 1
                #expect(window === fixture.parent)
                #expect(alert.buttons.count == 3)
                #expect(alert.buttons[0].isEnabled)
                return choice.response
            }
            let outcome = await fixture.coordinator.saveReceived(fixture.request(sameVolume: sameVolume),
                control: fixture.control, parentWindow: fixture.parent)
            #expect(shown == 1)
            let existing = try Data(contentsOf: fixture.target)
            switch choice {
            case .replace:
                #expect(outcome == .finished)
                #expect(existing == fixture.incoming)
            case .keepBoth:
                #expect(outcome == .finished)
                #expect(existing == fixture.original)
                let added = try Data(contentsOf: fixture.destination.appendingPathComponent("cat 2.png"))
                #expect(added == fixture.incoming)
            case .abort:
                #expect(existing == fixture.original)
                #expect(FileManager.default.fileExists(atPath: fixture.source.path))
                let names = try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path)
                #expect(names == ["cat.png"])
            }
            if choice != .abort {
                #expect(FileManager.default.fileExists(atPath: fixture.source.path) == !sameVolume)
            }
        }
    }

    @Test("Operation and collision confirmations prefer the receiving window")
    func explicitParentPrecedesUnrelatedWindow() async throws {
        try await withFixture(confirms: true) { fixture in
            let unrelated = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
            unrelated.isReleasedWhenClosed = false
            defer { unrelated.close() }
            fixture.confirmation.fallbackWindow = { Issue.record("Explicit parent must avoid global lookup"); return unrelated }
            fixture.conflict.fallbackWindow = { Issue.record("Explicit parent must avoid global lookup"); return unrelated }
            var shown: [String] = []
            fixture.confirmation.presentSheet = { _, window in
                #expect(window === fixture.parent)
                shown.append("confirmation")
                return .alertFirstButtonReturn
            }
            fixture.conflict.presentSheet = { _, window in
                #expect(window === fixture.parent)
                shown.append("collision")
                return .alertSecondButtonReturn
            }
            let outcome = await fixture.coordinator.saveReceived(fixture.request(sameVolume: true),
                control: fixture.control, parentWindow: fixture.parent)
            #expect(outcome == .finished)
            #expect(shown == ["confirmation", "collision"])
        }
    }

    @Test("Cancelling operation confirmation leaves both files unchanged")
    func confirmationCancellation() async throws {
        try await withFixture(confirms: true) { fixture in
            var shown = 0
            fixture.confirmation.presentSheet = { _, window in
                shown += 1
                #expect(window === fixture.parent)
                return .alertSecondButtonReturn
            }
            fixture.conflict.presentSheet = { _, _ in Issue.record("Cancelled import must not ask about collisions"); return .alertFirstButtonReturn }
            let outcome = await fixture.coordinator.saveReceived(fixture.request(sameVolume: true),
                control: fixture.control, parentWindow: fixture.parent)
            #expect(shown == 1)
            #expect(outcome == .cancelled)
            let existing = try Data(contentsOf: fixture.target)
            let source = try Data(contentsOf: fixture.source)
            #expect(existing == fixture.original)
            #expect(source == fixture.incoming)
        }
    }

    @Test("Existing callers can still use their fallback window")
    func legacyFallback() async throws {
        try await withFixture(confirms: false) { fixture in
            fixture.conflict.fallbackWindow = { fixture.parent }
            var shown = false
            fixture.conflict.presentSheet = { _, window in
                shown = true
                #expect(window === fixture.parent)
                return .alertThirdButtonReturn
            }
            let choice = await fixture.conflict.resolve(conflictingNames: ["cat.png"], destination: fixture.destination)
            #expect(shown)
            #expect(choice.resolution == .abort)
        }
    }

    @Test("Failures before confirmation use the receiving window", arguments: [false, true])
    func failuresPreferExplicitParent(destinationMissing: Bool) async throws {
        try await withFixture(confirms: true) { fixture in
            if destinationMissing { try FileManager.default.removeItem(at: fixture.destination) }
            fixture.coordinator.fallbackWindow = {
                Issue.record("Explicit failure parent must avoid global lookup")
                return nil
            }
            var shown = 0
            fixture.coordinator.presentSheet = { alert, window in
                shown += 1
                #expect(window === fixture.parent)
                #expect(alert.alertStyle == .warning)
                #expect(alert.informativeText.contains("rejected.png"))
                return .alertFirstButtonReturn
            }
            fixture.confirmation.presentSheet = { _, _ in
                Issue.record("Failed reception must not confirm a copy")
                return .alertSecondButtonReturn
            }
            let request = ImportSaveRequest(files: [],
                failures: [(URL(fileURLWithPath: "rejected.png"), .importRejected(.notImageOrVideo))],
                destination: fixture.destination, sameVolume: true)
            let outcome = await fixture.coordinator.saveReceived(request, control: fixture.control,
                parentWindow: fixture.parent)
            #expect(outcome == .failed)
            #expect(shown == 1)
        }
    }

    private func withFixture(confirms: Bool, _ body: (Fixture) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Folzio.Import.Prompt.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.confirmation.confirmBeforeFileOperations = confirms
        settings.viewSettings.lastFolder = destination
        let confirmation = ConfirmationPresenter(settings: settings)
        let conflict = ConflictPrompt()
        confirmation.fallbackWindow = { nil }
        conflict.fallbackWindow = { nil }
        let model = BrowserModel(kindNames: l10n.kindNames, lister: DirectoryLister(kindNames: l10n.kindNames),
            decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
        let coordinator = FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings,
            confirmation: confirmation, conflictPrompt: conflict)
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        let fixture = Fixture(source: root.appendingPathComponent("cat.png"), destination: destination,
            parent: parent, confirmation: confirmation, conflict: conflict, coordinator: coordinator)
        try fixture.incoming.write(to: fixture.source)
        try fixture.original.write(to: fixture.target)
        defer {
            confirmation.fallbackWindow = { nil }
            conflict.fallbackWindow = { nil }
            confirmation.presentSheet = { _, _ in .alertSecondButtonReturn }
            conflict.presentSheet = { _, _ in .alertThirdButtonReturn }
        }
        try await body(fixture)
    }

    @MainActor
    private struct Fixture {
        let source: URL
        let destination: URL
        let parent: NSWindow
        let confirmation: ConfirmationPresenter
        let conflict: ConflictPrompt
        let coordinator: FileOperationCoordinator
        let original = Data([9, 8, 7])
        let incoming = Data([1, 2, 3])
        var target: URL { destination.appendingPathComponent("cat.png") }
        var control: ImportSaveControl { ImportSaveControl(isActive: { true }, willConfirm: {}, didConfirm: {}) }
        func request(sameVolume: Bool) -> ImportSaveRequest {
            ImportSaveRequest(files: [source], failures: [], destination: destination, sameVolume: sameVolume)
        }
    }
}
