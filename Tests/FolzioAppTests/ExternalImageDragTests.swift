import AppKit
import FolzioCore
import FolzioLocalization
import Testing
@testable import FolzioApp

@Suite("External image drag", .serialized)
@MainActor
struct ExternalImageDragTests {
    @Test func registeredTypesAndPriority() {
        let required: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, .init("public.jpeg")] + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) }
        for type in required { #expect(ExternalImageDrag.registeredTypes.contains(type)) }
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        board.setData(Data([1]), forType: .png)
        #expect(ExternalImageDrag.payload(in: board) == .imageData(["public.png"]))
        #expect(ExternalImageDrag.operation(payload: .imageData(["public.png"]), mask: .copy, hasStaging: false) == .copy)
        #expect(ExternalImageDrag.operation(payload: .imageData(["public.png"]), mask: .move, hasStaging: true).isEmpty)
        #expect(ExternalImageDrag.operation(payload: .promises([.image]), mask: .copy, hasStaging: false).isEmpty)
        #expect(ExternalImageDrag.operation(payload: .promises([.image]), mask: .copy, hasStaging: true) == .copy)
        board.clearContents()
        board.setString("https://example.com/cat.png", forType: .URL)
        #expect(ExternalImageDrag.payload(in: board) == nil)
        board.clearContents()
        board.setString("text", forType: .string)
        #expect(ExternalImageDrag.payload(in: board) == nil)
        board.setString("file:///tmp/source.png", forType: .fileURL)
        #expect(ExternalImageDrag.payload(in: board) == .fileURLs)
        #expect(ExternalImageDrag.operation(payload: .fileURLs, mask: .copy, hasStaging: true).isEmpty)
    }

    @Test func cachesTypesOncePerSequence() {
        let cache = ExternalImageDrag()
        var reads = 0
        let read: () -> ImportPayload? = { reads += 1; return nil }
        #expect(cache.payload(sequence: 1, read: read) == nil)
        #expect(cache.payload(sequence: 1, read: read) == nil)
        #expect(reads == 1)
        _ = cache.payload(sequence: 2, read: read)
        #expect(reads == 2)
    }

    @Test func keepsImageAndURLOnTheSameItem() throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("https://example.com/wrong.jpg", forType: .URL)
        let second = NSPasteboardItem()
        second.setData(Data([1, 2]), forType: .png)
        second.setData(Data([3]), forType: .tiff)
        second.setString("https://example.com/right.jpg", forType: .URL)
        board.writeObjects([first, second])
        let images = ExternalImageDrag.images(in: board)
        #expect(images.count == 1)
        #expect(try images[0].data.get() == Data([1, 2]))
        #expect(images[0].name == "right.png")
    }
}


private struct ImportTestVolumes: VolumeProviding {
    func rootNodes() -> [FolderNode] { [] }
    var changes: AsyncStream<[FolderNode]> { AsyncStream { $0.finish() } }
}

extension ExternalImageDragTests {
    @Test func actualDropViewsRegisterEveryRequiredType() throws {
        _ = NSApplication.shared
        let suite = "Folzio.Import.Views.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let lister = DirectoryLister(kindNames: l10n.kindNames)
        let model = BrowserModel(kindNames: l10n.kindNames, lister: lister, decoder: ImageDecoder(),
            cache: DecodedImageCache(), settings: settings)
        let provider = ThumbnailProvider()
        let list = ListModeView(model: model, provider: provider)
        let thumbnails = ThumbnailModeView(model: model, provider: provider)
        let coordinator = FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings)
        let tree = DirectoryTreeViewController(model: model, lister: lister, volumes: ImportTestVolumes(),
            coordinator: coordinator, watcher: FileSystemWatcher(), settings: settings,
            confirmation: ConfirmationPresenter(settings: settings))
        func outline(in view: NSView) -> NSOutlineView? {
            if let result = view as? NSOutlineView { return result }
            return view.subviews.compactMap { outline(in: $0) }.first
        }
        let outline = try #require(outline(in: tree.view))
        for view in [list.focusView, thumbnails.focusView, outline] {
            for type in ExternalImageDrag.registeredTypes {
                #expect(view.registeredDraggedTypes.contains(type))
            }
        }
    }
}

private final class ImportTestImageProvider: NSObject, NSPasteboardItemDataProvider {
    var reads = 0
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        reads += 1
        item.setData(Data([1, 2]), forType: type)
    }
}

extension ExternalImageDragTests {
    @Test func hoverClassificationNeverRequestsImageBytes() {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let provider = ImportTestImageProvider()
        let item = NSPasteboardItem()
        item.setDataProvider(provider, forTypes: [.png])
        board.writeObjects([item])
        let before = provider.reads
        #expect(ExternalImageDrag.payload(in: board) == .imageData(["public.png"]))
        #expect(provider.reads == before)
        #expect(ExternalImageDrag.images(in: board).count == 1)
        #expect(provider.reads > before)
    }

    @Test func rejectsDeclaredPDFPromise() throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let delegate = ImportTestPromiseProvider()
        let provider = NSFilePromiseProvider(fileType: "com.adobe.pdf", delegate: delegate)
        #expect(board.writeObjects([provider]))
        let receivers = try #require(board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver])
        #expect(!receivers.isEmpty)
        #expect(ExternalImageDrag.payload(in: board) == nil)
    }
}


private final class ImportTestPromiseProvider: NSObject, NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { "file.pdf" }
    func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) { completionHandler(nil) }
}


private final class ImportTestPhotosPromise: NSFilePromiseProvider {
    var representsPhotos = true
    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.fileURL] + (representsPhotos ? [.init("com.apple.photos.object-reference.asset")] : [])
    }
    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .fileURL { return "file:///tmp/thumbnail.jpg" }
        if type.rawValue == "com.apple.photos.object-reference.asset" { return Data() }
        return super.pasteboardPropertyList(forType: type)
    }
}

extension ExternalImageDragTests {
    private static var sequence = 1_000_000
    private func nextSequence() -> Int { Self.sequence += 1; return Self.sequence }

    @Test(arguments: ["com.apple.quicktime-movie", "public.mpeg-4", "public.jpeg", "public.heic"])
    func photosPromisesBypassThumbnailFileURLs(type: String) throws {
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let delegate = ImportTestPromiseProvider()
        defer { withExtendedLifetime(delegate) {} }
        let provider = ImportTestPhotosPromise(fileType: type, delegate: delegate)
        #expect(board.writeObjects([provider]))
        let kind = try #require(ImportPayloadPolicy.expectedKind(declaredTypes: [type]))
        #expect(ExternalImageDrag.payload(in: board) == .promises([kind]))
        #expect(ExternalDrag.fileURLs(in: board, sequence: nextSequence()) == nil)
        #expect(ExternalImageDrag.operation(payload: .promises([kind]), mask: .copy, hasStaging: false).isEmpty)
    }

    @Test func otherAppsAndUnavailablePhotosPromisesKeepFileURLs() {
        let delegate = ImportTestPromiseProvider()
        defer { withExtendedLifetime(delegate) {} }
        for (type, photos) in [("public.mpeg-4", false), ("com.adobe.pdf", true)] {
            let board = NSPasteboard(name: .init(UUID().uuidString))
            defer { board.releaseGlobally() }
            let provider = ImportTestPhotosPromise(fileType: type, delegate: delegate)
            provider.representsPhotos = photos
            #expect(board.writeObjects([provider]))
            #expect(ExternalImageDrag.payload(in: board) == .fileURLs)
            #expect(ExternalDrag.fileURLs(in: board, sequence: nextSequence()) == [URL(fileURLWithPath: "/tmp/thumbnail.jpg")])
        }
        let board = NSPasteboard(name: .init(UUID().uuidString))
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("file:///tmp/thumbnail.jpg", forType: .fileURL)
        item.setData(Data(), forType: .init("com.apple.photos.object-reference.asset"))
        #expect(board.writeObjects([item]))
        #expect(ExternalImageDrag.payload(in: board) == .fileURLs)
    }
}
