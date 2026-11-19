import Foundation
import Testing
import FixtureKit
@testable import FolzioCore

@Suite("BrowserModel trash selection")
@MainActor
struct BrowserModelTrashSelectionTests {
    private actor Lister: DirectoryListing {
        var files: [MediaFile]
        var denied = false
        init(_ files: [MediaFile]) { self.files = files }
        func replace(_ files: [MediaFile], denied: Bool = false) { self.files = files; self.denied = denied }
        func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] {
            if denied { throw .accessDenied }
            return files
        }
        func subfolders(of folder: URL) async throws(ListingError) -> [URL] { [] }
    }

    private func withModel(_ body: (BrowserModel, Lister, [URL]) async throws -> Void) async throws {
        let folder = URL(fileURLWithPath: "/tmp/trash-model-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let rows = ["a.mov", "b.mov", "c.mov"].map { name in
            MediaFile(url: folder.appendingPathComponent(name), name: name, kind: .media(.mov),
                typeDescription: "Movie", creationDate: nil, fileSize: 0)
        }
        let suite = "TrashModel.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let lister = Lister(rows)
        let model = BrowserModel(kindNames: FixtureKit.kindNames, lister: lister, decoder: ImageDecoder(),
            cache: DecodedImageCache(), settings: SettingsStore(defaults: defaults))
        model.setNavigationRoots([folder])
        await model.selectFolder(folder)
        try await body(model, lister, rows.map(\.url))
    }

    @Test("An earlier watcher reload does not cancel the pending next-row selection")
    func watcherFirst() async throws {
        try await withModel { model, lister, urls in
            model.select([urls[1]], focused: urls[1])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[1]]))
            let stops = model.stopPlaybackSignal
            await lister.replace(model.listing.files.filter { $0.url != urls[1] })
            await model.handleFileSystemEvent([model.listing.folder])
            #expect(model.selection.focused == nil)
            model.applySelectionAfterTrashing(snapshot, removed: [urls[1]])
            #expect(model.selection.selected == [urls[2]])
            #expect(model.selection.focused == urls[2])
            #expect(model.stopPlaybackSignal > stops)
            if case let .video(url) = model.preview { #expect(url == urls[2]) }
            else { Issue.record("Expected the successor video") }
        }
    }

    @Test("The last item leaves no selection or preview and stops playback")
    func lastItem() async throws {
        try await withModel { model, lister, urls in
            model.select([urls[2]], focused: urls[2])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[2]]))
            let stops = model.stopPlaybackSignal
            await lister.replace(model.listing.files.filter { $0.url != urls[2] })
            await model.reloadCurrentFolder()
            model.applySelectionAfterTrashing(snapshot, removed: [urls[2]])
            #expect(model.selection.selected.isEmpty)
            #expect(model.selection.focused == nil)
            #expect(model.stopPlaybackSignal > stops)
            if case .empty = model.preview {} else { Issue.record("Expected empty preview") }
        }
    }

    @Test("User changes invalidate an earlier snapshot even after changing back", arguments: 0..<7)
    func changedIntent(_ change: Int) async throws {
        try await withModel { model, _, urls in
            model.select([urls[1]], focused: urls[1])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[1]]))
            switch change {
            case 0:
                model.select([urls[0]], focused: urls[0]); model.select([urls[1]], focused: urls[1])
            case 1:
                model.sortOrder = SortOrder(column: .name, ascending: false)
                model.sortOrder = SortOrder(column: .name, ascending: true)
            case 2:
                model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true)); model.setMediaTypeFilter(MediaTypeFilter())
            case 3:
                model.setNameFilter("a"); model.setNameFilter("")
            case 4:
                model.setShowsZipFiles(true); model.setShowsZipFiles(false)
            case 5:
                model.setKindNames(KindNames(folder: "Z Folder", zipArchive: "Z Zip"))
                model.setKindNames(FixtureKit.kindNames)
            default:
                await model.selectFolder(model.listing.folder)
                model.select([urls[1]], focused: urls[1])
            }
            let selected = model.selection
            model.applySelectionAfterTrashing(snapshot, removed: [urls[1]])
            #expect(model.selection.selected == selected.selected)
            #expect(model.selection.focused == selected.focused)
        }
    }

    @Test("A search continuation skips a vanished successor and respects intervening selection changes", arguments: [false, true])
    func continuation(_ userSelects: Bool) async throws {
        try await withModel { model, lister, urls in
            model.select([urls[0]], focused: urls[0])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[0]]))
            await lister.replace(model.listing.files.filter { $0.url != urls[0] })
            await model.reloadCurrentFolder()
            let continuation = try #require(model.applySelectionAfterTrashing(snapshot, removed: [urls[0]]))
            #expect(model.selection.focused == urls[1])
            if userSelects { model.select([], focused: nil) }
            await lister.replace(model.listing.files.filter { $0.url != urls[1] })
            await model.reloadCurrentFolder()
            model.applySelectionAfterTrashing(continuation, removed: [urls[0]])
            #expect(model.selection.focused == (userSelects ? nil : urls[2]))
        }
    }

    @Test("The successor follows visible sort order and ignores media and name filtered rows", arguments: [false, true])
    func sortedAndFiltered(_ descending: Bool) async throws {
        try await withModel { model, lister, urls in
            let hidden = MediaFile(url: model.listing.folder.appendingPathComponent("bb.jpg"), name: "bb.jpg",
                kind: .media(.jpeg), typeDescription: "JPEG", creationDate: nil, fileSize: 0)
            await lister.replace(model.listing.files + [hidden])
            await model.reloadCurrentFolder()
            model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
            model.setNameFilter("?.mov")
            model.sortOrder = SortOrder(column: .name, ascending: !descending)
            model.select([urls[1]], focused: urls[1])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[1]]))
            await lister.replace(model.listing.files.filter { $0.url != urls[1] } + [hidden])
            await model.reloadCurrentFolder()
            model.applySelectionAfterTrashing(snapshot, removed: [urls[1]])
            #expect(model.selection.focused == (descending ? urls[0] : urls[2]))
            #expect(!model.selection.selected.contains(hidden.url))
        }
    }

    @Test("A folder or zip successor is selected without opening it", arguments: [ListItemKind.folder, .archive])
    func nonMediaSuccessor(_ kind: ListItemKind) async throws {
        try await withModel { model, lister, urls in
            model.setShowsZipFiles(true)
            model.sortOrder = SortOrder(column: .size, ascending: true)
            let folder = model.listing.folder
            let next = MediaFile(url: folder.appendingPathComponent("z"), name: "z", kind: kind,
                typeDescription: "Container", creationDate: nil, fileSize: 0)
            await lister.replace(model.listing.files + [next])
            await model.reloadCurrentFolder()
            model.select([urls[2]], focused: urls[2])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[2]]))
            await lister.replace(model.listing.files.filter { $0.url != urls[2] })
            await model.reloadCurrentFolder()
            model.applySelectionAfterTrashing(snapshot, removed: [urls[2]])
            #expect(model.selection.focused == next.url)
            #expect(model.listing.folder == folder)
            #expect(!model.isBrowsingArchive)
            if case .empty = model.preview {} else { Issue.record("Expected empty preview for a container") }
        }
    }

    @Test("Failed reloads and absent successes do not apply a new selection")
    func failure() async throws {
        try await withModel { model, lister, urls in
            model.select([urls[1]], focused: urls[1])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[1]]))
            let stops = model.stopPlaybackSignal
            model.applySelectionAfterTrashing(snapshot, removed: [])
            #expect(model.selection.focused == urls[1])
            #expect(model.stopPlaybackSignal == stops)
            await lister.replace([], denied: true)
            await model.reloadCurrentFolder()
            model.applySelectionAfterTrashing(snapshot, removed: [urls[1]])
            #expect(model.selection.selected.isEmpty)
            #expect(model.selection.focused == nil)
        }
    }

    @Test("A surviving selected item replaces a removed focus without adding a successor")
    func partialFailure() async throws {
        try await withModel { model, lister, urls in
            model.select([urls[0], urls[1]], focused: urls[0])
            let snapshot = try #require(model.selectionBeforeTrashing([urls[0], urls[1]]))
            await lister.replace(model.listing.files.filter { $0.url != urls[0] })
            await model.reloadCurrentFolder()
            model.applySelectionAfterTrashing(snapshot, removed: [urls[0]])
            #expect(model.selection.selected == [urls[1]])
            #expect(model.selection.focused == urls[1])
        }
    }
}
