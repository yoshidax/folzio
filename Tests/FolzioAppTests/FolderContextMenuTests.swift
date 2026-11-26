import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Folder context menu integration", .serialized)
@MainActor
struct FolderContextMenuTests {
    @Test("Folder menus share their actions and paste targets without changing selection", arguments: [DisplayMode.list, .thumbnails])
    func folderMenu(_ mode: DisplayMode) async throws {
        try await withFixture(mode) { model, list, coordinator, _, parent, a, b in
            model.select([b], focused: b)
            let index = try #require(model.listing.files.firstIndex { $0.url == a })
            list.recordContextMenuTarget(clickedIndex: index)
            list.fileContextMenu.refreshItems()
            let menu = list.fileContextMenu.menu
            #expect(!menu.items.contains { $0.action == #selector(FileListViewController.open(_:)) })
            #expect(!menu.items.contains { $0.submenu != nil })
            let paste = try #require(menu.items.first { $0.action == #selector(FileListViewController.paste(_:)) })
            #expect(list.pasteDestination(for: paste) == a)
            #expect(list.pasteDestination(for: nil) == parent)
            #expect(model.selection.selected == [b])
            let add = try #require(menu.items.first { $0.action == #selector(FileListViewController.addToFavorites(_:)) })
            var registered: [URL] = []
            list.canAddFavorite = { !registered.contains($0) }
            list.onAddFavorite = { registered.append($0) }
            #expect(list.validateMenuItem(add))
            list.addToFavorites(add)
            #expect(registered == [a])
            #expect(!list.validateMenuItem(add))
            #expect(model.selection.selected == [b])

            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let source = parent.appendingPathComponent("source.png")
            try Data([1, 2, 3]).write(to: source)
            board.writeObjects([source as NSURL])
            await coordinator.paste(into: try #require(list.pasteDestination(for: paste)), move: false, pasteboard: board)
            #expect(FileManager.default.fileExists(atPath: a.appendingPathComponent("source.png").path))
            #expect(!FileManager.default.fileExists(atPath: b.appendingPathComponent("source.png").path))
            #expect(try Data(contentsOf: source) == Data([1, 2, 3]))
            let moving = a.appendingPathComponent("moving.png")
            try Data([4, 5]).write(to: moving)
            board.clearContents()
            board.writeObjects([moving as NSURL])
            await coordinator.paste(into: try #require(list.pasteDestination(for: nil)), move: true, pasteboard: board)
            #expect(try Data(contentsOf: parent.appendingPathComponent("moving.png")) == Data([4, 5]))
            #expect(!FileManager.default.fileExists(atPath: moving.path))
            #expect(!FileManager.default.fileExists(atPath: b.appendingPathComponent("moving.png").path))

            model.select([a, b], focused: a)
            list.recordContextMenuTarget(clickedIndex: index)
            #expect(list.pasteDestination(for: paste) == nil)
            #expect(!list.validateMenuItem(add))
            // A subsequent unselected media menu restores the external-app actions.
            await model.reloadCurrentFolder()
            let mediaIndex = try #require(model.listing.files.firstIndex { $0.name == "source.png" })
            list.recordContextMenuTarget(clickedIndex: mediaIndex)
            list.fileContextMenu.refreshItems()
            #expect(menu.items.contains { $0.action == #selector(FileListViewController.open(_:)) })
        }
    }

    @Test("A missing context target cannot redirect paste or favorites to the selection", arguments: [false, true])
    func missingTarget(_ selected: Bool) async throws {
        try await withFixture(.list) { model, list, _, _, parent, a, b in
            model.select(selected ? [a] : [b], focused: selected ? a : b)
            let clicked = try #require(model.listing.files.firstIndex { $0.url == a })
            list.recordContextMenuTarget(clickedIndex: clicked)
            list.fileContextMenu.refreshItems()
            let copy = try #require(list.fileContextMenu.menu.items.first { $0.action == #selector(FileListViewController.copy(_:)) })
            model.select([b], focused: b)
            #expect(list.operationTarget(for: copy).urls == [a])
            #expect(list.operationTarget(for: nil).urls == [b])
            let paste = try #require(list.fileContextMenu.menu.items.first { $0.action == #selector(FileListViewController.paste(_:)) })
            try FileManager.default.removeItem(at: a)
            await model.reloadCurrentFolder()
            #expect(list.pasteDestination(for: paste) == nil)
            #expect(list.favoriteAdditionTarget(for: paste) == nil)
            #expect(list.pasteDestination(for: nil) == parent)
        }
    }

    @Test("Tree menu actions copy and duplicate actual folders through the shared coordinator")
    func treeOperations() async throws {
        try await withFixture(.list) { model, _, coordinator, settings, parent, a, b in
            let tree = DirectoryTreeViewController(model: model, lister: DirectoryLister(kindNames: l10n.kindNames),
                volumes: FolderMenuVolumes(urls: [parent]), coordinator: coordinator, watcher: FileSystemWatcher(),
                settings: settings, confirmation: ConfirmationPresenter(settings: settings))
            let outline = try #require(findOutline(in: tree.view))
            let root = try #require(outline.item(atRow: 1) as? DirectoryTreeViewController.Node)
            let children = [a, b].map {
                DirectoryTreeViewController.Node(folder: FolderNode(url: $0, name: $0.lastPathComponent, kind: .folder))
            }
            root.children = children
            root.folder.applySubfolderListing(.success(children.count))
            outline.reloadItem(root, reloadChildren: true)
            outline.expandItem(root)
            outline.selectRowIndexes(IndexSet(children.map { outline.row(forItem: $0) }), byExtendingSelection: false)
            let menu = try #require(outline.menu)
            tree.menuNeedsUpdate(menu)
            let copy = try #require(menu.items.first { $0.action == #selector(DirectoryTreeViewController.copy(_:)) })
            let duplicate = try #require(menu.items.first { $0.action == #selector(DirectoryTreeViewController.duplicate(_:)) })
            #expect(tree.validateMenuItem(copy))
            #expect(tree.validateMenuItem(duplicate))
            #expect(!menu.items.contains { $0.action == #selector(DirectoryTreeViewController.newFolder(_:)) })
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            await tree.copyFolders(copy, to: board)
            let copied = ClipboardFileReferences.resolve(PasteboardFileURLs.entries(in: board)).compactMap { resolution in
                if case .found(let url) = resolution { url.resolvingSymlinksInPath().path } else { nil }
            }
            #expect(Set(copied) == Set([a, b].map { $0.resolvingSymlinksInPath().path }))
            let content = Data([8, 9])
            try content.write(to: a.appendingPathComponent("content.dat"))
            await withCheckedContinuation { continuation in
                coordinator.onFoldersChanged = { _ in continuation.resume() }
                tree.duplicate(duplicate)
                // Changing the selection before the Task starts must not retarget the operation.
                outline.deselectAll(nil)
            }
            coordinator.onFoldersChanged = nil
            #expect(try Data(contentsOf: parent.appendingPathComponent("a 2/content.dat")) == content)
            #expect(FileManager.default.fileExists(atPath: parent.appendingPathComponent("b 2").path))
            #expect(try Data(contentsOf: a.appendingPathComponent("content.dat")) == content)
            // Roots remain copyable but cannot be duplicated through either menu validation or direct actions.
            outline.selectRowIndexes(IndexSet(integer: outline.row(forItem: root)), byExtendingSelection: false)
            tree.menuNeedsUpdate(menu)
            let rootCopy = try #require(menu.items.first { $0.action == #selector(DirectoryTreeViewController.copy(_:)) })
            let rootDuplicate = try #require(menu.items.first { $0.action == #selector(DirectoryTreeViewController.duplicate(_:)) })
            #expect(tree.validateMenuItem(rootCopy))
            #expect(!tree.validateMenuItem(rootDuplicate))
            tree.duplicate(rootDuplicate)
            // Duplicate registration preserves the stored order.
            tree.addFavorite(a)
            tree.addFavorite(b)
            tree.addFavorite(a)
            #expect(settings.favorites.urls.map(\.path) == [a.path, b.path])
        }
    }

    @Test("The file list protects root duplication in single and mixed selections", arguments: [false, true])
    func listRootDuplication(_ multiple: Bool) async throws {
        try await withFixture(.list) { model, list, _, _, parent, a, b in
            model.setNavigationRoots([parent, a])
            model.select(multiple ? [a, b] : [a], focused: a)
            let index = try #require(model.listing.files.firstIndex { $0.url == a })
            list.recordContextMenuTarget(clickedIndex: index)
            list.fileContextMenu.refreshItems()
            let duplicate = try #require(list.fileContextMenu.menu.items.first {
                $0.action == #selector(FileListViewController.duplicate(_:))
            })
            #expect(!list.validateMenuItem(duplicate))
            list.duplicate(duplicate)
            list.duplicate(nil)
            await Task.yield()
            #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("a 2").path))
        }
    }

    @Test("A selected context target cannot rename a different focused row")
    func renameRequiresFocusInTargets() async throws {
        try await withFixture(.list) { model, list, _, _, _, a, b in
            model.select([a], focused: b)
            let index = try #require(model.listing.files.firstIndex { $0.url == a })
            list.recordContextMenuTarget(clickedIndex: index)
            list.fileContextMenu.refreshItems()
            let rename = try #require(list.fileContextMenu.menu.items.first {
                $0.action == #selector(FileListViewController.rename(_:))
            })
            #expect(!list.operationTarget(for: rename).allowsRename)
            #expect(!list.validateMenuItem(rename))
        }
    }

    @Test("Context operations retain initially unlisted selection URLs but reject newly vanished rows")
    func initiallyUnlistedSelection() async throws {
        try await withFixture(.list) { model, list, _, _, parent, a, b in
            let unlisted = parent.appendingPathComponent("unlisted.png")
            try Data([3]).write(to: unlisted)
            model.select([a, unlisted], focused: a)
            let index = try #require(model.listing.files.firstIndex { $0.url == a })
            list.recordContextMenuTarget(clickedIndex: index)
            list.fileContextMenu.refreshItems()
            let copy = try #require(list.fileContextMenu.menu.items.first {
                $0.action == #selector(FileListViewController.copy(_:))
            })
            #expect(Set(list.operationTarget(for: copy).urls) == [a, unlisted])
            #expect(list.validateMenuItem(copy))
            model.select([b], focused: b)
            #expect(Set(list.operationTarget(for: copy).urls) == [a, unlisted])
            #expect(list.operationTarget(for: nil).urls == [b])
            try FileManager.default.removeItem(at: a)
            await model.reloadCurrentFolder()
            #expect(list.operationTarget(for: copy).urls.isEmpty)
            #expect(!list.validateMenuItem(copy))
        }
    }

    private func findOutline(in view: NSView) -> NSOutlineView? {
        if let outline = view as? NSOutlineView { return outline }
        return view.subviews.compactMap { findOutline(in: $0) }.first
    }

    private func withFixture(_ mode: DisplayMode,
        body: @MainActor (BrowserModel, FileListViewController, FileOperationCoordinator, SettingsStore, URL, URL, URL) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("folder-menus-\(UUID())")
        let a = parent.appendingPathComponent("a", isDirectory: true)
        let b = parent.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let suite = "Folzio.FolderMenus.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.confirmation = ConfirmationOptions(copy: false, move: false, rename: false, removeFavorite: false, trash: false)
        var viewSettings = settings.viewSettings
        viewSettings.displayMode = mode
        settings.viewSettings = viewSettings
        let lister = DirectoryLister(kindNames: l10n.kindNames)
        let model = BrowserModel(kindNames: l10n.kindNames, lister: lister, decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
        model.setNavigationRoots([parent])
        await model.selectFolder(parent)
        let coordinator = FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings)
        let list = FileListViewController(model: model, settings: settings, thumbnailProvider: ThumbnailProvider(), coordinator: coordinator)
        _ = list.view
        let listedA = try #require(model.listing.files.first { $0.name == "a" }?.url)
        let listedB = try #require(model.listing.files.first { $0.name == "b" }?.url)
        try await body(model, list, coordinator, settings, model.listing.folder, listedA, listedB)
    }
}

private struct FolderMenuVolumes: VolumeProviding {
    let urls: [URL]
    func rootNodes() -> [FolderNode] {
        urls.map { FolderNode(url: $0, name: $0.lastPathComponent, kind: .volume) }
    }
    var changes: AsyncStream<[FolderNode]> { AsyncStream { $0.finish() } }
}
