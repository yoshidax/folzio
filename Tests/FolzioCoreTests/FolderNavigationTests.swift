import Foundation
import Testing
@testable import FolzioCore

@Suite("FolderNavigation")
struct FolderNavigationTests {
    private static let roots = [
        URL(fileURLWithPath: "/", isDirectory: true),
        URL(fileURLWithPath: "/Users/me", isDirectory: true),
        URL(fileURLWithPath: "/Volumes/Ext", isDirectory: true),
    ]

    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func enclosing(_ path: String, roots: [URL] = Self.roots) -> String? {
        FolderNavigation.enclosingFolder(of: folder(path), roots: roots)?.standardizedFileURL.path
    }

    @Test("Returns nil at the root itself", arguments: ["/", "/Users/me", "/Users/me/", "/Volumes/Ext", "/Volumes/Ext/"])
    func rootHasNoEnclosingFolder(path: String) {
        #expect(enclosing(path) == nil)
    }

    @Test("Under the home folder, returns the parent within the deepest matching home root")
    func deepestRootWins() {
        #expect(enclosing("/Users/me/a") == "/Users/me")
        #expect(enclosing("/Users/me/a/b") == "/Users/me/a")
    }

    @Test("Returns parents within the startup and external volumes")
    func volumes() {
        #expect(enclosing("/Users/x") == "/Users")
        #expect(enclosing("/Users") == "/")
        #expect(enclosing("/Volumes/Ext/p") == "/Volumes/Ext")
    }

    @Test("Compares path components without false string-prefix matches")
    func comparesPathComponents() {
        let homeOnly = [folder("/Users/me")]
        #expect(enclosing("/Users/me2/a", roots: homeOnly) == nil)
        #expect(enclosing("/Users/me/./a/../b/c", roots: homeOnly) == "/Users/me/b")
        #expect(enclosing("/Users/me/./a/../b", roots: homeOnly) == "/Users/me")
    }

    @Test("Returns nil outside all roots or with an empty roots list")
    func outsideRoots() {
        #expect(enclosing("/Volumes/Other/a", roots: [folder("/Users/me"), folder("/Volumes/Ext")]) == nil)
        #expect(enclosing("/Users/me/a", roots: []) == nil)
    }

    // MARK: - folderToShow(afterTrashing:showing:roots:)（FR-079）

    private static let trashRoots = [
        URL(fileURLWithPath: "/", isDirectory: true),
        URL(fileURLWithPath: "/Users/me", isDirectory: true),
    ]

    private func shown(_ trashed: [String], showing: String, roots: [URL] = Self.trashRoots) -> String? {
        FolderNavigation.folderToShow(
            afterTrashing: trashed.map { folder($0) },
            showing: folder(showing),
            roots: roots
        )?.standardizedFileURL.path
    }

    @Test("Trashing the current folder returns its parent")
    func trashedShowingFolder() {
        #expect(shown(["/Users/me/a/b"], showing: "/Users/me/a/b") == "/Users/me/a")
    }

    @Test("Trashing an ancestor returns its parent, which may be the root itself")
    func trashedAncestor() {
        #expect(shown(["/Users/me/a"], showing: "/Users/me/a/b/c") == "/Users/me")
    }

    @Test("Multiple trashed folders return the shallowest folder's parent regardless of array order")
    func shallowestWins() {
        #expect(shown(["/Users/me/a/b", "/Users/me/a"], showing: "/Users/me/a/b/c") == "/Users/me")
        #expect(shown(["/Users/me/a", "/Users/me/a/b"], showing: "/Users/me/a/b/c") == "/Users/me")
    }

    @Test("Returns nil for siblings, descendants only, name prefixes only, empty input, roots, and an empty roots list")
    func unrelatedIsNil() {
        #expect(shown(["/Users/me/a/x"], showing: "/Users/me/a/b") == nil)
        #expect(shown(["/Users/me/a/b/c"], showing: "/Users/me/a/b") == nil)
        #expect(shown(["/Users/me/a/b"], showing: "/Users/me/a/b2") == nil)
        #expect(shown([], showing: "/Users/me/a/b") == nil)
        #expect(shown(["/Users/me"], showing: "/Users/me/a") == nil)
        #expect(shown(["/Users/me/a/b"], showing: "/Users/me/a/b", roots: []) == nil)
    }

    @Test("Trailing slashes and .. path representations produce the same result")
    func standardizesPaths() {
        #expect(shown(["/Users/me/a/b/"], showing: "/Users/me/a/b") == "/Users/me/a")
        #expect(shown(["/Users/me/a/b"], showing: "/Users/me/a/b/") == "/Users/me/a")
        #expect(shown(["/Users/me/a/x/../b"], showing: "/Users/me/a/b/c") == "/Users/me/a")
        #expect(shown(["/Users/me/a/b"], showing: "/Users/me/a/x/../b") == "/Users/me/a")
    }
}
