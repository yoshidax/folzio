import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("HistoryNavigator")
@MainActor
struct HistoryNavigatorTests {
    @MainActor
    private final class Host: HistoryPresentationHost {
        var presentation = HistoryPresentation(
            displayMode: .list,
            thumbnailSize: ViewSettings.defaultThumbnailSize,
            paneLayout: .all
        )
        var applied: [HistoryPresentation] = []

        var historyPresentation: HistoryPresentation { presentation }

        func applyHistoryPresentation(_ presentation: HistoryPresentation) {
            self.presentation = presentation
            applied.append(presentation)
        }
    }

    @MainActor
    private final class Env {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let model: BrowserModel
        let navigator: HistoryNavigator
        let host: Host

        init(reader: any ArchiveReading = ZipArchiveReader(kindNames: FixtureKit.kindNames)) throws {
            var root = FileManager.default.temporaryDirectory
                .appendingPathComponent("HistoryNavigatorTests-\(UUID().uuidString)", isDirectory: true)
            if root.path.hasPrefix("/var/") {
                root = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
            }
            let fileManager = FileManager.default
            for path in ["A", "A/Sub", "B", "B/Sub", "C", "D"] {
                try fileManager.createDirectory(
                    at: root.appendingPathComponent(path, isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            try ImageFixtures.jpeg(at: root.appendingPathComponent("A/cover.jpg"), width: 16, height: 12)
            try ImageFixtures.jpeg(at: root.appendingPathComponent("A/Sub/inner.jpg"), width: 16, height: 12)
            try ImageFixtures.jpeg(at: root.appendingPathComponent("B/photo.jpg"), width: 16, height: 12)
            try ImageFixtures.jpeg(at: root.appendingPathComponent("C/photo.jpg"), width: 16, height: 12)
            try ImageFixtures.jpeg(at: root.appendingPathComponent("D/photo.jpg"), width: 16, height: 12)

            let work = fileManager.temporaryDirectory
                .appendingPathComponent("HistoryNavigatorTests-work-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: work) }
            let jpeg = work.appendingPathComponent("photo.jpg")
            try ImageFixtures.jpeg(at: jpeg, width: 16, height: 12)
            for name in ["z1.zip", "z2.zip"] {
                try ZipFixtureWriter.write(
                    [ZipFixtureEntry(name: "sub/photo.jpg", content: .bytes(try Data(contentsOf: jpeg)))],
                    to: root.appendingPathComponent("A/\(name)")
                )
            }
            try ZipFixtureWriter.write(
                [ZipFixtureEntry(name: "photo.jpg", content: .bytes(try Data(contentsOf: jpeg)))],
                to: root.appendingPathComponent("C/broken-source.zip")
            )

            let suite = "HistoryNavigatorTests.\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "view.showsZipFiles")
            model = BrowserModel(
            kindNames: FixtureKit.kindNames,
                lister: DirectoryLister(kindNames: FixtureKit.kindNames),
                decoder: ImageDecoder(),
                cache: DecodedImageCache(costLimitBytes: 50_000_000),
                settings: SettingsStore(defaults: defaults),
                archiveReader: reader
            )
            model.setNavigationRoots([root])
            host = Host()
            navigator = HistoryNavigator(model: model)
            navigator.presentationHost = host
            self.root = root
            self.suite = suite
        }

        func url(_ path: String) -> URL {
            root.appendingPathComponent(path, isDirectory: true)
        }

        func select(_ path: String) async {
            await model.selectFolder(url(path))
        }

        func openFolder(_ path: String) async {
            await model.openItem(url(path))
        }

        func openArchiveDirectory(_ name: String) async {
            guard let row = model.listing.files.first(where: { $0.name == name && $0.kind == .directory }) else {
                Issue.record("Folder inside the zip is missing: \(name)")
                return
            }
            await model.openItem(row.url)
        }

        func openZip(_ name: String) async {
            guard let row = model.listing.files.first(where: { $0.name == name }) else {
                Issue.record("Zip row is missing: \(name)")
                return
            }
            await model.openItem(row.url)
        }

        func goBack() async {
            navigator.goBack()
            await navigator.waitUntilIdle()
            await waitForListing()
        }

        func goForward() async {
            navigator.goForward()
            await navigator.waitUntilIdle()
            await waitForListing()
        }

        func waitForListing() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while model.listing.state == .loading, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private final class SlowArchiveReader: ArchiveReading, @unchecked Sendable {
        private let base = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        private let delay: Duration

        init(delay: Duration) {
            self.delay = delay
        }

        func open(_ archive: URL) async throws(ArchiveError) -> ArchiveIndex {
            try? await Task.sleep(for: delay)
            return try await base.open(archive)
        }

        func data(for entryURL: URL, limit: Int) async throws(ArchiveError) -> Data {
            try await base.data(for: entryURL, limit: limit)
        }

        func stream(for entryURL: URL) async throws(ArchiveError) -> ArchiveEntryStream {
            try await base.stream(for: entryURL)
        }

        func identity(of archive: URL) -> ArchiveIdentity? {
            base.identity(of: archive)
        }
    }

    private func path(_ url: URL?) -> String? {
        url?.standardizedFileURL.path
    }

    private func name(_ navigator: HistoryNavigator) -> String? {
        navigator.history.current?.location.folder.lastPathComponent
    }

    private func archiveDirectory(_ navigator: HistoryNavigator) -> String? {
        navigator.history.current?.location.archive?.directory
    }

    @Test("The initial display records one entry with neither Back nor Forward available (SC-032)")
    func initialRecord() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        #expect(env.navigator.history.count == 1)
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.canGoBack == false)
        #expect(env.navigator.canGoForward == false)
    }

    @Test("Navigates back and forward through A, B, and C (US7-AS1, AS2)")
    func backAndForward() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        await env.select("C")
        #expect(env.navigator.history.count == 3)

        await env.goBack()
        #expect(name(env.navigator) == "B")
        await env.goBack()
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.canGoBack == false)
        await env.goForward()
        #expect(name(env.navigator) == "B")
    }

    @Test("New navigation after going back clears forward history (US7-AS5)")
    func newNavigationClearsForward() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        await env.select("C")
        await env.goBack()
        await env.goBack()
        #expect(env.navigator.canGoForward)

        await env.select("D")
        #expect(env.navigator.canGoForward == false)
        #expect(name(env.navigator) == "D")
        #expect(env.navigator.history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
    }

    @Test("Skips and removes a missing back destination and navigates to the preceding entry (EC-54, SC-030)")
    func skipsMissingBackEntry() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        await env.select("C")
        try FileManager.default.removeItem(at: env.url("B"))

        await env.goBack()
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.history.count == 2)
        #expect(env.navigator.history.forwardEntries.count == 1)

        await env.goForward()
        #expect(name(env.navigator) == "C")
        #expect(env.navigator.canGoForward == false)
    }

    @Test("Also skips missing forward destinations (EC-55)")
    func skipsMissingForwardEntry() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        await env.select("C")
        await env.goBack()
        await env.goBack()
        try FileManager.default.removeItem(at: env.url("B"))

        await env.goForward()
        #expect(name(env.navigator) == "C")
        #expect(env.navigator.history.count == 2)
        #expect(env.navigator.history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
    }

    @Test("Skips consecutive missing candidates until an existing entry is found")
    func skipsSeveralMissingEntries() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        await env.select("D")
        await env.select("C")
        try FileManager.default.removeItem(at: env.url("B"))
        try FileManager.default.removeItem(at: env.url("D"))

        await env.goBack()
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.history.count == 2)
    }

    @Test("Back reaches a previous entry even after the current folder disappears and its entry is removed (EC-65)")
    func removedCurrentStillAllowsBack() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        try FileManager.default.removeItem(at: env.url("B"))

        await env.navigator.revalidateAll()
        #expect(env.navigator.history.current == nil)
        #expect(env.navigator.history.count == 1)

        await env.goBack()
        #expect(name(env.navigator) == "A")
    }

    @Test("An externally renamed location is missing and removed (EC-57)")
    func externallyRenamedFolderIsRemoved() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        try FileManager.default.moveItem(at: env.url("B"), to: env.url("B2"))

        await env.navigator.revalidateAll()
        #expect(env.navigator.history.current == nil)
        #expect(env.navigator.history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        await env.goBack()
        #expect(name(env.navigator) == "A")
    }

    @Test("A deleted current folder is replaced by its parent and coalesced with an identical neighbor (EC-60)")
    func relocatedReplacesCurrentAndConsolidates() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("A/Sub")
        try FileManager.default.removeItem(at: env.url("A/Sub"))

        await env.model.handleFileSystemEvent([env.url("A/Sub")])
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(env.navigator.history.count == 1)
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.canGoBack == false)
    }

    @Test("Replacing the current entry preserves forward history (EC-60)")
    func relocatedKeepsForward() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("A/Sub")
        await env.select("C")
        await env.goBack()
        try FileManager.default.removeItem(at: env.url("A/Sub"))

        await env.model.handleFileSystemEvent([env.url("A/Sub")])
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.history.forwardEntries.map(\.location.folder.lastPathComponent) == ["C"])

        await env.goForward()
        #expect(name(env.navigator) == "C")
    }

    @Test("A damaged zip entry is not skipped and displays an error (EC-56)")
    func brokenArchiveIsNotSkipped() async throws {
        let env = try Env()
        defer { env.cleanup() }

        let broken = env.url("A").appendingPathComponent("broken.zip")
        try Data("not a zip".utf8).write(to: broken)
        await env.select("A")
        await env.openZip("broken.zip")
        #expect(env.navigator.history.current?.location.archive != nil)
        if case let .failed(message) = env.model.listing.state {
            #expect(message == .archive(.notAZip))
        } else {
            Issue.record("A corrupted zip did not become .failed: \(env.model.listing.state)")
        }

        await env.goBack()
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        await env.goForward()
        #expect(env.navigator.history.current?.location.archive != nil)
        #expect(env.navigator.canGoBack)
    }

    @Test("Back closes search results without moving through history (US7-AS11)")
    func backEndsSearch() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let count = env.navigator.history.count
        let pattern = try #require(SearchPattern(keyword: "photo"))
        env.model.startSearch(pattern, root: env.root)
        #expect(env.navigator.canGoBack)
        #expect(env.navigator.canGoForward == false)

        await env.goBack()
        #expect(env.model.isShowingSearchResults == false)
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(env.navigator.history.count == count)
        #expect(env.navigator.canGoBack == false)
    }

    @Test("Back also closes a search started immediately after launch (US7-AS12)")
    func backEndsSearchAtStartup() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let pattern = try #require(SearchPattern(keyword: "photo"))
        env.model.startSearch(pattern, root: env.root)
        #expect(env.navigator.canGoBack)

        await env.goBack()
        #expect(env.model.isShowingSearchResults == false)
        #expect(env.navigator.canGoBack == false)
    }

    @Test("Ending a search started inside a zip records the folder; another Back returns inside the zip (US7-AS13, R76)")
    func backEndsSearchInsideArchive() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.openZip("z1.zip")
        await env.openArchiveDirectory("sub")
        #expect(archiveDirectory(env.navigator) == "sub/")

        let pattern = try #require(SearchPattern(keyword: "photo"))
        env.model.startSearch(pattern, root: env.url("A"))
        await env.goBack()
        #expect(env.model.isShowingSearchResults == false)
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(env.model.listing.archive == nil)
        #expect(env.navigator.canGoBack)

        await env.goBack()
        #expect(env.model.listing.archive?.directory == "sub/")
        #expect(archiveDirectory(env.navigator) == "sub/")
    }

    @Test("Renaming replaces the current location and removes other affected entries (EC-61)")
    func renamedFolderUpdatesHistory() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        try FileManager.default.moveItem(at: env.url("B"), to: env.url("B2"))
        env.model.didRenameFolder(from: env.url("B"), to: env.url("B2"))
        env.navigator.didRenameFolder(from: env.url("B"), to: env.url("B2"))

        #expect(name(env.navigator) == "B2")
        #expect(env.navigator.history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
    }

    @Test("Removing trashed history entries preserves the current entry (EC-58, FR-109)")
    func removedItemsLeaveCurrent() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        await env.select("C")
        env.navigator.didRemoveItems([env.url("B")])
        #expect(env.navigator.history.count == 2)
        #expect(env.navigator.history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(name(env.navigator) == "C")
    }

    @Test("A location change during validation discards the old Back request (R72)")
    func supersededRequestIsDiscarded() async throws {
        let env = try Env(reader: SlowArchiveReader(delay: .milliseconds(300)))
        defer { env.cleanup() }

        await env.select("A")
        await env.openZip("z1.zip")
        await env.goBack()
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        await env.waitForListing()
        await env.openZip("z2.zip")
        await env.goBack()
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(env.navigator.canGoForward)

        env.navigator.goForward()
        try await Task.sleep(for: .milliseconds(50))
        await env.select("D")
        await env.navigator.waitUntilIdle()

        #expect(name(env.navigator) == "D")
        #expect(env.model.listing.archive == nil)
        #expect(path(env.model.listing.folder) == path(env.url("D")))
    }

    @Test("Repeated Back requests run sequentially and eventually move back two entries (R72)")
    func queuedRequestsKeepOrder() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        await env.select("C")

        let start = ContinuousClock.now
        env.navigator.goBack()
        env.navigator.goBack()
        let enqueueElapsed = ContinuousClock.now - start
        #expect(enqueueElapsed < .milliseconds(100), "Do not block the UI while accepting the request (measured: \(enqueueElapsed))")

        await env.navigator.waitUntilIdle()
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.history.current?.location.archive == nil)
        #expect(env.navigator.canGoBack == false)
        #expect(env.navigator.canGoForward)
    }

    @Test("goBack and goForward calls never block for 100 ms or more during validation and loading (SC-029)")
    func navigationCallDoesNotBlock() async throws {
        let env = try Env(reader: SlowArchiveReader(delay: .milliseconds(300)))
        defer { env.cleanup() }

        await env.select("A")
        await env.openZip("z1.zip")
        await env.goBack()

        let start = ContinuousClock.now
        env.navigator.goForward()
        let elapsed = ContinuousClock.now - start
        #expect(elapsed < .milliseconds(100), "Accepting goForward takes less than 100 ms (measured: \(elapsed))")

        await env.navigator.waitUntilIdle()
        #expect(env.navigator.history.current?.location.archive != nil)
    }

    @Test("Does not record view changes in search results or the not-found view (FR-113)")
    func recordViewChangeIgnoresUnavailableLocations() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let pattern = try #require(SearchPattern(keyword: "photo"))
        env.model.startSearch(pattern, root: env.root)
        let count = env.navigator.history.count
        env.navigator.recordViewChange(.viewChange)
        #expect(env.navigator.history.count == count)

        await env.goBack()
        await env.select("Missing")
        let noCurrentCount = env.navigator.history.count
        env.navigator.recordViewChange(.viewChange)
        #expect(env.navigator.history.count == noCurrentCount)
    }

    @Test("Records view changes using the restoration layout returned by presentationHost")
    func recordUsesHostProjection() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let normal = HistoryPresentation(
            displayMode: .thumbnails,
            thumbnailSize: 200,
            paneLayout: .all
        )
        env.host.presentation = normal
        env.navigator.recordViewChange(.viewChange)

        #expect(env.navigator.history.current?.viewState.presentation == normal)
    }

    @Test("Does not record view changes without a presentationHost")
    func recordViewChangeNeedsHost() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let count = env.navigator.history.count
        env.navigator.presentationHost = nil
        env.navigator.recordViewChange(.viewChange)
        #expect(env.navigator.history.count == count)
        env.navigator.presentationHost = env.host
    }

    @Test("Reapplying the same state records nothing")
    func recordViewChangeIgnoresSameState() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let version = env.navigator.history.version
        env.navigator.recordViewChange(.viewChange)
        env.navigator.recordViewChange(.thumbnailSize)
        #expect(env.navigator.history.version == version)
    }

    @Test("Back within the same location restores only view state without rebuilding the listing (US8-AS1, AS5)")
    func sameLocationRestoresPresentation() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let cover = try #require(env.model.listing.files.first { $0.name == "cover.jpg" })
        env.model.select([cover.url], focused: cover.url)
        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 256, paneLayout: .all)
        env.navigator.recordViewChange(.viewChange)
        #expect(env.navigator.history.count == 2)
        #expect(env.navigator.canGoBack)

        let listing = env.model.listing
        await env.goBack()
        #expect(env.host.presentation.displayMode == .list)
        #expect(env.host.presentation.thumbnailSize == 128)
        #expect(env.model.listing.folder == listing.folder)
        #expect(env.model.listing.files == listing.files)
        #expect(env.model.selection.focused == cover.url)
        #expect(env.navigator.canGoForward)
    }

    @Test("Back to a different location restores both location and view state (US8-AS5)")
    func differentLocationRestoresPresentation() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 192, paneLayout: .all)
        env.navigator.recordViewChange(.viewChange)
        await env.select("B")

        await env.goBack()
        #expect(name(env.navigator) == "A")
        #expect(env.host.presentation.displayMode == .thumbnails)
        #expect(env.host.presentation.thumbnailSize == 192)

        await env.goBack()
        #expect(env.host.presentation.displayMode == .list)
        #expect(env.host.presentation.thumbnailSize == 128)
    }

    @Test("Also restores media type filters, zip visibility, and pane visibility (US8-AS3, AS4)")
    func restoresModelAndPaneState() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let initialFilter = env.model.mediaTypeFilter
        let initialZip = env.model.showsZipFiles
        env.model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))
        env.model.setShowsZipFiles(false)
        env.host.presentation = HistoryPresentation(displayMode: .list, thumbnailSize: 128, paneLayout: .previewOnly)
        env.navigator.recordViewChange(.viewChange)

        await env.goBack()
        #expect(env.model.mediaTypeFilter == initialFilter)
        #expect(env.model.showsZipFiles == initialZip)
        #expect(env.host.presentation.paneLayout == .all)
        #expect(env.navigator.history.canGoBack == false)
    }

    @Test("View state after ending a search becomes the current history entry (R76)")
    func searchEndUpdatesCurrentViewState() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let pattern = try #require(SearchPattern(keyword: "photo"))
        env.model.startSearch(pattern, root: env.root)
        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 192, paneLayout: .all)

        await env.goBack()
        #expect(env.navigator.history.current?.viewState.presentation.displayMode == .thumbnails)
        #expect(env.navigator.history.current?.viewState.presentation.thumbnailSize == 192)
    }

    @Test("A view change immediately after Back creates a new entry and clears forward history (US8-AS7)")
    func viewChangeAfterBackClearsForward() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 160, paneLayout: .all)
        env.navigator.recordViewChange(.thumbnailSize)
        await env.goBack()
        #expect(env.navigator.canGoForward)

        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 176, paneLayout: .all)
        env.navigator.recordViewChange(.thumbnailSize)
        #expect(env.navigator.canGoForward == false)
        #expect(env.navigator.history.count == 2)
    }

    @Test("Navigation to a missing location cancels its record without retaining a current entry (EC-62)")
    func missingNavigationRollsBackRecord() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.select("B")
        let missing = env.url("Missing")
        await env.select("Missing")
        #expect(path(env.model.listing.folder) == path(missing))
        #expect(env.navigator.history.current == nil)
        #expect(env.navigator.history.count == 2)

        await env.goBack()
        #expect(name(env.navigator) == "B")
    }

    // MARK: - Opening Folders from Search Results (FR-113, 140; EC-99, EC-100)

    /// Waits until a folder row appears in search results and returns its URL.
    private func waitForSearchRow(_ env: Env, name: String) async -> URL? {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if let row = env.model.listing.files.first(where: { $0.name == name && $0.kind == .folder }) {
                return row.url
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return env.model.listing.files.first(where: { $0.name == name && $0.kind == .folder })?.url
    }

    @Test("Opening a search result folder applies and records the pre-search view state; Back returns to the pre-search location")
    func openingFolderFromSearchRecordsNavigation() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let pattern = try #require(SearchPattern(keyword: "B"))
        env.model.startSearch(pattern, root: env.root)
        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 192, paneLayout: .all)

        let row = try #require(await waitForSearchRow(env, name: "B"))
        await env.model.openItem(row)
        await env.waitForListing()

        #expect(!env.model.isShowingSearchResults)
        #expect(name(env.navigator) == "B")
        #expect(env.navigator.history.count == 2)
        #expect(env.navigator.history.current?.viewState.presentation.displayMode == .thumbnails)
        // The pre-search location also receives the presentation state at the end of the search.
        #expect(env.navigator.history.backEntries.last?.viewState.presentation.displayMode == .thumbnails)
        #expect(env.navigator.canGoForward == false)

        await env.goBack()
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(!env.model.isShowingSearchResults)
        #expect(env.navigator.history.current?.viewState.presentation.displayMode == .thumbnails)
    }

    @Test("Opening the pre-search location's row only applies view state without recording a new entry (EC-99)")
    func openingSameFolderFromSearchDoesNotRecord() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let pattern = try #require(SearchPattern(keyword: "A"))
        env.model.startSearch(pattern, root: env.root)
        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 192, paneLayout: .all)
        let row = try #require(await waitForSearchRow(env, name: "A"))
        await env.model.openItem(row)
        await env.waitForListing()

        #expect(!env.model.isShowingSearchResults)
        #expect(env.navigator.history.count == 1)
        #expect(name(env.navigator) == "A")
        #expect(env.navigator.history.current?.viewState.presentation.displayMode == .thumbnails)
        #expect(env.navigator.canGoBack == false)

        // When there is earlier history, going back moves before the pre-search location.
        await env.select("B")
        await env.select("A")
        env.model.startSearch(pattern, root: env.root)
        let again = try #require(await waitForSearchRow(env, name: "A"))
        await env.model.openItem(again)
        await env.waitForListing()

        // Keep the three entries A, B, A; opening A from search results does not record it as a separate location.
        #expect(env.navigator.history.count == 3)
        #expect(env.navigator.history.current?.location.folder.lastPathComponent == "A")
        await env.goBack()
        #expect(name(env.navigator) == "B")
    }

    @Test("Opening results from a search started inside a zip records after the zip location without recording its containing folder (EC-100)")
    func openingFolderFromSearchInsideArchive() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        await env.openZip("z1.zip")
        await env.openArchiveDirectory("sub")
        // A, the zip root, and sub inside the zip.
        #expect(env.navigator.history.count == 3)
        #expect(env.navigator.history.current?.location.archive?.directory == "sub/")

        let pattern = try #require(SearchPattern(keyword: "B"))
        env.model.startSearch(pattern, root: env.root)
        let row = try #require(await waitForSearchRow(env, name: "B"))
        await env.model.openItem(row)
        await env.waitForListing()

        // Record after the history inside the zip and do not insert a duplicate folder A containing the zip.
        #expect(env.navigator.history.count == 4)
        #expect(name(env.navigator) == "B")
        #expect(env.navigator.history.backEntries.last?.location.archive?.directory == "sub/")
        let plainA = env.navigator.history.allEntries.filter {
            $0.location.folder.standardizedFileURL == env.url("A").standardizedFileURL && $0.location.archive == nil
        }
        #expect(plainA.count == 1)

        await env.goBack()
        #expect(env.model.listing.archive?.directory == "sub/")
        #expect(env.navigator.history.current?.location.archive?.directory == "sub/")
    }

    @Test("A folder disappearing just before opening cancels its record and preserves the pre-search view state")
    func openingMissingFolderFromSearchRollsBack() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let pattern = try #require(SearchPattern(keyword: "B"))
        env.model.startSearch(pattern, root: env.root)
        env.host.presentation = HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 192, paneLayout: .all)
        let row = try #require(await waitForSearchRow(env, name: "B"))
        try FileManager.default.removeItem(at: row)
        await env.model.openItem(row)
        await env.waitForListing()

        #expect(!env.model.isShowingSearchResults)
        #expect(env.navigator.history.count == 1)
        #expect(env.navigator.history.current == nil)
        #expect(path(env.navigator.history.backEntries.last?.location.folder) == path(env.url("A")))
        #expect(env.navigator.history.backEntries.last?.viewState.presentation.displayMode == .thumbnails)
    }

    @Test("Trashing an ancestor of the pre-search folder in search results keeps searching; Back reports it missing (EC-101)")
    func trashingAncestorFromFileListDuringSearch() async throws {
        let env = try Env()
        defer { env.cleanup() }

        let parent = env.url("Outer/P")
        let a = parent.appendingPathComponent("A", isDirectory: true)
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try ImageFixtures.jpeg(at: a.appendingPathComponent("a.jpg"), width: 16, height: 12)
        await env.model.selectFolder(a)
        #expect(env.navigator.history.count == 1)

        // Use P's parent as the root so A's ancestor P becomes a row.
        let pattern = try #require(SearchPattern(keyword: "P"))
        env.model.startSearch(pattern, root: env.url("Outer"))
        let row = try #require(await waitForSearchRow(env, name: "P"))
        try await Task.sleep(for: .milliseconds(100))

        // Call in the same order as `FileOperationCoordinator.trash`.
        try FileManager.default.removeItem(at: parent)
        env.navigator.didRemoveItems([parent])
        #expect(await env.model.leaveTrashedFolders([parent], origin: .fileList) == false)
        #expect(env.model.isShowingSearchResults)
        await env.model.reloadCurrentFolder()
        #expect(env.model.listing.files.isEmpty)
        #expect(path(row) == path(parent))

        // End search results with ⌘[. Do not keep the current entry because the pre-search folder no longer exists.
        await env.goBack()
        #expect(!env.model.isShowingSearchResults)
        #expect(env.navigator.history.current == nil)
        #expect(env.navigator.history.allEntries.allSatisfy { !$0.location.isWithin(parent) })
        #expect(env.navigator.history.count == 0)
    }

    @Test("Selecting a folder while showing search results creates a new history entry (FR-113)")
    func folderSelectedDuringSearchIsRecorded() async throws {
        let env = try Env()
        defer { env.cleanup() }

        await env.select("A")
        let pattern = try #require(SearchPattern(keyword: "photo"))
        env.model.startSearch(pattern, root: env.root)
        await env.select("B")
        #expect(name(env.navigator) == "B")
        #expect(env.navigator.history.count == 2)
    }
}
