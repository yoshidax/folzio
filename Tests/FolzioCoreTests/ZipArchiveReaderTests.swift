import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("ZipArchiveReader")
struct ZipArchiveReaderTests {
    /// Content that compresses well and does not repeat within 1 MB.
    private func pattern(count: Int) -> Data {
        var generator = SplitMix(seed: 42)
        var data = Data(count: count)
        for index in 0..<count {
            data[index] = index % 64 < 48 ? UInt8(index % 251) : UInt8(truncatingIfNeeded: generator.next())
        }
        return data
    }

    private func write(_ entries: [ZipFixtureEntry], in directory: URL, name: String = "test.zip",
                       forceZip64: Bool = false) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try ZipFixtureWriter.write(entries, to: url, forceZip64: forceZip64)
        return url
    }

    private func entryURL(_ zip: URL, _ path: String) -> URL {
        ArchiveURL.entry(archive: zip, path: path)
    }

    // MARK: - open

    @Test("open builds the index and identity matches stat")
    func openBuildsIndexAndIdentity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try write([
            ZipFixtureEntry(name: "sub/a.jpg", content: .bytes(Data("a".utf8))),
            ZipFixtureEntry(name: "b.png", content: .bytes(Data("bb".utf8))),
        ], in: directory)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        let index = try await reader.open(zip)
        #expect(index.archive == zip)
        #expect(index.items(in: "").map(\.name).sorted() == ["b.png", "sub"])
        #expect(index.items(in: "sub/").map(\.name) == ["a.jpg"])

        var info = stat()
        #expect(stat(zip.path, &info) == 0)
        #expect(index.identity.fileSize == UInt64(info.st_size))
        #expect(index.identity.inode == UInt64(info.st_ino))
        let expectedDate = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        #expect(abs(index.identity.modificationDate.timeIntervalSince(expectedDate)) < 0.001)
        #expect(reader.identity(of: zip) == index.identity)
    }

    @Test("open runs off the UI thread and can be called from MainActor")
    @MainActor
    func openFromMainActor() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try write([ZipFixtureEntry(name: "a.jpg", content: .bytes(Data("a".utf8)))], in: directory)
        let index = try await ZipArchiveReader(kindNames: FixtureKit.kindNames).open(zip)
        #expect(index.items(in: "").count == 1)
    }

    // MARK: - data(for:limit:)

    @Test("Stored, deflate, and data-descriptor entries match their written contents")
    func readsEachMethod() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let small = pattern(count: 5_000)
        let large = pattern(count: 2_500_000)
        let zip = try write([
            ZipFixtureEntry(name: "stored.jpg", content: .bytes(large), method: .stored),
            ZipFixtureEntry(name: "deflated.png", content: .bytes(large), method: .deflated),
            ZipFixtureEntry(name: "desc-deflated.gif", content: .bytes(small), method: .deflated,
                            usesDataDescriptor: true),
            ZipFixtureEntry(name: "desc-stored.jpg", content: .bytes(small), method: .stored,
                            usesDataDescriptor: true),
            ZipFixtureEntry(name: "dir/日本語 名前.webp", content: .bytes(small), method: .deflated,
                            unixModificationTime: Date(timeIntervalSince1970: 1_600_000_000)),
            ZipFixtureEntry(name: "empty.png", content: .bytes(Data()), method: .deflated),
            ZipFixtureEntry(name: "empty-stored.png", content: .bytes(Data()), method: .stored),
        ], in: directory)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        let limit = 10_000_000
        #expect(try await reader.data(for: entryURL(zip, "stored.jpg"), limit: limit) == large)
        #expect(try await reader.data(for: entryURL(zip, "deflated.png"), limit: limit) == large)
        #expect(try await reader.data(for: entryURL(zip, "desc-deflated.gif"), limit: limit) == small)
        #expect(try await reader.data(for: entryURL(zip, "desc-stored.jpg"), limit: limit) == small)
        #expect(try await reader.data(for: entryURL(zip, "dir/日本語 名前.webp"), limit: limit) == small)
        #expect(try await reader.data(for: entryURL(zip, "empty.png"), limit: limit) == Data())
        #expect(try await reader.data(for: entryURL(zip, "empty-stored.png"), limit: limit) == Data())
        // Reading the same entry again returns the same data (the data start offset is cached).
        #expect(try await reader.data(for: entryURL(zip, "deflated.png"), limit: limit) == large)
    }

    @Test("Entries in a ZIP64 zip match their written contents")
    func readsZip64() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let content = pattern(count: 300_000)
        let zip = try write([
            ZipFixtureEntry(name: "first.jpg", content: .bytes(content), method: .stored),
            ZipFixtureEntry(name: "second.png", content: .bytes(content), method: .deflated),
            ZipFixtureEntry(name: "third.gif", content: .bytes(content), method: .deflated, usesDataDescriptor: true),
        ], in: directory, forceZip64: true)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        let index = try await reader.open(zip)
        #expect(index.items(in: "").count == 3)
        for name in ["first.jpg", "second.png", "third.gif"] {
            #expect(try await reader.data(for: entryURL(zip, name), limit: 1_000_000) == content)
        }
    }

    @Test("data(for:) opens and reads a zip without an explicit open call")
    func readsWithoutExplicitOpen() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try write([ZipFixtureEntry(name: "a.png", content: .bytes(Data("abc".utf8)))], in: directory)
        #expect(try await ZipArchiveReader(kindNames: FixtureKit.kindNames).data(for: entryURL(zip, "a.png"), limit: 100) == Data("abc".utf8))
    }

    @Test("Entries whose inflated size exceeds limit return tooLarge")
    func rejectsTooLarge() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try write([
            ZipFixtureEntry(name: "zeros.png", content: .zeros(count: 20_000_000), method: .deflated),
            ZipFixtureEntry(name: "exact.png", content: .bytes(Data(repeating: 1, count: 1000)), method: .stored),
        ], in: directory)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        await expectError(.tooLarge) { try await reader.data(for: entryURL(zip, "zeros.png"), limit: 1_000_000) }
        await expectError(.tooLarge) { try await reader.data(for: entryURL(zip, "exact.png"), limit: 999) }
        await expectError(.tooLarge) { try await reader.data(for: entryURL(zip, "exact.png"), limit: -1) }
        #expect(try await reader.data(for: entryURL(zip, "exact.png"), limit: 1000).count == 1000)
        #expect(MemoryLimits.archiveImageBytes == 512 * 1024 * 1024)
    }

    @Test("Encryption and unsupported methods return dedicated errors")
    func rejectsEncryptedAndUnsupported() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try write([
            ZipFixtureEntry(name: "secret.jpg", content: .bytes(Data("s".utf8)), encryptedFlag: true),
            ZipFixtureEntry(name: "bzip2.jpg", content: .bytes(Data("s".utf8)), method: .raw(12)),
        ], in: directory)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        let index = try await reader.open(zip)
        #expect(index.items(in: "").count == 2)
        await expectError(.entryEncrypted) { try await reader.data(for: entryURL(zip, "secret.jpg"), limit: 100) }
        await expectError(.unsupportedMethod(12)) { try await reader.data(for: entryURL(zip, "bzip2.jpg"), limit: 100) }
    }

    @Test("Unindexed entry URLs and directory URLs return corrupted")
    func rejectsUnknownEntries() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try write([ZipFixtureEntry(name: "sub/a.png", content: .bytes(Data("a".utf8)))], in: directory)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        await expectCorrupted { try await reader.data(for: entryURL(zip, "missing.png"), limit: 100) }
        await expectCorrupted { try await reader.data(for: entryURL(zip, "sub/"), limit: 100) }
        await expectCorrupted { try await reader.data(for: URL(fileURLWithPath: "/tmp/a.png"), limit: 100) }
        await expectCorrupted { try await reader.data(for: ArchiveURL.parentLink(of: ArchiveLocation(archive: zip, directory: "sub/")), limit: 100) }
    }

    // MARK: - Error Cases

    @Test("A nonexistent zip returns notFound")
    func missingArchive() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).zip")
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        await expectError(.notFound) { try await reader.open(missing) }
        #expect(reader.identity(of: missing) == nil)
    }

    @Test("A zip without permission returns accessDenied")
    func unreadableArchive() async throws {
        let directory = try makeTemporaryDirectory()
        let zip = try write([ZipFixtureEntry(name: "a.png", content: .bytes(Data("a".utf8)))], in: directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: zip.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: zip.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        await expectError(.accessDenied) { try await reader.open(zip) }
    }

    @Test("Text files named .zip, empty files, and directories return notAZip")
    func notAZip() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = directory.appendingPathComponent("text.zip")
        try Data(String(repeating: "this is not a zip file\n", count: 100).utf8).write(to: text)
        let empty = directory.appendingPathComponent("empty.zip")
        try Data().write(to: empty)
        let folder = directory.appendingPathComponent("folder.zip", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        await expectError(.notAZip) { try await reader.open(text) }
        await expectError(.notAZip) { try await reader.open(empty) }
        await expectError(.notAZip) { try await reader.open(folder) }
    }

    @Test("A truncated zip fails without crashing")
    func truncatedArchive() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try ZipFixtureWriter.archiveData([
            ZipFixtureEntry(name: "a.png", content: .bytes(pattern(count: 3000)), method: .deflated),
            ZipFixtureEntry(name: "b.png", content: .bytes(pattern(count: 3000)), method: .stored),
        ])
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        for length in stride(from: 0, to: data.count, by: max(1, data.count / 40)) {
            let url = directory.appendingPathComponent("cut-\(length).zip")
            try data.prefix(length).write(to: url)
            do {
                _ = try await reader.open(url)
                Issue.record("Did not fail at length \(length)")
            } catch {
                #expect(error == .notAZip || { if case .corrupted = error { return true }; return false }())
            }
        }
    }

    @Test("An entry with a local-header offset outside the file returns corrupted")
    func localHeaderOutsideFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var data = try ZipFixtureWriter.archiveData([
            ZipFixtureEntry(name: "a.png", content: .bytes(Data("abc".utf8))),
        ])
        let end = try ZipStructure.endOfCentralDirectory(
            inTail: Data(data.suffix(65_557)), fileSize: UInt64(data.count)
        )
        let offsetField = Int(end.location.offset) + 42
        for target in [UInt32(data.count - 5), UInt32(data.count), 0x7FFF_FFF0] {
            withUnsafeBytes(of: target.littleEndian) { bytes in
                data.replaceSubrange(offsetField..<offsetField + 4, with: bytes)
            }
            let zip = directory.appendingPathComponent("bad-\(target).zip")
            try data.write(to: zip)
            let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
            _ = try await reader.open(zip)
            await expectCorrupted { try await reader.data(for: entryURL(zip, "a.png"), limit: 100) }
        }
    }

    @Test("An entry whose size differs from its actual size returns corrupted without crashing")
    func mismatchedSizes() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let content = pattern(count: 20_000)
        let base = try ZipFixtureWriter.archiveData([
            ZipFixtureEntry(name: "a.png", content: .bytes(content), method: .deflated),
            ZipFixtureEntry(name: "b.png", content: .bytes(content), method: .stored),
        ])
        let end = try ZipStructure.endOfCentralDirectory(
            inTail: Data(base.suffix(65_557)), fileSize: UInt64(base.count)
        )
        let central = Int(end.location.offset)
        let secondCentral = central + 46 + 5

        func patched(_ position: Int, _ value: UInt32) -> Data {
            var data = base
            withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(position..<position + 4, with: $0) }
            return data
        }
        let cases: [(String, Data)] = [
            // deflate: inflated size is larger than actual.
            ("usize-large", patched(central + 24, 30_000)),
            // deflate: compressed size is smaller than actual (input ends early).
            ("csize-small", patched(central + 20, 10)),
            // stored: compressed size is smaller than the inflated size.
            ("stored-csize-small", patched(secondCentral + 20, 100)),
            // stored: size extends beyond the file.
            ("stored-huge", patched(secondCentral + 24, 0x7FFF_0000)),
        ]
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        for (name, data) in cases {
            let zip = directory.appendingPathComponent("\(name).zip")
            try data.write(to: zip)
            _ = try await reader.open(zip)
            let target = name.hasPrefix("stored") ? "b.png" : "a.png"
            do {
                let result = try await reader.data(for: entryURL(zip, target), limit: 0x7FFF_FFFF)
                Issue.record("\(name): did not fail (\(result.count) bytes)")
            } catch {
                if case .corrupted = error {} else if error == .tooLarge {} else {
                    Issue.record("\(name): unexpected error \(error)")
                }
            }
        }
    }

    @Test("Damaged deflate data returns a result without crashing")
    func garbledDeflateData() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let content = pattern(count: 50_000)
        var data = try ZipFixtureWriter.archiveData([
            ZipFixtureEntry(name: "a.png", content: .bytes(content), method: .deflated),
        ])
        for index in stride(from: 100, to: 3000, by: 7) { data[index] = data[index] ^ 0xA5 }
        let zip = directory.appendingPathComponent("garbled.zip")
        try data.write(to: zip)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        do {
            let result = try await reader.data(for: entryURL(zip, "a.png"), limit: 1_000_000)
            #expect(result != content)
        } catch {
            if case .corrupted = error {} else { Issue.record("Unexpected error \(error)") }
        }
    }

    // MARK: - Identity and Multiple Zips

    @Test("Overwriting or deleting a zip after opening changes identity")
    func identityChangesAfterModification() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let zip = try write([ZipFixtureEntry(name: "a.png", content: .bytes(Data("a".utf8)))], in: directory)

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        let index = try await reader.open(zip)
        #expect(reader.identity(of: zip) == index.identity)

        _ = try write([
            ZipFixtureEntry(name: "a.png", content: .bytes(Data("a".utf8))),
            ZipFixtureEntry(name: "b.png", content: .bytes(Data("b".utf8))),
        ], in: directory)
        let changed = reader.identity(of: zip)
        #expect(changed != nil)
        #expect(changed != index.identity)

        try FileManager.default.removeItem(at: zip)
        #expect(reader.identity(of: zip) == nil)
    }

    @Test("Alternating reads of two zip files with the same reader does not mix results")
    func alternatingArchives() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try write([
            ZipFixtureEntry(name: "same.png", content: .bytes(Data("from first".utf8)), method: .deflated),
        ], in: directory, name: "first.zip")
        let second = try write([
            ZipFixtureEntry(name: "same.png", content: .bytes(Data("from second archive".utf8)), method: .stored),
        ], in: directory, name: "second.zip")
        let third = try write([
            ZipFixtureEntry(name: "same.png", content: .bytes(Data("from third".utf8)), method: .deflated),
        ], in: directory, name: "third.zip")

        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        let firstIndex = try await reader.open(first)
        let secondIndex = try await reader.open(second)
        #expect(firstIndex.archive == first && secondIndex.archive == second)
        for _ in 0..<3 {
            #expect(try await reader.data(for: entryURL(first, "same.png"), limit: 100) == Data("from first".utf8))
            #expect(try await reader.data(for: entryURL(second, "same.png"), limit: 100) == Data("from second archive".utf8))
        }
        // Even beyond the cache size, reopen and return the correct result.
        #expect(try await reader.data(for: entryURL(third, "same.png"), limit: 100) == Data("from third".utf8))
        #expect(try await reader.data(for: entryURL(first, "same.png"), limit: 100) == Data("from first".utf8))
    }

    @Test("Concurrent reads from multiple tasks do not mix results")
    func concurrentReads() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contents = (0..<8).map { pattern(count: 100_000 + $0 * 1000) }
        let zip = try write(
            contents.enumerated().map {
                ZipFixtureEntry(name: "f\($0.offset).png", content: .bytes($0.element), method: .deflated)
            },
            in: directory
        )
        let reader = ZipArchiveReader(kindNames: FixtureKit.kindNames)
        _ = try await reader.open(zip)
        await withTaskGroup(of: Bool.self) { group in
            for round in 0..<4 {
                for (index, expected) in contents.enumerated() {
                    group.addTask {
                        let data = try? await reader.data(for: ArchiveURL.entry(archive: zip, path: "f\(index).png"), limit: 1_000_000)
                        _ = round
                        return data == expected
                    }
                }
            }
            for await result in group { #expect(result) }
        }
    }

    // MARK: - Helpers

    private func expectError<T>(
        _ expected: ArchiveError,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            Issue.record("Error \(expected) was not thrown", sourceLocation: sourceLocation)
        } catch {
            #expect(error as? ArchiveError == expected, sourceLocation: sourceLocation)
        }
    }

    private func expectCorrupted<T>(
        sourceLocation: SourceLocation = #_sourceLocation,
        _ body: () async throws -> T
    ) async {
        do {
            _ = try await body()
            Issue.record("corrupted was not thrown", sourceLocation: sourceLocation)
        } catch {
            if case .corrupted? = error as? ArchiveError { return }
            Issue.record("Unexpected error \(error)", sourceLocation: sourceLocation)
        }
    }
}

private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ZipArchiveReaderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
