import CoreGraphics
import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("ThumbnailProvider")
struct ThumbnailProviderTests {
    @Test("Rounds requested sizes up to 64, 128, 256, or 512")
    func roundsPointSizeToPixelSteps() {
        #expect(ThumbnailProvider.pixelSize(forPointSize: 16, scale: 1) == 64)
        #expect(ThumbnailProvider.pixelSize(forPointSize: 16, scale: 2) == 64)
        #expect(ThumbnailProvider.pixelSize(forPointSize: 50, scale: 1) == 64)
        #expect(ThumbnailProvider.pixelSize(forPointSize: 64, scale: 1) == 64)
        #expect(ThumbnailProvider.pixelSize(forPointSize: 64.1, scale: 1) == 128)
        #expect(ThumbnailProvider.pixelSize(forPointSize: 100, scale: 2) == 256)
        #expect(ThumbnailProvider.pixelSize(forPointSize: 300, scale: 2) == 512)
        #expect(ThumbnailProvider.pixelSize(forPointSize: 1000, scale: 1) == 512)
        #expect(ThumbnailProvider.pixelSize(forPointSize: .nan, scale: 1) == 64)
        #expect(ThumbnailProvider.pixelSize(forPointSize: .infinity, scale: 1) == 64)
    }

    @Test("Returns thumbnails for mixed JPEG and mp4 files", .timeLimit(.minutes(1)))
    func generatesThumbnailsForMixedFixtures() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FixtureSets.mixed(in: root)
        let folder = root.appendingPathComponent("mixed", isDirectory: true)
        let provider = ThumbnailProvider()

        let jpeg = await provider.thumbnail(
            for: folder.appendingPathComponent("01-photo.jpg"),
            pointSize: 100,
            scale: 2
        )
        #expect(jpeg != nil)
        if let jpeg {
            #expect(jpeg.width > 0)
            #expect(jpeg.height > 0)
        }

        let video = await provider.thumbnail(
            for: folder.appendingPathComponent("06-video.mp4"),
            pointSize: 100,
            scale: 2
        )
        #expect(video != nil)
        if let video {
            #expect(video.width > 0)
            #expect(video.height > 0)
        }
    }

    @Test("Returns nil for broken files without crashing", .timeLimit(.minutes(1)))
    func returnsNilForBrokenFixtures() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FixtureSets.broken(in: root)
        let folder = root.appendingPathComponent("broken", isDirectory: true)
        let provider = ThumbnailProvider()

        for name in ["truncated.jpg", "fake.jpg", "empty.mp4"] {
            let url = folder.appendingPathComponent(name)
            #expect(FileManager.default.fileExists(atPath: url.path))
            let image = await provider.thumbnail(for: url, pointSize: 100, scale: 2)
            #expect(image == nil)
        }
    }

    // MARK: - Images Inside a Zip

    @Test("Returns a downscaled image for a PNG inside a zip without using QuickLook", .timeLimit(.minutes(1)))
    func generatesThumbnailForImageInsideZip() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zip = try makeZip(in: root, entries: [
            ZipFixtureEntry(name: "pics/big.png", content: .bytes(try pngData(in: root, width: 800, height: 400)), method: .deflated),
        ])
        let provider = ThumbnailProvider(archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames))
        let url = ArchiveURL.entry(archive: zip, path: "pics/big.png")

        let image = await provider.thumbnail(for: url, pointSize: 50, scale: 2)
        let thumbnail = try #require(image)
        #expect(max(thumbnail.width, thumbnail.height) == 128)
        #expect(thumbnail.width > thumbnail.height)

        // The second call returns from the cache (the same CGImage).
        let again = await provider.thumbnail(for: url, pointSize: 50, scale: 2)
        #expect(again === thumbnail)
    }

    @Test("Returns nil for encrypted entries and broken videos and images inside a zip", .timeLimit(.minutes(1)))
    func returnsNilForUnreadableEntriesInsideZip() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let png = try pngData(in: root, width: 64, height: 64)
        let zip = try makeZip(in: root, entries: [
            ZipFixtureEntry(name: "locked.png", content: .bytes(png), encryptedFlag: true),
            ZipFixtureEntry(name: "clip.mp4", content: .bytes(Data("x".utf8))),
            ZipFixtureEntry(name: "broken.png", content: .bytes(Data("not an image".utf8))),
            ZipFixtureEntry(name: "odd.png", content: .bytes(png), method: .raw(99)),
            ZipFixtureEntry(name: "notes.txt", content: .bytes(Data("x".utf8))),
        ])
        let provider = ThumbnailProvider(archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames))

        for name in ["locked.png", "clip.mp4", "broken.png", "odd.png", "notes.txt", "missing.png"] {
            let image = await provider.thumbnail(
                for: ArchiveURL.entry(archive: zip, path: name),
                pointSize: 50,
                scale: 2
            )
            #expect(image == nil, "\(name)")
        }
    }

    @Test("Returns a downscaled first frame for an mp4 inside a zip and serves the second request from the cache", .timeLimit(.minutes(2)))
    func generatesThumbnailForVideoInsideZip() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // VideoFixtures blocks its thread while writing, so combine into one test to avoid overlap with parallel
        // tests.
        let video = root.appendingPathComponent("clip.mp4")
        try VideoFixtures.mp4(at: video, fastStart: false)
        let zip = try makeZip(in: root, entries: [
            ZipFixtureEntry(name: "movies/clip.mp4", content: .bytes(try Data(contentsOf: video)), method: .deflated),
        ])
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        let provider = ThumbnailProvider(archiveReader: reader)
        let url = ArchiveURL.entry(archive: zip, path: "movies/clip.mp4")

        let image = await provider.thumbnail(for: url, pointSize: 50, scale: 2)
        let thumbnail = try #require(image)
        #expect(thumbnail.width > 0)
        #expect(max(thumbnail.width, thumbnail.height) <= 128)

        let again = await provider.thumbnail(for: url, pointSize: 50, scale: 2)
        #expect(again === thumbnail)
    }

    @Test("Returns nil for URLs inside a zip when there is no archiveReader")
    func returnsNilForArchiveURLWithoutReader() async {
        let url = ArchiveURL.entry(archive: URL(fileURLWithPath: "/tmp/none.zip"), path: "a.png")
        let image = await ThumbnailProvider().thumbnail(for: url, pointSize: 50, scale: 2)
        #expect(image == nil)
    }

    @Test("Limits concurrent retrievals from a zip to 4", .timeLimit(.minutes(1)))
    func limitsConcurrentArchiveReads() async throws {
        let reader = SlowArchiveReader(delay: .milliseconds(50), data: try pngBytes(width: 32, height: 32))
        let provider = ThumbnailProvider(archiveReader: reader)
        let archive = URL(fileURLWithPath: "/tmp/none.zip")

        await withTaskGroup(of: CGImage?.self) { group in
            for index in 0..<12 {
                group.addTask {
                    await provider.thumbnail(
                        for: ArchiveURL.entry(archive: archive, path: "\(index).png"),
                        pointSize: 50,
                        scale: 2
                    )
                }
            }
            for await image in group {
                #expect(image != nil)
            }
        }

        let state = reader.snapshot()
        #expect(state.total == 12)
        #expect(state.maxRunning <= 4)
        #expect(state.maxRunning >= 2)
    }

    @Test("cancel(for:) cancels a zip request by URL and pixel size without affecting other sizes", .timeLimit(.minutes(1)))
    func cancelsArchiveRequestsByURLAndPixelSize() async throws {
        let reader = SlowArchiveReader(delay: .seconds(30), data: try pngBytes(width: 32, height: 32))
        let provider = ThumbnailProvider(archiveReader: reader)
        let url = ArchiveURL.entry(archive: URL(fileURLWithPath: "/tmp/none.zip"), path: "a.png")

        let small = Task { await provider.thumbnail(for: url, pointSize: 16, scale: 2) }
        let large = Task { await provider.thumbnail(for: url, pointSize: 100, scale: 2) }
        while reader.snapshot().running < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }

        provider.cancel(for: url, pointSize: 16, scale: 2)
        #expect(await small.value == nil)
        #expect(reader.snapshot().running == 1)

        provider.cancel(for: url, pointSize: 100, scale: 2)
        #expect(await large.value == nil)
        #expect(reader.snapshot().running == 0)
    }

    private func makeZip(in root: URL, entries: [ZipFixtureEntry]) throws -> URL {
        let zip = root.appendingPathComponent("sample-\(UUID().uuidString).zip")
        try ZipFixtureWriter.write(entries, to: zip)
        return zip
    }

    private func pngData(in root: URL, width: Int, height: Int) throws -> Data {
        let file = root.appendingPathComponent("src-\(UUID().uuidString).png")
        try ImageFixtures.png(at: file, width: width, height: height)
        return try Data(contentsOf: file)
    }

    private func pngBytes(width: Int, height: Int) throws -> Data {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        return try pngData(in: root, width: width, height: height)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Reader whose `data(for:)` takes a fixed time and records concurrency.
private final class SlowArchiveReader: ArchiveReading, @unchecked Sendable {
    struct Snapshot {
        var running = 0
        var maxRunning = 0
        var total = 0
    }

    private let delay: Duration
    private let payload: Data
    private let lock = NSLock()
    private var state = Snapshot()

    init(delay: Duration, data: Data) {
        self.delay = delay
        self.payload = data
    }

    func snapshot() -> Snapshot {
        lock.withLock { state }
    }

    func open(_ archive: URL) async throws(ArchiveError) -> ArchiveIndex {
        throw ArchiveError.notFound
    }

    func data(for entryURL: URL, limit: Int) async throws(ArchiveError) -> Data {
        lock.withLock {
            state.running += 1
            state.total += 1
            state.maxRunning = max(state.maxRunning, state.running)
        }
        defer { lock.withLock { state.running -= 1 } }
        do {
            try await Task.sleep(for: delay)
        } catch {
            throw ArchiveError.corrupted(.readCancelled)
        }
        return payload
    }

    func stream(for entryURL: URL) async throws(ArchiveError) -> ArchiveEntryStream {
        throw ArchiveError.notFound
    }

    func identity(of archive: URL) -> ArchiveIdentity? {
        nil
    }
}
