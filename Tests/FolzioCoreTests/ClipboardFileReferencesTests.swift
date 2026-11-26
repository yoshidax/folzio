import Foundation
import Testing
@testable import FolzioCore

@Suite("Clipboard file references")
struct ClipboardFileReferencesTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeFile(_ url: URL) throws {
        try Data(url.lastPathComponent.utf8).write(to: url)
    }

    /// The temporary directory is reached through `/var`, which resolves to `/private/var`, so compare real paths.
    private func realPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }

    private func foundPath(_ resolution: ClipboardFileResolution?) -> String? {
        guard case .found(let url)? = resolution else { return nil }
        return realPath(url)
    }

    @Test("Puts a file reference and the file name for each item, in order (FR-413)")
    func makesReferences() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("b.jpg")
        let second = root.appendingPathComponent("a.jpg")
        try makeFile(first)
        try makeFile(second)

        let entries = ClipboardFileReferences.entries(for: [first, second])

        #expect(entries.map(\.name) == ["b.jpg", "a.jpg"])
        #expect(entries.allSatisfy { $0.url.hasPrefix("file:///.file/id=") })
        #expect(entries[0].url != entries[1].url)
    }

    @Test("Resolves a reference to the new location after a rename or a move (FR-414, US94-AS1, US94-AS2)")
    func followsRenameAndMove() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("photo.jpg")
        let other = root.appendingPathComponent("other", isDirectory: true)
        try makeFile(file)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let entries = ClipboardFileReferences.entries(for: [file])

        let renamed = root.appendingPathComponent("renamed.jpg")
        try FileManager.default.moveItem(at: file, to: renamed)
        #expect(foundPath(ClipboardFileReferences.resolve(entries).first) == realPath(renamed))

        let moved = other.appendingPathComponent("renamed.jpg")
        try FileManager.default.moveItem(at: renamed, to: moved)
        #expect(foundPath(ClipboardFileReferences.resolve(entries).first) == realPath(moved))
    }

    @Test("Resolves a folder and an item inside it after the folder moves (US94-AS3)")
    func followsFolderMove() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("album", isDirectory: true)
        let inner = folder.appendingPathComponent("cat.jpg")
        let destination = root.appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try makeFile(inner)
        let entries = ClipboardFileReferences.entries(for: [folder, inner])

        let movedFolder = destination.appendingPathComponent("album", isDirectory: true)
        try FileManager.default.moveItem(at: folder, to: movedFolder)

        let resolved = ClipboardFileReferences.resolve(entries)
        #expect(foundPath(resolved[0]) == realPath(movedFolder))
        #expect(foundPath(resolved[1]) == realPath(movedFolder.appendingPathComponent("cat.jpg")))
    }

    @Test("Reports a deleted item as missing with its file name, and keeps the others (US94-AS9, EC-283)")
    func missingAfterDelete() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let deleted = root.appendingPathComponent("gone.jpg")
        let kept = root.appendingPathComponent("kept.jpg")
        try makeFile(deleted)
        try makeFile(kept)
        let entries = ClipboardFileReferences.entries(for: [deleted, kept])

        try FileManager.default.removeItem(at: deleted)

        let resolved = ClipboardFileReferences.resolve(entries)
        #expect(resolved[0] == .missing(name: "gone.jpg"))
        #expect(foundPath(resolved[1]) == realPath(kept))
    }

    @Test("Uses the reference string as the name when the clipboard item has no file name (EC-283)")
    func missingWithoutName() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("gone.jpg")
        try makeFile(file)
        let reference = try #require(ClipboardFileReferences.entries(for: [file]).first).url
        try FileManager.default.removeItem(at: file)

        let resolved = ClipboardFileReferences.resolve([ClipboardFileEntry(url: reference, name: nil)])

        #expect(resolved == [.missing(name: reference)])
    }

    @Test("Keeps the path for an item that does not exist when copied (EC-282)")
    func pathForMissingItem() {
        let missing = URL(fileURLWithPath: "/tmp/TAK-120-\(UUID().uuidString)/photo.jpg")

        let entries = ClipboardFileReferences.entries(for: [missing])

        #expect(entries == [ClipboardFileEntry(url: missing.absoluteString, name: "photo.jpg")])
    }

    @Test("Resolves a file path URL to its own path, as before (EC-285)")
    func pathURLsStay() {
        let path = URL(fileURLWithPath: "/tmp/TAK-120/photo.jpg")

        let resolved = ClipboardFileReferences.resolve([ClipboardFileEntry(url: path.absoluteString, name: "photo.jpg")])

        #expect(resolved == [.found(path)])
    }

    @Test("Reports a string that is not a file URL as missing")
    func notAFileURL() {
        let resolved = ClipboardFileReferences.resolve([ClipboardFileEntry(url: "https://example.com/a.jpg", name: "a.jpg")])

        #expect(resolved == [.missing(name: "a.jpg")])
    }
}
