import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Favorites expansion", .serialized)
@MainActor
struct FavoritesExpansionTests {
    @Test("Launch applies the setting without changing the displayed folder", arguments: [false, true], [false, true])
    func launch(restores: Bool, expanded: Bool) throws {
        let fixture = try Fixture(restores: restores, expanded: expanded)
        defer { fixture.finish() }
        let folder = fixture.model.listing.folder
        let (tree, outline, header) = try fixture.makeTree()
        #expect(outline.isItemExpanded(header) == (restores && expanded))
        #expect(fixture.settings.favoritesExpanded == (restores && expanded))
        #expect(fixture.settings.restoresFavoritesExpansion == restores)
        #expect(fixture.model.listing.folder == folder)
        #expect(outline.selectedRow == -1)
        withExtendedLifetime(tree) {}
    }

    @Test("Heading notifications save actual changes even while restoration is off")
    func headingChanges() throws {
        let fixture = try Fixture(restores: false, expanded: false)
        defer { fixture.finish() }
        let (tree, outline, header) = try fixture.makeTree()
        outline.expandItem(header)
        #expect(fixture.settings.favoritesExpanded)
        outline.collapseItem(header)
        #expect(!fixture.settings.favoritesExpanded)
        tree.focusFavoritesHeader()
        #expect(outline.isItemExpanded(header))
        #expect(fixture.settings.favoritesExpanded)
    }

    @Test("Ordinary node notifications do not rewrite the saved heading state")
    func ordinaryNodeNotifications() throws {
        let fixture = try Fixture(restores: false, expanded: false)
        defer { fixture.finish() }
        let (tree, outline, _) = try fixture.makeTree()
        fixture.settings.favoritesExpanded = true
        fixture.defaults.clearExpansionWrites()
        let other = DirectoryTreeViewController.Node(folder: FolderNode(
            url: URL(fileURLWithPath: "/tmp/folzio-other"), name: "other", kind: .folder
        ))
        tree.outlineViewItemDidCollapse(Notification(
            name: NSOutlineView.itemDidCollapseNotification, object: outline, userInfo: ["NSObject": other]
        ))
        #expect(fixture.settings.favoritesExpanded)
        tree.outlineViewItemDidExpand(Notification(
            name: NSOutlineView.itemDidExpandNotification, object: outline, userInfo: ["NSObject": other]
        ))
        #expect(fixture.settings.favoritesExpanded)
        #expect(fixture.defaults.expansionWrites.isEmpty)
    }

    @Test("The Settings checkbox is wired into the key loop and saves both states")
    func settingsCheckbox() throws {
        let fixture = try Fixture(restores: false, expanded: true)
        defer { fixture.finish() }
        let controller = SettingsWindowController(store: fixture.settings)
        let window = try #require(controller.window)
        let language = try #require(window.initialFirstResponder as? NSPopUpButton)
        let preview = try #require(language.nextKeyView as? NSPopUpButton)
        #expect(preview.action == NSSelectorFromString("selectPreviewMode:"))
        let checkbox = try #require(preview.nextKeyView as? NSButton)
        let autoplay = try #require(checkbox.nextKeyView as? NSButton)
        #expect(checkbox.action == NSSelectorFromString("toggleFavoritesRestoration:"))
        #expect(checkbox.target as? SettingsWindowController === controller)
        #expect(autoplay.action == NSSelectorFromString("toggleAutoplay:"))
        #expect(checkbox.state == .off)
        checkbox.performClick(nil)
        #expect(checkbox.state == .on)
        #expect(SettingsStore(defaults: fixture.defaults).restoresFavoritesExpansion)
        #expect(fixture.settings.favoritesExpanded)
        checkbox.performClick(nil)
        #expect(checkbox.state == .off)
        #expect(!SettingsStore(defaults: fixture.defaults).restoresFavoritesExpansion)
        #expect(fixture.settings.favoritesExpanded)
        withExtendedLifetime(controller) {}
    }

    @Test("Enabling restoration keeps the live state and restores it without another expansion")
    func enableAfterExpansion() throws {
        let fixture = try Fixture(restores: false, expanded: false)
        defer { fixture.finish() }
        let (first, outline, header) = try fixture.makeTree()
        outline.expandItem(header)
        fixture.settings.restoresFavoritesExpansion = true
        #expect(outline.isItemExpanded(header))
        let (second, nextOutline, nextHeader) = try fixture.makeTree()
        #expect(nextOutline.isItemExpanded(nextHeader))
        fixture.settings.restoresFavoritesExpansion = false
        #expect(nextOutline.isItemExpanded(nextHeader))
        let (third, closedOutline, closedHeader) = try fixture.makeTree()
        #expect(!closedOutline.isItemExpanded(closedHeader))
        #expect(!fixture.settings.favoritesExpanded)
        fixture.settings.restoresFavoritesExpansion = true
        let (fourth, finalOutline, finalHeader) = try fixture.makeTree()
        #expect(!finalOutline.isItemExpanded(finalHeader))
        withExtendedLifetime((first, second, third, fourth)) {}
    }

    @Test("Volume updates preserve the live state instead of applying launch settings again", arguments: [false, true])
    func volumeUpdate(expanded: Bool) async throws {
        let fixture = try Fixture(restores: false, expanded: false)
        defer { fixture.finish() }
        let (tree, outline, header) = try fixture.makeTree()
        if expanded { outline.expandItem(header) }
        fixture.settings.favoritesExpanded = !expanded
        fixture.defaults.clearExpansionWrites()
        let root = FolderNode(url: URL(fileURLWithPath: "/tmp/folzio-volume"), name: "volume", kind: .volume)
        fixture.volumes.continuation.yield([root])
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while outline.numberOfRows != 2 && clock.now < deadline { await Task.yield() }
        #expect(outline.numberOfRows == 2)
        #expect(outline.isItemExpanded(header) == expanded)
        #expect(fixture.settings.favoritesExpanded == !expanded)
        #expect(fixture.defaults.expansionWrites.isEmpty)
        withExtendedLifetime(tree) {}
    }

    @Test("A missing favorite remains registered when the heading is restored")
    func missingFavorite() async throws {
        let fixture = try Fixture(restores: true, expanded: true)
        defer { fixture.finish() }
        let missing = URL(fileURLWithPath: "/tmp/folzio-missing-\(UUID())", isDirectory: true)
        fixture.settings.favorites = FavoriteFolders(urls: [missing], customNames: [missing.path: "Missing"])
        let (tree, outline, header) = try fixture.makeTree()
        #expect(outline.isItemExpanded(header))
        let entry = try #require(outline.item(atRow: 1) as? DirectoryTreeViewController.FavoriteEntry)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while entry.availability != .missing && clock.now < deadline { await Task.yield() }
        #expect(entry.availability == .missing)
        #expect(entry.name == "Missing")
        #expect(fixture.settings.favorites.urls == [missing])
        #expect(fixture.settings.favoritesExpanded)
        withExtendedLifetime(tree) {}
    }

    @MainActor
    private final class Fixture {
        let suite = "Folzio.FavoritesExpansion.\(UUID())"
        let defaults: RecordingDefaults
        let settings: SettingsStore
        let model: BrowserModel
        let volumes = TestVolumes()
        let lister = EmptyLister()

        init(restores: Bool, expanded: Bool) throws {
            _ = NSApplication.shared
            defaults = try #require(RecordingDefaults(suiteName: suite))
            settings = SettingsStore(defaults: defaults)
            settings.restoresFavoritesExpansion = restores
            settings.favoritesExpanded = expanded
            model = BrowserModel(kindNames: l10n.kindNames, lister: lister, decoder: ImageDecoder(),
                                 cache: DecodedImageCache(), settings: settings)
        }

        func makeTree() throws -> (DirectoryTreeViewController, NSOutlineView, AnyObject) {
            let coordinator = FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings)
            let tree = DirectoryTreeViewController(
                model: model, lister: lister, volumes: volumes, coordinator: coordinator,
                watcher: EmptyWatcher(), settings: settings, confirmation: ConfirmationPresenter(settings: settings)
            )
            tree.loadViewIfNeeded()
            let outline = try #require(tree.primaryFocusView as? NSOutlineView)
            let header = try #require(outline.item(atRow: 0) as? DirectoryTreeViewController.FavoritesHeader)
            return (tree, outline, header)
        }

        func finish() {
            volumes.continuation.finish()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private final class RecordingDefaults: UserDefaults, @unchecked Sendable {
        private let lock = NSLock()
        private var recordedExpansionWrites: [Bool] = []

        var expansionWrites: [Bool] { lock.withLock { recordedExpansionWrites } }

        func clearExpansionWrites() {
            lock.withLock { recordedExpansionWrites.removeAll() }
        }

        override func set(_ value: Bool, forKey defaultName: String) {
            if defaultName == "favorites.isExpanded" {
                lock.withLock { recordedExpansionWrites.append(value) }
            }
            super.set(value, forKey: defaultName)
        }
    }

    private struct TestVolumes: VolumeProviding {
        let changes: AsyncStream<[FolderNode]>
        let continuation: AsyncStream<[FolderNode]>.Continuation

        init() {
            (changes, continuation) = AsyncStream.makeStream(of: [FolderNode].self)
        }

        func rootNodes() -> [FolderNode] { [] }
    }

    private struct EmptyWatcher: FileSystemWatching {
        var events: AsyncStream<Set<URL>> { AsyncStream { $0.finish() } }
        func watch(_ folders: Set<URL>, subtrees: Set<URL>) {}
    }

    private struct EmptyLister: DirectoryListing {
        func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] { [] }
        func subfolders(of folder: URL) async throws(ListingError) -> [URL] { [] }
    }
}
