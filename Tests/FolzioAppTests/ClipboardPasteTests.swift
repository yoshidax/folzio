import AppKit
import FolzioCore
import FolzioLocalization
import Testing
@testable import FolzioApp

@Suite("Paste after the copied items move", .serialized)
@MainActor
struct ClipboardPasteTests {
    @Test("Pastes again after a move paste, without changing the clipboard (US94-AS1, SC-235, SC-236)")
    func pasteAfterMovePaste() async throws {
        try await withFixture { fixture in
            let file = try fixture.makeFile("photo.jpg")
            await PasteboardFileURLs.copy([file], to: fixture.board)
            let copied = PasteboardFileURLs.entries(in: fixture.board)
            let changeCount = fixture.board.changeCount

            await fixture.coordinator.paste(into: fixture.b, move: true, pasteboard: fixture.board)
            await fixture.coordinator.paste(into: fixture.c, move: false, pasteboard: fixture.board)

            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(FileManager.default.fileExists(atPath: fixture.b.appendingPathComponent("photo.jpg").path))
            #expect(FileManager.default.fileExists(atPath: fixture.c.appendingPathComponent("photo.jpg").path))
            #expect(fixture.failures.isEmpty)
            #expect(PasteboardFileURLs.entries(in: fixture.board) == copied)
            #expect(fixture.board.changeCount == changeCount)
        }
    }

    @Test("Pastes a renamed item under its new name (US94-AS2)")
    func pasteAfterRename() async throws {
        try await withFixture { fixture in
            let file = try fixture.makeFile("photo.jpg")
            await PasteboardFileURLs.copy([file], to: fixture.board)
            try FileManager.default.moveItem(at: file, to: fixture.root.appendingPathComponent("renamed.jpg"))

            await fixture.coordinator.paste(into: fixture.c, move: false, pasteboard: fixture.board)

            #expect(FileManager.default.fileExists(atPath: fixture.c.appendingPathComponent("renamed.jpg").path))
            #expect(fixture.failures.isEmpty)
        }
    }

    @Test("Pastes a folder with its contents after the folder moves (US94-AS3)")
    func pasteAfterFolderMove() async throws {
        try await withFixture { fixture in
            let folder = fixture.root.appendingPathComponent("album", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data([1, 2]).write(to: folder.appendingPathComponent("cat.jpg"))
            await PasteboardFileURLs.copy([folder], to: fixture.board)
            try FileManager.default.moveItem(at: folder, to: fixture.b.appendingPathComponent("album", isDirectory: true))

            await fixture.coordinator.paste(into: fixture.c, move: false, pasteboard: fixture.board)

            let pasted = fixture.c.appendingPathComponent("album/cat.jpg")
            #expect(try Data(contentsOf: pasted) == Data([1, 2]))
            #expect(fixture.failures.isEmpty)
        }
    }

    @Test("Pastes a file path URL from the clipboard as before (EC-285)")
    func pastePathURL() async throws {
        try await withFixture { fixture in
            let file = try fixture.makeFile("photo.jpg")
            fixture.board.clearContents()
            fixture.board.writeObjects([file as NSURL])

            await fixture.coordinator.paste(into: fixture.c, move: false, pasteboard: fixture.board)

            #expect(FileManager.default.fileExists(atPath: fixture.c.appendingPathComponent("photo.jpg").path))
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test("Shows an item that no longer resolves by name and pastes the others (US94-AS9, EC-283)")
    func pasteWithMissingItem() async throws {
        try await withFixture { fixture in
            let gone = try fixture.makeFile("gone.jpg")
            let kept = try fixture.makeFile("kept.jpg")
            await PasteboardFileURLs.copy([gone, kept], to: fixture.board)
            try FileManager.default.removeItem(at: gone)

            await fixture.coordinator.paste(into: fixture.c, move: false, pasteboard: fixture.board)

            #expect(FileManager.default.fileExists(atPath: fixture.c.appendingPathComponent("kept.jpg").path))
            #expect(fixture.failures.count == 1)
            #expect(fixture.failures.first?.contains("gone.jpg") == true)
        }
    }

    @Test("Shows the failure when no item resolves (US94-AS9)")
    func pasteWithOnlyMissingItems() async throws {
        try await withFixture { fixture in
            let gone = try fixture.makeFile("gone.jpg")
            await PasteboardFileURLs.copy([gone], to: fixture.board)
            try FileManager.default.removeItem(at: gone)

            await fixture.coordinator.paste(into: fixture.c, move: true, pasteboard: fixture.board)

            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.c.path).isEmpty)
            #expect(fixture.failures.count == 1)
            #expect(fixture.failures.first?.contains("gone.jpg") == true)
        }
    }

    private func withFixture(_ body: @MainActor (Fixture) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let b = root.appendingPathComponent("B", isDirectory: true)
        let c = root.appendingPathComponent("C", isDirectory: true)
        for folder in [b, c] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Folzio.ClipboardPaste.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.viewSettings.lastFolder = root
        settings.confirmation = ConfirmationOptions(copy: false, move: false, rename: false, removeFavorite: false,
            trash: false)
        let model = BrowserModel(kindNames: l10n.kindNames, lister: DirectoryLister(kindNames: l10n.kindNames),
            decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
        let coordinator = FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let board = NSPasteboard(name: .init("FolzioTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let fixture = Fixture(root: root, b: b, c: c, board: board, coordinator: coordinator)
        coordinator.fallbackWindow = { window }
        coordinator.presentSheet = { [fixture] alert, _ in
            fixture.record(alert.informativeText)
            return .alertFirstButtonReturn
        }
        try await body(fixture)
    }

    @MainActor
    private final class Fixture {
        let root: URL
        let b: URL
        let c: URL
        let board: NSPasteboard
        let coordinator: FileOperationCoordinator
        private(set) var failures: [String] = []

        init(root: URL, b: URL, c: URL, board: NSPasteboard, coordinator: FileOperationCoordinator) {
            self.root = root
            self.b = b
            self.c = c
            self.board = board
            self.coordinator = coordinator
        }

        func record(_ text: String) {
            failures.append(text)
        }

        func makeFile(_ name: String) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data(name.utf8).write(to: url)
            return url
        }
    }
}
