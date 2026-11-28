import Foundation
import Testing
@testable import FolzioCore

@Suite("SearchListing")
struct SearchListingTests {
    private func listing(root: String, isDirectory: Bool = true) -> SearchListing {
        SearchListing(
            keyword: "cat",
            root: URL(fileURLWithPath: root, isDirectory: isDirectory),
            phase: .searching,
            totalCount: 0
        )
    }

    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    @Test("Joins the root folder name with the relative path to the folder containing the file")
    func locationUnderRoot() {
        let search = listing(root: "/test-homes/me/Pictures")
        #expect(search.location(of: file("/test-homes/me/Pictures/a.jpg")) == "Pictures")
        #expect(search.location(of: file("/test-homes/me/Pictures/2024/trip/a.jpg")) == "Pictures/2024/trip")
    }

    @Test("Uses an absolute path when the root is /")
    func locationUnderFilesystemRoot() {
        let search = listing(root: "/")
        #expect(search.location(of: file("/test-homes/me/a.jpg")) == "/test-homes/me")
        #expect(search.location(of: file("/a.jpg")) == "/")
    }

    @Test("Paths containing spaces and Japanese, and a root with a trailing /")
    func locationWithSpacesAndJapanese() {
        let expected = "写真 2024/旅行"
        let path = "/test-homes/me/写真 2024/旅行/a.jpg"
        #expect(listing(root: "/test-homes/me/写真 2024").location(of: file(path)) == expected)
        let trailing = SearchListing(
            keyword: "cat",
            root: URL(string: "file:///test-homes/me/%E5%86%99%E7%9C%9F%202024/")!,
            phase: .finished,
            totalCount: 0
        )
        #expect(trailing.root.absoluteString.hasSuffix("/"))
        #expect(trailing.location(of: file(path)) == expected)
    }

    private func listing(roots: [String]) -> SearchListing {
        SearchListing(
            keyword: "cat",
            roots: roots.map { URL(fileURLWithPath: $0, isDirectory: true) },
            phase: .finished,
            totalCount: 0
        )
    }

    @Test("Each item starts from the root that contains it")
    func locationWithMultipleRoots() {
        let search = listing(roots: ["/test-homes/me/Pictures", "/Volumes/Disk/Archive"])
        #expect(search.location(of: file("/test-homes/me/Pictures/2024/a.jpg")) == "Pictures/2024")
        #expect(search.location(of: file("/Volumes/Disk/Archive/b.jpg")) == "Archive")
        #expect(search.root(containing: file("/Volumes/Disk/Archive/x/b.jpg"))?.path == "/Volumes/Disk/Archive")
        #expect(search.root(containing: file("/elsewhere/c.jpg")) == nil)
    }

    @Test("A root nested behind a hidden folder of another root contains its own items")
    func nestedRootWins() {
        let search = listing(roots: ["/p", "/p/.hidden/d"])
        #expect(search.root(containing: file("/p/.hidden/d/e/a.jpg"))?.path == "/p/.hidden/d")
        #expect(search.location(of: file("/p/.hidden/d/e/a.jpg")) == "d/e")
        #expect(search.location(of: file("/p/x/a.jpg")) == "p/x")
    }

    @Test("Roots with the same folder name, ignoring case, start from their absolute paths")
    func sharedRootNames() {
        let search = listing(roots: ["/Volumes/X/Photos", "/test-homes/me/photos", "/test-homes/me/Other"])
        #expect(search.location(of: file("/Volumes/X/Photos/2024/a.jpg")) == "/Volumes/X/Photos/2024")
        #expect(search.location(of: file("/test-homes/me/photos/b.jpg")) == "/test-homes/me/photos")
        #expect(search.location(of: file("/test-homes/me/Other/c.jpg")) == "Other")
    }

    @Test("Summarizes the roots for the search bar and lists their absolute paths in order")
    func rootSummary() {
        #expect(listing(root: "/test-homes/me/Pictures").rootSummary == .single("Pictures"))
        #expect(listing(root: "/").rootSummary == .single("/"))
        let search = listing(roots: ["/a/First", "/b/Second", "/"])
        #expect(search.rootSummary == .multiple(first: "First", others: 2))
        #expect(search.rootPaths == ["/a/First", "/b/Second", "/"])
        #expect(search.root.path == "/a/First")
    }
}
