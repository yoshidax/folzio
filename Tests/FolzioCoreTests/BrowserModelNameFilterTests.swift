import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

/// Filtering the displayed list by name from the toolbar search field (TAK-86, FR-381–FR-386).
@Suite("BrowserModel name filter")
@MainActor
struct BrowserModelNameFilterTests {
    // MARK: - Fixtures

    /// Temporary folder `root` with the folder `A`:
    /// `cat01.jpg`, `Cat02.png`, `dog.png`, `cat.mov`, `cats/`, `sub/my_cat.png`, `photos.zip`, and the empty folder
    /// `empty/`. `photos.zip` holds `cat_in.jpg`, `dog_in.jpg`, and `catdir/x.jpg`.
    private struct Env {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let model: BrowserModel

        func url(_ path: String, isDirectory: Bool = false) -> URL {
            root.appendingPathComponent(path, isDirectory: isDirectory)
        }

        func folder(_ path: String) -> URL {
            url(path, isDirectory: true)
        }

        @MainActor
        var names: [String] {
            model.listing.files.map(\.name)
        }

        @MainActor
        func row(_ name: String) -> MediaFile? {
            model.listing.files.first { $0.name == name }
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// `DirectoryLister` returns `/private/var/...` URLs, so create the temporary folder with the same form.
    private func makeEnv() throws -> Env {
        var root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelNameFilterTests-\(UUID().uuidString)", isDirectory: true)
        if root.path.hasPrefix("/var/") {
            root = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        }
        let fileManager = FileManager.default
        for path in ["A/cats", "A/sub", "empty"] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try ImageFixtures.jpeg(at: root.appendingPathComponent("A/cat01.jpg"), width: 16, height: 12)
        try ImageFixtures.png(at: root.appendingPathComponent("A/Cat02.png"), width: 16, height: 12)
        try ImageFixtures.png(at: root.appendingPathComponent("A/dog.png"), width: 16, height: 12)
        try ImageFixtures.png(at: root.appendingPathComponent("A/sub/my_cat.png"), width: 16, height: 12)
        fileManager.createFile(atPath: root.appendingPathComponent("A/cat.mov").path, contents: Data())

        let jpeg = try smallJPEG()
        try ZipFixtureWriter.write([
            ZipFixtureEntry(name: "cat_in.jpg", content: .bytes(jpeg)),
            ZipFixtureEntry(name: "dog_in.jpg", content: .bytes(jpeg)),
            ZipFixtureEntry(name: "catdir/x.jpg", content: .bytes(jpeg)),
        ], to: root.appendingPathComponent("A/photos.zip"))

        let suite = "BrowserModelNameFilterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "view.showsZipFiles")
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 50_000_000),
            settings: SettingsStore(defaults: defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames)
        )
        model.setNavigationRoots([root])
        return Env(root: root, defaults: defaults, suite: suite, model: model)
    }

    private func smallJPEG() throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelNameFilterTests-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageFixtures.jpeg(at: url, width: 8, height: 8)
        return try Data(contentsOf: url)
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func isEmptyPreview(_ preview: PreviewContent) -> Bool {
        if case .empty = preview { return true }
        return false
    }

    // MARK: - Filtering

    @Test("Folder, media, and zip rows are filtered by name, and the .. row stays first (FR-381)")
    func filtersRowsAndKeepsParent() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        let all = Set(env.names)
        #expect(env.names.first == "..")

        env.model.setNameFilter("cat")
        #expect(env.names.first == "..")
        #expect(Set(env.names) == ["..", "cats", "cat01.jpg", "Cat02.png", "cat.mov"])
        #expect(env.model.listing.state == .loaded)
        #expect(env.model.nameFilterHidesAllRows == false)

        env.model.setNameFilter("*.png")
        #expect(Set(env.names) == ["..", "Cat02.png", "dog.png"])

        env.model.setNameFilter("photos")
        #expect(Set(env.names) == ["..", "photos.zip"])

        env.model.setNameFilter("")
        #expect(Set(env.names) == all)
        #expect(env.model.nameFilter.isFiltering == false)
    }

    @Test("The name filter narrows the rows that the media type filter and zip visibility leave (FR-381)")
    func combinesWithOtherFilters() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))

        env.model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        env.model.setNameFilter("cat")
        #expect(Set(env.names) == ["..", "cats", "cat.mov"])

        env.model.setMediaTypeFilter(MediaTypeFilter())
        #expect(env.model.nameFilter.text == "cat")
        #expect(Set(env.names) == ["..", "cats", "cat01.jpg", "Cat02.png", "cat.mov"])

        env.model.setNameFilter("photos")
        env.model.setShowsZipFiles(false)
        #expect(env.names == [".."])
        #expect(env.model.nameFilter.text == "photos")
    }

    @Test("Hiding every row shows the name filter's empty state; other empty states are unchanged (FR-386)")
    func emptyStates() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))

        env.model.setNameFilter("zzz")
        #expect(env.names == [".."])
        #expect(env.model.listing.state == .noMatches)
        #expect(env.model.nameFilterHidesAllRows)

        env.model.setNameFilter("")
        #expect(env.model.listing.state == .loaded)
        #expect(env.model.nameFilterHidesAllRows == false)

        // When the media type filter already hides every row, its own message stays.
        await env.model.selectFolder(env.folder("A/sub"))
        env.model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        env.model.setNameFilter("zzz")
        #expect(env.model.listing.state == .noMatches)
        #expect(env.model.nameFilterHidesAllRows == false)
        env.model.setMediaTypeFilter(MediaTypeFilter())

        // A folder without rows keeps the empty-folder state.
        await env.model.selectFolder(env.folder("empty"))
        env.model.setNameFilter("x")
        #expect(env.model.listing.state == .empty)
        #expect(env.model.nameFilterHidesAllRows == false)
    }

    @Test("Hidden rows leave the selection like the media type filter, and do not come back (FR-385)")
    func hiddenRowsLeaveSelection() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        let cat = try #require(env.row("cat01.jpg")).url
        let dog = try #require(env.row("dog.png")).url

        env.model.select([dog], focused: dog)
        env.model.setNameFilter("cat")
        #expect(env.model.selection.selected.isEmpty)
        #expect(env.model.selection.focused == nil)
        #expect(isEmptyPreview(env.model.preview))

        env.model.setNameFilter("")
        env.model.select([cat, dog], focused: dog)
        env.model.setNameFilter("cat")
        #expect(env.model.selection.selected == [cat])
        #expect(env.model.selection.focused == cat)

        env.model.setNameFilter("")
        #expect(env.model.selection.selected == [cat])
    }

    @Test("Text that differs only in surrounding whitespace keeps the rows and stores the typed text")
    func whitespaceOnlyChange() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        env.model.setNameFilter("cat")
        let rows = env.names
        env.model.setNameFilter("cat ")
        #expect(env.model.nameFilter.text == "cat ")
        #expect(env.names == rows)
        env.model.setNameFilter("   ")
        #expect(env.model.nameFilter.isFiltering == false)
        #expect(env.names.count > rows.count)
    }

    // MARK: - Clearing (FR-384)

    @Test("Selecting another folder, opening a folder row, and going up clear the name filter")
    func navigationClearsFilter() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))

        env.model.setNameFilter("cat")
        await env.model.selectFolder(env.folder("A/sub"))
        #expect(env.model.nameFilter.text == "")
        #expect(env.names.contains("my_cat.png"))

        await env.model.selectFolder(env.folder("A"))
        env.model.setNameFilter("cats")
        let cats = try #require(env.row("cats")).url
        await env.model.openItem(cats)
        #expect(env.model.nameFilter.text == "")

        env.model.setNameFilter("zzz")
        await env.model.goToEnclosingLevel()
        #expect(env.model.nameFilter.text == "")
        #expect(env.names.contains("dog.png"))
    }

    @Test("Showing a history location clears the name filter, which history does not record (FR-384, EC-254)")
    func historyClearsFilter() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        env.model.setNameFilter("cat")

        let location = HistoryLocation(folder: env.folder("A/sub"))
        guard case let .available(resolved) = await env.model.resolveHistoryLocation(location) else {
            Issue.record("The history location could not be resolved")
            return
        }
        env.model.showHistoryLocation(resolved, focusing: nil)
        #expect(env.model.nameFilter.text == "")
        let loaded = await waitUntil { env.model.listing.state != .loading }
        #expect(loaded)
        #expect(env.names.contains("my_cat.png"))
    }

    @Test("Reloading the same folder keeps the name filter and matches new items by their current name (EC-250)")
    func reloadKeepsFilter() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        env.model.setNameFilter("cat")

        try ImageFixtures.jpeg(at: env.url("A/cat99.jpg"), width: 8, height: 8)
        try ImageFixtures.jpeg(at: env.url("A/bird.jpg"), width: 8, height: 8)
        await env.model.reloadCurrentFolder()
        #expect(env.model.nameFilter.text == "cat")
        #expect(env.names.contains("cat99.jpg"))
        #expect(!env.names.contains("bird.jpg"))
        #expect(!env.names.contains("dog.png"))
    }

    // MARK: - Other Listings (FR-382)

    @Test("Search results are filtered without changing the search bar count; starting and leaving a search clear it")
    func searchResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        env.model.setNameFilter("dog")

        env.model.startSearch(try #require(SearchPattern(keyword: "*.png")), root: env.folder("A"))
        #expect(env.model.nameFilter.text == "")
        let finished = await waitUntil { env.model.listing.search?.phase == .finished }
        #expect(finished)
        let total = env.model.listing.search?.totalCount
        #expect(Set(env.names) == ["Cat02.png", "dog.png", "my_cat.png"])

        env.model.setNameFilter("my")
        #expect(env.names == ["my_cat.png"])
        #expect(env.model.listing.search?.totalCount == total)
        #expect(env.model.listing.search?.phase == .finished)
        #expect(env.model.isShowingSearchResults)

        env.model.setNameFilter("zzz")
        #expect(env.names.isEmpty)
        #expect(env.model.listing.state == .noMatches)
        #expect(env.model.nameFilterHidesAllRows)

        await env.model.selectFolder(env.model.listing.folder)
        #expect(env.model.isShowingSearchResults == false)
        #expect(env.model.nameFilter.text == "")
    }

    @Test("A search result renamed to a name that no longer matches is hidden and leaves the selection (EC-250)")
    func renamedSearchResultLeavesSelection() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        env.model.startSearch(try #require(SearchPattern(keyword: "*.png")), root: env.folder("A"))
        let finished = await waitUntil { env.model.listing.search?.phase == .finished }
        #expect(finished)
        env.model.setNameFilter("cat")
        let old = try #require(env.row("my_cat.png")).url
        env.model.select([old], focused: old)

        let renamed = old.deletingLastPathComponent().appendingPathComponent("bird.png")
        try FileManager.default.moveItem(at: old, to: renamed)
        env.model.didRenameItem(at: old, to: renamed)

        #expect(!env.names.contains("bird.png"))
        #expect(env.model.selection.selected.isEmpty)
        #expect(env.model.selection.focused == nil)
        #expect(isEmptyPreview(env.model.preview))
        env.model.setNameFilter("")
        #expect(env.names.contains("bird.png"))
    }

    @Test("A folder row renamed to a name that no longer matches is hidden and leaves the selection (EC-250)")
    func renamedFolderRowLeavesSelection() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        env.model.setNameFilter("cat")
        let cats = try #require(env.row("cats")).url
        let kept = try #require(env.row("cat01.jpg")).url
        env.model.select([cats, kept], focused: kept)

        let birds = env.folder("A/birds")
        try FileManager.default.moveItem(at: cats, to: birds)
        env.model.didRenameFolder(from: cats, to: birds)

        #expect(!env.names.contains("birds"))
        #expect(env.model.selection.selected == [kept])
        #expect(env.model.selection.focused == kept)
    }

    @Test("Rows inside a zip are filtered by name and .. stays; leaving the zip clears the filter")
    func zipListing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("A"))
        let zip = try #require(env.row("photos.zip")).url
        env.model.setNameFilter("photos")
        await env.model.openItem(zip)
        #expect(env.model.isBrowsingArchive)
        #expect(env.model.nameFilter.text == "")

        env.model.setNameFilter("cat")
        #expect(env.names.first == "..")
        #expect(Set(env.names) == ["..", "cat_in.jpg", "catdir"])

        await env.model.goToEnclosingLevel()
        #expect(env.model.isBrowsingArchive == false)
        #expect(env.model.nameFilter.text == "")
    }
}
