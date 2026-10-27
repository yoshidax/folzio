import Foundation
import Testing
@testable import FolzioCore

@Suite("FavoriteProbe")
struct FavoriteProbeTests {
    private func makeURLs(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/favorite-probe/\($0)", isDirectory: true) }
    }

    private func collect(_ stream: AsyncStream<FavoriteProbeResult>) async -> [FavoriteProbeResult] {
        var results: [FavoriteProbeResult] = []
        for await result in stream {
            results.append(result)
        }
        return results
    }

    @Test("True for an existing folder")
    func existingFolderExists() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(FavoriteProbe.folderExists(root))
    }

    @Test("False for a missing path")
    func missingPathDoesNotExist() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = root.appendingPathComponent("missing", isDirectory: true)
        #expect(!FavoriteProbe.folderExists(missing))
    }

    @Test("False for a regular file")
    func regularFileIsNotFolder() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("a.txt")
        try Data("a".utf8).write(to: file)
        #expect(!FavoriteProbe.folderExists(file))
    }

    @Test("True for a folder without permissions because it exists")
    func accessDeniedFolderExists() throws {
        let root = try makeTemporaryDirectory()
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        #expect(FavoriteProbe.folderExists(locked))
    }

    @Test("Emits each URL result once and keeps concurrency within the limit")
    func yieldsEveryURLOnceWithinLimit() async {
        let urls = makeURLs(6)
        let checker = FakeExistenceChecker()

        let results = await collect(FavoriteProbe.results(for: urls, maxConcurrent: 2) { await checker.exists($0) })

        #expect(results.count == 6)
        #expect(Set(results.map(\.url)) == Set(urls))
        #expect(await checker.started == 6)
        #expect(await checker.maxInFlight <= 2)
    }

    @Test("The exists result becomes FavoriteProbeResult.exists unchanged")
    func passesThroughExistence() async {
        let urls = makeURLs(4)
        let missing: Set<URL> = [urls[1], urls[3]]
        let checker = FakeExistenceChecker(missing: missing)

        let results = await collect(FavoriteProbe.results(for: urls, maxConcurrent: 2) { await checker.exists($0) })

        #expect(results.count == 4)
        for result in results {
            #expect(result.exists == !missing.contains(result.url))
        }
    }

    @Test("Finishes immediately for empty input")
    func finishesForEmptyInput() async {
        let checker = FakeExistenceChecker()
        let results = await collect(FavoriteProbe.results(for: []) { await checker.exists($0) })
        #expect(results.isEmpty)
        #expect(await checker.started == 0)
    }

    @Test("Treats a limit of 0 or less as 1")
    func treatsNonPositiveLimitAsOne() async {
        let urls = makeURLs(6)
        let checker = FakeExistenceChecker()

        let results = await collect(FavoriteProbe.results(for: urls, maxConcurrent: 0) { await checker.exists($0) })

        #expect(results.count == 6)
        #expect(await checker.maxInFlight == 1)
    }

    @Test("Does not start pending checks after leaving the stream")
    func stopsAfterTermination() async throws {
        let urls = makeURLs(20)
        let checker = FakeExistenceChecker()

        for await _ in FavoriteProbe.results(for: urls, maxConcurrent: 2, exists: { await checker.exists($0) }) {
            break
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(await checker.started < 20)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolzioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor FakeExistenceChecker {
    private let missing: Set<URL>
    private(set) var started = 0
    private(set) var maxInFlight = 0
    private var inFlight = 0

    init(missing: Set<URL> = []) {
        self.missing = missing
    }

    func exists(_ url: URL) async -> Bool {
        started += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }

        try? await Task.sleep(for: .milliseconds(20))
        return !missing.contains(url)
    }
}
