import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("FileOperationService")
struct FileOperationServiceTests {
    private let service = FileOperationService()

    @Test("Rejects replacing an item with itself without deleting the original")
    func refusesReplaceOfSource() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        let before = try Data(contentsOf: source)
        let result = await service.execute(FileOperation(kind: .copy, sources: [source], destination: folder), resolution: .replace)
        #expect(result.succeeded.isEmpty)
        #expect(result.failed.count == 1)
        #expect(try Data(contentsOf: source) == before)
        let kept = await service.execute(FileOperation(kind: .copy, sources: [source], destination: folder), resolution: .keepBoth)
        #expect(kept.failed.isEmpty)
        #expect(kept.succeeded.count == 1)
        #expect(try Data(contentsOf: source) == before)
    }

    @Test("Copying duplicates the item at the destination and preserves the original")
    func copiesFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let source = folder.appendingPathComponent("a.jpg")

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [source], destination: destination),
            resolution: .replace
        )

        #expect(result.failed.isEmpty)
        #expect(result.succeeded == [destination.appendingPathComponent("a.jpg")])
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: destination.appendingPathComponent("a.jpg")) == Data(contentsOf: source))
    }

    @Test("Moving removes the item from its original location")
    func movesFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let source = folder.appendingPathComponent("a.jpg")

        let result = await service.execute(
            FileOperation(kind: .move, sources: [source], destination: destination),
            resolution: .replace
        )

        #expect(result.failed.isEmpty)
        #expect(result.succeeded == [destination.appendingPathComponent("a.jpg")])
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.jpg").path))
    }

    @Test("Renaming keeps the item in the same folder with its new name")
    func renamesFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("b.png")
        let renamed = folder.appendingPathComponent("renamed.png")

        let result = await service.execute(
            FileOperation(kind: .rename(newName: "renamed.png"), sources: [source]),
            resolution: .replace
        )

        #expect(result.failed.isEmpty)
        #expect(result.succeeded == [renamed])
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test("Moving to Trash returns the URL in Trash and removes the item from its original location")
    func trashesFile() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        var trashed: URL?
        defer {
            if let trashed {
                try? FileManager.default.removeItem(at: trashed)
            }
        }

        let result = await service.execute(
            FileOperation(kind: .trash, sources: [source]),
            resolution: .replace
        )

        #expect(result.failed.isEmpty)
        let trashedURL = try #require(result.succeeded.first)
        trashed = trashedURL
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Detects conflicts")
    func detectsConflicts() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let source = folder.appendingPathComponent("a.jpg")
        try Data("existing".utf8).write(to: destination.appendingPathComponent("a.jpg"))

        let copy = FileOperation(kind: .copy, sources: [source], destination: destination)
        let move = FileOperation(kind: .move, sources: [source], destination: destination)
        #expect(service.conflicts(for: copy) == [source])
        #expect(service.conflicts(for: move) == [source])
        #expect(service.conflicts(for: FileOperation(kind: .rename(newName: "x.jpg"), sources: [source])) == [])
        #expect(service.conflicts(for: FileOperation(kind: .trash, sources: [source])) == [])
    }

    @Test("Replacing moves the existing item to Trash before copying")
    func replacesExistingItem() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let source = folder.appendingPathComponent("a.jpg")
        let existing = destination.appendingPathComponent("a.jpg")
        try Data("existing".utf8).write(to: existing)

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [source], destination: destination),
            resolution: .replace
        )

        #expect(result.failed.isEmpty)
        #expect(result.succeeded == [existing])
        #expect(try Data(contentsOf: existing) == Data(contentsOf: source))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Keeping both copies with a numbered name that does not conflict")
    func keepsBothOnConflict() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let a = folder.appendingPathComponent("a.jpg")
        let c = folder.appendingPathComponent("c 2.jpg")
        try Data("existing-a".utf8).write(to: destination.appendingPathComponent("a.jpg"))
        try Data("existing-c".utf8).write(to: destination.appendingPathComponent("c 2.jpg"))

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [a, c], destination: destination),
            resolution: .keepBoth
        )

        #expect(result.failed.isEmpty)
        #expect(Set(result.succeeded.map(\.lastPathComponent)) == ["a 2.jpg", "c 3.jpg"])
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a 2.jpg").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("c 3.jpg").path))
        #expect(try Data(contentsOf: destination.appendingPathComponent("a.jpg")) == Data("existing-a".utf8))
        #expect(try Data(contentsOf: destination.appendingPathComponent("c 2.jpg")) == Data("existing-c".utf8))
    }

    @Test("Copying with abort fails on a destination name conflict and preserves the existing item")
    func abortsCopyOnConflict() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let source = folder.appendingPathComponent("a.jpg")
        let existing = destination.appendingPathComponent("a.jpg")
        try Data("existing".utf8).write(to: existing)

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [source], destination: destination),
            resolution: .abort
        )

        #expect(result.succeeded.isEmpty)
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.url == source)
        #expect(result.failed.first != nil)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
    }

    @Test("The abort policy still moves items to Trash and returns their URLs in Trash")
    func trashesFileWithAbortResolution() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        var trashed: URL?
        defer {
            if let trashed {
                try? FileManager.default.removeItem(at: trashed)
            }
        }

        let result = await service.execute(
            FileOperation(kind: .trash, sources: [source]),
            resolution: .abort
        )

        #expect(result.failed.isEmpty)
        let trashedURL = try #require(result.succeeded.first)
        trashed = trashedURL
        #expect(trashedURL != source)
        #expect(FileManager.default.fileExists(atPath: trashedURL.path))
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Renaming with abort changes the name when no conflict exists")
    func renamesFileWithAbortResolution() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("b.png")
        let renamed = folder.appendingPathComponent("renamed.png")

        let result = await service.execute(
            FileOperation(kind: .rename(newName: "renamed.png"), sources: [source]),
            resolution: .abort
        )

        #expect(result.failed.isEmpty)
        #expect(result.succeeded == [renamed])
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: renamed.path))
    }

    @Test("Renaming with abort fails on a name conflict and preserves both files")
    func abortsRenameOnConflict() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        let existing = folder.appendingPathComponent("taken.jpg")
        let originalContents = try Data(contentsOf: source)
        try Data("existing".utf8).write(to: existing)

        let result = await service.execute(
            FileOperation(kind: .rename(newName: "taken.jpg"), sources: [source]),
            resolution: .abort
        )

        #expect(result.succeeded.isEmpty)
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.url == source)
        #expect(result.failed.first != nil)
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: source) == originalContents)
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
    }

    @Test("An unwritable folder returns a failure reason and preserves the source file")
    func failsInReadOnlyFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let source = folder.appendingPathComponent("a.jpg")
        let originalContents = try Data(contentsOf: source)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [source], destination: destination),
            resolution: .replace
        )

        #expect(result.succeeded.isEmpty)
        let failure = try #require(result.failed.first)
        #expect(failure.url == source)
                #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: source) == originalContents)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.jpg").path))
    }

    @Test("Moving to the same folder does nothing")
    func movingToSameFolderIsNoOp() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        let originalContents = try Data(contentsOf: source)

        let result = await service.execute(
            FileOperation(kind: .move, sources: [source], destination: folder),
            resolution: .replace
        )

        #expect(result.failed.isEmpty)
        #expect(result.succeeded == [source])
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: source) == originalContents)
    }

    @Test("Continues processing remaining items after one fails")
    func continuesAfterFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let missing = folder.appendingPathComponent("missing.jpg")
        let a = folder.appendingPathComponent("a.jpg")
        let b = folder.appendingPathComponent("b.png")

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [missing, a, b], destination: destination),
            resolution: .replace
        )

        #expect(result.succeeded.count == 2)
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.url == missing)
        #expect(result.failed.first != nil)
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("a.jpg").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("b.png").path))
    }

    @Test("Copying a folder onto itself fails")
    func refusesCopyingFolderIntoItself() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [source], destination: source),
            resolution: .replace
        )

        #expect(result.succeeded.isEmpty)
        let failure = try #require(result.failed.first)
        #expect(failure.url == source)
                #expect(FileManager.default.fileExists(atPath: source.path))
    }

    // MARK: - Folders (FR-018, 076)

    /// `ops/album/` (`a.jpg`, `inner/`) plus `inner/b.jpg` under it.
    private func makeAlbum(in folder: URL) throws -> URL {
        let album = folder.appendingPathComponent("album", isDirectory: true)
        try ImageFixtures.jpeg(at: album.appendingPathComponent("inner/b.jpg"), width: 8, height: 8)
        return album
    }

    private func contents(of folder: URL) -> Set<String> {
        let enumerator = FileManager.default.enumerator(atPath: folder.path)
        return Set((enumerator?.allObjects as? [String]) ?? [])
    }

    @Test("Copying a folder to the same parent with keep-both preserves the source and its contents")
    func copiesFolderIntoSameParent() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let album = try makeAlbum(in: folder)
        let expected = contents(of: album)
        let operation = FileOperation(kind: .copy, sources: [album], destination: folder)
        let replaced = await service.execute(operation, resolution: .replace)
        #expect(replaced.succeeded.isEmpty)
        #expect(replaced.failed.count == 1)
        #expect(contents(of: album) == expected)
        let result = await service.execute(operation, resolution: .keepBoth)
        #expect(result.failed.isEmpty)
        let copy = try #require(result.succeeded.first)
        #expect(copy != album)
        #expect(contents(of: copy) == expected)
        #expect(contents(of: album) == expected)
    }

    @Test("Copying a folder duplicates its contents and preserves the source")
    func copiesFolderWithContents() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let album = try makeAlbum(in: folder)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [album], destination: destination),
            resolution: .abort
        )

        #expect(result.failed.isEmpty)
        let copied = destination.appendingPathComponent("album", isDirectory: true)
        #expect(contents(of: copied) == contents(of: album))
        #expect(contents(of: album).contains("inner/b.jpg"))
    }

    @Test("Moving a folder moves its contents to the destination")
    func movesFolderWithContents() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let album = try makeAlbum(in: folder)
        let expected = contents(of: album)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)

        let result = await service.execute(
            FileOperation(kind: .move, sources: [album], destination: destination),
            resolution: .abort
        )

        #expect(result.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: album.path))
        #expect(contents(of: destination.appendingPathComponent("album", isDirectory: true)) == expected)
    }

    @Test("Renaming a folder preserves its contents")
    func renamesFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let album = try makeAlbum(in: folder)
        let expected = contents(of: album)

        let result = await service.execute(
            FileOperation(kind: .rename(newName: "album 2024"), sources: [album]),
            resolution: .abort
        )

        #expect(result.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: album.path))
        #expect(contents(of: folder.appendingPathComponent("album 2024", isDirectory: true)) == expected)
    }

    @Test("Moving a folder to Trash removes it from its original location and returns its URL in Trash")
    func trashesFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let album = try makeAlbum(in: folder)

        let result = await service.execute(FileOperation(kind: .trash, sources: [album]), resolution: .abort)

        #expect(result.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: album.path))
        let trashed = try #require(result.succeeded.first)
        #expect(trashed != album)
        #expect(FileManager.default.fileExists(atPath: trashed.appendingPathComponent("inner/b.jpg").path))
        try? FileManager.default.removeItem(at: trashed)
    }

    @Test("Same-name folders conflict; replace handles the whole folder and keep-both uses a numbered name")
    func folderConflicts() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let album = try makeAlbum(in: folder)
        let destination = folder.appendingPathComponent("dest", isDirectory: true)
        let existing = destination.appendingPathComponent("album", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try ImageFixtures.jpeg(at: existing.appendingPathComponent("old.jpg"), width: 8, height: 8)

        let operation = FileOperation(kind: .copy, sources: [album], destination: destination)
        #expect(service.conflicts(for: operation) == [album])

        let kept = await service.execute(operation, resolution: .keepBoth)
        #expect(kept.failed.isEmpty)
        #expect(contents(of: destination.appendingPathComponent("album 2", isDirectory: true)) == contents(of: album))

        let replaced = await service.execute(operation, resolution: .replace)
        #expect(replaced.failed.isEmpty)
        #expect(contents(of: existing) == contents(of: album))
        #expect(!contents(of: existing).contains("old.jpg"))
    }

    @Test("Moving or copying a folder into its descendants fails and changes nothing")
    func refusesMovingFolderIntoDescendant() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let album = try makeAlbum(in: folder)
        let expected = contents(of: album)
        let inner = album.appendingPathComponent("inner", isDirectory: true)

        for kind in [FileOperation.Kind.move, .copy] {
            let result = await service.execute(
                FileOperation(kind: kind, sources: [album], destination: inner),
                resolution: .abort
            )
            #expect(result.succeeded.isEmpty)
            #expect(result.failed.first?.reason == .intoItself)
            #expect(contents(of: album) == expected)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolzioOpsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeOps(in root: URL) throws -> URL {
        try FixtureSets.ops(in: root)
        return root.appendingPathComponent("ops", isDirectory: true)
    }
}
