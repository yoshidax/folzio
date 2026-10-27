import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("BrowserModel search")
@MainActor
struct BrowserModelSearchTests {
    @Test("Removes moved search results and delayed old results while preserving the remaining selection")
    func movedSearchResultsAreNotReintroduced() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        let moved = try env.makeResult("trip/day1/cat.jpg")
        let kept = try env.makeResult("trip/day2/dog.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([moved, kept], env, expecting: 2)
        env.model.select([moved.url, kept.url], focused: kept.url)
        env.model.didMoveSearchItems([env.folder("trip/day1")])
        #expect(env.model.isShowingSearchResults)
        #expect(env.model.listing.files.map(\.url) == [kept.url])
        #expect(env.model.selection.selected == [kept.url])
        #expect(env.model.selection.focused == kept.url)
        env.searcher.send([moved])
        await finish(env)
        #expect(env.model.listing.files.map(\.url) == [kept.url])
    }

    // MARK: - Fixtures

    /// Temporary folder `root`. Contains `cover.jpg`, `trip/day1/1.jpg`, `trip/day2/`, and `empty/`.
    /// Passes the search root in the same form as `SearchRoot.validate` (without `/private`, as `/var/...`).
    private struct Env {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let model: BrowserModel
        let searcher: FakeSearcher

        func url(_ path: String) -> URL {
            root.appendingPathComponent(path)
        }

        func folder(_ path: String) -> URL {
            root.appendingPathComponent(path, isDirectory: true)
        }

        /// Creates an image on disk (an empty video for `.mp4` and `.mov`) and returns a search result row.
        func makeResult(_ path: String) throws -> MediaFile {
            let url = url(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let kind = try #require(MediaKind(fileExtension: url.pathExtension))
            if kind.isVideo {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            } else {
                try ImageFixtures.jpeg(at: url, width: 32, height: 24)
            }
            return Self.result(url)
        }

        static func folderResult(_ url: URL) -> MediaFile {
            DirectoryLister.folderRow(at: url, creationDate: nil, kindNames: FixtureKit.kindNames)
        }

        static func result(_ url: URL) -> MediaFile {
            let kind = MediaKind(fileExtension: url.pathExtension) ?? .jpeg
            return MediaFile(
                url: url,
                name: url.lastPathComponent,
                kind: .media(kind),
                typeDescription: kind.isVideo ? "ムービー" : "JPEG イメージ",
                creationDate: nil,
                fileSize: 0
            )
        }

        var viewSettings: ViewSettings {
            SettingsStore(defaults: defaults).viewSettings
        }

        var lastFolder: URL? {
            SettingsStore(defaults: defaults).viewSettings.lastFolder
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeEnv() throws -> Env {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelSearchTests-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        for path in ["trip/day1", "trip/day2", "empty"] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try ImageFixtures.jpeg(at: root.appendingPathComponent("cover.jpg"), width: 32, height: 24)
        try ImageFixtures.jpeg(at: root.appendingPathComponent("trip/day1/1.jpg"), width: 32, height: 24)

        let suite = "BrowserModelSearchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let searcher = FakeSearcher()
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 50_000_000),
            settings: SettingsStore(defaults: defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames),
            searcher: searcher
        )
        model.setNavigationRoots([root])
        return Env(root: root, defaults: defaults, suite: suite, model: model, searcher: searcher)
    }

    private func pattern(_ keyword: String = "a") -> SearchPattern {
        SearchPattern(keyword: keyword)!
    }

    private func path(_ url: URL?) -> String? {
        url?.standardizedFileURL.path
    }

    private func names(_ model: BrowserModel) -> [String] {
        model.listing.files.map(\.name)
    }

    private func isEmptyPreview(_ preview: PreviewContent) -> Bool {
        if case .empty = preview { return true }
        return false
    }

    private func isImagePreview(_ preview: PreviewContent) -> Bool {
        if case .image = preview { return true }
        return false
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Sends a batch and waits until the listing has `count` items.
    private func send(_ batch: [MediaFile], _ env: Env, expecting count: Int) async {
        env.searcher.send(batch)
        let arrived = await waitUntil { env.model.listing.search?.totalCount == count }
        #expect(arrived, "Batch was not added to the listing. totalCount: \(env.model.listing.search?.totalCount ?? -1)")
    }

    private func finish(_ env: Env) async {
        env.searcher.finish()
        let finished = await waitUntil { env.model.listing.search?.phase == .finished }
        #expect(finished)
    }

    // MARK: - Starting

    @Test("Starting a search clears selection and preview without changing the previous folder, lastFolder, or tree synchronization")
    func startingSearchResetsSelectionOnly() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let day1 = env.folder("trip/day1")
        await env.model.selectFolder(day1)
        let image = try #require(env.model.listing.files.first { $0.name == "1.jpg" })
        env.model.select([image.url], focused: image.url)
        #expect(await waitUntil { isImagePreview(env.model.preview) })
        let lastFolder = env.lastFolder
        let syncRequest = env.model.treeSyncRequest

        env.model.startSearch(pattern(), root: env.root)

        #expect(env.model.isShowingSearchResults)
        let search = try #require(env.model.listing.search)
        #expect(search.keyword == "a")
        #expect(path(search.root) == path(env.root))
        #expect(search.phase == .searching)
        #expect(search.totalCount == 0)
        #expect(env.model.listing.state == .loading)
        #expect(env.model.selection.selected.isEmpty)
        #expect(env.model.selection.focused == nil)
        #expect(isEmptyPreview(env.model.preview))
        #expect(path(env.model.listing.folder) == path(day1))
        #expect(path(env.lastFolder) == path(lastFolder))
        #expect(env.model.treeSyncRequest == syncRequest)
        #expect(env.searcher.requests.count == 1)
    }

    @Test("Starting a search during video preview stops playback")
    func startingSearchStopsVideo() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        FileManager.default.createFile(atPath: env.url("clip.mp4").path, contents: Data())
        await env.model.selectFolder(env.root)
        let clip = try #require(env.model.listing.files.first { $0.name == "clip.mp4" })
        env.model.select([clip.url], focused: clip.url)
        guard case .video = env.model.preview else {
            Issue.record("Preview did not become a video")
            return
        }
        let signal = env.model.stopPlaybackSignal

        env.model.startSearch(pattern(), root: env.root)

        #expect(env.model.stopPlaybackSignal > signal)
    }

    // MARK: - Batches and Completion

    @Test("Merges batches in sort order, preserves selection and focus, and includes no .. or folder rows")
    func batchesMergeAndKeepSelection() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("trip"))
        #expect(env.model.listing.files.first?.kind == .parent)
        let b = try env.makeResult("s/b.jpg")
        let d = try env.makeResult("s/d.jpg")
        let a = try env.makeResult("s/a.jpg")
        let c = try env.makeResult("s/c.jpg")

        env.model.startSearch(pattern(), root: env.root)
        await send([b, d], env, expecting: 2)
        #expect(env.model.listing.state == .loaded)
        env.model.select([b.url], focused: b.url)
        #expect(await waitUntil { isImagePreview(env.model.preview) })

        await send([a, c], env, expecting: 4)

        #expect(names(env.model) == ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])
        #expect(env.model.listing.state == .loaded)
        #expect(env.model.selection.selected == [b.url])
        #expect(env.model.selection.focused == b.url)
        #expect(isImagePreview(env.model.preview), "Preview was reloaded: \(env.model.preview)")
        #expect(!env.model.listing.files.contains { $0.kind == .parent || $0.kind == .folder })
        #expect(env.model.hasEnclosingLevel == false)
    }

    @Test("Stream completion becomes finished, or empty with zero results")
    func finishing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.startSearch(pattern(), root: env.root)
        await finish(env)
        #expect(env.model.listing.state == .empty)

        let a = try env.makeResult("s/a.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([a], env, expecting: 1)
        await finish(env)
        #expect(env.model.listing.state == .loaded)
    }

    @Test("A media type filter with zero results becomes noMatches without changing totalCount")
    func filterWithSearchResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let a = try env.makeResult("s/a.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([a], env, expecting: 1)
        await finish(env)

        env.model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))

        #expect(env.model.listing.state == .noMatches)
        #expect(env.model.listing.search?.totalCount == 1)
    }

    // MARK: - Cancellation and New Searches

    @Test("Selecting a folder cancels and closes search results and ignores later batches")
    func selectingFolderLeavesSearch() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("trip"))
        let a = try env.makeResult("s/a.jpg")
        env.model.startSearch(pattern(), root: env.root)
        env.model.setNavigationRoots([env.root, env.folder("empty")])
        #expect(!env.model.listing.files.contains { $0.kind == .parent })
        await send([a], env, expecting: 1)
        env.model.setNavigationRoots([env.root])
        #expect(!env.model.listing.files.contains { $0.kind == .parent })

        await env.model.selectFolder(env.folder("trip"))

        #expect(!env.model.isShowingSearchResults)
        #expect(await waitUntil { env.searcher.cancelledCount == 1 })
        env.searcher.send([try env.makeResult("s/z.jpg")])
        try await Task.sleep(for: .milliseconds(100))
        #expect(!names(env.model).contains("z.jpg"))
        #expect(!names(env.model).contains("a.jpg"))
        #expect(names(env.model) == ["..", "day1", "day2"])
    }

    @Test("Starting a new search while showing results cancels the previous search and replaces its results")
    func newSearchReplacesResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let a = try env.makeResult("s/a.jpg")
        let b = try env.makeResult("s/b.jpg")
        env.model.startSearch(pattern("a"), root: env.root)
        await send([a], env, expecting: 1)

        env.model.startSearch(pattern("b"), root: env.root)

        #expect(await waitUntil { env.searcher.cancelledCount == 1 })
        #expect(env.model.listing.search?.keyword == "b")
        #expect(env.model.listing.files.isEmpty)
        await send([b], env, expecting: 1)
        #expect(names(env.model) == ["b.jpg"])
    }

    @Test("Late batches from the replaced search are not added to the results")
    func replacedSearchDropsOldBatches() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let a = try env.makeResult("s/a.jpg")
        let b = try env.makeResult("s/b.jpg")
        env.model.startSearch(pattern("a"), root: env.root)
        await send([a], env, expecting: 1)

        env.model.startSearch(pattern("b"), root: env.root)
        #expect(await waitUntil { env.searcher.cancelledCount == 1 })
        env.searcher.send([b], to: 1)
        #expect(await waitUntil { names(env.model) == ["b.jpg"] })
        env.searcher.send([a], to: 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(names(env.model) == ["b.jpg"], "Stale batches are discarded (actual: \(names(env.model)))")
    }

    @Test("Starting a search inside a zip discards zip state and keeps listing.folder at the containing folder")
    func startingSearchInsideArchive() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try ZipFixtureWriter.write(
            [ZipFixtureEntry(name: "01.jpg", content: .bytes(Data(count: 16)), method: .stored)],
            to: env.url("photos.zip")
        )
        env.model.setShowsZipFiles(true)
        await env.model.selectFolder(env.root)
        let zip = try #require(env.model.listing.files.first { $0.name == "photos.zip" })
        await env.model.openItem(zip.url)
        #expect(env.model.isBrowsingArchive)

        env.model.startSearch(pattern(), root: env.root)

        #expect(!env.model.isBrowsingArchive)
        #expect(path(env.model.listing.folder) == path(env.root))
    }

    // MARK: - Zip File Visibility (FR-098)

    @Test("Toggling zip visibility in search results only saves the setting and preserves results, selection, and preview")
    func togglingZipVisibilityDuringSearchChangesNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let x = try env.makeResult("b/a.jpg")
        let y = try env.makeResult("a/z.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([x, y], env, expecting: 2)
        env.model.select([x.url], focused: x.url)
        #expect(await waitUntil { isImagePreview(env.model.preview) })

        let files = env.model.listing.files.map(\.url)
        let state = env.model.listing.state
        let totalCount = env.model.listing.search?.totalCount
        let keyword = env.model.listing.search?.keyword
        #expect(!env.model.listing.files.contains { $0.kind == .archive })

        for shows in [true, false] {
            env.model.setShowsZipFiles(shows)

            #expect(env.defaults.object(forKey: "view.showsZipFiles") as? Bool == shows)
            #expect(env.model.isShowingSearchResults)
            #expect(env.model.listing.files.map(\.url) == files)
            #expect(env.model.listing.state == state)
            #expect(env.model.listing.search?.totalCount == totalCount)
            #expect(env.model.listing.search?.keyword == keyword)
            #expect(!env.model.listing.files.contains { $0.kind == .archive })
            #expect(env.model.selection.selected == [x.url])
            #expect(env.model.selection.focused == x.url)
            #expect(isImagePreview(env.model.preview))
        }
    }

    // MARK: - Sorting

    @Test("Search results support location sorting without saving it; leaving restores the saved sort order")
    func locationSortDuringSearch() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let saved = env.viewSettings.sortOrder
        let x = try env.makeResult("b/a.jpg")
        let y = try env.makeResult("a/z.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([x, y], env, expecting: 2)
        #expect(names(env.model) == ["a.jpg", "z.jpg"])

        env.model.sortOrder = SortOrder(column: .location, ascending: true)

        #expect(names(env.model) == ["z.jpg", "a.jpg"])
        #expect(env.viewSettings.sortOrder == saved)

        await env.model.selectFolder(env.root)
        #expect(env.model.sortOrder == saved)

        env.model.startSearch(pattern(), root: env.root)
        env.model.sortOrder = SortOrder(column: .kind, ascending: false)
        await env.model.selectFolder(env.root)
        #expect(env.model.sortOrder == SortOrder(column: .kind, ascending: false))
        #expect(env.viewSettings.sortOrder == SortOrder(column: .kind, ascending: false))
    }

    @Test("Regular folders reject location sorting without changing settings or the listing")
    func locationSortRejectedOutsideSearch() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.sortOrder = SortOrder(column: .kind, ascending: false)
        await env.model.selectFolder(env.root)
        let before = env.model.sortOrder
        let files = names(env.model)
        let storedColumn = env.defaults.string(forKey: "view.sort.column")
        let storedAscending = env.defaults.object(forKey: "view.sort.ascending") as? Bool

        for ascending in [true, false] {
            env.model.sortOrder = SortOrder(column: .location, ascending: ascending)

            #expect(env.model.sortOrder == before)
            #expect(env.viewSettings.sortOrder == before)
            #expect(env.defaults.string(forKey: "view.sort.column") == storedColumn)
            #expect(env.defaults.object(forKey: "view.sort.ascending") as? Bool == storedAscending)
            #expect(names(env.model) == files)
        }
    }

    // MARK: - Pruning Results

    @Test("reloadCurrentFolder removes only missing results and adds no new files")
    func reloadPrunesMissingResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let a = try env.makeResult("s/a.jpg")
        let b = try env.makeResult("s/b.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([a, b], env, expecting: 2)
        env.model.select([a.url], focused: a.url)
        #expect(await waitUntil { isImagePreview(env.model.preview) })

        try FileManager.default.removeItem(at: a.url)
        _ = try env.makeResult("s/new-a.jpg")
        await env.model.reloadCurrentFolder()

        #expect(names(env.model) == ["b.jpg"])
        #expect(env.model.selection.focused == nil)
        #expect(env.model.selection.selected.isEmpty)
        #expect(isEmptyPreview(env.model.preview))
        #expect(env.model.listing.search?.totalCount == 1)
    }

    @Test("didRenameItem replaces and resorts the row, updates selected URLs, and removes unsupported media")
    func renamingResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let cat = try env.makeResult("s/cat.jpg")
        let dog = try env.makeResult("s/dog.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([cat, dog], env, expecting: 2)
        env.model.select([cat.url], focused: cat.url)

        let kitten = env.url("s/kitten.jpg")
        try FileManager.default.moveItem(at: cat.url, to: kitten)
        env.model.didRenameItem(at: cat.url, to: kitten)

        #expect(names(env.model) == ["dog.jpg", "kitten.jpg"])
        let row = try #require(env.model.listing.files.last)
        #expect(row.url == kitten)
        #expect(env.model.selection.selected == [kitten])
        #expect(env.model.selection.focused == kitten)

        let text = env.url("s/kitten.txt")
        try FileManager.default.moveItem(at: kitten, to: text)
        env.model.didRenameItem(at: kitten, to: text)
        #expect(names(env.model) == ["dog.jpg"])
        #expect(env.model.selection.focused == nil)
        #expect(isEmptyPreview(env.model.preview))

        await env.model.selectFolder(env.root)
        let cover = try #require(env.model.listing.files.first { $0.name == "cover.jpg" })
        let before = names(env.model)
        env.model.didRenameItem(at: cover.url, to: env.url("renamed.jpg"))
        #expect(names(env.model) == before)
    }

    @Test("handleFileSystemEvent checks only results under the event folder and does not navigate up if the previous folder disappears")
    func fileSystemEventsPruneUnderFolders() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let day1 = env.folder("trip/day1")
        await env.model.selectFolder(day1)
        let sub = try env.makeResult("s/sub/a.jpg")
        let deep = try env.makeResult("s/sub/deep/b.jpg")
        let other = try env.makeResult("s/other/c.jpg")
        let kept = try env.makeResult("s/other/d.jpg")
        let renameSource = try env.makeResult("s/other/e.jpg")
        env.model.startSearch(pattern(), root: env.folder("s"))
        await send([sub, deep, other, kept, renameSource], env, expecting: 5)

        try FileManager.default.removeItem(at: sub.url)
        try FileManager.default.removeItem(at: other.url)
        await env.model.handleFileSystemEvent([env.folder("s/sub")])
        #expect(Set(names(env.model)) == ["b.jpg", "c.jpg", "d.jpg", "e.jpg"])

        try FileManager.default.removeItem(at: day1)
        await env.model.handleFileSystemEvent([day1])
        #expect(env.model.isShowingSearchResults)
        #expect(path(env.model.listing.folder) == path(day1))

        try FileManager.default.moveItem(at: env.folder("s/sub"), to: env.folder("moved-sub"))
        await env.model.handleFileSystemEvent([env.folder("s")])
        #expect(Set(names(env.model)) == ["d.jpg", "e.jpg"])

        let renamed = env.url("s/other/f.jpg")
        try FileManager.default.moveItem(at: renameSource.url, to: renamed)
        env.model.didRenameItem(at: renameSource.url, to: renamed)
        try FileManager.default.removeItem(at: renamed)
        await env.model.handleFileSystemEvent([env.folder("s/other")])
        #expect(names(env.model) == ["d.jpg"])
    }

    @Test("Deleting the search root removes all results while keeping search results open")
    func searchRootDisappears() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let day1 = env.folder("trip/day1")
        await env.model.selectFolder(day1)
        let lastFolder = env.lastFolder
        let syncRequest = env.model.treeSyncRequest
        let clip = try env.makeResult("s/x/clip.mp4")
        let image = try env.makeResult("s/y/a.jpg")
        let searchRoot = env.folder("s")
        env.model.startSearch(pattern(), root: searchRoot)
        await send([clip, image], env, expecting: 2)
        await finish(env)
        env.model.select([clip.url], focused: clip.url)
        let signal = env.model.stopPlaybackSignal

        try FileManager.default.removeItem(at: searchRoot)
        await env.model.handleFileSystemEvent([searchRoot])

        #expect(env.model.listing.files.isEmpty)
        #expect(env.model.listing.state == .empty)
        #expect(env.model.isShowingSearchResults)
        #expect(env.model.listing.search?.keyword == "a")
        #expect(path(env.model.listing.search?.root) == path(searchRoot))
        #expect(path(env.model.listing.folder) == path(day1))
        #expect(path(env.lastFolder) == path(lastFolder))
        #expect(env.model.treeSyncRequest == syncRequest)
        #expect(env.model.stopPlaybackSignal > signal)

        await env.model.reloadCurrentFolder()
        #expect(env.model.listing.files.isEmpty)
        #expect(env.model.listing.state == .empty)
        #expect(env.model.isShowingSearchResults)
    }

    @Test("leaveTrashedFolders navigates up and closes results for an ancestor of the previous folder but preserves unrelated results")
    func trashingAncestorLeavesSearch() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("trip/day1"))
        env.model.startSearch(pattern(), root: env.root)

        #expect(await env.model.leaveTrashedFolders([env.folder("empty")]) == false)
        #expect(env.model.isShowingSearchResults)

        try FileManager.default.removeItem(at: env.folder("trip"))
        #expect(await env.model.leaveTrashedFolders([env.folder("trip")]) == true)
        #expect(!env.model.isShowingSearchResults)
        #expect(path(env.model.listing.folder) == path(env.root))
    }

    // MARK: - Folder Renames (FR-105, EC-52, R63)

    private func renameFolder(_ env: Env, _ from: String, to newName: String) throws -> (URL, URL) {
        let old = env.folder(from)
        let new = old.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: true)
        try FileManager.default.moveItem(at: old, to: new)
        return (old, new)
    }

    @Test("Renaming a folder in search results preserves results, updates locations and selection, and keeps the preview")
    func renamingFolderRebasesResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.startSearch(pattern(), root: env.root)
        let photo = env.url("trip/day1/1.jpg")
        await send([Env.result(photo), Env.result(env.url("cover.jpg"))], env, expecting: 2)
        await finish(env)
        env.model.select([photo], focused: photo)
        #expect(await waitUntil { isImagePreview(env.model.preview) })
        let signal = env.model.stopPlaybackSignal

        let (old, new) = try renameFolder(env, "trip", to: "trip2")
        env.model.didRenameFolder(from: old, to: new)

        let moved = env.url("trip2/day1/1.jpg")
        let search = try #require(env.model.listing.search)
        #expect(search.totalCount == 2)
        #expect(env.model.listing.files.contains { path($0.url) == path(moved) })
        #expect(search.location(of: moved) == "\(env.root.lastPathComponent)/trip2/day1")
        #expect(path(env.model.selection.focused) == path(moved))
        #expect(isImagePreview(env.model.preview))
        #expect(env.model.stopPlaybackSignal == signal)
        #expect(env.searcher.requests.count == 1)

        // Even after rechecking external changes, results at the new location are not removed.
        await env.model.reloadCurrentFolder()
        #expect(env.model.listing.search?.totalCount == 2)
    }

    @Test("Location sorting reorders results by their new locations after a rename")
    func renamingFolderResortsByLocation() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let other = try env.makeResult("m/a.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([Env.result(env.url("trip/day1/1.jpg")), other], env, expecting: 2)
        await finish(env)
        env.model.sortOrder = SortOrder(column: .location, ascending: true)
        #expect(names(env.model) == ["a.jpg", "1.jpg"])

        let (old, new) = try renameFolder(env, "trip", to: "a-trip")
        env.model.didRenameFolder(from: old, to: new)

        #expect(names(env.model) == ["1.jpg", "a.jpg"])
    }

    @Test("Renaming the search root updates its location without removing results")
    func renamingSearchRoot() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.startSearch(pattern(), root: env.folder("trip"))
        await send([Env.result(env.url("trip/day1/1.jpg"))], env, expecting: 1)
        await finish(env)

        let (old, new) = try renameFolder(env, "trip", to: "trip2")
        env.model.didRenameFolder(from: old, to: new)

        let search = try #require(env.model.listing.search)
        #expect(path(search.root) == path(env.folder("trip2")))
        #expect(search.totalCount == 1)
        #expect(search.location(of: env.url("trip2/day1/1.jpg")) == "trip2/day1")
        #expect(env.searcher.requests.count == 1)
    }

    @Test("Renaming during search remaps late results at old locations, enumerates the new location, and removes duplicates (EC-52)")
    func renamingFolderWhileSearching() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.startSearch(pattern(), root: env.root)
        await send([Env.result(env.url("cover.jpg"))], env, expecting: 1)

        let (old, new) = try renameFolder(env, "trip", to: "trip2")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.searcher.requests.count == 2)
        #expect(path(env.searcher.requests.last?.root) == path(new))

        env.searcher.send([Env.result(env.url("trip/day1/1.jpg"))], to: 0)
        #expect(await waitUntil { env.model.listing.search?.totalCount == 2 })
        #expect(env.model.listing.files.contains { path($0.url) == path(env.url("trip2/day1/1.jpg")) })

        // Only one row remains even when the additional enumeration returns the same file.
        env.searcher.send([Env.result(env.url("trip2/day1/1.jpg"))], to: 1)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(env.model.listing.search?.totalCount == 2)
        #expect(env.model.listing.files.filter { $0.name == "1.jpg" }.count == 1)

        env.searcher.finish(at: 0)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(env.model.listing.search?.phase == .searching)
        env.searcher.finish(at: 1)
        #expect(await waitUntil { env.model.listing.search?.phase == .finished })
    }

    @Test("Renaming the search root during search additionally enumerates the new root")
    func renamingSearchRootWhileSearching() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.startSearch(pattern(), root: env.folder("trip"))

        let (old, new) = try renameFolder(env, "trip", to: "trip2")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.searcher.requests.count == 2)
        #expect(path(env.searcher.requests.last?.root) == path(new))
        // Do not enumerate the root itself (it does not become a row).
        #expect(env.searcher.requests.last?.matchesRoot == false)
        #expect(path(env.model.listing.search?.root) == path(new))
    }

    @Test("Renaming a folder outside the search root during search does not trigger additional enumeration")
    func renamingFolderOutsideSearchRoot() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.startSearch(pattern(), root: env.folder("trip"))

        let (old, new) = try renameFolder(env, "empty", to: "empty2")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.searcher.requests.count == 1)
        #expect(path(env.model.listing.search?.root) == path(env.folder("trip")))
    }

    // MARK: - Folder Rows (US15, FR-139)

    /// Creates a folder on disk and returns a folder row with the same values as a regular listing.
    private func makeFolderResult(_ env: Env, _ path: String) throws -> MediaFile {
        let url = env.folder(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return DirectoryLister.folderRow(
            at: url,
            creationDate: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate,
            kindNames: FixtureKit.kindNames
        )
    }

    @Test("Counts include folders and files and distinguish folder-only matches from zero results (US15-AS10, EC-32, EC-96)")
    func folderRowsCountTowardsTotal() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder1 = try makeFolderResult(env, "s/2024_Kyoto")
        let folder2 = try makeFolderResult(env, "s/kyoto")
        let image1 = try env.makeResult("s/kyoto_map.jpg")
        let image2 = try env.makeResult("s/a/kyoto_01.jpg")
        let image3 = try env.makeResult("s/b/kyoto_02.jpg")

        env.model.startSearch(pattern("kyoto"), root: env.root)
        await send([folder1, folder2, image1], env, expecting: 3)
        #expect(env.model.listing.search?.totalCount == 3)
        await send([image2, image3], env, expecting: 5)
        await finish(env)

        #expect(env.model.listing.search?.totalCount == 5)
        #expect(env.model.listing.search?.phase == .finished)
        #expect(env.model.listing.state == .loaded)
        #expect(env.model.listing.files.count == 5)

        // Do not show the no-matching-items message when only one folder matches.
        env.model.startSearch(pattern("kyoto"), root: env.root)
        await send([folder1], env, expecting: 1)
        await finish(env)
        #expect(env.model.listing.state == .loaded)

        env.model.startSearch(pattern("kyoto"), root: env.root)
        await finish(env)
        #expect(env.model.listing.state == .empty)
        #expect(env.model.listing.search?.totalCount == 0)
    }

    @Test("Media type filters preserve folder rows; no remaining matching media gives noMatches, while folders alone give loaded")
    func folderRowsWithTypeFilter() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let clips = try makeFolderResult(env, "s/clips")
        let video = try env.makeResult("s/kyoto_clip.mp4")

        env.model.startSearch(pattern("clip"), root: env.root)
        await send([clips, video], env, expecting: 2)
        await finish(env)

        env.model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))

        #expect(names(env.model) == ["clips"])
        #expect(env.model.listing.state == .noMatches)
        #expect(env.model.listing.search?.totalCount == 2)
        #expect(env.model.mediaTypeFilter.emptyState == .imagesOnly)

        // Do not show the filtering message when only folders match.
        env.model.startSearch(pattern("clip"), root: env.root)
        await send([clips], env, expecting: 1)
        await finish(env)
        #expect(names(env.model) == ["clips"])
        #expect(env.model.listing.state == .loaded)
    }

    @Test("Focusing a folder row clears the preview and stops any playing video (US15-AS4)")
    func focusingFolderRowClearsPreviewAndStopsVideo() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeFolderResult(env, "s/kyoto")
        let video = try env.makeResult("s/kyoto_clip.mp4")

        env.model.startSearch(pattern("kyoto"), root: env.root)
        await send([folder, video], env, expecting: 2)
        await finish(env)

        env.model.select([video.url], focused: video.url)
        guard case .video = env.model.preview else {
            Issue.record("Preview did not become a video")
            return
        }
        let signal = env.model.stopPlaybackSignal

        env.model.select([folder.url], focused: folder.url)

        #expect(isEmptyPreview(env.model.preview))
        #expect(env.model.stopPlaybackSignal > signal)
        #expect(env.model.selection.focused == folder.url)
    }

    @Test("Name, creation date, and location sorting interleave folders and files without distinction (FR-084, A-25)")
    func folderRowsSortMixedWithMedia() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folderA = try makeFolderResult(env, "s/2024_Kyoto")
        let folderB = try makeFolderResult(env, "s/zzz_Kyoto")
        var image = try env.makeResult("s/m_Kyoto.jpg")
        var video = try env.makeResult("s/n_Kyoto.mp4")

        image.creationDate = Date(timeIntervalSince1970: 1_000)
        video.creationDate = Date(timeIntervalSince1970: 2_000)
        var datedFolderA = folderA
        datedFolderA.creationDate = Date(timeIntervalSince1970: 3_000)
        var datedFolderB = folderB
        datedFolderB.creationDate = Date(timeIntervalSince1970: 4_000)

        env.model.startSearch(pattern("Kyoto"), root: env.root)
        await send([datedFolderA, datedFolderB], env, expecting: 2)
        await send([image, video], env, expecting: 4)
        await finish(env)

        env.model.sortOrder = SortOrder(column: .name, ascending: true)
        #expect(names(env.model) == ["2024_Kyoto", "m_Kyoto.jpg", "n_Kyoto.mp4", "zzz_Kyoto"])

        env.model.sortOrder = SortOrder(column: .creationDate, ascending: true)
        #expect(names(env.model) == ["m_Kyoto.jpg", "n_Kyoto.mp4", "2024_Kyoto", "zzz_Kyoto"])

        env.model.sortOrder = SortOrder(column: .location, ascending: true)
        #expect(names(env.model) == ["2024_Kyoto", "m_Kyoto.jpg", "n_Kyoto.mp4", "zzz_Kyoto"])

        // Folder rows are not removed when sorting by kind.
        env.model.sortOrder = SortOrder(column: .kind, ascending: true)
        #expect(Set(names(env.model)) == ["2024_Kyoto", "zzz_Kyoto", "m_Kyoto.jpg", "n_Kyoto.mp4"])
        #expect(env.model.listing.state == .loaded)
    }

    @Test("Search results have no .. row at the start (FR-084)")
    func searchResultsHaveNoParentRow() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("trip/day1"))
        let folder = try makeFolderResult(env, "s/kyoto")
        let image = try env.makeResult("s/kyoto_map.jpg")

        env.model.startSearch(pattern("kyoto"), root: env.root)
        await send([folder, image], env, expecting: 2)

        #expect(!env.model.listing.files.contains { $0.kind == .parent })
        #expect(!names(env.model).contains(".."))
    }

    // MARK: - Opening Folder Rows (FR-140, US15-AS3, EC-93)

    @Test("Opening a folder row during search stops the search, shows the folder, synchronizes the tree and lastFolder, and discards late results")
    func openingFolderRowDuringSearch() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("trip"))
        let day2 = try makeFolderResult(env, "trip/day2")

        env.model.startSearch(pattern(), root: env.root)
        await send([day2], env, expecting: 1)
        env.model.select([day2.url], focused: day2.url)

        await env.model.openItem(day2.url)

        #expect(await waitUntil { env.searcher.cancelledCount == 1 })
        #expect(!env.model.isShowingSearchResults)
        #expect(env.model.listing.search == nil)
        #expect(path(env.model.listing.folder) == path(day2.url))
        #expect(env.model.listing.files.first?.kind == .parent)
        #expect(path(env.model.treeSyncRequest?.folder) == path(day2.url))
        #expect(path(env.lastFolder) == path(day2.url))

        // Batches from a stopped enumeration do not enter the listing.
        let late = try env.makeResult("s/late.jpg")
        env.searcher.send([late], to: 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(!names(env.model).contains("late.jpg"))
        // day2 is an empty folder.
        #expect(Set(names(env.model)) == [".."])
    }

    @Test("Opening a folder row after search completion behaves the same way")
    func openingFolderRowAfterSearchFinished() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("trip"))
        let day1 = try makeFolderResult(env, "trip/day1")

        env.model.startSearch(pattern(), root: env.root)
        await send([day1], env, expecting: 1)
        await finish(env)

        await env.model.openItem(day1.url)

        #expect(!env.model.isShowingSearchResults)
        #expect(path(env.model.listing.folder) == path(day1.url))
        #expect(env.model.listing.files.first?.kind == .parent)
        #expect(path(env.lastFolder) == path(day1.url))
        #expect(path(env.model.treeSyncRequest?.folder) == path(day1.url))
    }

    @Test("Opening a folder row while sorting by location restores the saved sort order")
    func openingFolderRowRestoresSortOrder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let saved = env.viewSettings.sortOrder
        let day1 = try makeFolderResult(env, "trip/day1")
        env.model.startSearch(pattern(), root: env.root)
        await send([day1], env, expecting: 1)
        env.model.sortOrder = SortOrder(column: .location, ascending: true)

        await env.model.openItem(day1.url)

        #expect(env.model.sortOrder == saved)
        #expect(env.viewSettings.sortOrder == saved)
    }

    @Test("Opening a media row changes nothing")
    func openingMediaRowDoesNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let image = try env.makeResult("s/a.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([image], env, expecting: 1)
        let folder = env.model.listing.folder
        let request = env.model.treeSyncRequest

        await env.model.openItem(image.url)

        #expect(env.model.isShowingSearchResults)
        #expect(path(env.model.listing.folder) == path(folder))
        #expect(env.model.treeSyncRequest == request)
        #expect(env.searcher.cancelledCount == 0)
    }

    @Test("Only opening a folder from search results emits openedSearchResultFolder; regular listings still emit navigated")
    func openingFolderRowSendsOpenedSearchResultFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        var events: [LocationEvent] = []
        env.model.onLocationEvent = { events.append($0) }

        await env.model.selectFolder(env.folder("trip"))
        let day2 = try makeFolderResult(env, "trip/day2")
        env.model.startSearch(pattern(), root: env.root)
        await send([day2], env, expecting: 1)
        env.model.select([day2.url], focused: day2.url)
        events.removeAll()

        await env.model.openItem(day2.url)

        #expect(events == [.openedSearchResultFolder(leavingFocus: day2.url)])

        // Opening a folder from a regular listing still reports navigated.
        await env.model.selectFolder(env.folder("trip"))
        events.removeAll()
        let day1 = try #require(env.model.listing.files.first { $0.name == "day1" })
        await env.model.openItem(day1.url)
        #expect(events.count == 1, "Received events: \(events)")
        #expect(events.first == .navigated(leavingFocus: nil))
    }

    @Test("Opening an unreadable folder row shows accessDenied and allows returning via ..")
    func openingUnreadableFolderRow() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let locked = try makeFolderResult(env, "s/locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.url.path) }

        await env.model.selectFolder(env.folder("trip"))
        env.model.startSearch(pattern(), root: env.root)
        await send([locked], env, expecting: 1)

        await env.model.openItem(locked.url)

        #expect(!env.model.isShowingSearchResults)
        #expect(env.model.listing.state == .denied)
        #expect(env.model.listing.files.first?.kind == .parent)
    }

    // MARK: - Tree Synchronization Completion (EC-102)

    @Test("Completed synchronization for a folder opened from search results saves its displayable ancestor as the last folder")
    func completeSearchResultTreeSyncSavesVisibleAncestor() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let visible = env.root
        let open = try makeFolderResult(env, ".hidden-parent/search-root/kyoto_open")
        var events: [LocationEvent] = []
        env.model.onLocationEvent = { events.append($0) }

        env.model.startSearch(pattern("kyoto"), root: env.folder(".hidden-parent/search-root"))
        await send([open], env, expecting: 1)
        await env.model.openItem(open.url)
        let request = try #require(env.model.treeSyncRequest)
        let focused = env.model.selection.focused
        events.removeAll()

        env.model.completeSearchResultTreeSync(request, selectedFolder: visible)

        #expect(path(env.lastFolder) == path(visible))
        #expect(path(env.model.listing.folder) == path(open.url))
        #expect(env.model.treeSyncRequest == request)
        #expect(env.model.selection.focused == focused)
        #expect(events.isEmpty)

        // Ignore duplicate completions.
        env.model.completeSearchResultTreeSync(request, selectedFolder: env.folder(".hidden-parent"))
        #expect(path(env.lastFolder) == path(visible))
    }

    @Test("Completed synchronization saves the opened folder itself when it can be selected")
    func completeSearchResultTreeSyncSavesSelectedFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let open = try makeFolderResult(env, ".hidden-parent/search-root/kyoto_open")

        env.model.startSearch(pattern("kyoto"), root: env.folder(".hidden-parent/search-root"))
        await send([open], env, expecting: 1)
        await env.model.openItem(open.url)
        let request = try #require(env.model.treeSyncRequest)

        env.model.completeSearchResultTreeSync(request, selectedFolder: open.url)

        #expect(path(env.lastFolder) == path(open.url))
    }

    @Test("Old requests, other requests, non-ancestor locations, and regular navigation synchronization do not change the saved location")
    func completeSearchResultTreeSyncRejectsInvalidRequests() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let open = try makeFolderResult(env, ".hidden-parent/search-root/kyoto_open")
        let sibling = try makeFolderResult(env, ".hidden-parent/search-root/kyoto_open2")

        env.model.startSearch(pattern("kyoto"), root: env.folder(".hidden-parent/search-root"))
        await send([open], env, expecting: 1)
        await env.model.openItem(open.url)
        let request = try #require(env.model.treeSyncRequest)
        let saved = env.lastFolder

        // Stale ID or a different request.
        env.model.completeSearchResultTreeSync(TreeSyncRequest(folder: open.url, id: request.id - 1), selectedFolder: env.root)
        #expect(path(env.lastFolder) == path(saved))
        env.model.completeSearchResultTreeSync(TreeSyncRequest(folder: open.url, id: request.id + 1), selectedFolder: env.root)
        #expect(path(env.lastFolder) == path(saved))

        // A location that is not an ancestor (including siblings sharing a string prefix).
        env.model.completeSearchResultTreeSync(request, selectedFolder: sibling.url)
        #expect(path(env.lastFolder) == path(saved))
        env.model.completeSearchResultTreeSync(request, selectedFolder: env.folder("trip"))
        #expect(path(env.lastFolder) == path(saved))

        // Requests opened from a regular listing are not eligible.
        let day1 = try makeFolderResult(env, "trip/day1")
        await env.model.selectFolder(env.root)
        await env.model.openItem(day1.url)
        let normalRequest = try #require(env.model.treeSyncRequest)
        let normalSaved = env.lastFolder
        env.model.completeSearchResultTreeSync(normalRequest, selectedFolder: env.root)
        #expect(path(env.lastFolder) == path(normalSaved))
    }

    @Test("After further navigation, old synchronization completions are ignored even when showing the same folder again")
    func completeSearchResultTreeSyncIgnoresAfterNavigation() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let open = try makeFolderResult(env, ".hidden-parent/search-root/kyoto_open")

        env.model.startSearch(pattern("kyoto"), root: env.folder(".hidden-parent/search-root"))
        await send([open], env, expecting: 1)
        await env.model.openItem(open.url)
        let request = try #require(env.model.treeSyncRequest)

        // Show the same folder as a regular listing again after another navigation (resetForNavigation).
        await env.model.selectFolder(env.folder("trip"))
        await env.model.selectFolder(open.url)
        let saved = env.lastFolder

        env.model.completeSearchResultTreeSync(request, selectedFolder: env.root)
        #expect(path(env.lastFolder) == path(saved))
    }

    @Test("Synchronization completion for a missing folder saves nothing")
    func completeSearchResultTreeSyncIgnoresNotFound() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let open = try makeFolderResult(env, ".hidden-parent/search-root/kyoto_open")

        env.model.startSearch(pattern("kyoto"), root: env.folder(".hidden-parent/search-root"))
        await send([open], env, expecting: 1)
        try FileManager.default.removeItem(at: open.url)
        await env.model.openItem(open.url)
        let request = try #require(env.model.treeSyncRequest)

        env.model.completeSearchResultTreeSync(request, selectedFolder: env.root)

        #expect(path(env.lastFolder) == path(open.url))
    }

    // MARK: - File Operations and External Changes (US15, FR-087, 105; EC-35, 36, 94, 95, 101)

    private func location(_ env: Env, of url: URL) -> String? {
        env.model.listing.search?.location(of: url)
    }

    @Test("Renaming a folder row updates it and its descendant results and preserves selection and focus with new URLs")
    func renamingFolderRow() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeFolderResult(env, "trip/F")
        let child = try env.makeResult("trip/F/g.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([folder, child], env, expecting: 2)
        await finish(env)
        env.model.select([child.url], focused: child.url)
        #expect(await waitUntil { isImagePreview(env.model.preview) })

        let renamed = env.folder("trip/zzz")
        try FileManager.default.moveItem(at: folder.url, to: renamed)
        env.model.didRenameFolder(from: folder.url, to: renamed)

        let row = try #require(env.model.listing.files.first { $0.kind == .folder })
        #expect(row.name == "zzz")
        #expect(path(row.url) == path(renamed))
        let movedChild = try #require(env.model.listing.files.first { $0.name == "g.jpg" })
        #expect(path(movedChild.url) == path(renamed.appendingPathComponent("g.jpg")))
        #expect(location(env, of: movedChild.url) == "\(env.root.lastPathComponent)/trip/zzz")
        #expect(path(env.model.selection.focused) == path(movedChild.url))
        #expect(env.model.selection.selected == [movedChild.url])
        #expect(isImagePreview(env.model.preview))
        #expect(env.model.listing.search?.totalCount == 2)

        // When sorting by Name, re-sort with the new name.
        env.model.sortOrder = SortOrder(column: .name, ascending: true)
        #expect(names(env.model) == ["g.jpg", "zzz"])
    }

    @Test("Deleting a folder after renaming its row removes both the row and its descendant results")
    func renamedFolderRowIsRemovedWithItsResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeFolderResult(env, "trip/F")
        let child = try env.makeResult("trip/F/g.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([folder, child], env, expecting: 2)
        await finish(env)

        let renamed = env.folder("trip/zzz")
        try FileManager.default.moveItem(at: folder.url, to: renamed)
        env.model.didRenameFolder(from: folder.url, to: renamed)
        try FileManager.default.removeItem(at: renamed)

        await env.model.reloadCurrentFolder()

        #expect(env.model.listing.files.isEmpty)
        #expect(env.model.listing.search?.totalCount == 0)
        #expect(env.model.listing.state == .empty)
        #expect(env.model.isShowingSearchResults)
    }

    @Test("Deleting a renamed folder with a previewed descendant result clears the preview and decreases the count")
    func deletingRenamedFolderClearsPreview() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeFolderResult(env, "trip/F")
        let child = try env.makeResult("trip/F/g.jpg")
        let other = try env.makeResult("trip/other.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([folder, child, other], env, expecting: 3)
        await finish(env)

        let renamed = env.folder("trip/zzz")
        try FileManager.default.moveItem(at: folder.url, to: renamed)
        env.model.didRenameFolder(from: folder.url, to: renamed)
        let movedChild = try #require(env.model.listing.files.first { $0.name == "g.jpg" })
        env.model.select([movedChild.url], focused: movedChild.url)
        #expect(await waitUntil { isImagePreview(env.model.preview) })

        try FileManager.default.removeItem(at: renamed)
        await env.model.reloadCurrentFolder()

        #expect(names(env.model) == ["other.jpg"])
        #expect(env.model.listing.search?.totalCount == 1)
        #expect(env.model.selection.focused == nil)
        #expect(isEmptyPreview(env.model.preview))
    }

    @Test("Moving a folder outside the app removes its row and descendant results without adding newly appearing folders")
    func externallyMovedFolderIsRemoved() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeFolderResult(env, "trip/F")
        let child = try env.makeResult("trip/F/g.jpg")
        let other = try env.makeResult("trip/a.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([folder, child, other], env, expecting: 3)
        await finish(env)

        let outside = env.folder("moved/F")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder.url, to: outside)
        try FileManager.default.createDirectory(at: env.folder("trip/kyoto_new"), withIntermediateDirectories: true)
        await env.model.handleFileSystemEvent([env.folder("trip")])

        #expect(names(env.model) == ["a.jpg"])
        #expect(env.model.listing.search?.totalCount == 1)
        #expect(env.model.isShowingSearchResults)
    }

    @Test("Duplicating a folder row does not add the duplicate folder to results")
    func copiedFolderIsNotAdded() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeFolderResult(env, "trip/F")
        let child = try env.makeResult("trip/F/g.jpg")
        env.model.startSearch(pattern(), root: env.root)
        await send([folder, child], env, expecting: 2)
        await finish(env)

        try FileManager.default.copyItem(at: folder.url, to: env.folder("trip/F copy"))
        await env.model.reloadCurrentFolder()

        #expect(env.model.listing.search?.totalCount == 2)
        #expect(!names(env.model).contains("F copy"))
    }

    @Test("Renaming a folder outside the search root leaves results unchanged")
    func renamingFolderOutsideRootChangesNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeFolderResult(env, "trip/F")
        env.model.startSearch(pattern(), root: env.folder("trip"))
        await send([folder], env, expecting: 1)
        await finish(env)
        let before = env.model.listing.files.map(\.url)

        let (old, new) = try renameFolder(env, "empty", to: "empty2")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.model.listing.files.map(\.url) == before)
        #expect(env.searcher.requests.count == 1)
    }

    @Test("Renaming a folder without a result row after search completion starts no additional enumeration (EC-94, first half)")
    func renamingNonRowFolderAfterSearchDoesNotEnumerate() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let row = try makeFolderResult(env, "trip/F")
        let hidden = try makeFolderResult(env, "trip/zzz-inner")
        env.model.startSearch(pattern(), root: env.folder("trip"))
        await send([row], env, expecting: 1)
        await finish(env)
        let count = env.model.listing.files.count
        let totalCount = env.model.listing.search?.totalCount
        let requests = env.searcher.requests.count

        let (old, new) = try renameFolder(env, "trip/zzz-inner", to: "F-inner")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.searcher.requests.count == requests)
        #expect(env.model.listing.files.count == count)
        #expect(env.model.listing.search?.totalCount == totalCount)
        #expect(!names(env.model).contains("F-inner"))
        _ = hidden
    }

    @Test("Trashing an ancestor of the previous folder from search results keeps results open and removes rows (EC-101)")
    func trashingSearchFolderAncestorFromFileListKeepsResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let day1 = env.folder("trip/day1")
        await env.model.selectFolder(day1)
        let parent = try makeFolderResult(env, "trip")
        let inside = try env.makeResult("trip/trip_photo.jpg")
        var events: [LocationEvent] = []
        env.model.onLocationEvent = { events.append($0) }
        env.model.startSearch(pattern("trip"), root: env.root)
        await send([parent, inside], env, expecting: 2)
        await finish(env)
        let lastFolder = env.lastFolder
        let request = env.model.treeSyncRequest

        try FileManager.default.removeItem(at: env.folder("trip"))

        #expect(await env.model.leaveTrashedFolders([env.folder("trip")], origin: .fileList) == false)
        #expect(env.model.isShowingSearchResults)
        #expect(path(env.model.listing.folder) == path(day1))
        #expect(path(env.lastFolder) == path(lastFolder))
        #expect(env.model.treeSyncRequest == request)
        #expect(events.isEmpty)

        await env.model.reloadCurrentFolder()
        #expect(names(env.model).isEmpty)

        // Ending search results through the same path as Esc reports that the pre-search folder was not found.
        let target = env.model.listing.folder
        await env.model.selectFolder(target)
        #expect(!env.model.isShowingSearchResults)
        // Report not found after the navigation notification.
        #expect(events.last == .notFound(HistoryLocation(folder: day1)), "Received events: \(events)")
    }

    @Test("Trashing an ancestor of the previous folder via the tree still navigates up while search results are shown")
    func trashingSearchFolderAncestorFromTreeLeavesSearch() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.folder("trip/day1"))
        let parent = try makeFolderResult(env, "trip")
        env.model.startSearch(pattern("trip"), root: env.root)
        await send([parent], env, expecting: 1)
        await finish(env)

        try FileManager.default.removeItem(at: env.folder("trip"))

        #expect(await env.model.leaveTrashedFolders([env.folder("trip")], origin: .tree) == true)
        #expect(!env.model.isShowingSearchResults)
        #expect(path(env.model.listing.folder) == path(env.root))
    }

    @Test("Moving an ancestor of the previous folder in search results removes rows and keeps results open (EC-101, move)")
    func movingSearchFolderAncestorKeepsResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let day1 = env.folder("trip/day1")
        await env.model.selectFolder(day1)
        let parent = try makeFolderResult(env, "trip")
        let inside = try env.makeResult("trip/trip_photo.jpg")
        var events: [LocationEvent] = []
        env.model.onLocationEvent = { events.append($0) }
        env.model.startSearch(pattern("trip"), root: env.root)
        await send([parent, inside], env, expecting: 2)
        await finish(env)
        let lastFolder = env.lastFolder
        let request = env.model.treeSyncRequest

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelSearchTests-moved-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: env.folder("trip"), to: destination.appendingPathComponent("trip"))

        await env.model.reloadCurrentFolder()

        #expect(env.model.isShowingSearchResults)
        #expect(env.model.listing.files.isEmpty)
        #expect(path(env.model.listing.folder) == path(day1))
        #expect(path(env.lastFolder) == path(lastFolder))
        #expect(env.model.treeSyncRequest == request)

        await env.model.selectFolder(env.model.listing.folder)
        // Report not found after the navigation notification.
        #expect(events.last == .notFound(HistoryLocation(folder: day1)), "Received events: \(events)")
    }

    @Test("Deleting the search root with its folder row and descendant results removes everything and keeps results open (EC-36)")
    func searchRootDisappearsWithFolderRows() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let day1 = env.folder("trip/day1")
        await env.model.selectFolder(day1)
        let child = try makeFolderResult(env, "s/x")
        let other = try makeFolderResult(env, "s/y")
        let clip = try env.makeResult("s/x/clip.mp4")
        let image = try env.makeResult("s/y/a.jpg")
        let searchRoot = env.folder("s")
        env.model.startSearch(pattern(), root: searchRoot)
        await send([child, other, clip, image], env, expecting: 4)
        await finish(env)
        env.model.select([clip.url], focused: clip.url)
        let signal = env.model.stopPlaybackSignal
        let lastFolder = env.lastFolder
        let request = env.model.treeSyncRequest

        try FileManager.default.removeItem(at: searchRoot)
        await env.model.handleFileSystemEvent([searchRoot])

        #expect(env.model.listing.files.isEmpty)
        #expect(env.model.listing.state == .empty)
        #expect(env.model.isShowingSearchResults)
        #expect(env.model.listing.search?.keyword == "a")
        #expect(path(env.model.listing.search?.root) == path(searchRoot))
        #expect(path(env.model.listing.folder) == path(day1))
        #expect(path(env.lastFolder) == path(lastFolder))
        #expect(env.model.treeSyncRequest == request)
        #expect(env.model.stopPlaybackSignal > signal)
    }

    // MARK: - Renames During Search (EC-52, EC-94; FR-105)

    private func makeEmptyFolder(_ env: Env, _ path: String) throws -> URL {
        let url = env.folder(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Renaming an already evaluated folder does not recheck the new location during additional enumeration or add a row (EC-94, first half)")
    func renamingVisitedFolderDoesNotRecheckTheFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeEmptyFolder(env, "trip/zzz")
        env.model.startSearch(pattern("b"), root: env.folder("trip"))
        #expect(env.searcher.requests.count == 1)
        // Enumeration 0 matched and recorded F, but did not emit a row because the name did not match.
        env.searcher.requests[0].visits.record(folder.path)

        let (old, new) = try renameFolder(env, "trip/zzz", to: "bbb")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.searcher.requests.count == 2)
        #expect(path(env.searcher.requests.last?.root) == path(new))
        #expect(env.searcher.requests.last?.matchesRoot == false)
        #expect(env.model.listing.search?.totalCount == 0)
    }

    @Test("Renaming an unevaluated folder checks the new location as a root and discards old-location rows (EC-94, second half)")
    func renamingUnvisitedFolderRechecksTheFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeEmptyFolder(env, "trip/zzz")
        env.model.startSearch(pattern("b"), root: env.folder("trip"))

        let (old, new) = try renameFolder(env, "trip/zzz", to: "bbb")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.searcher.requests.count == 2)
        #expect(path(env.searcher.requests.last?.root) == path(new))
        #expect(env.searcher.requests.last?.matchesRoot == true)

        // Drop old-location rows from enumeration 0, which started before the rename.
        env.searcher.send([Env.folderResult(old)], to: 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(env.model.listing.search?.totalCount == 0)

        // Only the row from the additional enumeration remains under the new name.
        env.searcher.send([Env.folderResult(new)], to: 1)
        #expect(await waitUntil { env.model.listing.search?.totalCount == 1 })
        let row = try #require(env.model.listing.files.first)
        #expect(row.name == "bbb")
        #expect(path(row.url) == path(new))
        #expect(row.kind == .folder)
    }

    @Test("An already matched folder row keeps its new name and late descendant results use the new location (EC-52)")
    func renamingVisitedFolderKeepsRowAndReroutesResults() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeEmptyFolder(env, "trip/bbb")
        env.model.startSearch(pattern("b"), root: env.folder("trip"))
        env.searcher.requests[0].visits.record(folder.path)
        await send([Env.folderResult(folder)], env, expecting: 1)

        // The row remains even when it no longer matches the keyword.
        let (old, new) = try renameFolder(env, "trip/bbb", to: "zzz")
        env.model.didRenameFolder(from: old, to: new)

        let row = try #require(env.model.listing.files.first)
        #expect(row.name == "zzz")
        #expect(path(row.url) == path(new))

        // Results from enumeration 0 started before the rename are added at the new location.
        let inside = new.appendingPathComponent("b-1.jpg")
        env.searcher.send([Env.result(old.appendingPathComponent("b-1.jpg"))], to: 0)
        #expect(await waitUntil { env.model.listing.search?.totalCount == 2 })
        #expect(env.model.listing.files.contains { path($0.url) == path(inside) }, "Listing: \(names(env.model))")
    }

    @Test("An already evaluated folder row arriving after a rename is added with its new URL and name")
    func visitedFolderRowArrivingAfterRenameUsesNewName() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = try makeEmptyFolder(env, "trip/zzz")
        env.model.startSearch(pattern("b"), root: env.folder("trip"))
        env.searcher.requests[0].visits.record(folder.path)

        let (old, new) = try renameFolder(env, "trip/zzz", to: "bbb")
        env.model.didRenameFolder(from: old, to: new)

        env.searcher.send([Env.folderResult(old)], to: 0)

        #expect(await waitUntil { env.model.listing.search?.totalCount == 1 })
        let row = try #require(env.model.listing.files.first)
        #expect(row.name == "bbb")
        #expect(path(row.url) == path(new))
    }
}

/// Searcher that emits results in any order and at any time from tests. Records cancellation count.
private final class FakeSearcher: FileNameSearching, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<[MediaFile]>.Continuation] = []
    private var _requests: [(root: URL, pattern: SearchPattern, matchesRoot: Bool, visits: SearchVisitLog)] = []
    private var _cancelledCount = 0

    var requests: [(root: URL, pattern: SearchPattern, matchesRoot: Bool, visits: SearchVisitLog)] {
        lock.withLock { _requests }
    }

    var cancelledCount: Int {
        lock.withLock { _cancelledCount }
    }

    func search(_ request: SearchRequest) -> AsyncStream<[MediaFile]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [MediaFile].self)
        continuation.onTermination = { [weak self] reason in
            guard case .cancelled = reason, let self else { return }
            self.lock.withLock { self._cancelledCount += 1 }
        }
        lock.withLock {
            continuations.append(continuation)
            _requests.append((request.root, request.pattern, request.matchesRoot, request.visits))
        }
        return stream
    }

    /// Sends a batch to the most recently started search stream.
    func send(_ batch: [MediaFile]) {
        let continuation = lock.withLock { continuations.last }
        continuation?.yield(batch)
    }

    func finish() {
        let continuation = lock.withLock { continuations.last }
        continuation?.finish()
    }

    /// Sends a batch to the search stream started at `index`.
    func send(_ batch: [MediaFile], to index: Int) {
        let continuation = lock.withLock { continuations[index] }
        continuation.yield(batch)
    }

    func finish(at index: Int) {
        let continuation = lock.withLock { continuations[index] }
        continuation.finish()
    }
}
