import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("FileContentVersion")
struct FileContentVersionTests {
    @Test("Values differ when any of size, modification date, or file identifier differs (A-141)")
    func comparesAllComponents() {
        let date = Date(timeIntervalSince1970: 100)
        let base = FileContentVersion(fileSize: 10, modificationDate: date, fileIdentifier: 1)
        #expect(base == FileContentVersion(fileSize: 10, modificationDate: date, fileIdentifier: 1))
        #expect(base != FileContentVersion(fileSize: 11, modificationDate: date, fileIdentifier: 1))
        #expect(base != FileContentVersion(fileSize: 10, modificationDate: date.addingTimeInterval(1), fileIdentifier: 1))
        #expect(base != FileContentVersion(fileSize: 10, modificationDate: date, fileIdentifier: 2))
        #expect(base != FileContentVersion(fileSize: 10, modificationDate: nil, fileIdentifier: 1))
    }

    @Test("Reads the current value of a file and changes after it is overwritten")
    func readsCurrentValue() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileContentVersionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.png")

        try ImageFixtures.png(at: url, width: 40, height: 20)
        let before = try #require(FileContentVersion.current(of: url))
        #expect(before.fileSize > 0)
        #expect(before.modificationDate != nil)
        #expect(before.fileIdentifier != nil)

        try ImageFixtures.png(at: url, width: 200, height: 100)
        let after = try #require(FileContentVersion.current(of: url))
        #expect(after != before)
    }

    @Test("Reads the new value through a URL that cached resource values before the overwrite (Q8, FR-232)")
    func ignoresResourceValuesCachedByTheURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileContentVersionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("a.png")

        try ImageFixtures.png(at: url, width: 40, height: 20)
        // Search results keep the URL objects that read their values when found.
        let cached = try #require(FileContentVersion(resourceValues: try url.resourceValues(
            forKeys: FileContentVersion.resourceKeys
        )))

        try ImageFixtures.png(at: url, width: 200, height: 100)
        let after = try #require(FileContentVersion.current(of: url))
        #expect(after != cached)
    }

    @Test("Returns nil for a missing file")
    func returnsNilForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/FileContentVersionTests-missing-\(UUID().uuidString).png")
        #expect(FileContentVersion.current(of: url) == nil)
        #expect(FileContentVersion(resourceValues: nil) == nil)
    }

    @Test("Builds the value of entries inside a zip from the zip identity (FR-231)")
    func buildsFromArchiveIdentity() {
        let date = Date(timeIntervalSince1970: 100)
        let identity = ArchiveIdentity(fileSize: 42, modificationDate: date, inode: 9)
        let version = FileContentVersion(archiveIdentity: identity)
        #expect(version == FileContentVersion(fileSize: 42, modificationDate: date, fileIdentifier: 9))
        #expect(version != FileContentVersion(
            archiveIdentity: ArchiveIdentity(fileSize: 42, modificationDate: date, inode: 10)
        ))
    }
}
