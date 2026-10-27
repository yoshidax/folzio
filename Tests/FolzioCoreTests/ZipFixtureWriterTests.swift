import Foundation
import Testing
@testable import FixtureKit

@Suite("ZipFixtureWriter")
struct ZipFixtureWriterTests {
    @Test("Known CRC32 values")
    func crcKnownValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data()) == 0)
    }

    @Test("Incremental CRC32 matches one-shot computation")
    func crcIncremental() {
        let bytes = Array("123456789".utf8)
        let partial = bytes[0..<4].withUnsafeBytes { CRC32.update(0, $0) }
        let full = bytes[4...].withUnsafeBytes { CRC32.update(partial, $0) }
        #expect(full == 0xCBF4_3926)
    }

    @Test("The end record for one stored entry contains the signature and entry count")
    func singleStoredEntry() throws {
        let data = try ZipFixtureWriter.archiveData([
            ZipFixtureEntry(name: "a.txt", content: .bytes(Data("hello".utf8))),
        ])
        #expect(Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
        let eocd = data.suffix(22)
        #expect(Array(eocd.prefix(4)) == [0x50, 0x4B, 0x05, 0x06])
        let base = eocd.startIndex
        #expect(eocd[base + 8] == 1 && eocd[base + 9] == 0)
        #expect(eocd[base + 10] == 1 && eocd[base + 11] == 0)
    }

    @Test("forceZip64 writes the ZIP64 end record and locator")
    func zip64Records() throws {
        let data = try ZipFixtureWriter.archiveData(
            [ZipFixtureEntry(name: "a.txt", content: .bytes(Data("hello".utf8)))],
            forceZip64: true
        )
        let locator = data.suffix(22 + 20).prefix(4)
        #expect(Array(locator) == [0x50, 0x4B, 0x06, 0x07])
    }

    @Test("archiveData and write produce the same bytes")
    func dataAndFileAreIdentical() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-fixture-writer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let entries = [
            ZipFixtureEntry(name: "dir/", isDirectory: true),
            ZipFixtureEntry(name: "dir/a.txt", content: .bytes(Data("hello".utf8))),
            ZipFixtureEntry(
                name: "dir/b.txt",
                content: .bytes(Data(String(repeating: "deflate ", count: 500).utf8)),
                method: .deflated,
                usesDataDescriptor: true
            ),
            ZipFixtureEntry(name: "zeros.bin", content: .zeros(count: 3_000_000), method: .deflated),
        ]
        for forceZip64 in [false, true] {
            let url = directory.appendingPathComponent("out-\(forceZip64).zip")
            try ZipFixtureWriter.write(entries, to: url, forceZip64: forceZip64)
            let onDisk = try Data(contentsOf: url)
            let inMemory = try ZipFixtureWriter.archiveData(entries, forceZip64: forceZip64)
            #expect(onDisk == inMemory)
        }
    }
}
