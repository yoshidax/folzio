import AVFoundation
import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

/// `VideoFixtures` blocks its thread while writing. Running in parallel can exhaust the cooperative thread pool
/// and hang, so run serially.
@Suite("ArchiveAssetLoader", .serialized)
struct ArchiveAssetLoaderTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let method: ZipFixtureEntry.Method
        let methodLabel: String
        var testDescription: String { "\(name) (\(methodLabel))" }
    }

    /// Four combinations: mp4 and mov (with playback metadata at the end), each stored or deflated.
    private static let cases: [Case] = [
        Case(name: "clip.mp4", method: .stored, methodLabel: "stored"),
        Case(name: "clip.mp4", method: .deflated, methodLabel: "deflated"),
        Case(name: "clip.mov", method: .stored, methodLabel: "stored"),
        Case(name: "clip.mov", method: .deflated, methodLabel: "deflated"),
    ]

    private struct Prepared {
        let original: URL
        let zip: URL
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveAssetLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Creates a video and stores it in a zip. Uses fastStart: false for both mov and mp4 (playback metadata at the
    /// end).
    private func prepare(_ testCase: Case, in directory: URL) throws -> Prepared {
        let original = directory.appendingPathComponent(testCase.name)
        if testCase.name.hasSuffix(".mov") {
            try VideoFixtures.mov(at: original, fastStart: false)
        } else {
            try VideoFixtures.mp4(at: original, fastStart: false)
        }
        let zip = directory.appendingPathComponent("video.zip")
        try ZipFixtureWriter.write([
            ZipFixtureEntry(name: testCase.name, content: .bytes(try Data(contentsOf: original)), method: testCase.method),
            ZipFixtureEntry(
                name: "secret.mp4", content: .bytes(try Data(contentsOf: original)), encryptedFlag: true
            ),
        ], to: zip)
        return Prepared(original: original, zip: zip)
    }

    @Test("Asset duration matches the original file and the asset has a video track", arguments: cases)
    func durationAndTracks(testCase: Case) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try prepare(testCase, in: directory)
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(prepared.zip)

        let asset = ArchiveAssetFactory.makeAsset(
            for: ArchiveURL.entry(archive: prepared.zip, path: testCase.name), reader: reader
        )
        let duration = try await asset.load(.duration)
        let expected = try await AVURLAsset(url: prepared.original).load(.duration)
        #expect(duration == expected)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(!tracks.isEmpty)
    }

    @Test("AVAssetImageGenerator returns the first frame", arguments: cases)
    func firstFrame(testCase: Case) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try prepare(testCase, in: directory)
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(prepared.zip)

        let asset = ArchiveAssetFactory.makeAsset(
            for: ArchiveURL.entry(archive: prepared.zip, path: testCase.name), reader: reader
        )
        let generator = AVAssetImageGenerator(asset: asset)
        let result = try await generator.image(at: .zero)
        #expect(result.image.width > 0)
    }

    @Test("Loading completes after the asset-creating function returns without retaining the loader externally")
    func loaderIsRetainedByAsset() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let testCase = Self.cases[1]
        let prepared = try prepare(testCase, in: directory)
        let url = ArchiveURL.entry(archive: prepared.zip, path: testCase.name)

        // Release the reader and loader inside this function and return only the asset.
        let asset: AVURLAsset = try await {
            let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
            _ = try await reader.open(prepared.zip)
            return ArchiveAssetFactory.makeAsset(for: url, reader: reader)
        }()
        let duration = try await asset.load(.duration)
        #expect(duration.seconds > 0)
    }

    @Test("load(.duration) fails for an asset with an encrypted entry")
    func encryptedEntryFails() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = try prepare(Self.cases[0], in: directory)
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(prepared.zip)

        let asset = ArchiveAssetFactory.makeAsset(
            for: ArchiveURL.entry(archive: prepared.zip, path: "secret.mp4"), reader: reader
        )
        await #expect(throws: (any Error).self) {
            _ = try await asset.load(.duration)
        }
    }
}
