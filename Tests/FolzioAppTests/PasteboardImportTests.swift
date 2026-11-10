import AppKit
import FolzioCore
import FolzioLocalization
import Testing
@testable import FolzioApp

@Suite("Pasteboard image import", .serialized)
@MainActor
struct PasteboardImportTests {
    @Test(arguments: ["public.png", "public.jpeg", "public.tiff"])
    func imagesEnableCopyButNeverMove(type: String) {
        withBoard { board in
            board.setData(Data([1]), forType: .init(type))
            let available = PasteboardImport.availability(in: board)
            #expect(available == .imageData)
            #expect(available.allowsPaste(move: false))
            #expect(!available.allowsPaste(move: true))
        }
    }

    @Test func filesTakePriorityOverPhotosThumbnailsAndPromises() {
        withBoard { board in
            let item = NSPasteboardItem()
            item.setString("file:///tmp/photo.heic", forType: .fileURL)
            item.setData(Data([1]), forType: .png)
            item.setData(Data(), forType: .init("com.apple.photos.object-reference.asset"))
            for type in NSFilePromiseReceiver.readableDraggedTypes {
                item.setString("public.heic", forType: .init(type))
            }
            #expect(board.writeObjects([item]))
            let available = PasteboardImport.availability(in: board)
            #expect(available == .fileURLs)
            #expect(available.allowsPaste(move: false))
            #expect(available.allowsPaste(move: true))
        }
    }

    @Test func clipboardPromisesAreIgnoredEvenWhenImagesAreAvailable() {
        withBoard { board in
            let item = NSPasteboardItem()
            for type in NSFilePromiseReceiver.readableDraggedTypes {
                item.setString("public.png", forType: .init(type))
            }
            #expect(board.writeObjects([item]))
            #expect(PasteboardImport.availability(in: board) == .none)
            board.clearContents()
            let imageItem = NSPasteboardItem()
            for type in NSFilePromiseReceiver.readableDraggedTypes {
                imageItem.setString("public.png", forType: .init(type))
            }
            imageItem.setData(Data([1]), forType: .tiff)
            #expect(board.writeObjects([imageItem]))
            #expect(PasteboardImport.availability(in: board) == .imageData)
        }
    }

    @Test(arguments: [NSPasteboard.PasteboardType.URL, .string, .pdf])
    func unsupportedRepresentationsDisableBothPasteActions(type: NSPasteboard.PasteboardType) {
        withBoard { board in
            board.setString("https://example.com/image.png", forType: type)
            let available = PasteboardImport.availability(in: board)
            #expect(available == .none)
            #expect(!available.allowsPaste(move: false))
            #expect(!available.allowsPaste(move: true))
            board.clearContents()
            #expect(PasteboardImport.availability(in: board) == .none)
        }
    }

    @Test(arguments: [NSPasteboard.PasteboardType.fileURL, .png, .tiff])
    func availabilityDoesNotRequestDeferredData(type: NSPasteboard.PasteboardType) {
        withBoard { board in
            let provider = DeferredPasteboardData()
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [type])
            #expect(board.writeObjects([item]))
            for _ in 0..<3 {
                let available = PasteboardImport.availability(in: board)
                #expect(available == (type == .fileURL ? .fileURLs : .imageData))
                #expect(available.allowsPaste(move: false))
                #expect(available.allowsPaste(move: true) == (type == .fileURL))
            }
            #expect(provider.requests == 0)
            withExtendedLifetime(provider) {}
        }
    }

    private func withBoard(_ body: (NSPasteboard) -> Void) {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        body(board)
    }
}

private final class DeferredPasteboardData: NSObject, NSPasteboardItemDataProvider {
    var requests = 0

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        requests += 1
        if type == .fileURL { item.setString("file:///tmp/image.png", forType: type) }
        else { item.setData(Data([1]), forType: type) }
    }
}


extension PasteboardImportTests {
    private var png: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
    }

    @Test(arguments: [NSPasteboard.PasteboardType.png, .tiff])
    func pasteSavesPNGWithTheOriginalWindowAndExistingConflictHandling(type: NSPasteboard.PasteboardType) async throws {
        try await withFixture { fixture in
            let original = Data([9, 8, 7])
            let target = fixture.destination.appendingPathComponent("copy.png")
            try original.write(to: target)
            let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            for x in 0..<2 { for y in 0..<2 { bitmap.setColor(.red, atX: x, y: y) } }
            let data = try #require(type == .png ? png : bitmap.representation(using: .tiff, properties: [:]))
            let item = NSPasteboardItem()
            item.setData(data, forType: type)
            item.setString("https://example.com/copy.jpg", forType: .URL)
            #expect(fixture.board.writeObjects([item]))
            fixture.settings.confirmation.confirmBeforeFileOperations = true
            fixture.confirmation.fallbackWindow = { Issue.record("Paste must retain its destination window"); return nil }
            fixture.conflict.fallbackWindow = { Issue.record("Conflict must retain the paste window"); return nil }
            var prompts: [String] = []
            fixture.confirmation.presentSheet = { _, window in
                #expect(window === fixture.window)
                prompts.append("copy")
                return .alertFirstButtonReturn
            }
            fixture.conflict.presentSheet = { _, window in
                #expect(window === fixture.window)
                prompts.append("conflict")
                return .alertSecondButtonReturn
            }
            await fixture.coordinator.paste(into: fixture.destination, move: false,
                pasteboard: fixture.board, parentWindow: fixture.window)
            let session = try #require(fixture.manager.sessions.first)
            // Capture image contents at the command, before clipboard changes or asynchronous inspection.
            fixture.board.clearContents()
            fixture.board.setString("new clipboard", forType: .string)
            await session.task?.value
            #expect(session.state.phase == .finished)
            #expect(prompts == ["copy", "conflict"])
            #expect(try Data(contentsOf: target) == original)
            let saved = fixture.destination.appendingPathComponent("copy 2.png")
            let output = try Data(contentsOf: saved)
            #expect(output.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
            if type == .png { #expect(output == png) }
            let values = try saved.resourceValues(forKeys: [.quarantinePropertiesKey])
            #expect(values.quarantineProperties != nil)
        }
    }

    @Test(arguments: [false, true])
    func fileCopyAndMoveIgnoreThePhotosThumbnail(move: Bool) async throws {
        try await withFixture { fixture in
            let source = fixture.root.appendingPathComponent("original.heic")
            let original = Data([5, 4, 3, 2, 1])
            try original.write(to: source)
            let provider = DeferredPasteboardData()
            let item = NSPasteboardItem()
            item.setString(source.absoluteString, forType: .fileURL)
            item.setData(Data(), forType: .init("com.apple.photos.object-reference.asset"))
            item.setDataProvider(provider, forTypes: [.png])
            #expect(fixture.board.writeObjects([item]))
            await fixture.coordinator.paste(into: fixture.destination, move: move,
                pasteboard: fixture.board, parentWindow: fixture.window)
            #expect(provider.requests == 0)
            #expect(fixture.manager.sessions.isEmpty)
            #expect(try Data(contentsOf: fixture.destination.appendingPathComponent("original.heic")) == original)
            #expect(FileManager.default.fileExists(atPath: source.path) == !move)
            withExtendedLifetime(provider) {}
        }
    }

    @Test func movePasteDoesNotReadOrSaveImageData() async throws {
        try await withFixture { fixture in
            let provider = DeferredPasteboardData()
            let item = NSPasteboardItem()
            item.setDataProvider(provider, forTypes: [.png])
            #expect(fixture.board.writeObjects([item]))
            await fixture.coordinator.paste(into: fixture.destination, move: true,
                pasteboard: fixture.board, parentWindow: fixture.window)
            #expect(provider.requests == 0)
            #expect(fixture.manager.sessions.isEmpty)
            let names = try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path)
            #expect(names.isEmpty)
            withExtendedLifetime(provider) {}
        }
    }

    private func withFixture(_ body: @MainActor (PasteFixture) async throws -> Void) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Folzio.Paste.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.viewSettings.lastFolder = destination
        settings.confirmation.confirmBeforeFileOperations = false
        let store = ImportCleanupStore(defaults: defaults)
        let pool = ImportStagingPool(factory: { try ImportStaging.create(store: store, temporaryDirectory: root) })
        let manager = ImportSessionManager(pool: pool, automaticTicks: false, showsPanel: false)
        let confirmation = ConfirmationPresenter(settings: settings)
        let conflict = ConflictPrompt()
        let model = BrowserModel(kindNames: l10n.kindNames, lister: DirectoryLister(kindNames: l10n.kindNames),
            decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
        let coordinator = FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings,
            confirmation: confirmation, conflictPrompt: conflict, imports: manager)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        confirmation.fallbackWindow = { window }
        confirmation.presentSheet = { _, _ in .alertFirstButtonReturn }
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let fixture = PasteFixture(root: root, destination: destination, window: window, board: board,
            settings: settings, manager: manager, confirmation: confirmation, conflict: conflict, coordinator: coordinator)
        do {
            try await body(fixture)
        } catch {
            await manager.shutdown()
            throw error
        }
        await manager.shutdown()
        #expect(store.records().isEmpty)
    }

    private struct PasteFixture {
        let root: URL
        let destination: URL
        let window: NSWindow
        let board: NSPasteboard
        let settings: SettingsStore
        let manager: ImportSessionManager
        let confirmation: ConfirmationPresenter
        let conflict: ConflictPrompt
        let coordinator: FileOperationCoordinator
    }
}
