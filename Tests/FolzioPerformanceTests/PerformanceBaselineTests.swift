import CoreGraphics
import Foundation
import Testing
import FixtureKit
@testable import FolzioCore

@Suite("PerformanceBaseline", .serialized)
struct PerformanceBaselineTests {
    @Test("Decodes a 24 MP JPEG within 0.5 seconds")
    func decodes24MegapixelJPEGWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("24mp.jpg")
        try ImageFixtures.jpeg(at: url, width: 6000, height: 4000)

        let decoder = ImageDecoder()
        let start = ContinuousClock.now
        let image = try await decoder.decode(url, maxPixelSize: 5120)
        let elapsed = ContinuousClock.now - start

        #expect(
            max(image.pixelSize.width, image.pixelSize.height) <= 5120,
            "The longest edge must be at most maxPixelSize (actual: \(image.pixelSize))"
        )
        #expect(
            elapsed < .milliseconds(500),
            "Decoding a 24 MP JPEG must take at most 0.5 seconds (measured: \(elapsed))"
        )
    }

    @Test("Switches to a cached adjacent file within 0.1 seconds")
    @MainActor
    func cachedNeighborSwitchWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let names = ["01.jpg", "02.jpg", "03.jpg"]
        for name in names {
            try ImageFixtures.jpeg(
                at: directory.appendingPathComponent(name),
                width: 1600,
                height: 1200
            )
        }

        let suite = "PerformanceBaselineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let cache = DecodedImageCache()
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: cache,
            settings: SettingsStore(defaults: defaults)
        )
        model.screenMaxPixel = 5120

        await model.selectFolder(directory)
        #expect(
            model.listing.files.map(\.name) == names,
            "Three items must be enumerated in name order (actual: \(model.listing.files.map(\.name)))"
        )
        guard model.listing.files.count == 3 else {
            Issue.record("At least 3 items are required to measure adjacent file switching")
            return
        }

        let previous = model.listing.files[0]
        let middle = model.listing.files[1]
        let next = model.listing.files[2]

        model.select([middle.url], focused: middle.url)
        let middleVisible = await waitUntil(timeout: .seconds(10)) {
            if case .image = model.preview {
                return model.selection.focused == middle.url
            }
            return false
        }
        #expect(middleVisible, "The middle file's preview is displayed")

        let previousCached = await waitForCache(cache, previous.url, timeout: .seconds(10))
        let nextCached = await waitForCache(cache, next.url, timeout: .seconds(10))
        #expect(previousCached, "The previous file is prefetched into the cache")
        #expect(nextCached, "The next file is prefetched into the cache")

        let start = ContinuousClock.now
        model.moveFocus(.next)
        let settled = await waitUntil(timeout: .seconds(10)) {
            if case .image = model.preview {
                return model.selection.focused == next.url
            }
            return false
        }
        let elapsed = ContinuousClock.now - start

        #expect(settled, "The next file's preview is displayed")
        #expect(model.selection.focused == next.url, "Focus moves to the next file")
        #expect(
            elapsed < .milliseconds(100),
            "Switching to a cached adjacent file must take at most 0.1 seconds (measured: \(elapsed))"
        )
    }

    @Test("Enumerates and sorts huge(10,000) within one second")
    func hugeFolderListingAndSortingWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FixtureSets.huge(in: directory, count: 10_000)
        let folder = directory.appendingPathComponent("huge", isDirectory: true)

        let lister = DirectoryLister(kindNames: FixtureKit.kindNames)
        let start = ContinuousClock.now
        let files = try await lister.mediaFiles(in: folder)
        let ordered = sorted(files, by: SortOrder())
        let elapsed = ContinuousClock.now - start

        #expect(files.count == 10_000, "10,000 items are enumerated (actual: \(files.count))")
        #expect(ordered.count == 10_000, "10,000 items are sorted (actual: \(ordered.count))")
        #expect(
            ordered.first?.name == "img_00001.jpg",
            "The first item in natural order must be img_00001.jpg (actual: \(ordered.first?.name ?? "nil"))"
        )
        #expect(
            elapsed < .seconds(1),
            "Enumerating and sorting 10,000 files must take at most one second (measured: \(elapsed))"
        )
    }

    @Test("Displays the first item within one second when returning to a 10,000-file folder")
    @MainActor
    func historyBackToHugeFolderWithinBudget() async throws {
        // Create 10,000 files off the MainActor so concurrent tests are not blocked.
        let directory = try await Task.detached(priority: .userInitiated) {
            let directory = try makeTemporaryDirectory()
            try FixtureSets.huge(in: directory, count: 10_000)
            let small = directory.appendingPathComponent("small", isDirectory: true)
            try FileManager.default.createDirectory(at: small, withIntermediateDirectories: true)
            try ImageFixtures.jpeg(at: small.appendingPathComponent("one.jpg"), width: 64, height: 64)
            return directory
        }.value
        defer { try? FileManager.default.removeItem(at: directory) }

        let huge = directory.appendingPathComponent("huge", isDirectory: true)
        let small = directory.appendingPathComponent("small", isDirectory: true)

        let suite = "PerformanceBaselineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(),
            settings: SettingsStore(defaults: defaults)
        )
        model.setNavigationRoots([directory])
        let navigator = HistoryNavigator(model: model)
        let host = PerformanceHistoryHost()
        navigator.presentationHost = host

        await model.selectFolder(huge)
        await model.selectFolder(small)
        #expect(navigator.canGoBack)

        let start = ContinuousClock.now
        navigator.goBack()
        let ready = await waitUntil(timeout: .seconds(10)) {
            model.listing.folder == huge
                && model.listing.state == .loaded
                && !model.listing.files.isEmpty
        }
        let elapsed = ContinuousClock.now - start

        #expect(ready, "A listing of 10,000 files is displayed")
        #expect(
            model.listing.files.filter { $0.kind != .parent }.count == 10_000,
            "The listing must contain 10,000 items (actual: \(model.listing.files.filter { $0.kind != .parent }.count))"
        )
        #expect(
            elapsed < .seconds(1),
            "Returning to a 10,000-file folder must display the first item within one second (measured: \(elapsed))"
        )
    }

    @Test("Applies media type filtering to 10,000 items within 0.05 seconds")
    func mediaTypeFilterOnHugeFolderWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FixtureSets.huge(in: directory, count: 10_000)
        let folder = directory.appendingPathComponent("huge", isDirectory: true)

        let lister = DirectoryLister(kindNames: FixtureKit.kindNames)
        let files = try await lister.mediaFiles(in: folder)
        let ordered = sorted(files, by: SortOrder())

        let start = ContinuousClock.now
        let images = MediaTypeFilter(imagesOnly: true).apply(to: ordered)
        let videos = MediaTypeFilter(videosOnly: true).apply(to: ordered)
        let elapsed = ContinuousClock.now - start

        #expect(images.count == 10_000, "Images only: 10,000 items (actual: \(images.count))")
        #expect(videos.isEmpty, "Videos only: 0 items (actual: \(videos.count))")
        #expect(
            elapsed < .milliseconds(50),
            "Applying media type filters must take at most 0.05 seconds (measured: \(elapsed))"
        )
    }

    @Test("Applies zip visibility to 10,000 items including zip files within 0.05 seconds")
    func zipFileVisibilityOnHugeFolderWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FixtureSets.huge(in: directory, count: 10_000)
        let folder = directory.appendingPathComponent("huge", isDirectory: true)

        let lister = DirectoryLister(kindNames: FixtureKit.kindNames)
        let files = try await lister.mediaFiles(in: folder)
        let ordered = sorted(files, by: SortOrder())

        // Exclude preparation (replacing one in ten rows with a zip file row) from measurement.
        var mixed = ordered
        for index in mixed.indices where index.isMultiple(of: 10) {
            var archive = mixed[index]
            archive.name = String(format: "img_%05d.zip", index + 1)
            archive.url = folder.appendingPathComponent(archive.name)
            archive.kind = .archive
            mixed[index] = archive
        }

        let start = ContinuousClock.now
        let hidden = ZipFileVisibility(showsZipFiles: false).apply(to: mixed)
        let shown = ZipFileVisibility(showsZipFiles: true).apply(to: mixed)
        let elapsed = ContinuousClock.now - start

        #expect(hidden.count == 9_000, "Hidden: 9,000 items (actual: \(hidden.count))")
        #expect(shown.count == 10_000, "Shown: 10,000 items (actual: \(shown.count))")
        print("[perf] ZipFileVisibility.apply 10,000 (hide + show): \(elapsed)")
        #expect(
            elapsed < .milliseconds(50),
            "Applying zip visibility must take at most 0.05 seconds (measured: \(elapsed))"
        )
    }

    @Test("Toggles zip visibility in a 10,000-file folder within 0.2 seconds")
    @MainActor
    func toggleZipFileVisibilityOnHugeFolderWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FixtureSets.huge(in: directory, count: 10_000)
        let folder = directory.appendingPathComponent("huge", isDirectory: true)

        // Exclude preparation (replacing one in ten rows with a zip file) from measurement.
        let template = directory.appendingPathComponent("template.zip")
        try ZipFixtureWriter.write([], to: template)
        let fileManager = FileManager.default
        for index in stride(from: 0, to: 10_000, by: 10) {
            try fileManager.removeItem(at: folder.appendingPathComponent(String(format: "img_%05d.jpg", index + 1)))
            try fileManager.copyItem(
                at: template,
                to: folder.appendingPathComponent(String(format: "img_%05d.zip", index + 1))
            )
        }

        let suite = "PerformanceBaselineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(),
            settings: SettingsStore(defaults: defaults)
        )

        await model.selectFolder(folder)
        #expect(model.listing.files.count == 9_000, "Hidden by default: 9,000 items (actual: \(model.listing.files.count))")

        let showStart = ContinuousClock.now
        model.setShowsZipFiles(true)
        let showElapsed = ContinuousClock.now - showStart
        #expect(model.listing.files.count == 10_000, "Shown: 10,000 items (actual: \(model.listing.files.count))")

        let hideStart = ContinuousClock.now
        model.setShowsZipFiles(false)
        let hideElapsed = ContinuousClock.now - hideStart
        #expect(model.listing.files.count == 9_000, "Hidden: 9,000 items (actual: \(model.listing.files.count))")

        print("[perf] setShowsZipFiles 10,000: show \(showElapsed), hide \(hideElapsed)")
        #expect(showElapsed < .milliseconds(200), "Switching to shown takes at most 0.2 seconds (measured: \(showElapsed))")
        #expect(hideElapsed < .milliseconds(200), "Switching to hidden takes at most 0.2 seconds (measured: \(hideElapsed))")
    }

    @Test("didRenameFolder handles 10,000 search results including folder rows within 0.1 seconds")
    @MainActor
    func renameFolderWithHugeSearchResultsWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        try FixtureSets.huge(in: directory, count: 10_000)
        // Include the renamed folder's own row and 100 other folder rows in the results (R4, R9).
        let seeded = directory.appendingPathComponent("huge", isDirectory: true)
        for index in 0 ..< 100 {
            try FileManager.default.createDirectory(
                at: seeded.appendingPathComponent(String(format: "img-folder-%03d", index), isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        let folder = directory.appendingPathComponent("img-huge", isDirectory: true)
        try FileManager.default.moveItem(at: seeded, to: folder)
        let expectedCount = 10_000 + 1 + 100

        let suite = "PerformanceBaselineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(),
            settings: SettingsStore(defaults: defaults)
        )

        // Exclude waiting for the search to finish and the on-disk rename from measurement.
        model.startSearch(try #require(SearchPattern(keyword: "img")), root: directory)
        let finished = await waitUntil(timeout: .seconds(30)) { model.listing.search?.phase == .finished }
        #expect(finished, "The search finishes")
        #expect(
            model.listing.search?.totalCount == expectedCount,
            "10,101 items (actual: \(model.listing.search?.totalCount ?? -1))"
        )
        #expect(model.listing.files.filter { $0.kind == .folder }.count == 101, "There are 101 folder rows")
        // To avoid outliers on loaded machines, alternate names and measure three times, using the median.
        let names = ["img-huge2", "img-huge", "img-huge2"]
        var current = folder
        var samples: [Duration] = []
        for name in names {
            let next = directory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.moveItem(at: current, to: next)

            let start = ContinuousClock.now
            model.didRenameFolder(from: current, to: next)
            samples.append(ContinuousClock.now - start)

            let mediaMoved = model.listing.files
                .filter(\.kind.isMedia)
                .allSatisfy { $0.url.deletingLastPathComponent().lastPathComponent == name }
            #expect(mediaMoved, "All media rows move to the new location (\(name))")
            // The renamed folder's own row gets the new URL and name.
            let renamedRow = model.listing.files.first {
                $0.kind == .folder && $0.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
            }
            #expect(renamedRow?.name == name, "The folder row name becomes \(name)")
            #expect(renamedRow?.url.standardizedFileURL.path == next.standardizedFileURL.path)
            #expect(model.listing.files.filter { $0.kind == .folder }.count == 101, "Other folder rows remain")
            current = next
        }
        let median = samples.sorted()[1]
        print("[perf] didRenameFolder 10,000 search results with folders: \(samples), median \(median)")
        #expect(median < .milliseconds(100), "Rebasing after rename takes at most 0.1 seconds (median: \(median), measured: \(samples))")
    }

    @Test("hasSubfolders checks a 10,000-file folder without subfolders within 0.2 seconds")
    func hasSubfoldersInLargeFolderWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<10_000 {
            let path = directory.appendingPathComponent(String(format: "%05d.jpg", index)).path
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        let lister = DirectoryLister(kindNames: FixtureKit.kindNames)
        let start = ContinuousClock.now
        let hasSubfolders = try await lister.hasSubfolders(in: directory)
        let elapsed = ContinuousClock.now - start

        #expect(!hasSubfolders, "There are no subfolders")
        #expect(
            elapsed < .milliseconds(200),
            "Checking for subfolders in a 10,000-file folder must take at most 0.2 seconds (measured: \(elapsed))"
        )
    }

    @Test("Enumerates a folder with 10,000 files and 1,000 subfolders within one second")
    func listsLargeFolderWithSubfoldersWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        for index in 0..<10_000 {
            let path = directory.appendingPathComponent(String(format: "%05d.jpg", index)).path
            FileManager.default.createFile(atPath: path, contents: nil)
        }
        for index in 0..<1_000 {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(String(format: "folder-%04d", index), isDirectory: true),
                withIntermediateDirectories: false
            )
        }

        let lister = DirectoryLister(kindNames: FixtureKit.kindNames)
        let start = ContinuousClock.now
        let files = try await lister.mediaFiles(in: directory)
        let elapsed = ContinuousClock.now - start

        #expect(files.count == 11_000)
        #expect(files.filter { $0.kind == .folder }.count == 1_000)
        print("mediaFiles(in:) 10,000 files + 1,000 folders: \(elapsed)")
        #expect(
            elapsed < .seconds(1),
            "Enumerating 10,000 files and 1,000 subfolders must take at most one second, as in SC-003 (measured: \(elapsed))"
        )
    }

    @Test("Decodes a 100 MP grayscale PNG while limiting byte cost")
    func decodesHundredMegapixelPNGWithinMemoryBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("big.png")
        try ImageFixtures.grayscalePNG(at: url, width: 10_000, height: 10_000)

        let decoder = ImageDecoder()
        let image = try await decoder.decode(url, maxPixelSize: 5120)

        let maximumByteCost = 5120 * 5120 * 4
        let longSide = max(image.pixelSize.width, image.pixelSize.height)

        #expect(
            image.byteCost <= maximumByteCost,
            "byteCost must be at most 5120x5120x4 (actual: \(image.byteCost))"
        )
        #expect(
            longSide <= 5120,
            "The longest edge must be at most 5120 px (actual: \(image.pixelSize))"
        )
        #expect(
            image.originalPixelSize.width == 10_000 && image.originalPixelSize.height == 10_000,
            "The original size must be 10000x10000 (actual: \(image.originalPixelSize))"
        )
    }

    @Test("Preview cache stays at or below 256 MB after 100 consecutive focus moves")
    @MainActor
    func repeatedFocusMovesStayWithinCacheLimit() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let folder = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 1...100 {
            try ImageFixtures.jpeg(
                at: folder.appendingPathComponent(String(format: "img_%03d.jpg", index)),
                width: 1024,
                height: 768
            )
        }

        let suite = "PerformanceBaselineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let cache = DecodedImageCache()
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: cache,
            settings: SettingsStore(defaults: defaults)
        )

        await model.selectFolder(folder)
        #expect(model.listing.files.count == 100, "100 items are enumerated (actual: \(model.listing.files.count))")
        guard model.listing.files.count == 100 else {
            Issue.record("At least 100 items are required to measure focus movement")
            return
        }

        let first = model.listing.files[0]
        model.select([first.url], focused: first.url)

        for _ in 0..<100 {
            model.moveFocus(.next)
        }

        let settled = await waitUntil(timeout: .seconds(30)) {
            if case .image = model.preview {
                return true
            }
            return false
        }
        #expect(settled, "After 100 moves, the preview settles as an image")

        let isUnavailable: Bool
        if case .unavailable = model.preview {
            isUnavailable = true
        } else {
            isUnavailable = false
        }
        #expect(!isUnavailable, "The preview does not remain in an error state")

        let totalCost = await cache.totalCost
        #expect(
            totalCost <= MemoryLimits.previewCacheBytes,
            "Cache totalCost must be at most 256 MB (actual: \(totalCost) bytes)"
        )
        #expect(
            model.selection.focused == model.listing.files.last?.url,
            "The last file must be focused"
        )
    }

    @Test("Opening a 10,000-entry zip and calling items(in:) takes at most 0.5 seconds in total")
    func opensLargeArchiveWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Exclude zip creation time from measurement.
        let zip = try makeLargeZip(in: directory)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        let start = ContinuousClock.now
        let index = try await reader.open(zip)
        let items = index.items(in: "")
        let elapsed = ContinuousClock.now - start

        print("ZipArchiveReader.open + items(in:) for 10,000 entries: \(elapsed)")
        #expect(items.count == 10_000, "10,000 items are enumerated (actual: \(items.count))")
        #expect(
            elapsed < .milliseconds(500),
            "Opening a 10,000-entry zip and listing items must take at most 0.5 seconds (measured: \(elapsed))"
        )
    }

    /// `items(in:)` is called from `BrowserModel` on the MainActor after the zip opens. Rows are built in the
    /// background by `open` and are not built here (zero stops of 100 ms or more for SC-015).
    @Test("items(in:) takes at most 10 ms after opening a 10,000-entry zip (SC-015)")
    func archiveItemsAreReadyAfterOpen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let zip = try makeLargeZip(in: directory)
        let index = try await ZipArchiveReader(kindNames: FixtureKit.kindNames).open(zip)

        let start = ContinuousClock.now
        let items = index.items(in: "")
        let elapsed = ContinuousClock.now - start

        print("ArchiveIndex.items(in:) for 10,000 entries: \(elapsed)")
        #expect(items.count == 10_000, "10,000 items are enumerated (actual: \(items.count))")
        #expect(elapsed < .milliseconds(10), "items(in:) takes at most 10 ms (measured: \(elapsed))")
    }

    /// Zip of 10,000 small JPEGs (1 KB each, stored).
    private func makeLargeZip(in directory: URL) throws -> URL {
        let zip = directory.appendingPathComponent("large.zip")
        let body = Data(repeating: 0xAB, count: 1024)
        let entries = (0..<10_000).map { index in
            ZipFixtureEntry(
                name: String(format: "img_%05d.jpg", index),
                content: .bytes(body),
                method: .stored
            )
        }
        try ZipFixtureWriter.write(entries, to: zip)
        return zip
    }

    @Test("Streaming a 1 GB deflate entry increases phys_footprint by at most 128 MB (SC-014)")
    func entryStreamReadsStayWithinMemoryBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Store 1 GB of zeros with deflate. Exclude zip creation time from measurement.
        let zip = directory.appendingPathComponent("big-deflated.zip")
        let length: UInt64 = 1 << 30
        try ZipFixtureWriter.write(
            [ZipFixtureEntry(name: "zeros.mp4", content: .zeros(count: length), method: .deflated)],
            to: zip
        )

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        let stream = try await reader.stream(for: ArchiveURL.entry(archive: zip, path: "zeros.mp4"))
        #expect(stream.length == length, "The inflated size is 1 GB (actual: \(stream.length))")

        let chunk = 512 * 1024
        let mebibyte: UInt64 = 1 << 20
        // Read 512 KB at a time from start to end, then 4 MB each from positions 900 MB, 100 MB, and 10 MB
        // (backward).
        var plan: [(offset: UInt64, count: Int)] = []
        var position: UInt64 = 0
        while position < length {
            plan.append((position, chunk))
            position += UInt64(chunk)
        }
        for startMiB in [UInt64(900), 100, 10] {
            for step in 0..<(4 * 1024 * 1024 / chunk) {
                plan.append((startMiB * mebibyte + UInt64(step * chunk), chunk))
            }
        }

        let baseline = physicalFootprint()
        var maximumIncrease: Int64 = 0
        var readBytes = 0
        let start = ContinuousClock.now
        for (index, step) in plan.enumerated() {
            let data = try stream.read(offset: step.offset, maxLength: step.count)
            readBytes += data.count
            if (index + 1) % 64 == 0 || index == plan.count - 1 {
                maximumIncrease = max(maximumIncrease, Int64(physicalFootprint()) - Int64(baseline))
            }
        }
        let elapsed = ContinuousClock.now - start

        print("ArchiveEntryStream 1 GB deflate: maximum increase \(maximumIncrease / 1_048_576) MB (\(maximumIncrease) bytes), elapsed \(elapsed), reads \(plan.count)")
        #expect(readBytes > 0)
        #expect(
            maximumIncrease <= 128 * 1024 * 1024,
            "The maximum phys_footprint increase sampled every 64 reads must be at most 128 MB (measured: \(maximumIncrease) bytes)"
        )
    }

    // MARK: - File Name Search (FR-085, SC-016)

    @Test("Searches a 10,000-file hierarchy within three seconds (SC-016)")
    func searchingTenThousandFilesWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let templateURL = directory.appendingPathComponent("template.jpg")
        try ImageFixtures.jpeg(at: templateURL, width: 8, height: 8)
        let template = try Data(contentsOf: templateURL)
        try FileManager.default.removeItem(at: templateURL)
        let root = directory.appendingPathComponent("tree", isDirectory: true)
        for folderIndex in 0..<100 {
            let folder = root.appendingPathComponent(String(format: "folder-%03d", folderIndex), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for fileIndex in 0..<100 {
                let name = fileIndex.isMultiple(of: 2)
                    ? String(format: "cat_%03d.jpg", fileIndex)
                    : String(format: "dog_%03d.jpg", fileIndex)
                try template.write(to: folder.appendingPathComponent(name))
            }
        }

        let pattern = try #require(SearchPattern(keyword: "cat"))
        let start = ContinuousClock.now
        var count = 0
        for await batch in FileNameSearcher(kindNames: FixtureKit.kindNames).search(in: root, matching: pattern) {
            count += batch.count
        }
        let elapsed = ContinuousClock.now - start

        #expect(count == 5_000, "Half of the items, 5,000, are found (actual: \(count))")
        #expect(elapsed < .seconds(3), "Searching a 10,000-file hierarchy takes at most 3 seconds (measured: \(elapsed))")
        print("[perf] search 10,000 files: \(elapsed)")
    }

    @Test("Searches a 10,000-file hierarchy including folder-name matching within three seconds (SC-054)")
    func searchingFoldersAndFilesWithinBudget() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let templateURL = directory.appendingPathComponent("template.jpg")
        try ImageFixtures.jpeg(at: templateURL, width: 8, height: 8)
        let template = try Data(contentsOf: templateURL)
        try FileManager.default.removeItem(at: templateURL)
        // The same 100 folders × 100 files as SC-016. Half of the folder names (50) contain the keyword.
        let root = directory.appendingPathComponent("tree", isDirectory: true)
        for folderIndex in 0 ..< 100 {
            let folderName = folderIndex.isMultiple(of: 2)
                ? String(format: "cat-folder-%03d", folderIndex)
                : String(format: "folder-%03d", folderIndex)
            let folder = root.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for fileIndex in 0 ..< 100 {
                let fileName = fileIndex.isMultiple(of: 2)
                    ? String(format: "cat_%03d.jpg", fileIndex)
                    : String(format: "dog_%03d.jpg", fileIndex)
                try template.write(to: folder.appendingPathComponent(fileName))
            }
        }

        let pattern = try #require(SearchPattern(keyword: "cat"))
        let start = ContinuousClock.now
        var folderCount = 0
        var fileCount = 0
        var matchingFolderNames: [String] = []
        for await batch in FileNameSearcher(kindNames: FixtureKit.kindNames).search(in: root, matching: pattern) {
            for file in batch {
                if file.kind == .folder {
                    folderCount += 1
                    matchingFolderNames.append(file.name)
                } else if file.kind.isMedia {
                    fileCount += 1
                }
            }
        }
        let elapsed = ContinuousClock.now - start

        #expect(folderCount == 50, "50 folders match (actual: \(folderCount))")
        #expect(fileCount == 5_000, "5,000 files match (actual: \(fileCount))")
        // folder-%03d does not contain cat, so the SC-016 search (5,000 files only) is unchanged.
        #expect(!matchingFolderNames.contains { $0.hasPrefix("folder-") })
        #expect(elapsed < .seconds(3), "Searching 10,000 files including folders takes at most 3 seconds (measured: \(elapsed))")
        print("[perf] search 10,000 files with folders: \(elapsed), folders \(folderCount), files \(fileCount)")
    }

    @Test("Merges 256 items into 10,000 items within 0.05 seconds (FR-085)")
    @MainActor
    func mergingBatchIntoTenThousandWithinBudget() async throws {
        let order = SortOrder()
        let existing = sorted(syntheticResults(count: 10_000, folders: 1, prefix: "img"), by: order)
        let batch = sorted(syntheticResults(count: 256, folders: 1, prefix: "img", offset: 10_000), by: order)

        let mergeStart = ContinuousClock.now
        let merged = sortedMerge(existing, batch, by: order)
        let mergeElapsed = ContinuousClock.now - mergeStart
        #expect(merged.count == 10_256)
        #expect(mergeElapsed < .milliseconds(50), "sortedMerge takes at most 0.05 seconds (measured: \(mergeElapsed))")

        let modelElapsed = try await measureBatch(existing: existing, batch: batch)
        #expect(modelElapsed < .milliseconds(50), "BrowserModel processing one batch takes at most 0.05 seconds (measured: \(modelElapsed))")
        print("[perf] merge 256 into 10,000: sortedMerge \(mergeElapsed), BrowserModel \(modelElapsed)")
    }

    @Test("Processes a 256-item batch against 50,000 items in under 100 ms (FR-085, SC-016)")
    @MainActor
    func processingBatchIntoFiftyThousandWithinBudget() async throws {
        let order = SortOrder()
        let existing = sorted(syntheticResults(count: 50_000, folders: 500, prefix: "photo"), by: order)
        let batch = sorted(syntheticResults(count: 256, folders: 500, prefix: "photo", offset: 50_000), by: order)

        let elapsed = try await measureBatch(existing: existing, batch: batch)
        #expect(elapsed < .milliseconds(100), "Processing one batch into 50,000 items takes less than 100 ms (measured: \(elapsed))")
        print("[perf] batch 256 into 50,000: \(elapsed)")
    }

    /// Time from sending `batch` to the listing count increasing after `existing` from the fake searcher.
    @MainActor
    private func measureBatch(existing: [MediaFile], batch: [MediaFile]) async throws -> Duration {
        let suite = "PerformanceBaselineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let searcher = StreamingSearcher()
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(),
            settings: SettingsStore(defaults: defaults),
            searcher: searcher
        )
        model.startSearch(try #require(SearchPattern(keyword: "*")), root: URL(fileURLWithPath: "/r", isDirectory: true))
        searcher.send(existing)
        let loaded = await waitUntil { model.listing.files.count == existing.count }
        #expect(loaded, "Existing results enter the listing (actual: \(model.listing.files.count))")

        let start = ContinuousClock.now
        searcher.send(batch)
        while model.listing.files.count == existing.count, ContinuousClock.now - start < .seconds(5) {
            await Task.yield()
        }
        let elapsed = ContinuousClock.now - start
        #expect(model.listing.files.count == existing.count + batch.count)
        return elapsed
    }

    /// Search results that do not use the disk. Spread across `folders` folders.
    private func syntheticResults(count: Int, folders: Int, prefix: String, offset: Int = 0) -> [MediaFile] {
        (0..<count).map { index in
            let serial = index + offset
            let folder = "/r/folder-\(serial % folders)"
            let name = "\(prefix)_\((serial * 7_919) % 1_000_003).jpg"
            return MediaFile(
                url: URL(fileURLWithPath: "\(folder)/\(serial)-\(name)"),
                name: name,
                kind: .media(.jpeg),
                typeDescription: "JPEG イメージ",
                creationDate: nil,
                fileSize: 0
            )
        }
    }
}

@Test("Converts row indices for 5,000 selected items among 10,000 rows in under 100 ms (FR-016, SC-003)")
func selectionIndexTenThousandRows() {
    let urls = (0..<10_000).map {
        URL(fileURLWithPath: "/selection/\($0)", isDirectory: true)
    }
    var selected: Set<URL> = []
    selected.reserveCapacity(5_000)
    for index in stride(from: 0, to: urls.count, by: 2) {
        selected.insert(urls[index])
    }

    let start = ContinuousClock.now
    let indexes = SelectionIndex.indexes(of: selected, in: urls)
    let elapsed = ContinuousClock.now - start
    print("[perf] selection index 10,000 rows / 5,000 selected: \(elapsed)")
    #expect(indexes.count == 5_000)
    #expect(indexes.first == 0)
    #expect(indexes.last == 9_998)
    #expect(elapsed < .milliseconds(100), "Selection synchronization does not stall for 100 ms or more")
}

/// `phys_footprint` of the current process in bytes.
private func physicalFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FolzioPerformanceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(5),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

private func waitForCache(
    _ cache: DecodedImageCache,
    _ url: URL,
    timeout: Duration = .seconds(10)
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await cache.get(url) != nil {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await cache.get(url) != nil
}

/// Searcher that emits results at any time from tests.
private final class StreamingSearcher: FileNameSearching, @unchecked Sendable {
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
}

@MainActor
private final class PerformanceHistoryHost: HistoryPresentationHost {
    var presentation = HistoryPresentation(
        displayMode: .list,
        thumbnailSize: ViewSettings.defaultThumbnailSize,
        paneLayout: .all
    )

    var historyPresentation: HistoryPresentation { presentation }

    func applyHistoryPresentation(_ presentation: HistoryPresentation) {
        self.presentation = presentation
    }
}
