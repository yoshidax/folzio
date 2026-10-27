import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("FileNameSearcher", .serialized)
struct FileNameSearcherTests {
    private struct Env {
        let base: URL
        let root: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    private func makeEnv() throws -> Env {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNameSearcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FixtureSets.search(in: base)
        return Env(base: base, root: base.appendingPathComponent("search", isDirectory: true))
    }

    private func collect(
        _ searcher: FileNameSearcher = FileNameSearcher(kindNames: FixtureKit.kindNames),
        in root: URL,
        _ keyword: String
    ) async throws -> [[MediaFile]] {
        let pattern = try #require(SearchPattern(keyword: keyword))
        var batches: [[MediaFile]] = []
        for await batch in searcher.search(in: root, matching: pattern) {
            batches.append(batch)
        }
        return batches
    }

    /// Relative paths from the root (normalized to NFC). Also verifies that result URLs start with the root form.
    private func relativePaths(_ files: [MediaFile], root: URL) -> Set<String> {
        Set(files.map { file in
            #expect(file.url.path.hasPrefix(root.path + "/"), "URL has a different form from the root: \(file.url.path)")
            return String(file.url.path.dropFirst(root.path.count + 1)).precomposedStringWithCanonicalMapping
        })
    }

    // MARK: - Folder Matching (US15)

    private struct FolderSearchEnv {
        let base: URL
        let root: URL

        func cleanup() {
            try? FileManager.default.removeItem(at: base)
        }
    }

    private func makeFolderSearchEnv() throws -> FolderSearchEnv {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNameSearcherTests-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try FixtureSets.folderSearch(in: base)
        return FolderSearchEnv(
            base: base,
            root: base.appendingPathComponent("folder-search/Kyoto", isDirectory: true)
        )
    }

    @Test("Returns matching folders alongside files and excludes hidden items, packages, folder links, zip files, and the root")
    func folderSearchMatchesFolders() async throws {
        let env = try makeFolderSearchEnv()
        defer { env.cleanup() }

        let results = try await collect(in: env.root, "kyoto").flatMap { $0 }
        #expect(relativePaths(results, root: env.root) == [
            "2024_Kyoto",
            "2024_Kyoto_old",
            "clips/kyoto_clip.mov",
            "east/kyoto_day1",
            "kyoto",
            "kyoto/kyoto_01.jpg",
            "kyoto/kyoto_day2",
            "kyoto_map.png",
            "locked_kyoto",
            "locked_kyoto/secret_kyoto.jpg",
            "west/kyoto_day1",
        ])
        // Hidden folders, packages, links to folders, zip files, the root itself, and non-matching files inside.
        for excluded in [
            ".kyoto", "Kyoto.app", "kyoto_link", "kyoto.zip",
            "2024_Kyoto/IMG_0001.jpg", "kyoto/IMG_0002.jpg", ".",
        ] {
            #expect(
                !relativePaths(results, root: env.root).contains(excluded),
                "Unexpected result row: \(excluded)"
            )
        }

        func kind(_ relative: String) -> ListItemKind? {
            results.first { file in
                String(file.url.path.dropFirst(env.root.path.count + 1)) == relative
            }?.kind
        }
        #expect(kind("2024_Kyoto") == .folder)
        #expect(kind("kyoto") == .folder)
        #expect(kind("east/kyoto_day1") == .folder)
        #expect(kind("kyoto_map.png") == .media(.png))
        #expect(kind("clips/kyoto_clip.mov") == .media(.mov))
    }

    @Test("Wildcards match the entire folder name without treating dots as extensions")
    func folderSearchWildcardsAndDots() async throws {
        let env = try makeFolderSearchEnv()
        defer { env.cleanup() }

        // Whole-name match with a wildcard. Case-insensitive, so `locked_kyoto` matches, while `2024_Kyoto_old`,
        // which matches only in the middle, does not (US15-AS2).
        let kyoto2024 = try await collect(in: env.root, "*_Kyoto").flatMap { $0 }
        #expect(relativePaths(kyoto2024, root: env.root) == ["2024_Kyoto", "locked_kyoto"])
        #expect(!relativePaths(kyoto2024, root: env.root).contains("2024_Kyoto_old"))

        let dotted = try await collect(in: env.root, "2024.10").flatMap { $0 }
        #expect(relativePaths(dotted, root: env.root) == ["2024.10_trip"])

        let jpgFolders = try await collect(in: env.root, "*.jpg").flatMap { $0 }
        let photoFolder = try #require(jpgFolders.first { $0.name == "photos.jpg" })
        #expect(photoFolder.kind == .folder)
        #expect(jpgFolders.contains { $0.name == "kyoto_01.jpg" && $0.kind == .media(.jpeg) })
        #expect(!jpgFolders.contains { $0.name.hasSuffix(".png") })
    }

    @Test("A folder without permission becomes a row if its name matches but is not traversed (EC-33, EC-91)")
    func folderSearchUnreadableFolder() async throws {
        let env = try makeFolderSearchEnv()
        defer { env.cleanup() }

        let locked = env.root.appendingPathComponent("locked_kyoto", isDirectory: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let results = try await collect(in: env.root, "kyoto").flatMap { $0 }
        #expect(results.contains { $0.name == "locked_kyoto" && $0.kind == .folder })
        #expect(!results.contains { $0.name == "secret_kyoto.jpg" })
    }

    @Test("Folder row values match DirectoryLister folder rows")
    func folderRowValuesMatchLister() async throws {
        let env = try makeFolderSearchEnv()
        defer { env.cleanup() }

        let results = try await collect(in: env.root, "kyoto").flatMap { $0 }
        let row = try #require(results.first { $0.name == "kyoto_day1" && $0.url.deletingLastPathComponent().lastPathComponent == "east" })
        #expect(row.kind == .folder)
        #expect(row.typeDescription == FixtureKit.kindNames.folder)
        #expect(row.fileSize == 0)

        let listed = try #require(
            try await DirectoryLister(kindNames: FixtureKit.kindNames).mediaFiles(in: env.root.appendingPathComponent("east", isDirectory: true))
                .first { $0.name == "kyoto_day1" }
        )
        #expect(row.creationDate == listed.creationDate)
        #expect(row.name == listed.name)
        #expect(row.typeDescription == listed.typeDescription)
        #expect(row.fileSize == listed.fileSize)
        // Result URLs use the root form (/var/... for a /var/... root) and point at or below the root.
        #expect(row.url.path.hasPrefix(env.root.path + "/"))
    }

    @Test("Matches the root only when matchesRoot is true and excludes hidden and package roots")
    func matchesRootOption() async throws {
        let env = try makeFolderSearchEnv()
        defer { env.cleanup() }
        let pattern = try #require(SearchPattern(keyword: "kyoto"))
        let kyoto2024 = env.root.appendingPathComponent("2024_Kyoto", isDirectory: true)

        func search(root: URL, matchesRoot: Bool) async -> [MediaFile] {
            var found: [MediaFile] = []
            for await batch in FileNameSearcher(kindNames: FixtureKit.kindNames).search(
                SearchRequest(root: root, pattern: pattern, matchesRoot: matchesRoot)
            ) {
                found.append(contentsOf: batch)
            }
            return found
        }

        let withRoot = await search(root: kyoto2024, matchesRoot: true)
        #expect(withRoot.contains {
            $0.url.standardizedFileURL == kyoto2024.standardizedFileURL && $0.kind == .folder
        })
        let withoutRoot = await search(root: kyoto2024, matchesRoot: false)
        #expect(!withoutRoot.contains { $0.url.standardizedFileURL == kyoto2024.standardizedFileURL })

        let hiddenRoot = env.root.appendingPathComponent(".kyoto", isDirectory: true)
        #expect(!(await search(root: hiddenRoot, matchesRoot: true)).contains { $0.name == ".kyoto" })

        let packageRoot = env.root.appendingPathComponent("Kyoto.app", isDirectory: true)
        #expect(!(await search(root: packageRoot, matchesRoot: true)).contains { $0.name == "Kyoto.app" })
    }

    @Test("SC-053: Returns exactly 100 matches comprising 50 folders and 50 files")
    func scaleMatchingFoldersAndFiles() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNameSearcherTests-scale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let root = try FixtureSets.folderSearchScale(in: base)
        let results = try await collect(in: root, "kyoto").flatMap { $0 }

        #expect(results.count == 100, "Expected 100 matches (actual: \(results.count))")
        #expect(results.filter { $0.kind == .folder }.count == 50)
        #expect(results.filter { $0.kind.isMedia }.count == 50)
        #expect(!results.contains { $0.name.hasPrefix("kyoto-link-") })
        #expect(!results.contains { $0.name.hasPrefix("kyoto-package-") })
        #expect(!results.contains { $0.name.hasPrefix(".kyoto-hidden-") })
        #expect(!results.contains { $0.name.hasSuffix(".zip") })
        #expect(!results.contains { $0.name.hasPrefix("other-") })
        #expect(!results.contains { $0.url.standardizedFileURL == root.standardizedFileURL })
    }

    @Test("Records directories before matching but excludes files, hidden items, links, package contents, and the root")
    func recordsVisitedDirectories() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let pattern = try #require(SearchPattern(keyword: "cat"))
        let visits = SearchVisitLog()
        var found: [[MediaFile]] = []
        for await batch in FileNameSearcher(kindNames: FixtureKit.kindNames).search(
            SearchRequest(root: env.root, pattern: pattern, visits: visits)
        ) {
            found.append(batch)
        }
        // Verify after collecting results because the recorded path is used.
        #expect(!found.isEmpty)

        func path(_ relative: String) -> String {
            env.root.appendingPathComponent(relative).standardizedFileURL.path
        }

        for relative in ["a", "a/b", "a/b/deep", "b", "numbers", "kana", "cat-folder", "Viewer.app"] {
            #expect(visits.contains(path(relative)), "No record: \(relative)")
        }
        for relative in ["Cat01.jpg", ".hidden", "link", "Viewer.app/Contents", "cats.zip"] {
            #expect(!visits.contains(path(relative)), "Recorded: \(relative)")
        }
        #expect(!visits.contains(env.root.standardizedFileURL.path), "The root was recorded")

        // The protocol extension search(in:matching:) returns the same results as search(_:).
        let shortcut = try await collect(in: env.root, "cat").flatMap { $0 }
        #expect(relativePaths(shortcut, root: env.root) == relativePaths(found.flatMap { $0 }, root: env.root))
    }

    @Test("cat returns supported media and folders but excludes hidden items, packages, zip files, linked paths, and nonmatching descendants")
    func keywordCat() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let files = try await collect(in: env.root, "cat").flatMap { $0 }
        #expect(relativePaths(files, root: env.root) == [
            "Cat01.jpg", "a/my_cat.mov", "a/b/deep/cat-deep.png", "b/Cat01.jpg", "cat-folder",
        ])
        #expect(files.count == 5)
        // Descends into folders whose names match, but does not treat their contents as matches merely because the
        // parent matched (EC-92).
        #expect(!files.contains { $0.url.path.hasSuffix("cat-folder/x.jpg") })
        #expect(files.first { $0.name == "cat-folder" }?.kind == .folder)
    }

    @Test("Matches wildcards and NFD names")
    func wildcardsAndNormalization() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let png = try await collect(in: env.root, "*.png").flatMap { $0 }
        #expect(relativePaths(png, root: env.root) == ["a/dog.png", "a/b/deep/cat-deep.png", "kana/が.png"])
        let img = try await collect(in: env.root, "IMG_????.jpg").flatMap { $0 }
        #expect(relativePaths(img, root: env.root) == ["numbers/IMG_0001.jpg"])
        let ga = try await collect(in: env.root, "が").flatMap { $0 }
        #expect(relativePaths(ga, root: env.root) == ["kana/が.png"])
    }

    @Test("Returns file links as regular files and does not traverse folder links")
    func symbolicLinks() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let linked = try await collect(in: env.root, "linked").flatMap { $0 }
        #expect(relativePaths(linked, root: env.root) == ["linked.jpg"])
        let listed = try await DirectoryLister(kindNames: FixtureKit.kindNames).mediaFiles(in: env.root)
        #expect(listed.contains { $0.name == "linked.jpg" })

        let link = try await collect(in: env.root, "link").flatMap { $0 }
        #expect(relativePaths(link, root: env.root) == ["linked.jpg"])
        let dog = try await collect(in: env.root, "dog").flatMap { $0 }
        #expect(relativePaths(dog, root: env.root) == ["a/dog.png"])
    }

    @Test("Returned MediaFile values match DirectoryLister")
    func mediaFileValuesMatchLister() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let files = try await collect(in: env.root, "cat").flatMap { $0 }
        let top = try #require(files.first { $0.url.path == env.root.appendingPathComponent("Cat01.jpg").path })
        let movie = try #require(files.first { $0.name == "my_cat.mov" })
        #expect(top.kind == .media(.jpeg))
        #expect(movie.kind == .media(.mov))
        #expect(top.name == "Cat01.jpg")

        let listedTop = try #require(try await DirectoryLister(kindNames: FixtureKit.kindNames).mediaFiles(in: env.root).first { $0.name == "Cat01.jpg" })
        let listedMovie = try #require(
            try await DirectoryLister(kindNames: FixtureKit.kindNames).mediaFiles(in: env.root.appendingPathComponent("a", isDirectory: true))
                .first { $0.name == "my_cat.mov" }
        )
        for (found, listed) in [(top, listedTop), (movie, listedMovie)] {
            #expect(found.fileSize == listed.fileSize)
            #expect(found.creationDate == listed.creationDate)
            #expect(found.typeDescription == listed.typeDescription)
            #expect(!found.typeDescription.isEmpty)
        }
    }

    @Test("Skips subfolders without permission and completes")
    func skipsUnreadableFolders() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let denied = env.root.appendingPathComponent("denied", isDirectory: true)
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        try ImageFixtures.jpeg(at: denied.appendingPathComponent("cat-denied.jpg"), width: 8, height: 8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: denied.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: denied.path) }

        let files = try await collect(in: env.root, "cat").flatMap { $0 }
        // `denied` does not match cat, so it is not a row and cat-denied.jpg inside is not emitted. `cat-folder`
        // becomes a row.
        #expect(relativePaths(files, root: env.root) == [
            "Cat01.jpg", "a/my_cat.mov", "a/b/deep/cat-deep.png", "b/Cat01.jpg", "cat-folder",
        ])
    }

    @Test("Completes without yielding results for nonexistent roots and empty folders")
    func emptyAndMissingRoots() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let empty = env.base.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(try await collect(in: empty, "*").isEmpty)
        #expect(try await collect(in: env.base.appendingPathComponent("missing", isDirectory: true), "*").isEmpty)
    }

    @Test("Yields batches of at most batchSize items")
    func batches() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let batches = try await collect(FileNameSearcher(kindNames: FixtureKit.kindNames, batchSize: 2, batchInterval: .seconds(10)), in: env.root, "cat")
        #expect(batches.allSatisfy { $0.count <= 2 && !$0.isEmpty })
        #expect(batches.map(\.count).reduce(0, +) == 5)
    }

    /// Runs the receiver on the main actor as BrowserModel does (does not hang even when the cooperative thread pool
    /// is blocked).
    @Test("Cancelling the Task collecting the stream stops enumeration")
    @MainActor
    func cancellationStopsEnumeration() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileNameSearcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FixtureSets.huge(in: base)

        let counter = BatchCounter()
        let pattern = try #require(SearchPattern(keyword: "*"))
        let stream = FileNameSearcher(kindNames: FixtureKit.kindNames).search(in: base.appendingPathComponent("huge", isDirectory: true), matching: pattern)
        // Cancel the collecting task itself when the first batch arrives.
        let collector = Task { @MainActor in
            for await batch in stream {
                counter.add(batch.count)
                if counter.batches == 1 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
        }
        await collector.value
        let countAtCancel = counter.total
        try await Task.sleep(for: .milliseconds(500))

        #expect(counter.batches >= 1)
        #expect(counter.total == countAtCancel)
        #expect(countAtCancel < 10_000)
    }
}

@MainActor
private final class BatchCounter {
    private(set) var batches = 0
    private(set) var total = 0

    func add(_ count: Int) {
        batches += 1
        total += count
    }
}
