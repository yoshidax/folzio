import Foundation
import Testing
@testable import FolzioCore

@Suite("ArchiveURL")
struct ArchiveURLTests {
    private let archive = URL(fileURLWithPath: "/tmp/z/写真 集.zip")

    @Test("Entry URLs use the mvzip scheme and return the name and extension")
    func entryURLShape() {
        let url = ArchiveURL.entry(archive: archive, path: "sub/a b.jpg")
        #expect(url.scheme == "mvzip")
        #expect(url.lastPathComponent == "a b.jpg")
        #expect(url.pathExtension == "jpg")
        #expect(url.isFileURL == false)
    }

    @Test("parse restores the original values")
    func parseRoundTrip() throws {
        let url = ArchiveURL.entry(archive: archive, path: "sub/a b.jpg")
        let parsed = try #require(ArchiveURL.parse(url))
        #expect(parsed.archive == archive)
        #expect(parsed.path == "sub/a b.jpg")
        #expect(parsed.isParentLink == false)
    }

    @Test("Round-trips paths containing Japanese, spaces, #, ?, and %, including the zip path")
    func parseRoundTripWithSpecialCharacters() throws {
        let archives = [
            archive,
            URL(fileURLWithPath: "/tmp/z/a#b?c%d;e f.zip"),
            URL(fileURLWithPath: "/tmp/日本語/フォルダ 1/写真.zip"),
        ]
        let paths = [
            "写真/日本語 name.jpg",
            "a#b/c?d/e%20f.png",
            "100%/;semi;/x.gif",
            "sp ace/",
        ]
        for archive in archives {
            for path in paths {
                let url = ArchiveURL.entry(archive: archive, path: path)
                let parsed = try #require(ArchiveURL.parse(url))
                #expect(parsed.archive == archive)
                #expect(parsed.path == path)
                #expect(parsed.isParentLink == false)
            }
        }
    }

    @Test("Directories keep a trailing / and the root has an empty path")
    func directoryAndRoot() throws {
        let directory = ArchiveURL.entry(archive: archive, path: "sub/")
        #expect(try #require(ArchiveURL.parse(directory)).path == "sub/")
        #expect(directory.absoluteString.hasPrefix("mvzip:///sub/?archive="))

        let root = ArchiveURL.entry(archive: archive, path: "")
        #expect(root.absoluteString.hasPrefix("mvzip:///?archive="))
        let parsed = try #require(ArchiveURL.parse(root))
        #expect(parsed.path == "")
        #expect(parsed.archive == archive)
    }

    @Test("parentLink uses the parent fragment and only equal levels compare equal")
    func parentLink() throws {
        let location = ArchiveLocation(archive: archive, directory: "sub/")
        let link = ArchiveURL.parentLink(of: location)
        #expect(link.fragment == "parent")
        let parsed = try #require(ArchiveURL.parse(link))
        #expect(parsed.isParentLink == true)
        #expect(parsed.path == "sub/")
        #expect(parsed.archive == archive)

        #expect(link == ArchiveURL.parentLink(of: ArchiveLocation(archive: archive, directory: "sub/")))
        #expect(link != ArchiveURL.parentLink(of: ArchiveLocation(archive: archive, directory: "")))
        #expect(link != ArchiveURL.parentLink(of: ArchiveLocation(archive: archive, directory: "sub/deep/")))
        #expect(link != ArchiveURL.entry(archive: archive, path: "sub/"))
    }

    @Test("URLs created with the same arguments are equal and deduplicate in a Set")
    func equalityAndHashing() {
        let first = ArchiveURL.entry(archive: archive, path: "sub/a b.jpg")
        let second = ArchiveURL.entry(archive: archive, path: "sub/a b.jpg")
        #expect(first == second)
        let set: Set<URL> = [first, second, ArchiveURL.entry(archive: archive, path: "sub/c.jpg")]
        #expect(set.count == 2)
    }

    @Test("parse returns nil for file URLs and schemes other than mvzip")
    func parseRejectsOtherSchemes() {
        #expect(ArchiveURL.parse(URL(fileURLWithPath: "/tmp/a.jpg")) == nil)
        #expect(ArchiveURL.parse(URL(string: "other:///a.jpg?archive=%2Ftmp%2Fz.zip")!) == nil)
    }

    @Test("parse rejects mvzip URLs without an archive")
    func parseRejectsMissingArchive() {
        #expect(ArchiveURL.parse(URL(string: "mvzip:///a.jpg")!) == nil)
    }

    @Test("ArchiveLocation.parent returns the enclosing level and nil at the root")
    func locationParent() {
        let deep = ArchiveLocation(archive: archive, directory: "a/b/")
        #expect(deep.parent == ArchiveLocation(archive: archive, directory: "a/"))
        #expect(deep.parent?.parent == ArchiveLocation(archive: archive, directory: ""))
        #expect(deep.parent?.parent?.parent == nil)
    }
}
