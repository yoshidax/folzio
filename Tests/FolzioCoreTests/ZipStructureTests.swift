import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("ZipStructure")
struct ZipStructureTests {
    private static let maxTail = 65_557

    private func tail(of data: Data) -> Data {
        Data(data.suffix(Self.maxTail))
    }

    private func endRecord(of data: Data) throws -> ZipStructure.EndOfCentralDirectory {
        try ZipStructure.endOfCentralDirectory(inTail: tail(of: data), fileSize: UInt64(data.count))
    }

    private func slice(_ data: Data, offset: UInt64, length: UInt64) -> Data {
        Data(data[Int(offset)..<Int(offset + length)])
    }

    private func centralEntries(of data: Data) throws -> [ZipStructure.CentralEntry] {
        let end = try endRecord(of: data)
        let directory = slice(data, offset: end.location.offset, length: end.location.size)
        return try ZipStructure.centralDirectoryEntries(directory, count: end.location.entryCount)
    }

    private func sample(_ name: String, _ text: String = "hello") -> ZipFixtureEntry {
        ZipFixtureEntry(name: name, content: .bytes(Data(text.utf8)))
    }

    // MARK: - End Record

    @Test("Finds the end record without a comment")
    func findsEndRecordWithoutComment() throws {
        let data = try ZipFixtureWriter.archiveData([sample("a.txt"), sample("b.txt")])
        let end = try endRecord(of: data)
        #expect(end.location.entryCount == 2)
        #expect(end.recordOffset == UInt64(data.count - 22))
        #expect(end.needsZip64 == false)
        #expect(end.location.offset + end.location.size == end.recordOffset)
    }

    @Test("Also finds the end record with 1 KB and 65535-byte comments", arguments: [1024, 65_535])
    func findsEndRecordWithComment(commentLength: Int) throws {
        let comment = Data(repeating: 0x41, count: commentLength)
        let data = try ZipFixtureWriter.archiveData([sample("a.txt")], comment: comment)
        let end = try endRecord(of: data)
        #expect(end.location.entryCount == 1)
        #expect(end.recordOffset == UInt64(data.count - 22 - commentLength))
    }

    @Test("Returns the real end record even when the comment contains its signature")
    func ignoresSignatureInsideComment() throws {
        var comment = Data()
        comment.append(contentsOf: [0x50, 0x4B, 0x05, 0x06])
        comment.append(Data(repeating: 0xFF, count: 40))
        let data = try ZipFixtureWriter.archiveData([sample("a.txt")], comment: comment)
        let end = try endRecord(of: data)
        #expect(end.location.entryCount == 1)
        #expect(end.recordOffset == UInt64(data.count - 22 - comment.count))
    }

    @Test("Truncated Data returns notAZip")
    func truncatedTail() throws {
        let data = try ZipFixtureWriter.archiveData([sample("a.txt")], comment: Data("comment".utf8))
        for cut in [1, 5, 12, 22, 25] {
            let truncated = Data(data.dropLast(cut))
            #expect(throws: ArchiveError.notAZip) {
                try ZipStructure.endOfCentralDirectory(
                    inTail: truncated, fileSize: UInt64(truncated.count)
                )
            }
        }
    }

    @Test("Random 1 KB data returns notAZip")
    func randomBytes() {
        var generator = SystemRandomNumberGenerator()
        let bytes = Data((0..<1024).map { _ in UInt8.random(in: 0...255, using: &generator) })
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.endOfCentralDirectory(inTail: bytes, fileSize: UInt64(bytes.count))
        }
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.endOfCentralDirectory(inTail: Data(), fileSize: 0)
        }
    }

    @Test("An end-record disk number of 1 returns multiDisk")
    func multiDisk() throws {
        var data = try ZipFixtureWriter.archiveData([sample("a.txt")])
        data[data.count - 22 + 4] = 1
        #expect(throws: ArchiveError.multiDisk) { try endRecord(of: data) }

        var second = try ZipFixtureWriter.archiveData([sample("a.txt")])
        second[second.count - 22 + 6] = 1
        #expect(throws: ArchiveError.multiDisk) { try endRecord(of: second) }
    }

    @Test("A central-directory offset outside the file returns notAZip")
    func centralDirectoryOutsideFile() throws {
        var data = try ZipFixtureWriter.archiveData([sample("a.txt")])
        let position = data.count - 22 + 16
        data.replaceSubrange(position..<position + 4, with: [0xF0, 0xFF, 0xFF, 0x7F])
        #expect(throws: ArchiveError.notAZip) { try endRecord(of: data) }

        var oversized = try ZipFixtureWriter.archiveData([sample("a.txt")])
        let sizePosition = oversized.count - 22 + 12
        oversized.replaceSubrange(sizePosition..<sizePosition + 4, with: [0xF0, 0xFF, 0xFF, 0x7F])
        #expect(throws: ArchiveError.notAZip) { try endRecord(of: oversized) }
    }

    // MARK: - Central Directory

    @Test("Central-directory entries match their written values")
    func parsesCentralDirectory() throws {
        let content = Data("deflate me deflate me deflate me".utf8)
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let unix = Date(timeIntervalSince1970: 1_650_000_002)
        let entries = [
            ZipFixtureEntry(
                name: "sub/日本語.txt", content: .bytes(content), method: .deflated,
                modificationDate: modified, unixModificationTime: unix
            ),
            ZipFixtureEntry(
                name: "plain.bin", content: .bytes(Data([1, 2, 3])), method: .stored, utf8Flag: false
            ),
            ZipFixtureEntry(name: "dir", isDirectory: true),
        ]
        let data = try ZipFixtureWriter.archiveData(entries)
        let parsed = try centralEntries(of: data)
        #expect(parsed.count == 3)

        let first = parsed[0]
        #expect(first.nameBytes == Data("sub/日本語.txt".utf8))
        #expect(first.flags & 0x0800 != 0)
        #expect(first.flags & 0x0001 == 0)
        #expect(first.method == 8)
        #expect(first.crc32 == CRC32.checksum(content))
        #expect(first.uncompressedSize == UInt64(content.count))
        #expect(first.compressedSize > 0)
        #expect(first.localHeaderOffset == 0)
        #expect(first.extraField == Data([0x55, 0x54, 0x05, 0x00, 0x01, 0x82, 0x00, 0x59, 0x62]))
        #expect(
            ZipStructure.modificationDate(
                dosDate: first.dosDate, dosTime: first.dosTime, extra: first.extraField
            ) == unix
        )

        let second = parsed[1]
        #expect(second.nameBytes == Data("plain.bin".utf8))
        #expect(second.flags & 0x0800 == 0)
        #expect(second.method == 0)
        #expect(second.compressedSize == 3 && second.uncompressedSize == 3)
        #expect(second.crc32 == CRC32.checksum(Data([1, 2, 3])))
        #expect(second.localHeaderOffset == first.localHeaderOffset + UInt64(30 + first.nameBytes.count)
            + UInt64(first.extraField.count) + first.compressedSize)
        #expect(second.extraField.isEmpty)

        let third = parsed[2]
        #expect(third.nameBytes == Data("dir/".utf8))
        #expect(third.uncompressedSize == 0)

        // Signature of the first local header.
        #expect(Array(data[Int(second.localHeaderOffset)..<Int(second.localHeaderOffset) + 4]) == [0x50, 0x4B, 0x03, 0x04])
    }

    @Test("Entries with data descriptors (bit 3) still use central-directory sizes")
    func dataDescriptorSizes() throws {
        let content = Data(repeating: 0x42, count: 5000)
        let data = try ZipFixtureWriter.archiveData([
            ZipFixtureEntry(name: "d.bin", content: .bytes(content), method: .deflated, usesDataDescriptor: true),
            ZipFixtureEntry(name: "s.bin", content: .bytes(content), method: .stored, usesDataDescriptor: true),
        ])
        let parsed = try centralEntries(of: data)
        #expect(parsed[0].flags & 0x0008 != 0)
        #expect(parsed[0].uncompressedSize == 5000)
        #expect(parsed[0].compressedSize > 0 && parsed[0].compressedSize < 5000)
        #expect(parsed[1].uncompressedSize == 5000)
        #expect(parsed[1].compressedSize == 5000)
        #expect(parsed[0].crc32 == CRC32.checksum(content))

        // The local header size is 0, but the data start offset can still be computed.
        let offset = parsed[1].localHeaderOffset
        let header = Data(data[Int(offset)..<Int(offset) + 30])
        let start = try ZipStructure.dataOffset(localHeader: header, localHeaderOffset: offset)
        #expect(Data(data[Int(start)..<Int(start) + 5000]) == content)
    }

    @Test("Reads forceZip64 archives by following the ZIP64 end record and locator")
    func zip64Chain() throws {
        let content = Data("zip64 content".utf8)
        let data = try ZipFixtureWriter.archiveData(
            [
                ZipFixtureEntry(name: "a.txt", content: .bytes(content)),
                ZipFixtureEntry(name: "b.txt", content: .bytes(content), method: .deflated),
            ],
            forceZip64: true
        )
        let end = try endRecord(of: data)
        #expect(end.needsZip64)

        let locatorOffset = Int(end.recordOffset) - 20
        let zip64Offset = try ZipStructure.zip64Locator(Data(data[locatorOffset..<locatorOffset + 20]))
        #expect(zip64Offset == UInt64(locatorOffset - 56))

        let location = try ZipStructure.zip64EndOfCentralDirectory(
            Data(data[Int(zip64Offset)..<Int(zip64Offset) + 56]), fileSize: UInt64(data.count)
        )
        #expect(location.entryCount == 2)

        let directory = slice(data, offset: location.offset, length: location.size)
        let parsed = try ZipStructure.centralDirectoryEntries(directory, count: location.entryCount)
        #expect(parsed.count == 2)
        #expect(parsed[0].uncompressedSize == UInt64(content.count))
        #expect(parsed[0].compressedSize == UInt64(content.count))
        #expect(parsed[0].localHeaderOffset == 0)
        #expect(parsed[1].uncompressedSize == UInt64(content.count))
        #expect(parsed[1].localHeaderOffset > 0)
        #expect(parsed[1].localHeaderOffset == UInt64(30 + 5 + 20 + content.count))
    }

    @Test("Incorrect ZIP64 locator or end-record signatures return notAZip")
    func zip64BadSignatures() {
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.zip64Locator(Data(repeating: 0, count: 20))
        }
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.zip64Locator(Data(repeating: 0, count: 4))
        }
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.zip64EndOfCentralDirectory(Data(repeating: 0, count: 56), fileSize: 1000)
        }
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.zip64EndOfCentralDirectory(Data(), fileSize: 1000)
        }
    }

    @Test("A damaged central directory returns notAZip without crashing")
    func corruptedCentralDirectory() throws {
        let data = try ZipFixtureWriter.archiveData([sample("a.txt"), sample("b.txt")])
        let end = try endRecord(of: data)
        let directory = slice(data, offset: end.location.offset, length: end.location.size)

        // Entry count is larger than actual.
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.centralDirectoryEntries(directory, count: 3)
        }
        // Very large entry count.
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.centralDirectoryEntries(directory, count: UInt64.max)
        }
        // Does not crash when truncated at any position.
        for length in 0..<directory.count {
            #expect(throws: ArchiveError.notAZip) {
                try ZipStructure.centralDirectoryEntries(Data(directory.prefix(length)), count: 2)
            }
        }
        // Corrupted signature.
        var broken = directory
        broken[0] = 0
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.centralDirectoryEntries(broken, count: 2)
        }
        // Name length exceeds the whole data.
        var longName = directory
        longName[28] = 0xFF
        longName[29] = 0xFF
        #expect(throws: ArchiveError.notAZip) {
            try ZipStructure.centralDirectoryEntries(longName, count: 2)
        }
    }

    // MARK: - Local Header

    @Test("Computes the data offset from the local-header name and extra-field lengths")
    func dataOffsetUsesLocalHeader() throws {
        let content = Data("local header content".utf8)
        let data = try ZipFixtureWriter.archiveData(
            [
                ZipFixtureEntry(name: "first.txt", content: .bytes(Data("x".utf8))),
                ZipFixtureEntry(
                    name: "二番目.txt", content: .bytes(content),
                    unixModificationTime: Date(timeIntervalSince1970: 1_600_000_000)
                ),
            ]
        )
        let parsed = try centralEntries(of: data)
        for (entry, expected) in zip(parsed, [Data("x".utf8), content]) {
            let offset = Int(entry.localHeaderOffset)
            let header = Data(data[offset..<offset + 30])
            let start = try ZipStructure.dataOffset(localHeader: header, localHeaderOffset: entry.localHeaderOffset)
            #expect(start == entry.localHeaderOffset + 30 + UInt64(entry.nameBytes.count)
                + UInt64(entry.extraField.count))
            #expect(Data(data[Int(start)..<Int(start) + expected.count]) == expected)
        }
    }

    @Test("Returns the correct offset even when central-directory and local-header extra-field lengths differ")
    func dataOffsetWhenExtraLengthsDiffer() throws {
        let content = Data("zip64 local header is longer".utf8)
        let data = try ZipFixtureWriter.archiveData(
            [ZipFixtureEntry(name: "a.txt", content: .bytes(content))],
            forceZip64: true
        )
        let entry = try {
            let end = try endRecord(of: data)
            let locatorOffset = Int(end.recordOffset) - 20
            let zip64Offset = try ZipStructure.zip64Locator(Data(data[locatorOffset..<locatorOffset + 20]))
            let location = try ZipStructure.zip64EndOfCentralDirectory(
                Data(data[Int(zip64Offset)..<Int(zip64Offset) + 56]), fileSize: UInt64(data.count)
            )
            let directory = slice(data, offset: location.offset, length: location.size)
            return try ZipStructure.centralDirectoryEntries(directory, count: location.entryCount)[0]
        }()
        // The central directory extra field is 28 bytes; the local one is 20 bytes.
        #expect(entry.extraField.count == 28)
        let header = Data(data[0..<30])
        let start = try ZipStructure.dataOffset(localHeader: header, localHeaderOffset: 0)
        #expect(start == 30 + 5 + 20)
        #expect(Data(data[Int(start)..<Int(start) + content.count]) == content)
    }

    @Test("An invalid local header returns corrupted")
    func invalidLocalHeader() {
        #expect(throws: ArchiveError.self) {
            try ZipStructure.dataOffset(localHeader: Data(repeating: 0, count: 30), localHeaderOffset: 0)
        }
        #expect(throws: ArchiveError.self) {
            try ZipStructure.dataOffset(localHeader: Data(repeating: 0x50, count: 10), localHeaderOffset: 0)
        }
        #expect(throws: ArchiveError.self) {
            try ZipStructure.dataOffset(localHeader: Data(), localHeaderOffset: 0)
        }
    }

    // MARK: - Dates

    @Test("Uses the 0x5455 modification time when present and otherwise interprets DOS dates in local time")
    func modificationDates() throws {
        var extra = Data([0x55, 0x54, 0x05, 0x00, 0x01])
        let unix: UInt32 = 1_650_000_002
        withUnsafeBytes(of: unix.littleEndian) { extra.append(contentsOf: $0) }
        #expect(
            ZipStructure.modificationDate(dosDate: 0, dosTime: 0, extra: extra)
                == Date(timeIntervalSince1970: 1_650_000_002)
        )

        // Convert 2023-11-14 22:13:20 (even seconds) to DOS date and time in local time.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let expected = try #require(
            calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 22, minute: 13, second: 20))
        )
        let dosDate = UInt16((2023 - 1980) << 9 | 11 << 5 | 14)
        let dosTime = UInt16(22 << 11 | 13 << 5 | 20 / 2)
        #expect(ZipStructure.modificationDate(dosDate: dosDate, dosTime: dosTime, extra: Data()) == expected)

        // Use the DOS date and time when the 0x5455 extended field is absent or damaged.
        let other = Data([0x01, 0x00, 0x02, 0x00, 0xAA, 0xBB])
        #expect(ZipStructure.modificationDate(dosDate: dosDate, dosTime: dosTime, extra: other) == expected)
        let truncated = Data([0x55, 0x54, 0x09, 0x00, 0x01])
        #expect(ZipStructure.modificationDate(dosDate: dosDate, dosTime: dosTime, extra: truncated) == expected)

        // Returns nil for DOS date and time values that are not valid dates.
        #expect(ZipStructure.modificationDate(dosDate: 0, dosTime: 0, extra: Data()) == nil)
    }

    @Test("DOS dates round-trip with the writer")
    func dosRoundTripWithWriter() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let data = try ZipFixtureWriter.archiveData([
            ZipFixtureEntry(name: "a.txt", content: .bytes(Data("a".utf8)), modificationDate: modified),
        ])
        let entry = try centralEntries(of: data)[0]
        let date = ZipStructure.modificationDate(dosDate: entry.dosDate, dosTime: entry.dosTime, extra: entry.extraField)
        #expect(abs((date ?? .distantPast).timeIntervalSince(modified)) <= 2)
    }
}
