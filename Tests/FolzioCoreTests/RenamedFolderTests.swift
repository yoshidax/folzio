import Foundation
import Testing
@testable import FolzioCore

@Suite("RenamedFolder")
struct RenamedFolderTests {
    private let renamed = RenamedFolder(
        from: URL(fileURLWithPath: "/tmp/r/Album/2025"),
        to: URL(fileURLWithPath: "/tmp/r/Album/2025b")
    )

    @Test("Rebases the renamed folder itself; a URL marked as a directory produces a directory result")
    func rebasesFolderItself() {
        #expect(renamed.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025"))?.path == "/tmp/r/Album/2025b")
        let directory = renamed.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025/", isDirectory: true))
        #expect(directory?.path == "/tmp/r/Album/2025b")
        #expect(directory?.hasDirectoryPath == true)
    }

    @Test("Rebases URLs under the folder")
    func rebasesDescendants() {
        #expect(
            renamed.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025/Trip/a.jpg"))?.path
                == "/tmp/r/Album/2025b/Trip/a.jpg"
        )
    }

    @Test("reversed rebases from the new location back to the original")
    func reversedRebasesBack() {
        let reversed = renamed.reversed
        #expect(reversed.from.path == "/tmp/r/Album/2025b")
        #expect(reversed.to.path == "/tmp/r/Album/2025")
        #expect(reversed.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025b"))?.path == "/tmp/r/Album/2025")
        #expect(
            reversed.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025b/Trip/a.jpg"))?.path
                == "/tmp/r/Album/2025/Trip/a.jpg"
        )
        #expect(reversed.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025")) == nil)
        #expect(renamed.reversed.reversed.from.path == renamed.from.path)
    }

    @Test("Does not rebase sibling folders whose names share a prefix", arguments: [
        "/tmp/r/Album/20250/a.jpg",
        "/tmp/r/Album/2025b/a.jpg",
    ])
    func ignoresSiblingsWithSharedPrefix(path: String) {
        #expect(renamed.rebase(URL(fileURLWithPath: path)) == nil)
    }

    @Test("Returns nil for unrelated URLs; rebaseOrSelf returns the original URL", arguments: [
        "/tmp/r/Album/Other",
        "/tmp/r/Album",
        "/tmp/x",
    ])
    func ignoresUnrelatedURLs(path: String) {
        let url = URL(fileURLWithPath: path)
        #expect(renamed.rebase(url) == nil)
        #expect(renamed.rebaseOrSelf(url) == url)
    }

    @Test("Rebases URLs containing spelling differences (. and ..)", arguments: [
        "/tmp/r/Album/./2025/a.jpg",
        "/tmp/r/Album/x/../2025/a.jpg",
    ])
    func rebasesNonStandardizedURLs(path: String) {
        #expect(renamed.rebase(URL(fileURLWithPath: path))?.path == "/tmp/r/Album/2025b/a.jpg")
    }

    @Test("Rebuilds entries inside a zip and .. by rebasing the zip location")
    func rebasesArchiveURLs() {
        let oldArchive = URL(fileURLWithPath: "/tmp/r/Album/2025/t.zip")
        let newArchive = URL(fileURLWithPath: "/tmp/r/Album/2025b/t.zip")
        #expect(
            renamed.rebase(ArchiveURL.entry(archive: oldArchive, path: "dir/a.jpg"))
                == ArchiveURL.entry(archive: newArchive, path: "dir/a.jpg")
        )
        #expect(
            renamed.rebase(ArchiveURL.parentLink(of: ArchiveLocation(archive: oldArchive, directory: "dir/")))
                == ArchiveURL.parentLink(of: ArchiveLocation(archive: newArchive, directory: "dir/"))
        )
        let unrelated = URL(fileURLWithPath: "/tmp/r/Other/t.zip")
        #expect(renamed.rebase(ArchiveURL.entry(archive: unrelated, path: "a.jpg")) == nil)
    }

    @Test("Returns nil for .. of a regular folder and for non-file schemes")
    func ignoresOtherSchemes() {
        #expect(renamed.rebase(ParentLink.url(for: URL(fileURLWithPath: "/tmp/r/Album/2025"))) == nil)
        #expect(renamed.rebase(URL(string: "https://example.com/")!) == nil)
    }

    @Test("Returns the same location for itself and descendants when from and to are equal")
    func sameLocationKeepsURLs() {
        let same = RenamedFolder(from: renamed.from, to: renamed.from)
        #expect(same.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025"))?.path == "/tmp/r/Album/2025")
        #expect(same.rebase(URL(fileURLWithPath: "/tmp/r/Album/2025/a.jpg"))?.path == "/tmp/r/Album/2025/a.jpg")
    }
}
