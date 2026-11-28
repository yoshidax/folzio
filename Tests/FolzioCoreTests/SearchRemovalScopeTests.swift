import Foundation
import Testing
@testable import FolzioCore

@Suite("Search removal scope")
struct SearchRemovalScopeTests {
    private let root = URL(fileURLWithPath: "/search/root", isDirectory: true)

    @Test("Removed scopes match whole path components, standardized paths, and the root")
    func matchingScopes() {
        let scope = URL(fileURLWithPath: "/search/root/trip/", isDirectory: true).standardizedFileURL.path
        #expect(SearchRemovalScope.contains(URL(fileURLWithPath: "/search/root/trip"), in: [scope]))
        #expect(SearchRemovalScope.contains(URL(fileURLWithPath: "/search/root/trip/day/../a.jpg"), in: [scope]))
        #expect(!SearchRemovalScope.contains(URL(fileURLWithPath: "/search/root/trip2/a.jpg"), in: [scope]))
        #expect(SearchRemovalScope.contains(root, in: ["/"]))
        #expect(SearchRemovalScope.contains(URL(fileURLWithPath: "/"), in: ["/"]))
        #expect(!SearchRemovalScope.contains(root, in: []))
    }

    /// Runs the lookup against a fake file system that contains only `existing`, and counts the existence checks.
    private func topmost(
        _ path: String,
        root: URL?,
        existing: Set<String>,
        known: inout [String: Bool],
        checks: inout Int
    ) -> String {
        var count = 0
        let result = SearchRemovalScope.topmostMissing(URL(fileURLWithPath: path), root: root, known: &known) { url in
            count += 1
            return existing.contains(url.standardizedFileURL.path)
        }
        checks += count
        return result.path
    }

    @Test("Records the moved folder when a whole folder is gone (EC-236)")
    func folderMovedAway() {
        var known: [String: Bool] = [:]
        var checks = 0
        let existing: Set<String> = ["/", "/search", "/search/root", "/search/root/trip"]
        #expect(topmost("/search/root/trip/day1/cat.jpg", root: root, existing: existing, known: &known, checks: &checks)
            == "/search/root/trip/day1")
    }

    @Test("Records only the file when its folder still exists")
    func onlyFileRemoved() {
        var known: [String: Bool] = [:]
        var checks = 0
        let existing: Set<String> = ["/", "/search", "/search/root", "/search/root/trip", "/search/root/trip/day2"]
        #expect(topmost("/search/root/trip/day2/a.jpg", root: root, existing: existing, known: &known, checks: &checks)
            == "/search/root/trip/day2/a.jpg")
    }

    @Test("Stops at the search root and records the root when the root itself is gone")
    func stopsAtTheRoot() {
        var known: [String: Bool] = [:]
        var checks = 0
        // Neither the root nor its parent exists; the walk must not go above the root.
        let existing: Set<String> = ["/"]
        #expect(topmost("/search/root/x/a.jpg", root: root, existing: existing, known: &known, checks: &checks)
            == "/search/root")
        #expect(known["/search"] == nil)
    }

    @Test("Checks each folder once across results in the same call")
    func checksEachFolderOnce() {
        var known: [String: Bool] = [:]
        var checks = 0
        let existing: Set<String> = ["/", "/search", "/search/root", "/search/root/trip"]
        _ = topmost("/search/root/trip/day1/a.jpg", root: root, existing: existing, known: &known, checks: &checks)
        let first = checks
        _ = topmost("/search/root/trip/day1/b.jpg", root: root, existing: existing, known: &known, checks: &checks)
        #expect(first == 2)
        #expect(checks == first)
    }

    @Test("Without a root, stops at the first existing parent")
    func withoutRoot() {
        var known: [String: Bool] = [:]
        var checks = 0
        let existing: Set<String> = ["/", "/a"]
        #expect(topmost("/a/b/c/d.jpg", root: nil, existing: existing, known: &known, checks: &checks) == "/a/b")
    }

    @Test("With several roots, stops at the root that contains the result and records only that root (EC-306)")
    func severalRoots() {
        let search = SearchListing(
            keyword: "cat",
            roots: [
                URL(fileURLWithPath: "/search/a", isDirectory: true),
                URL(fileURLWithPath: "/search/b", isDirectory: true),
            ],
            phase: .finished,
            totalCount: 0
        )
        var known: [String: Bool] = [:]
        var checks = 0
        // Root b and its folders are gone; root a still exists.
        let existing: Set<String> = ["/", "/search", "/search/a", "/search/a/x"]
        let inB = URL(fileURLWithPath: "/search/b/x/a.jpg")
        #expect(topmost(inB.path, root: search.root(containing: inB), existing: existing, known: &known, checks: &checks)
            == "/search/b")
        let inA = URL(fileURLWithPath: "/search/a/x/gone.jpg")
        #expect(topmost(inA.path, root: search.root(containing: inA), existing: existing, known: &known, checks: &checks)
            == "/search/a/x/gone.jpg")
        #expect(!SearchRemovalScope.contains(URL(fileURLWithPath: "/search/a/x/kept.jpg"), in: ["/search/b"]))
    }
}
