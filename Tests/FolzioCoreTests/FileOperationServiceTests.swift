import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("FileOperationService")
struct FileOperationServiceTests {
    private let service = FileOperationService()

    @Test("Replacing an ancestor of the source is rejected before either item changes")
    func refusesReplacingSourceAncestor() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let parent = root.appendingPathComponent("album", isDirectory: true)
        let source = parent.appendingPathComponent("album", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let marker = source.appendingPathComponent("photo.txt")
        try Data("original".utf8).write(to: marker)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)

        for kind in [FileOperation.Kind.copy, .move] {
            for path in [source, alias.appendingPathComponent("album", isDirectory: true)] {
                let result = await service.execute(
                    FileOperation(kind: kind, sources: [path], destination: root), resolution: .replace
                )
                #expect(result.succeeded.isEmpty)
                #expect(result.failed.first?.reason == .replacementContainsSource)
                #expect(try Data(contentsOf: marker) == Data("original".utf8))
            }
        }
        let kept = await service.execute(
            FileOperation(kind: .copy, sources: [source], destination: root), resolution: .keepBoth
        )
        #expect(kept.failed.isEmpty)
        #expect(try Data(contentsOf: root.appendingPathComponent("album 2/photo.txt")) == Data("original".utf8))
    }

    @Test("Replacement cannot remove another selected source")
    func refusesReplacingAncestorOfAnotherSource() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("album", isDirectory: true)
        let external = root.appendingPathComponent("external/album", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let otherSource = target.appendingPathComponent("photo.txt")
        try Data("selected".utf8).write(to: otherSource)

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [external, otherSource], destination: root), resolution: .replace
        )
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.url == external)
        #expect(result.failed.first?.reason == .replacementContainsSource)
        #expect(try Data(contentsOf: otherSource) == Data("selected".utf8))
        #expect(try Data(contentsOf: root.appendingPathComponent("photo.txt")) == Data("selected".utf8))
    }

    @Test("A similarly prefixed sibling is not treated as an ancestor")
    func allowsReplacingSimilarlyNamedSibling() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("album", isDirectory: true)
        let source = root.appendingPathComponent("album-extra/album", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source.appendingPathComponent("photo.txt"))

        let result = await service.execute(
            FileOperation(kind: .copy, sources: [source], destination: root), resolution: .replace
        )
        #expect(result.failed.isEmpty)
        #expect(try Data(contentsOf: target.appendingPathComponent("photo.txt")) == Data("source".utf8))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

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

    @Test("Case-only file renames preserve contents and store the requested spelling", arguments: [
        "Photo.png", "photo.PNG",
    ])
    func renamesFileCaseOnly(newName: String) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("photo.png")
        let bytes = Data("case-only rename".utf8)
        try bytes.write(to: source)
        let result = await service.execute(
            FileOperation(kind: .rename(newName: newName), sources: [source]), resolution: .abort
        )
        #expect(result.failed.isEmpty)
        #expect(result.succeeded.map(\.lastPathComponent) == [newName])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains(newName))
        #expect(!names.contains("photo.png"))
        #expect(try Data(contentsOf: folder.appendingPathComponent(newName)) == bytes)
    }

    @Test("Case-only rename accepts the cached URL returned by directory enumeration", arguments: [
        "Hans-veth-vyQgv-eURTU-unsplash.jpg", "hans-veth-vyQgv-eURTU-unsplash.JPG",
    ])
    func renamesEnumeratedFileCaseOnly(newName: String) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let oldName = "hans-veth-vyQgv-eURTU-unsplash.jpg"
        let bytes = Data("enumerated file".utf8)
        try bytes.write(to: folder.appendingPathComponent(oldName))
        let listed = try await DirectoryLister(kindNames: FixtureKit.kindNames).mediaFiles(in: folder)
        let source = try #require(listed.first { $0.name == oldName }).url
        let result = await service.execute(
            FileOperation(kind: .rename(newName: newName), sources: [source]), resolution: .abort
        )
        #expect(result.failed.isEmpty)
        #expect(result.succeeded.map(\.lastPathComponent) == [newName])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains(newName))
        #expect(try Data(contentsOf: folder.appendingPathComponent(newName)) == bytes)
    }

    @Test("Rename rejects a different entry for every conflict resolution", arguments: [
        ConflictResolution.abort, .replace, .keepBoth,
    ])
    func refusesRenameReplacement(resolution: ConflictResolution) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        let existing = folder.appendingPathComponent("taken.jpg")
        let before = try Data(contentsOf: source)
        try Data("other".utf8).write(to: existing)
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "TAKEN.JPG"), sources: [source]), resolution: resolution
        )
        #expect(result.succeeded.isEmpty)
        #expect(result.failed.first?.reason == .sameNameExists)
        #expect(try Data(contentsOf: source) == before)
        #expect(try Data(contentsOf: existing) == Data("other".utf8))
    }

    @Test("Rename treats links as separate entries, including dangling links", arguments: [
        "hard", "symbolic", "dangling",
    ], [ConflictResolution.abort, .replace, .keepBoth])
    func refusesRenameOverLink(linkKind: String, resolution: ConflictResolution) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        let link = folder.appendingPathComponent("other.jpg")
        let before = try Data(contentsOf: source)
        if linkKind == "hard" {
            try FileManager.default.linkItem(at: source, to: link)
        } else {
            try FileManager.default.createSymbolicLink(
                at: link, withDestinationURL: linkKind == "dangling" ? folder.appendingPathComponent("missing") : source
            )
        }
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "other.jpg"), sources: [source]), resolution: resolution
        )
        #expect(result.succeeded.isEmpty)
        #expect(result.failed.first?.reason == .sameNameExists)
        #expect(try Data(contentsOf: source) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("other.jpg"))
        if linkKind != "hard" {
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path)
                == (linkKind == "dangling" ? folder.appendingPathComponent("missing").path : source.path))
        }
    }

    @Test("Rename failures in unreadable or unwritable parents preserve the source", arguments: [0o111, 0o555])
    func refusesRenameInRestrictedParent(permissions: Int) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        let before = try Data(contentsOf: source)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: folder.path)
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "A.JPG"), sources: [source]), resolution: .abort
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        #expect(result.succeeded.isEmpty)
        let failure = try #require(result.failed.first)
        guard case .systemFailure = failure.reason else {
            Issue.record("Expected a system error, got \(failure.reason)")
            return
        }
        #expect(try Data(contentsOf: source) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("a.jpg"))
    }

    private static let hasCaseSensitiveNames: Bool = {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("FolzioCaseProbe-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try Data().write(to: root.appendingPathComponent("probe"))
            return !fm.fileExists(atPath: root.appendingPathComponent("PROBE").path)
        } catch {
            return false
        }
    }()

    @Test("Case-sensitive volumes still reject a separate case-equivalent entry",
          .enabled(if: FileOperationServiceTests.hasCaseSensitiveNames, "Requires a case-sensitive temporary volume"),
          arguments: ["file", "hard", "symbolic"], [ConflictResolution.abort, .replace, .keepBoth])
    func refusesSeparateCaseEquivalentEntry(kind: String, resolution: ConflictResolution) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("photo.png")
        let other = folder.appendingPathComponent("Photo.png")
        let bytes = Data("original".utf8)
        try bytes.write(to: source)
        switch kind {
        case "hard": try FileManager.default.linkItem(at: source, to: other)
        case "symbolic": try FileManager.default.createSymbolicLink(at: other, withDestinationURL: source)
        default: try Data("other".utf8).write(to: other)
        }
        let before = try Data(contentsOf: other)
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "PHOTO.PNG"), sources: [source]), resolution: resolution
        )
        #expect(result.succeeded.isEmpty)
        #expect(result.failed.first?.reason == .sameNameExists)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try Data(contentsOf: other) == before)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains("photo.png") && names.contains("Photo.png"))
        #expect(!names.contains("PHOTO.PNG"))
    }

    @Test("Renaming to the identical spelling is a no-op")
    func identicalRenameKeepsSource() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("a.jpg")
        let before = try Data(contentsOf: source)
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "a.jpg"), sources: [source]), resolution: .replace
        )
        #expect(result.failed.isEmpty)
        #expect(result.succeeded == [source])
        #expect(try Data(contentsOf: source) == before)
    }

    @Test("Renaming a missing source reports sourceNotFound")
    func refusesMissingRenameSource() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("missing.png")
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "Missing.png"), sources: [source]), resolution: .abort
        )
        #expect(result.succeeded.isEmpty)
        #expect(result.failed.first?.reason == .sourceNotFound)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("Case-only folder renames preserve children and store the requested spelling")
    func renamesFolderCaseOnly() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("CaseAlbum", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains("CaseAlbum"))
        let bytes = Data("child contents".utf8)
        try bytes.write(to: source.appendingPathComponent("child.png"))
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "casealbum"), sources: [source]), resolution: .abort
        )
        #expect(result.failed.isEmpty)
        #expect(result.succeeded.map(\.lastPathComponent) == ["casealbum"])
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains("casealbum"))
        #expect(!names.contains("CaseAlbum"))
        #expect(try Data(contentsOf: folder.appendingPathComponent("casealbum/child.png")) == bytes)
    }

    @Test("A folder cannot be renamed over another file or folder", arguments: [false, true])
    func refusesFolderRenameCollision(otherIsFolder: Bool) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let source = folder.appendingPathComponent("CaseAlbum", isDirectory: true)
        let other = folder.appendingPathComponent("Taken", isDirectory: otherIsFolder)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: source.appendingPathComponent("child.png"))
        if otherIsFolder {
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            try Data("other".utf8).write(to: other.appendingPathComponent("child.png"))
        } else {
            try Data("other".utf8).write(to: other)
        }
        let result = await service.execute(
            FileOperation(kind: .rename(newName: "taken"), sources: [source]), resolution: .replace
        )
        #expect(result.succeeded.isEmpty)
        #expect(result.failed.first?.reason == .sameNameExists)
        #expect(try Data(contentsOf: source.appendingPathComponent("child.png")) == Data("source".utf8))
        #expect(try Data(contentsOf: otherIsFolder ? other.appendingPathComponent("child.png") : other)
            == Data("other".utf8))
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

    @Test("Creating a folder uses the base name and leaves an empty directory (FR-209)")
    func createsFolderWithBaseName() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try makeOps(in: root)
        let before = try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))

        let created = try await service.createFolder(in: folder, baseName: "untitled folder").get()

        #expect(created == folder.appendingPathComponent("untitled folder"))
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: created.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(try FileManager.default.contentsOfDirectory(atPath: created.path).isEmpty)
        let after = try Set(FileManager.default.contentsOfDirectory(atPath: folder.path))
        #expect(after == before.union(["untitled folder"]))
    }

    @Test("Creating a folder numbers the name when any entry already uses it (FR-209)")
    func numbersCreatedFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: root.appendingPathComponent("untitled folder"),
            withIntermediateDirectories: false
        )
        try Data("x".utf8).write(to: root.appendingPathComponent("untitled folder 2"))
        let existing = try Data(contentsOf: root.appendingPathComponent("untitled folder 2"))

        let created = try await service.createFolder(in: root, baseName: "untitled folder").get()

        #expect(created.lastPathComponent == "untitled folder 3")
        #expect(try Data(contentsOf: root.appendingPathComponent("untitled folder 2")) == existing)
        #expect(try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent("untitled folder").path).isEmpty)
    }

    @Test("Creating a folder in a missing destination fails without creating anything (EC-141)")
    func refusesCreateInMissingFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        let file = root.appendingPathComponent("file.txt")
        try Data("x".utf8).write(to: file)

        for destination in [missing, file] {
            let result = await service.createFolder(in: destination, baseName: "untitled folder")
            guard case .failure(let reason) = result else {
                Issue.record("Expected a failure for \(destination.lastPathComponent)")
                continue
            }
            #expect(reason == .destinationNotFound)
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["file.txt"])
    }

    @Test("Creating a folder in an unwritable destination reports a system failure (EC-141)")
    func refusesCreateInUnwritableFolder() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: destination.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }

        let result = await service.createFolder(in: destination, baseName: "untitled folder")

        guard case .failure(let reason) = result, case .systemFailure = reason else {
            Issue.record("Expected a system failure, got \(result)")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
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
