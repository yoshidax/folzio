import AppKit
import Foundation
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("File list empty selection navigation", .serialized)
@MainActor
struct FileListEmptySelectionNavigationTests {
    @Test("After deleting the last item, Up selects the last survivor and Down the first",
          arguments: [false, true], [true, false])
    func afterLastDeletion(_ thumbnails: Bool, _ up: Bool) async throws {
        try await withFixture(thumbnails: thumbnails) { model, controller in
            let removed = try #require(model.listing.files.last?.url)
            model.select([removed], focused: removed)
            let snapshot = try #require(model.selectionBeforeTrashing([removed]))
            try FileManager.default.removeItem(at: removed)
            await model.reloadCurrentFolder()
            model.applySelectionAfterTrashing(snapshot, removed: [removed])
            try #require(model.selection.selected.isEmpty && model.selection.focused == nil)
            try await synchronize(model, view: controller.primaryFocusView)
            let expected = up ? model.listing.files.last?.url : model.listing.files.first?.url
            try send(up ? .upArrow : .downArrow, to: controller.primaryFocusView)
            #expect(model.selection.selected == Set(expected.map { [$0] } ?? []))
            #expect(model.selection.focused == expected)
        }
    }

    @Test("Empty and parent-only lists handle both arrows", arguments: [false, true], [false, true])
    func emptyAndParentOnly(_ thumbnails: Bool, _ parent: Bool) async throws {
        try await withFixture(thumbnails: thumbnails, parent: parent, count: 0) { model, controller in
            for key in [NSEvent.SpecialKey.upArrow, .downArrow] {
                model.select([], focused: nil)
                try await synchronize(model, view: controller.primaryFocusView)
                try send(key, to: controller.primaryFocusView)
                #expect(model.selection.focused == model.listing.files.first?.url)
                #expect(model.selection.selected == Set(model.listing.files.map(\.url)))
            }
        }
    }

    @Test("Down can select the parent link at the top", arguments: [false, true])
    func parentIsFirst(_ thumbnails: Bool) async throws {
        try await withFixture(thumbnails: thumbnails, parent: true) { model, controller in
            let first = try #require(model.listing.files.first)
            try #require(first.kind == .parent)
            try send(.downArrow, to: controller.primaryFocusView)
            #expect(model.selection.focused == first.url)
            #expect(model.selection.selected == [first.url])
        }
    }

    @Test("A selected item and Shift or horizontal moves retain thumbnail navigation rules")
    func existingThumbnailNavigation() async throws {
        try await withFixture(thumbnails: true) { model, controller in
            let urls = model.listing.files.map(\.url)
            let view = controller.primaryFocusView
            model.select([urls[0]], focused: urls[0])
            try await synchronize(model, view: view)
            try send(.rightArrow, to: view)
            #expect(model.selection.focused == urls[1])
            try send(.rightArrow, modifiers: [.shift], to: view)
            #expect(model.selection.selected == [urls[1], urls[2]])
            #expect(model.selection.focused == urls[2])
            model.select([], focused: nil)
            try send(.upArrow, modifiers: [.shift], to: view)
            #expect(model.selection.focused == urls[0])
            model.select([], focused: nil)
            try send(.leftArrow, to: view)
            #expect(model.selection.focused == urls[0])
        }
    }

    private func withFixture(
        thumbnails: Bool, parent: Bool = false, count: Int = 3,
        body: @MainActor (BrowserModel, FileListViewController) async throws -> Void
    ) async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("empty-selection-\(UUID())", isDirectory: true)
        let folder = root.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<count { try Data().write(to: folder.appendingPathComponent("\(index).mov")) }
        let suite = "EmptySelection.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        var viewSettings = settings.viewSettings
        viewSettings.displayMode = thumbnails ? .thumbnails : .list
        settings.viewSettings = viewSettings
        let model = BrowserModel(kindNames: l10n.kindNames, lister: DirectoryLister(kindNames: l10n.kindNames),
            decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
        model.setNavigationRoots([parent ? root : folder])
        await model.selectFolder(folder)
        let controller = FileListViewController(model: model, settings: settings, thumbnailProvider: ThumbnailProvider(),
            coordinator: FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.makeFirstResponder(nil); window.close() }
        window.contentView = controller.view
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 500)
        controller.view.layoutSubtreeIfNeeded()
        try #require(window.makeFirstResponder(controller.primaryFocusView))
        try await synchronize(model, view: controller.primaryFocusView)
        try await body(model, controller)
    }

    private func synchronize(_ model: BrowserModel, view: NSView) async throws {
        let indexes = SelectionIndex.indexes(of: model.selection.selected, in: model.listing.files.map(\.url))
        func matches() -> Bool {
            if let table = view as? NSTableView {
                return table.numberOfRows == model.listing.files.count && table.selectedRowIndexes == indexes
            }
            if let collection = view as? NSCollectionView {
                let paths = Set(indexes.map { IndexPath(item: $0, section: 0) })
                return collection.numberOfSections > 0
                    && collection.numberOfItems(inSection: 0) == model.listing.files.count
                    && collection.selectionIndexPaths == paths
            }
            return false
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while !matches(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        try #require(matches())
    }

    private func send(_ key: NSEvent.SpecialKey, modifiers: NSEvent.ModifierFlags = [], to view: NSView) throws {
        let code: UInt16
        switch key {
        case .upArrow: code = 126
        case .downArrow: code = 125
        case .leftArrow: code = 123
        default: code = 124
        }
        let characters = String(UnicodeScalar(key.rawValue)!)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
            timestamp: 0, windowNumber: view.window?.windowNumber ?? 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        view.keyDown(with: event)
    }
}
