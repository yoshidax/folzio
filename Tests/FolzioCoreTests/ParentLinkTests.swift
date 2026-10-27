import Foundation
import Testing
@testable import FolzioCore

@Suite("ParentLink")
struct ParentLinkTests {
    private let folder = URL(fileURLWithPath: "/tmp/写真 集/a#b", isDirectory: true)

    @Test("Creates an mvparent URL and returns the same URL for the same folder")
    func makesStableURL() {
        let url = ParentLink.url(for: folder)
        #expect(url.scheme == "mvparent")
        #expect(url.isFileURL == false)
        #expect(url == ParentLink.url(for: folder))
        #expect(url == ParentLink.url(for: URL(fileURLWithPath: "/tmp/写真 集/a#b/", isDirectory: true)))
        #expect(url != ParentLink.url(for: URL(fileURLWithPath: "/tmp/写真 集", isDirectory: true)))
    }

    @Test("isParentLink is true only for mvparent URLs")
    func detectsParentLink() {
        #expect(ParentLink.isParentLink(ParentLink.url(for: folder)))
        #expect(!ParentLink.isParentLink(folder))
        let zip = URL(fileURLWithPath: "/tmp/z.zip")
        #expect(!ParentLink.isParentLink(ArchiveURL.entry(archive: zip, path: "a.jpg")))
        #expect(!ParentLink.isParentLink(ArchiveURL.parentLink(of: ArchiveLocation(archive: zip, directory: ""))))
    }
}
