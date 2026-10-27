import CoreFoundation
import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("ArchiveIndex")
struct ArchiveIndexTests {
    private let archive = URL(fileURLWithPath: "/tmp/test.zip")

    private func makeIndex(_ entries: [ZipFixtureEntry]) throws -> ArchiveIndex {
        let data = try ZipFixtureWriter.archiveData(entries)
        let end = try ZipStructure.endOfCentralDirectory(
            inTail: Data(data.suffix(65_557)), fileSize: UInt64(data.count)
        )
        let start = Int(end.location.offset)
        let directory = Data(data[start..<start + Int(end.location.size)])
        let central = try ZipStructure.centralDirectoryEntries(directory, count: end.location.entryCount)
        return ArchiveIndex(
            archive: archive,
            identity: ArchiveIdentity(
                fileSize: UInt64(data.count),
                modificationDate: Date(timeIntervalSince1970: 0),
                inode: 1
            ),
            centralEntries: central,
            kindNames: FixtureKit.kindNames
        )
    }

    private func file(_ name: String, _ text: String = "x") -> ZipFixtureEntry {
        ZipFixtureEntry(name: name, content: .bytes(Data(text.utf8)))
    }

    private func names(_ items: [MediaFile]) -> [String] {
        items.map(\.name).sorted()
    }

    @Test("Synthesizes intermediate directories even without explicit directory entries")
    func synthesizesDirectories() throws {
        let index = try makeIndex([file("sub/deep/a.jpg")])

        let top = index.items(in: "")
        #expect(top.map(\.name) == ["sub"])
        #expect(top[0].kind == .directory)

        let sub = index.items(in: "sub/")
        #expect(sub.map(\.name) == ["deep"])
        #expect(sub[0].kind == .directory)

        let deep = index.items(in: "sub/deep/")
        #expect(deep.map(\.name) == ["a.jpg"])
        #expect(deep[0].kind == .media(.jpeg))
    }

    @Test("Excludes hidden entries, __MACOSX, .., and unsupported media")
    func excludesHiddenAndUnsupported() throws {
        let index = try makeIndex([
            file(".hidden.jpg"),
            file(".git/x.png"),
            file("__MACOSX/._a.jpg"),
            file("a/../b.jpg"),
            file("readme.txt"),
            file("inner.zip"),
            file("sub/.DS_Store"),
            file("sub/.secret/c.png"),
            file("visible.jpg"),
            file("noextension"),
        ])
        #expect(names(index.items(in: "")) == ["visible.jpg"])
        #expect(index.items(in: ".git/").isEmpty)
        #expect(index.items(in: "__MACOSX/").isEmpty)
        #expect(index.items(in: "a/").isEmpty)
        #expect(index.entry(at: ".hidden.jpg") == nil)
        #expect(index.entry(at: "readme.txt") == nil)
    }

    @Test("Removes leading slashes, empty components, and dots; backslashes remain part of names")
    func normalizesPaths() throws {
        let index = try makeIndex([
            file("/x//./y.png"),
            file("a\\b.jpg"),
        ])
        #expect(index.items(in: "").map(\.name).sorted() == ["a\\b.jpg", "x"])
        #expect(index.items(in: "x/").map(\.name) == ["y.png"])
        #expect(index.entry(at: "x/y.png")?.name == "y.png")
        #expect(index.entry(at: "a\\b.jpg")?.name == "a\\b.jpg")
    }

    @Test("Uses the first entry when paths are duplicated")
    func duplicatesUseFirst() throws {
        let index = try makeIndex([
            file("dup.jpg", "first"),
            file("dup.jpg", "second entry"),
        ])
        let items = index.items(in: "")
        #expect(items.count == 1)
        #expect(items[0].fileSize == 5)
        #expect(index.entry(at: "dup.jpg")?.uncompressedSize == 5)
    }

    @Test("Treats a file and directory with the same name as a directory", arguments: [true, false])
    func directoryWinsOverFile(fileFirst: Bool) throws {
        let fileEntry = file("pic.jpg")
        let directoryEntry = ZipFixtureEntry(name: "pic.jpg", isDirectory: true)
        let index = try makeIndex(fileFirst ? [fileEntry, directoryEntry] : [directoryEntry, fileEntry])
        let items = index.items(in: "")
        #expect(items.count == 1)
        #expect(items[0].name == "pic.jpg")
        #expect(items[0].kind == .directory)
    }

    @Test("Treats a file sharing the name of a nonempty directory as a directory")
    func implicitDirectoryWinsOverFile() throws {
        let index = try makeIndex([file("pic.jpg"), file("pic.jpg/inner.png")])
        let items = index.items(in: "")
        #expect(items.count == 1)
        #expect(items[0].kind == .directory)
        #expect(index.items(in: "pic.jpg/").map(\.name) == ["inner.png"])
    }

    @Test("readability: methods 0 and 8 are readable, encryption is encrypted, and method 12 is unsupportedMethod")
    func readability() throws {
        let index = try makeIndex([
            ZipFixtureEntry(name: "stored.jpg", content: .bytes(Data("a".utf8)), method: .stored),
            ZipFixtureEntry(name: "deflated.jpg", content: .bytes(Data("a".utf8)), method: .deflated),
            ZipFixtureEntry(name: "encrypted.jpg", content: .bytes(Data("a".utf8)), encryptedFlag: true),
            ZipFixtureEntry(name: "bzip2.jpg", content: .bytes(Data("a".utf8)), method: .raw(12)),
        ])
        #expect(index.entry(at: "stored.jpg")?.readability == .readable)
        #expect(index.entry(at: "deflated.jpg")?.readability == .readable)
        #expect(index.entry(at: "encrypted.jpg")?.readability == .encrypted)
        #expect(index.entry(at: "encrypted.jpg")?.isEncrypted == true)
        #expect(index.entry(at: "bzip2.jpg")?.readability == .unsupportedMethod)
        #expect(index.entry(at: "bzip2.jpg")?.method == 12)
        #expect(index.items(in: "").count == 4)
    }

    @Test("Row values include the name, modification date, inflated size, kind, and URL")
    func rowValues() throws {
        let modified = Date(timeIntervalSince1970: 1_650_000_002)
        let content = Data(repeating: 0x61, count: 1234)
        let index = try makeIndex([
            ZipFixtureEntry(
                name: "folder/photo.jpg", content: .bytes(content), method: .deflated,
                unixModificationTime: modified
            ),
            ZipFixtureEntry(name: "folder", isDirectory: true),
        ])
        let directory = try #require(index.items(in: "").first)
        #expect(directory.name == "folder")
        #expect(directory.kind == .directory)
        #expect(directory.typeDescription == FixtureKit.kindNames.folder)
        #expect(directory.fileSize == 0)
        #expect(directory.url == ArchiveURL.entry(archive: archive, path: "folder/"))

        let photo = try #require(index.items(in: "folder/").first)
        #expect(photo.name == "photo.jpg")
        #expect(photo.kind == .media(.jpeg))
        #expect(!photo.typeDescription.isEmpty)
        #expect(photo.creationDate == modified)
        #expect(photo.fileSize == 1234)
        #expect(photo.url == ArchiveURL.entry(archive: archive, path: "folder/photo.jpg"))
        #expect(index.entry(at: "folder/photo.jpg")?.uncompressedSize == 1234)
    }

    @Test("Uses the DOS date as the modification date when no extended timestamp exists")
    func dosModificationDate() throws {
        let modified = Date(timeIntervalSince1970: 1_700_000_000)
        let index = try makeIndex([
            ZipFixtureEntry(name: "a.png", content: .bytes(Data("a".utf8)), modificationDate: modified),
        ])
        let date = try #require(index.items(in: "").first?.creationDate)
        #expect(abs(date.timeIntervalSince(modified)) <= 2)
    }

    @Test("items excludes .. and returns an empty array for nonexistent levels")
    func noParentRowAndMissingDirectory() throws {
        let index = try makeIndex([file("sub/a.jpg")])
        #expect(!index.items(in: "").contains { $0.kind == .parent || $0.name == ".." })
        #expect(!index.items(in: "sub/").contains { $0.kind == .parent || $0.name == ".." })
        #expect(index.items(in: "missing/").isEmpty)
        #expect(index.items(in: "sub/a.jpg").isEmpty)
    }

    @Test("Builds the hierarchy from CP932 names without the UTF-8 flag (FR-074)")
    func cp932Names() throws {
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
            )
        )
        let rawName = try #require("フォルダ/画像.png".data(using: encoding))
        let index = try makeIndex([
            ZipFixtureEntry(
                name: "ignored", rawName: rawName, content: .bytes(Data("a".utf8)), utf8Flag: false
            ),
        ])
        #expect(index.items(in: "").map(\.name) == ["フォルダ"])
        #expect(index.items(in: "フォルダ/").map(\.name) == ["画像.png"])
        #expect(index.entry(at: "フォルダ/画像.png")?.path == "フォルダ/画像.png")
    }

    @Test("Retains the identity and zip URL")
    func keepsIdentityAndArchive() throws {
        let index = try makeIndex([file("a.jpg")])
        #expect(index.archive == archive)
        #expect(index.identity.inode == 1)
        #expect(index.identity.modificationDate == Date(timeIntervalSince1970: 0))
        #expect(index.identity.fileSize > 0)
    }

    @Test("entry(at:) finds directory entries by paths with a trailing slash")
    func entryLookupForDirectories() throws {
        let index = try makeIndex([file("sub/deep/a.jpg")])
        #expect(index.entry(at: "sub/")?.isDirectory == true)
        #expect(index.entry(at: "sub/deep/")?.name == "deep")
        #expect(index.entry(at: "sub/deep/a.jpg")?.isDirectory == false)
        #expect(index.entry(at: "nothing") == nil)
    }

    @Test("containsDirectory is true only for the root and existing directories")
    func containsDirectory() throws {
        let explicit = try makeIndex([
            file("a/"),
            file("a/b/"),
            file("a/b/1.jpg"),
            file("photo.jpg"),
        ])
        #expect(explicit.containsDirectory(""))
        #expect(explicit.containsDirectory("a/"))
        #expect(explicit.containsDirectory("a/b/"))
        #expect(explicit.containsDirectory("c/") == false)
        #expect(explicit.containsDirectory("a/c/") == false)
        #expect(explicit.containsDirectory("a/b/1.jpg") == false)

        let implicit = try makeIndex([file("a/b/1.jpg")])
        #expect(implicit.containsDirectory("a/"))
        #expect(implicit.containsDirectory("a/b/"))
        #expect(implicit.containsDirectory("a/b/1.jpg") == false)
        #expect(implicit.containsDirectory("b/") == false)
    }
}
