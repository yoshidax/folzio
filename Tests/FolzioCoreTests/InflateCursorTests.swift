import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("InflateCursor")
struct InflateCursorTests {
    private struct Fixture {
        var directory: URL
        var file: ArchiveFile
        var dataOffset: UInt64
        var compressedSize: UInt64
        var content: Data
    }

    private func makeFixture(size: Int) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InflateCursorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var content = Data(count: size)
        var state: UInt32 = 12345
        for index in 0..<size {
            state = state &* 1_664_525 &+ 1_013_904_223
            content[index] = index % 8 < 5 ? UInt8(index % 200) : UInt8(truncatingIfNeeded: state >> 24)
        }
        let url = directory.appendingPathComponent("z.zip")
        try ZipFixtureWriter.write(
            [ZipFixtureEntry(name: "a.bin", content: .bytes(content), method: .deflated)], to: url
        )
        let file = try ArchiveFile.open(url)
        let data = try Data(contentsOf: url)
        let end = try ZipStructure.endOfCentralDirectory(
            inTail: Data(data.suffix(65_557)), fileSize: UInt64(data.count)
        )
        let start = Int(end.location.offset)
        let central = try ZipStructure.centralDirectoryEntries(
            Data(data[start..<start + Int(end.location.size)]), count: end.location.entryCount
        )[0]
        let dataOffset = try ZipStructure.dataOffset(
            localHeader: Data(data[0..<30]), localHeaderOffset: central.localHeaderOffset
        )
        return Fixture(
            directory: directory, file: file, dataOffset: dataOffset,
            compressedSize: central.compressedSize, content: content
        )
    }

    private func makeCursor(_ fixture: Fixture) -> InflateCursor {
        InflateCursor(file: fixture.file, dataOffset: fixture.dataOffset, compressedSize: fixture.compressedSize)
    }

    private func readAll(_ cursor: InflateCursor, chunk: Int) throws -> Data {
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: chunk)
        while true {
            let count = try buffer.withUnsafeMutableBytes { try cursor.read(into: $0, maxLength: chunk) }
            if count == 0 { break }
            result.append(contentsOf: buffer[0..<count])
        }
        return result
    }

    private func read(_ cursor: InflateCursor, length: Int) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: length)
        var total = 0
        while total < length {
            let count = try buffer.withUnsafeMutableBytes {
                try cursor.read(into: UnsafeMutableRawBufferPointer(rebasing: $0[total...]), maxLength: length - total)
            }
            if count == 0 { break }
            total += count
        }
        return Data(buffer[0..<total])
    }

    @Test("Inflating forward from the start reproduces the content and advances position", arguments: [1, 7, 4096, 100_000, 1 << 20])
    func sequentialRead(chunk: Int) throws {
        let fixture = try makeFixture(size: 1_500_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cursor = makeCursor(fixture)
        #expect(cursor.position == 0)
        if chunk == 1 {
            // Checking every byte is slow, so verify only the beginning.
            #expect(try read(cursor, length: 2000) == fixture.content.prefix(2000))
            #expect(cursor.position == 2000)
        } else {
            #expect(try readAll(cursor, chunk: chunk) == fixture.content)
            #expect(cursor.position == UInt64(fixture.content.count))
        }
    }

    @Test("Reading past the end returns only what could be inflated, then 0")
    func readPastEnd() throws {
        let fixture = try makeFixture(size: 100_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cursor = makeCursor(fixture)
        let all = try read(cursor, length: 150_000)
        #expect(all == fixture.content)
        #expect(cursor.position == 100_000)
        var buffer = [UInt8](repeating: 0, count: 10)
        #expect(try buffer.withUnsafeMutableBytes { try cursor.read(into: $0, maxLength: 10) } == 0)
        #expect(cursor.position == 100_000)
    }

    @Test("skip(to:) advances by discarding data and subsequent reads succeed")
    func skipForward() throws {
        let fixture = try makeFixture(size: 1_000_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cursor = makeCursor(fixture)
        try cursor.skip(to: 654_321)
        #expect(cursor.position == 654_321)
        #expect(try read(cursor, length: 5000) == fixture.content[654_321..<659_321])
        #expect(cursor.position == 659_321)
        try cursor.skip(to: 659_321)
        #expect(cursor.position == 659_321)
        try cursor.skip(to: 900_000)
        #expect(try read(cursor, length: 10) == fixture.content[900_000..<900_010])
    }

    @Test("skip(to:) stops at the end when the target is beyond it")
    func skipPastEnd() throws {
        let fixture = try makeFixture(size: 50_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cursor = makeCursor(fixture)
        try cursor.skip(to: 1_000_000)
        #expect(cursor.position == 50_000)
        #expect(try read(cursor, length: 10).isEmpty)
    }

    @Test("reset() inflates again from the start, as does skip(to:) to an earlier position")
    func resetAndSkipBackward() throws {
        let fixture = try makeFixture(size: 800_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cursor = makeCursor(fixture)
        try cursor.skip(to: 500_000)
        cursor.reset()
        #expect(cursor.position == 0)
        #expect(try read(cursor, length: 3000) == fixture.content.prefix(3000))

        try cursor.skip(to: 700_000)
        try cursor.skip(to: 1234)
        #expect(cursor.position == 1234)
        #expect(try read(cursor, length: 100) == fixture.content[1234..<1334])

        // reset can read again even after reaching the end.
        _ = try readAll(cursor, chunk: 65_536)
        cursor.reset()
        #expect(try readAll(cursor, chunk: 65_536) == fixture.content)
    }

    @Test("Reads nothing when maxLength is 0")
    func zeroLength() throws {
        let fixture = try makeFixture(size: 1000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cursor = makeCursor(fixture)
        var buffer = [UInt8](repeating: 0, count: 4)
        #expect(try buffer.withUnsafeMutableBytes { try cursor.read(into: $0, maxLength: 0) } == 0)
        #expect(cursor.position == 0)
    }

    @Test("Stops at the inflated portion and does not crash when the compressed data ends early")
    func truncatedInput() throws {
        let fixture = try makeFixture(size: 500_000)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let cursor = InflateCursor(
            file: fixture.file, dataOffset: fixture.dataOffset, compressedSize: fixture.compressedSize / 2
        )
        let result = try? readAll(cursor, chunk: 65_536)
        if let result {
            #expect(result.count < fixture.content.count)
            #expect(result == fixture.content.prefix(result.count))
        }
    }
}
