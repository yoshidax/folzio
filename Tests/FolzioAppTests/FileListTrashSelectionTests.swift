import AppKit
import Foundation
import FolzioCore
import Observation
import Testing
@testable import FolzioApp

@Suite("File list trash selection", .serialized)
@MainActor
struct FileListTrashSelectionTests {
    @MainActor private final class FocusRecord { var url: URL? }

    private struct Searcher: FileNameSearching {
        let rows: [MediaFile]
        func search(_ request: SearchRequest) -> AsyncStream<[MediaFile]> {
            AsyncStream { continuation in
                continuation.yield(rows)
                continuation.finish()
            }
        }
    }

    private actor Lister: DirectoryListing {
        var rows: [MediaFile]
        init(_ rows: [MediaFile]) { self.rows = rows }
        func remove(_ urls: Set<URL>) { rows.removeAll { urls.contains($0.url) } }
        func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] { rows }
        func subfolders(of folder: URL) async throws(ListingError) -> [URL] { [] }
    }

    private struct Service: FileOperating {
        let run: @Sendable (FileOperation) async -> FileOperationResult
        func conflicts(for operation: FileOperation) -> [URL] { [] }
        func execute(_ operation: FileOperation, resolution: ConflictResolution) async -> FileOperationResult {
            await run(operation)
        }
        func createFolder(in parent: URL, baseName: String) async -> Result<URL, OperationFailureReason> {
            .failure(.systemFailure(systemReason: "Unused test operation"))
        }
    }

    @Test("The controller connects successful deletion to the successor in both modes", arguments: [false, true], [false, true])
    func controllerSelection(_ thumbnails: Bool, _ confirms: Bool) async throws {
        try await withFixture(thumbnails, confirms: confirms) { model, controller, coordinator, _, urls in
            model.select([urls[1]], focused: urls[1])
            var finished = false
            coordinator.onOperationFinished = { _, _ in finished = true }
            controller.moveToTrash(nil)
            try await wait { finished }
            #expect(model.selection.selected == [urls[2]])
            #expect(model.selection.focused == urls[2])
            if case let .video(url) = model.preview { #expect(url == urls[2]) }
            else { Issue.record("Expected successor preview") }
        }
    }

    @Test("Context menus keep unselected targets separate, and selected targets use the whole selection",
          arguments: [false, true], [false, true])
    func contextTarget(_ thumbnails: Bool, _ unselected: Bool) async throws {
        try await withFixture(thumbnails) { model, controller, coordinator, _, urls in
            let selected: Set<URL> = unselected ? [urls[0]] : [urls[0], urls[1]]
            model.select(selected, focused: urls[0])
            controller.recordContextMenuTarget(clickedIndex: 1)
            let item = try #require(controller.fileContextMenu.menu.items.first {
                $0.action == #selector(FileListViewController.moveToTrash(_:))
            })
            var finished = false
            coordinator.onOperationFinished = { _, _ in finished = true }
            controller.moveToTrash(item)
            try await wait { finished }
            #expect(model.selection.selected == [unselected ? urls[0] : urls[2]])
            #expect(model.selection.focused == (unselected ? urls[0] : urls[2]))
        }
    }

    @Test("Cancellation and failure preserve selection, while partial success retains failed items", arguments: 0..<3)
    func failures(_ scenario: Int) async throws {
        try await withFixture(false, confirms: true, cancel: scenario == 0, failedIndexes: scenario == 1 ? [0, 1] : [1]) {
            model, _, coordinator, _, urls in
            model.select([urls[0], urls[1]], focused: urls[0])
            let stops = model.stopPlaybackSignal
            var removed: [URL] = []
            coordinator.onOperationFinished = { _, actual in removed = actual }
            await coordinator.trash([urls[0], urls[1]])
            if scenario == 2 {
                #expect(model.selection.selected == [urls[1]])
                #expect(model.selection.focused == urls[1])
                #expect(removed == [urls[0]])
            } else {
                #expect(model.selection.selected == [urls[0], urls[1]])
                #expect(model.selection.focused == urls[0])
                #expect(model.stopPlaybackSignal == stops)
                #expect(removed.isEmpty)
            }
        }
    }

    @Test("Tree deletion and a last-row deletion do not select a successor", arguments: [false, true])
    func noSuccessor(_ tree: Bool) async throws {
        try await withFixture(false) { model, _, coordinator, _, urls in
            let target = tree ? urls[1] : urls[2]
            model.select([target], focused: target)
            await coordinator.trash([target], origin: tree ? .tree : .fileList)
            #expect(model.selection.selected.isEmpty)
            #expect(model.selection.focused == nil)
        }
    }

    @Test("Selection changes while the service is suspended take precedence")
    func selectionChangesDuringOperation() async throws {
        try await withFixture(false, changesSelection: true) { model, _, coordinator, _, urls in
            model.select([urls[1]], focused: urls[1])
            await coordinator.trash([urls[1]])
            #expect(model.selection.selected == [urls[0]])
            #expect(model.selection.focused == urls[0])
        }
    }

    @Test("Search selects immediately, then skips an externally vanished successor during pruning")
    func searchSelectsBeforePruning() async throws {
        try await withFixture(false, search: true) { model, _, coordinator, _, urls in
            try FileManager.default.removeItem(at: urls[1])
            model.select([urls[0]], focused: urls[0])
            let firstSuccessor = FocusRecord()
            withObservationTracking {
                _ = model.trashSelectionGeneration
            } onChange: {
                MainActor.assumeIsolated { firstSuccessor.url = model.selection.focused }
            }
            await coordinator.trash([urls[0]])
            #expect(firstSuccessor.url == urls[1])
            #expect(model.selection.focused == urls[2])
            #expect(model.listing.files.map(\.url) == [urls[2]])
        }
    }

    @Test("A selected parent row is ignored after successful trash in both display modes",
          arguments: [false, true], [2, 3])
    func selectedParent(_ thumbnails: Bool, _ count: Int) async throws {
        try await withFixture(thumbnails, count: count, parent: true) { model, _, coordinator, _, urls in
            let parent = try #require(model.listing.files.first { $0.kind == .parent }?.url)
            model.select([parent, urls[0], urls[1]], focused: parent)
            await coordinator.trash(model.operableSelection)
            let expected = count == 3 ? urls[2] : nil
            #expect(model.selection.focused == expected)
            #expect(model.selection.selected == Set(expected.map { [$0] } ?? []))
        }
    }

    @Test("A thumbnail successor below the viewport is revealed without changing the first responder")
    func thumbnailScrolls() async throws {
        try await withFixture(true, count: 24) { model, controller, coordinator, _, urls in
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 230),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            window.contentView = controller.view
            controller.view.frame = NSRect(x: 0, y: 0, width: 400, height: 230)
            controller.view.layoutSubtreeIfNeeded()
            let collection = try #require(controller.primaryFocusView as? NSCollectionView)
            let scroll = try #require(collection.enclosingScrollView)
            window.makeFirstResponder(collection)
            let responder = window.firstResponder
            model.select([urls[18]], focused: urls[18])
            try await wait { collection.selectionIndexPaths == [IndexPath(item: 18, section: 0)] }
            let before = scroll.contentView.bounds.minY
            await coordinator.trash([urls[18]])
            try await wait { collection.selectionIndexPaths == [IndexPath(item: 18, section: 0)]
                && scroll.contentView.bounds.minY > before }
            let frame = try #require(collection.layoutAttributesForItem(at: IndexPath(item: 18, section: 0))?.frame)
            #expect(scroll.contentView.bounds.contains(frame))
            #expect(window.firstResponder === responder)
        }
    }

    private func withFixture(
        _ thumbnails: Bool, confirms: Bool = false, cancel: Bool = false,
        failedIndexes: Set<Int> = [], changesSelection: Bool = false, count: Int = 3, search: Bool = false,
        parent: Bool = false,
        body: @MainActor (BrowserModel, FileListViewController, FileOperationCoordinator, Lister, [URL]) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("trash-app-\(UUID())", isDirectory: true)
        let rows = (0..<count).map { index in
            MediaFile(url: folder.appendingPathComponent("\(index).mov"), name: "\(index).mov", kind: .media(.mov),
                typeDescription: "Movie", creationDate: nil, fileSize: 0)
        }
        let urls = rows.map(\.url)
        if search {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for url in urls { try Data().write(to: url) }
        }
        defer { if search { try? FileManager.default.removeItem(at: folder) } }
        let failed = Set(failedIndexes.map { urls[$0] })
        let suite = "TrashApp.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        var viewSettings = settings.viewSettings
        viewSettings.displayMode = thumbnails ? .thumbnails : .list
        settings.viewSettings = viewSettings
        var confirmation = settings.confirmation
        confirmation.trash = confirms
        settings.confirmation = confirmation
        let lister = Lister(rows)
        let model = BrowserModel(kindNames: l10n.kindNames, lister: lister, decoder: ImageDecoder(),
            cache: DecodedImageCache(), settings: settings, searcher: Searcher(rows: rows))
        model.setNavigationRoots([parent ? folder.deletingLastPathComponent() : folder])
        await model.selectFolder(folder)
        if search {
            model.startSearch(try #require(SearchPattern(keyword: "*")), root: folder)
            try await wait { model.listing.search?.phase == .finished }
        }
        let service = Service { operation in
            if changesSelection { await model.select([urls[0]], focused: urls[0]) }
            let succeeded = operation.sources.filter { !failed.contains($0) }
            await lister.remove(Set(succeeded))
            // Successful result URLs point into the Trash rather than matching the source rows.
            return FileOperationResult(succeeded: succeeded.map { URL(fileURLWithPath: "/fake-trash/" + $0.lastPathComponent) },
                failed: operation.sources.filter { failed.contains($0) }.map { ($0, .systemFailure(systemReason: "Test failure")) })
        }
        let presenter = ConfirmationPresenter(settings: settings)
        presenter.fallbackWindow = { nil }
        presenter.runModal = { _ in cancel ? .alertSecondButtonReturn : .alertFirstButtonReturn }
        let coordinator = FileOperationCoordinator(model: model, service: service, settings: settings, confirmation: presenter)
        coordinator.fallbackWindow = { nil }
        let controller = FileListViewController(model: model, settings: settings, thumbnailProvider: ThumbnailProvider(), coordinator: coordinator)
        _ = controller.view
        try await body(model, controller, coordinator, lister, urls)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
}
