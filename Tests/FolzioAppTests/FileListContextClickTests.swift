import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("File list context menu target", .serialized)
@MainActor
struct FileListContextClickTests {
    enum Mode: CaseIterable, Sendable {
        case list, thumbnails
    }

    @MainActor
    private struct Fixture {
        let model: BrowserModel
        let controller: FileListViewController
        let files: [MediaFile]

        func url(_ name: String) throws -> URL {
            try #require(files.first { $0.url.lastPathComponent == name }?.url)
        }

        func index(_ name: String) throws -> Int {
            try #require(files.firstIndex { $0.url.lastPathComponent == name })
        }

        /// An item of the file list context menu with `action`.
        func contextItem(_ action: Selector) throws -> NSMenuItem {
            try #require(controller.fileContextMenu.menu.items.first { $0.action == action })
        }
    }

    @Test("An unselected item is the context menu target, and the selection does not change (FR-397, SC-219)",
          arguments: Mode.allCases)
    func unselectedItemIsTheTarget(_ mode: Mode) async throws {
        try await withFixture(mode, selected: ["a.png"]) { fixture in
            let a = try fixture.url("a.png")
            let b = try fixture.url("b.png")
            fixture.controller.recordContextMenuTarget(clickedIndex: try fixture.index("b.png"))

            #expect(fixture.model.selection.selected == [a])
            #expect(fixture.model.selection.focused == a)
            for action in [#selector(FileListViewController.moveToTrash(_:)), #selector(FileListViewController.copy(_:)),
                           #selector(FileListViewController.duplicate(_:)), #selector(FileListViewController.open(_:)),
                           #selector(FileListViewController.copyPathname(_:)),
                           #selector(FileListViewController.revealInFinder(_:))] {
                let item = try fixture.contextItem(action)
                #expect(fixture.controller.operationTarget(for: item).urls == [b], "\(action)")
                #expect(fixture.controller.validateMenuItem(item), "\(action)")
            }
            let renameItem = try fixture.contextItem(#selector(FileListViewController.rename(_:)))
            let rename = fixture.controller.operationTarget(for: renameItem)
            #expect(rename.focused == b)
            #expect(rename.allowsRename)
        }
    }

    @Test("The keyboard and the menu bar keep acting on the selection (A-239)", arguments: Mode.allCases)
    func menuBarActsOnTheSelection(_ mode: Mode) async throws {
        try await withFixture(mode, selected: ["a.png"]) { fixture in
            fixture.controller.recordContextMenuTarget(clickedIndex: try fixture.index("b.png"))
            let a = try fixture.url("a.png")
            let menuBarItem = NSMenuItem(title: "", action: #selector(FileListViewController.moveToTrash(_:)),
                                         keyEquivalent: "")
            // Xcode 16.0 does not accept `try` inside `#expect`, so the values are prepared outside it.
            #expect(fixture.controller.operationTarget(for: menuBarItem).urls == [a])
            #expect(fixture.controller.operationTarget(for: nil).urls == [a])
        }
    }

    @Test("A selected item targets the whole selection (SC-220)", arguments: Mode.allCases)
    func selectedItemTargetsTheSelection(_ mode: Mode) async throws {
        try await withFixture(mode, selected: ["a.png", "b.png", "c.png"]) { fixture in
            fixture.controller.recordContextMenuTarget(clickedIndex: try fixture.index("b.png"))
            let item = try fixture.contextItem(#selector(FileListViewController.moveToTrash(_:)))
            let expected = try ["a.png", "b.png", "c.png"].map { try fixture.url($0) }
            #expect(fixture.controller.operationTarget(for: item).urls == expected)
            #expect(fixture.model.selection.selected == Set(expected))
        }
    }

    @Test("A context click on the background keeps the selection as the item target (FR-213)", arguments: Mode.allCases)
    func backgroundKeepsTheSelection(_ mode: Mode) async throws {
        try await withFixture(mode, selected: ["a.png"]) { fixture in
            fixture.controller.recordContextMenuTarget(clickedIndex: try fixture.index("b.png"))
            fixture.controller.recordContextMenuTarget(clickedIndex: nil)
            let item = try fixture.contextItem(#selector(FileListViewController.moveToTrash(_:)))
            let a = try fixture.url("a.png")
            #expect(fixture.controller.operationTarget(for: item).urls == [a])
        }
    }

    @Test("An unselected `..` disables the file operations even when the selection allows them (EC-264)",
          arguments: Mode.allCases)
    func parentRowDisablesFileOperations(_ mode: Mode) async throws {
        try await withFixture(mode, selected: ["a.png"]) { fixture in
            let parent = try #require(fixture.files.firstIndex { $0.kind == .parent })
            fixture.controller.recordContextMenuTarget(clickedIndex: parent)
            for action in [#selector(FileListViewController.moveToTrash(_:)), #selector(FileListViewController.copy(_:)),
                           #selector(FileListViewController.duplicate(_:)),
                           #selector(FileListViewController.rename(_:))] {
                let item = try fixture.contextItem(action)
                #expect(!fixture.controller.validateMenuItem(item), "\(action)")
            }
            let trashItem = try fixture.contextItem(#selector(FileListViewController.moveToTrash(_:)))
            #expect(fixture.controller.operationTarget(for: trashItem).urls.isEmpty)
        }
    }

    private func withFixture(
        _ mode: Mode,
        selected: [String],
        _ body: @MainActor (Fixture) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        // Shows `sub` under the tree root `root`, so the listing has a `..` row (FR-077).
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("folzio-context-menu-\(UUID().uuidString)", isDirectory: true)
        let folder = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a.png", "b.png", "c.png"] {
            try Data().write(to: folder.appendingPathComponent(name))
        }

        let suite = "Folzio.ContextMenu.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        var viewSettings = settings.viewSettings
        viewSettings.displayMode = mode == .list ? .list : .thumbnails
        settings.viewSettings = viewSettings
        let model = BrowserModel(kindNames: l10n.kindNames, lister: DirectoryLister(kindNames: l10n.kindNames),
            decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
        model.setNavigationRoots([root])
        await model.selectFolder(folder)
        let files = model.listing.files
        let selectedURLs = Set(selected.compactMap { name in files.first { $0.url.lastPathComponent == name }?.url })
        try #require(selectedURLs.count == selected.count)
        model.select(selectedURLs, focused: selectedURLs.max { $0.path < $1.path })

        let controller = FileListViewController(
            model: model, settings: settings, thumbnailProvider: ThumbnailProvider(),
            coordinator: FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings)
        )
        _ = controller.view
        try await body(Fixture(model: model, controller: controller, files: files))
    }
}
