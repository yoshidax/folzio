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
}
