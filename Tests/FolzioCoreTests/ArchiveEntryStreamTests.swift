import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("ArchiveEntryStream")
struct ArchiveEntryStreamTests {
    private static let size = 5 * 1024 * 1024
    private static let mb = 1 << 20

    /// Repeats 0–255 so the value identifies the position.
    private static let content: Data = {
        var data = Data(count: size)
        for index in 0..<size { data[index] = UInt8(truncatingIfNeeded: index) }
        return data
    }()

    private func makeZip(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("stream.zip")
        try ZipFixtureWriter.write([
            ZipFixtureEntry(name: "stored.mp4", content: .bytes(Self.content), method: .stored),
            ZipFixtureEntry(name: "deflated.mp4", content: .bytes(Self.content), method: .deflated),
            ZipFixtureEntry(name: "secret.mp4", content: .bytes(Data("s".utf8)), encryptedFlag: true),
            ZipFixtureEntry(name: "bzip2.mp4", content: .bytes(Data("s".utf8)), method: .raw(12)),
        ], to: url)
        return url
    }

    private func expected(_ offset: Int, _ length: Int) -> Data {
        let end = min(offset + length, Self.size)
        return offset >= end ? Data() : Self.content.subdata(in: offset..<end)
    }

    private func openStream(_ name: String, in directory: URL) async throws -> ArchiveEntryStream {
        let zip = try makeZip(in: directory)
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        return try await reader.stream(for: ArchiveURL.entry(archive: zip, path: name))
    }

    private static let names = ["stored.mp4", "deflated.mp4"]

    @Test("length matches the inflated size", arguments: names)
    func length(name: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try await openStream(name, in: directory)
        #expect(stream.length == UInt64(Self.size))
    }

    @Test("Reads at the start, across a boundary, before the end, at the end, and past the end", arguments: names)
    func readsPositions(name: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try await openStream(name, in: directory)
        let cases: [(Int, Int)] = [
            (0, 1000),
            (Self.mb - 500, 1000),
            (Self.size - 300, 1000),
            (Self.size, 100),
            (Self.size + 5000, 100),
            (0, 0),
        ]
        for (offset, length) in cases {
            let data = try stream.read(offset: UInt64(offset), maxLength: length)
            #expect(data == expected(offset, length), "offset \(offset)")
        }
        #expect(try stream.read(offset: UInt64(Self.size), maxLength: 100).isEmpty)
        #expect(try stream.read(offset: UInt64(Self.size + 5000), maxLength: 100).isEmpty)
    }

    @Test("deflate matches when read in an order that includes backward reads")
    func deflateBackwards() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try await openStream("deflated.mp4", in: directory)
        for offset in [4 * Self.mb, Self.mb, 3 * Self.mb, 0] {
            let data = try stream.read(offset: UInt64(offset), maxLength: 4096)
            #expect(data == expected(offset, 4096), "offset \(offset)")
        }
    }

    @Test("deflate matches when two distant ranges are read alternately 20 times")
    func deflateAlternating() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try await openStream("deflated.mp4", in: directory)
        for round in 0..<20 {
            let offset = round % 2 == 0 ? 100 : 4 * Self.mb + 77
            #expect(try stream.read(offset: UInt64(offset), maxLength: 2048) == expected(offset, 2048))
        }
    }

    @Test("Reads separate ranges concurrently from multiple tasks", arguments: names)
    func concurrentReads(name: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try await openStream(name, in: directory)
        let content = Self.content
        let size = Self.size
        let failures = await withTaskGroup(of: Int.self) { group in
            for task in 0..<8 {
                group.addTask {
                    var bad = 0
                    for round in 0..<10 {
                        let offset = ((task * 7 + round * 13) * 123_457) % size
                        let end = min(offset + 3000, size)
                        let data = try? stream.read(offset: UInt64(offset), maxLength: 3000)
                        if data != content.subdata(in: offset..<end) { bad += 1 }
                    }
                    return bad
                }
            }
            return await group.reduce(0, +)
        }
        #expect(failures == 0)
    }

    @Test("stream(for:) fails for encrypted entries and method 12")
    func rejectsEncryptedAndUnsupported() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try makeZip(in: directory)
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        do {
            _ = try await reader.stream(for: ArchiveURL.entry(archive: zip, path: "secret.mp4"))
            Issue.record("Expected an error to be thrown")
        } catch {
            #expect(error == .entryEncrypted)
        }
        do {
            _ = try await reader.stream(for: ArchiveURL.entry(archive: zip, path: "bzip2.mp4"))
            Issue.record("Expected an error to be thrown")
        } catch {
            #expect(error == .unsupportedMethod(12))
        }
    }

    @Test("MemoryLimits.archiveStreamCacheBytes is 32 MB")
    func cacheLimit() {
        #expect(MemoryLimits.archiveStreamCacheBytes == 32 * 1024 * 1024)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ArchiveEntryStreamTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
