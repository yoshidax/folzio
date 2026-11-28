import AppKit
import CoreGraphics
import Foundation
@testable import FolzioCore
import Testing
@testable import FolzioApp

/// While a search is running, the file list makes thumbnails only for visible items, keeps visible items when results
/// are appended, and shows the focused item or the top after the final sort (TAK-129: FR-442, FR-443, FR-444).
@Suite("Search thumbnail requests", .serialized)
@MainActor
struct SearchThumbnailRequestTests {
    /// Records requested and cancelled URLs. Requests stay in flight until cancelled, like slow thumbnail generation.
    private final class RecordingProvider: ThumbnailProviding, @unchecked Sendable {
        private let lock = NSLock()
        private var _requested: [URL] = []
        private var _cancelled: [URL] = []

        var requested: [URL] { lock.withLock { _requested } }
        var cancelled: [URL] { lock.withLock { _cancelled } }

        func thumbnail(for url: URL, pointSize: Double, scale: Double, version: FileContentVersion?) async -> CGImage? {
            lock.withLock { _requested.append(url) }
            try? await Task.sleep(for: .seconds(60))
            return nil
        }

        func cancel(for url: URL, pointSize: Double, scale: Double, version: FileContentVersion?) {
            lock.withLock { _cancelled.append(url) }
        }
    }

    /// Makes a thumbnail at once and keeps it, like `ThumbnailProvider` with its cache. Counts how often each URL
    /// is made.
    private final class CachingProvider: ThumbnailProviding, @unchecked Sendable {
        static let size = (width: 77, height: 55)
        private let lock = NSLock()
        private var counts: [URL: Int] = [:]
        private var kept: [URL: CGImage] = [:]
        private let image: CGImage

        init() throws {
            let context = try #require(CGContext(
                data: nil,
                width: Self.size.width,
                height: Self.size.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            image = try #require(context.makeImage())
        }

        func count(for url: URL) -> Int { lock.withLock { counts[url, default: 0] } }

        func thumbnail(for url: URL, pointSize: Double, scale: Double, version: FileContentVersion?) async -> CGImage? {
            lock.withLock {
                counts[url, default: 0] += 1
                kept[url] = image
            }
            return image
        }

        func cancel(for url: URL, pointSize: Double, scale: Double, version: FileContentVersion?) {}

        func cachedThumbnail(for url: URL, pointSize: Double, scale: Double, version: FileContentVersion?) -> CGImage? {
            lock.withLock { kept[url] }
        }
    }

    /// Searcher whose batches and completion the test controls.
    private final class ControlledSearcher: FileNameSearching, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncStream<[MediaFile]>.Continuation?

        func search(_ request: SearchRequest) -> AsyncStream<[MediaFile]> {
            let (stream, continuation) = AsyncStream.makeStream(of: [MediaFile].self)
            lock.withLock { self.continuation = continuation }
            return stream
        }

        func send(_ batch: [MediaFile]) {
            let continuation = lock.withLock { self.continuation }
            continuation?.yield(batch)
        }

        func finish() {
            let continuation = lock.withLock { self.continuation }
            continuation?.finish()
        }
    }

    private actor Lister: DirectoryListing {
        let rows: [MediaFile]
        init(_ rows: [MediaFile]) { self.rows = rows }
        func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] { rows }
        func subfolders(of folder: URL) async throws(ListingError) -> [URL] { [] }
    }

    private struct Fixture {
        let model: BrowserModel
        let searcher: ControlledSearcher
        let provider: RecordingProvider
        let window: NSWindow
        let folder: URL
        let rows: [MediaFile]
    }

    /// Rows named so that the found order (index order) is the reverse of the name order.
    private static func rows(_ count: Int, in folder: URL) -> [MediaFile] {
        (0..<count).map { index in
            let name = String(format: "img_%05d.jpg", count - index)
            return MediaFile(
                url: folder.appendingPathComponent(name),
                name: name,
                kind: .media(.jpeg),
                typeDescription: "JPEG",
                creationDate: nil,
                fileSize: 0
            )
        }
    }

    private func makeFixture(count: Int) throws -> Fixture {
        _ = NSApplication.shared
        let folder = URL(fileURLWithPath: "/tmp/search-thumbnail-\(UUID().uuidString)", isDirectory: true)
        let rows = Self.rows(count, in: folder)
        let suite = "SearchThumbnailRequestTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let searcher = ControlledSearcher()
        let model = BrowserModel(
            kindNames: l10n.kindNames,
            lister: Lister(rows),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(),
            settings: SettingsStore(defaults: defaults),
            searcher: searcher
        )
        model.setNavigationRoots([folder])
        model.searchReflectionInterval = { _ in .zero }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return Fixture(
            model: model, searcher: searcher, provider: RecordingProvider(), window: window, folder: folder, rows: rows
        )
    }

    private func install(_ view: NSView, in window: NSWindow) {
        guard let content = window.contentView else {
            Issue.record("The window has no content view")
            return
        }
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        content.addSubview(view)
        view.layoutSubtreeIfNeeded()
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for subview in view.subviews {
            if let match = descendant(type, in: subview) { return match }
        }
        return nil
    }

    /// URLs of items inside the visible rectangle of the collection view.
    private func visibleURLs(_ collectionView: NSCollectionView, _ model: BrowserModel) -> Set<URL> {
        let files = model.listing.files
        return Set(collectionView.indexPathsForVisibleItems().compactMap { path in
            guard files.indices.contains(path.item),
                  collectionView.frameForItem(at: path.item).intersects(collectionView.visibleRect) else { return nil }
            return files[path.item].url
        })
    }

    private func wait(
        timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    /// Lets observation callbacks, layout, and thumbnail tasks run.
    private func settle(_ view: NSView) async {
        for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(30))
            view.layoutSubtreeIfNeeded()
        }
    }

    @Test("While searching, only visible items get thumbnails, appended results keep them, and scrolling moves them (FR-442, FR-443, EC-310, EC-311, SC-256)")
    func thumbnailsWhileSearching() async throws {
        let fixture = try makeFixture(count: 2_000)
        defer { fixture.window.close() }
        let view = ThumbnailModeView(model: fixture.model, provider: fixture.provider)
        view.thumbnailRequestDelay = .zero
        install(view, in: fixture.window)
        let collectionView = try #require(descendant(NSCollectionView.self, in: view))
        let scrollView = try #require(descendant(NSScrollView.self, in: view))

        fixture.model.startSearch(try #require(SearchPattern(keyword: "img")), root: fixture.folder)
        fixture.searcher.send(Array(fixture.rows[0..<500]))
        #expect(await wait { fixture.model.listing.files.count == 500 })
        await settle(view)

        let firstVisible = visibleURLs(collectionView, fixture.model)
        let firstRequested = fixture.provider.requested
        #expect(!firstVisible.isEmpty)
        #expect(Set(firstRequested) == firstVisible, "Requested items outside the visible rectangle")

        // A prefetch while searching requests nothing (FR-442).
        view.collectionView(collectionView, prefetchItemsAt: [IndexPath(item: 300, section: 0)])
        await settle(view)
        #expect(fixture.provider.requested.count == firstRequested.count)

        // Appending results keeps the visible items and does not request their thumbnails again (FR-443).
        fixture.searcher.send(Array(fixture.rows[500..<1_000]))
        #expect(await wait { fixture.model.listing.files.count == 1_000 })
        await settle(view)
        #expect(fixture.provider.requested.count == firstRequested.count)

        // Scrolling requests the newly visible items and cancels the ones that left (EC-310).
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 3_000))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(view)
        let scrolledVisible = visibleURLs(collectionView, fixture.model)
        let afterScroll = Set(fixture.provider.requested.dropFirst(firstRequested.count))
        #expect(!scrolledVisible.isEmpty)
        #expect(afterScroll.isSubset(of: scrolledVisible), "Requested items outside the visible rectangle after scrolling")
        #expect(scrolledVisible.isSubset(of: Set(fixture.provider.requested)))
        #expect(firstVisible.subtracting(scrolledVisible).isSubset(of: Set(fixture.provider.cancelled)))

        // Changing the thumbnail size while searching still requests only visible items (EC-311).
        let beforeResize = fixture.provider.requested.count
        view.thumbnailSize = 220
        await settle(view)
        let resizedVisible = visibleURLs(collectionView, fixture.model)
        #expect(Set(fixture.provider.requested.dropFirst(beforeResize)).isSubset(of: resizedVisible))
    }

    @Test("After the final sort, the top is shown and prefetching resumes (FR-444, US102-AS3, US102-AS8)")
    func finalSortShowsTopAndResumesPrefetch() async throws {
        let fixture = try makeFixture(count: 600)
        defer { fixture.window.close() }
        let view = ThumbnailModeView(model: fixture.model, provider: fixture.provider)
        view.thumbnailRequestDelay = .zero
        install(view, in: fixture.window)
        let collectionView = try #require(descendant(NSCollectionView.self, in: view))
        let scrollView = try #require(descendant(NSScrollView.self, in: view))

        fixture.model.startSearch(try #require(SearchPattern(keyword: "img")), root: fixture.folder)
        fixture.searcher.send(fixture.rows)
        #expect(await wait { fixture.model.listing.files.count == 600 })
        await settle(view)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 2_000))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(view)

        fixture.searcher.finish()
        #expect(await wait { fixture.model.listing.search?.phase == .finished })
        await settle(view)

        // Sorted by name, and the top of the list is shown because nothing is focused.
        #expect(fixture.model.listing.files.first?.name == "img_00001.jpg")
        #expect(scrollView.contentView.bounds.origin.y < 1)
        let topURL = try #require(fixture.model.listing.files.first?.url)
        #expect(visibleURLs(collectionView, fixture.model).contains(topURL))
        #expect(fixture.provider.requested.contains(topURL))

        // Prefetching works again after the search (FR-442, A-274).
        let target = fixture.model.listing.files[400].url
        view.collectionView(collectionView, prefetchItemsAt: [IndexPath(item: 400, section: 0)])
        #expect(await wait { fixture.provider.requested.contains(target) })
    }

    @Test("A regular folder listing still prefetches thumbnails (A-274)")
    func regularFolderPrefetches() async throws {
        let fixture = try makeFixture(count: 300)
        defer { fixture.window.close() }
        let view = ThumbnailModeView(model: fixture.model, provider: fixture.provider)
        view.thumbnailRequestDelay = .zero
        install(view, in: fixture.window)
        let collectionView = try #require(descendant(NSCollectionView.self, in: view))

        await fixture.model.selectFolder(fixture.folder)
        #expect(await wait { fixture.model.listing.files.count == 300 })
        await settle(view)

        let target = fixture.model.listing.files[250].url
        view.collectionView(collectionView, prefetchItemsAt: [IndexPath(item: 250, section: 0)])
        #expect(await wait { fixture.provider.requested.contains(target) })
    }

    @Test("The list keeps visible rows when results are appended and shows the focused row after the final sort (FR-443, FR-444, US102-AS4)")
    func listKeepsRowsAndShowsFocusedRow() async throws {
        let fixture = try makeFixture(count: 400)
        defer { fixture.window.close() }
        let view = ListModeView(model: fixture.model, provider: fixture.provider)
        install(view, in: fixture.window)
        let tableView = try #require(descendant(NSTableView.self, in: view))

        fixture.model.startSearch(try #require(SearchPattern(keyword: "img")), root: fixture.folder)
        fixture.searcher.send(Array(fixture.rows[0..<200]))
        #expect(await wait { fixture.model.listing.files.count == 200 })
        await settle(view)
        let requestedBefore = fixture.provider.requested.count
        #expect(requestedBefore > 0)

        fixture.searcher.send(Array(fixture.rows[200..<400]))
        #expect(await wait { fixture.model.listing.files.count == 400 })
        await settle(view)
        #expect(fixture.provider.requested.count == requestedBefore, "Visible rows were reloaded")

        // Focus a row near the top in found order; it sorts near the end.
        let focused = fixture.rows[3].url
        fixture.model.select([focused], focused: focused)
        await settle(view)

        fixture.searcher.finish()
        #expect(await wait { fixture.model.listing.search?.phase == .finished })
        await settle(view)

        let index = try #require(fixture.model.listing.files.firstIndex { $0.url == focused })
        #expect(index > 300)
        let visibleRows = tableView.rows(in: tableView.visibleRect)
        #expect(visibleRows.contains(index), "The focused row \(index) is not visible: \(visibleRows)")
        #expect(fixture.model.selection.focused == focused)
    }

    @Test("A kept thumbnail is shown again at once without being made again after scrolling away and back (FR-445, SC-258)")
    func keptThumbnailIsShownAgain() async throws {
        let fixture = try makeFixture(count: 600)
        defer { fixture.window.close() }
        let provider = try CachingProvider()
        let view = ThumbnailModeView(model: fixture.model, provider: provider)
        view.thumbnailRequestDelay = .zero
        install(view, in: fixture.window)
        let collectionView = try #require(descendant(NSCollectionView.self, in: view))
        let scrollView = try #require(descendant(NSScrollView.self, in: view))

        await fixture.model.selectFolder(fixture.folder)
        #expect(await wait { fixture.model.listing.files.count == 600 })
        await settle(view)
        let top = try #require(fixture.model.listing.files.first?.url)
        #expect(await wait { provider.count(for: top) == 1 })

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 8_000))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(view)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        await settle(view)

        #expect(provider.count(for: top) == 1, "The kept thumbnail was made again")
        let item = try #require(collectionView.visibleItems().compactMap { $0 as? ThumbnailItemView }
            .first { $0.representedURL == top })
        let imageView = try #require(descendant(VideoBadgeImageView.self, in: item.view))
        #expect(imageView.image?.size == NSSize(width: CachingProvider.size.width, height: CachingProvider.size.height),
                "The item shows \(String(describing: imageView.image?.size)) instead of the kept thumbnail")
    }

    @Test("A kept list icon thumbnail is shown again without being made again after scrolling away and back (FR-445, SC-258)")
    func keptListIconIsShownAgain() async throws {
        let fixture = try makeFixture(count: 600)
        defer { fixture.window.close() }
        let provider = try CachingProvider()
        let view = ListModeView(model: fixture.model, provider: provider)
        install(view, in: fixture.window)
        let tableView = try #require(descendant(NSTableView.self, in: view))

        await fixture.model.selectFolder(fixture.folder)
        #expect(await wait { fixture.model.listing.files.count == 600 })
        await settle(view)
        let top = try #require(fixture.model.listing.files.first?.url)
        #expect(await wait { provider.count(for: top) == 1 })

        tableView.scrollRowToVisible(599)
        await settle(view)
        tableView.scrollRowToVisible(0)
        await settle(view)

        #expect(provider.count(for: top) == 1, "The kept thumbnail was made again")
        let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        let cell = try #require(tableView.view(atColumn: column, row: 0, makeIfNecessary: false))
        let imageView = try #require(descendant(VideoBadgeImageView.self, in: cell))
        #expect(imageView.image != nil)
    }

    @Test("Items that only pass by while scrolling fast get no thumbnail request; items that stay get one (FR-446)")
    func passingItemsGetNoRequest() async throws {
        let fixture = try makeFixture(count: 2_000)
        defer { fixture.window.close() }
        let view = ThumbnailModeView(model: fixture.model, provider: fixture.provider)
        view.thumbnailRequestDelay = .milliseconds(150)
        install(view, in: fixture.window)
        let collectionView = try #require(descendant(NSCollectionView.self, in: view))
        let scrollView = try #require(descendant(NSScrollView.self, in: view))

        await fixture.model.selectFolder(fixture.folder)
        #expect(await wait { fixture.model.listing.files.count == 2_000 })
        // Lay out without waiting long enough for the first screen's requests to become due.
        view.layoutSubtreeIfNeeded()

        // Scroll through the list quickly, as when dragging the scroll bar: each position is shown for a few ms.
        var passed = Set<URL>()
        for step in 1...20 {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(step) * 1_000))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            view.layoutSubtreeIfNeeded()
            passed.formUnion(visibleURLs(collectionView, fixture.model))
            try? await Task.sleep(for: .milliseconds(5))
        }
        let stopped = visibleURLs(collectionView, fixture.model)
        #expect(!stopped.isEmpty)

        // Items that stayed in view are requested once the delay has passed.
        #expect(await wait { stopped.isSubset(of: Set(fixture.provider.requested)) })
        let requested = Set(fixture.provider.requested)
        let passedOnly = passed.subtracting(stopped)
        #expect(!passedOnly.isEmpty)
        #expect(requested.isDisjoint(with: passedOnly), "Requested \(requested.intersection(passedOnly).count) items that only passed by")
    }
}
