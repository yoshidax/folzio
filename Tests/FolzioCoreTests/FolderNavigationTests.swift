import Foundation
import Testing
@testable import FolzioCore

@Suite("FolderNavigation")
struct FolderNavigationTests {
    private static let roots = [
        URL(fileURLWithPath: "/", isDirectory: true),
        URL(fileURLWithPath: "/test-homes/me", isDirectory: true),
        URL(fileURLWithPath: "/Volumes/Ext", isDirectory: true),
    ]

    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func enclosing(_ path: String, roots: [URL] = Self.roots) -> String? {
        FolderNavigation.enclosingFolder(of: folder(path), roots: roots)?.standardizedFileURL.path
    }

    @Test("Returns nil at the root itself", arguments: ["/", "/test-homes/me", "/test-homes/me/", "/Volumes/Ext", "/Volumes/Ext/"])
    func rootHasNoEnclosingFolder(path: String) {
        #expect(enclosing(path) == nil)
    }

    @Test("Under the home folder, returns the parent within the deepest matching home root")
    func deepestRootWins() {
        #expect(enclosing("/test-homes/me/a") == "/test-homes/me")
        #expect(enclosing("/test-homes/me/a/b") == "/test-homes/me/a")
    }

    @Test("Returns parents within the startup and external volumes")
    func volumes() {
        #expect(enclosing("/test-homes/x") == "/test-homes")
        #expect(enclosing("/test-homes") == "/")
        #expect(enclosing("/Volumes/Ext/p") == "/Volumes/Ext")
    }

    @Test("Compares path components without false string-prefix matches")
    func comparesPathComponents() {
        let homeOnly = [folder("/test-homes/me")]
        #expect(enclosing("/test-homes/me2/a", roots: homeOnly) == nil)
        #expect(enclosing("/test-homes/me/./a/../b/c", roots: homeOnly) == "/test-homes/me/b")
        #expect(enclosing("/test-homes/me/./a/../b", roots: homeOnly) == "/test-homes/me")
    }

    @Test("Returns nil outside all roots or with an empty roots list")
    func outsideRoots() {
        #expect(enclosing("/Volumes/Other/a", roots: [folder("/test-homes/me"), folder("/Volumes/Ext")]) == nil)
        #expect(enclosing("/test-homes/me/a", roots: []) == nil)
    }

    // MARK: - folderToShow(afterTrashing:showing:roots:)（FR-079）

    private static let trashRoots = [
        URL(fileURLWithPath: "/", isDirectory: true),
        URL(fileURLWithPath: "/test-homes/me", isDirectory: true),
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
        #expect(shown(["/test-homes/me/a/b"], showing: "/test-homes/me/a/b") == "/test-homes/me/a")
    }

    @Test("Trashing an ancestor returns its parent, which may be the root itself")
    func trashedAncestor() {
        #expect(shown(["/test-homes/me/a"], showing: "/test-homes/me/a/b/c") == "/test-homes/me")
    }

    @Test("Multiple trashed folders return the shallowest folder's parent regardless of array order")
    func shallowestWins() {
        #expect(shown(["/test-homes/me/a/b", "/test-homes/me/a"], showing: "/test-homes/me/a/b/c") == "/test-homes/me")
        #expect(shown(["/test-homes/me/a", "/test-homes/me/a/b"], showing: "/test-homes/me/a/b/c") == "/test-homes/me")
    }

    @Test("Returns nil for siblings, descendants only, name prefixes only, empty input, roots, and an empty roots list")
    func unrelatedIsNil() {
        #expect(shown(["/test-homes/me/a/x"], showing: "/test-homes/me/a/b") == nil)
        #expect(shown(["/test-homes/me/a/b/c"], showing: "/test-homes/me/a/b") == nil)
        #expect(shown(["/test-homes/me/a/b"], showing: "/test-homes/me/a/b2") == nil)
        #expect(shown([], showing: "/test-homes/me/a/b") == nil)
        #expect(shown(["/test-homes/me"], showing: "/test-homes/me/a") == nil)
        #expect(shown(["/test-homes/me/a/b"], showing: "/test-homes/me/a/b", roots: []) == nil)
    }

    @Test("Trailing slashes and .. path representations produce the same result")
    func standardizesPaths() {
        #expect(shown(["/test-homes/me/a/b/"], showing: "/test-homes/me/a/b") == "/test-homes/me/a")
        #expect(shown(["/test-homes/me/a/b"], showing: "/test-homes/me/a/b/") == "/test-homes/me/a")
        #expect(shown(["/test-homes/me/a/x/../b"], showing: "/test-homes/me/a/b/c") == "/test-homes/me/a")
        #expect(shown(["/test-homes/me/a/b"], showing: "/test-homes/me/a/x/../b") == "/test-homes/me/a")
    }

    // MARK: - Vanished Displayed Folder (FR-042, EC-13)

    @Test("Detects the folder itself or an ancestor among reported folders by path components")
    func containsFolderOrAncestor() {
        let showing = folder("/a/b/c")
        #expect(FolderNavigation.containsFolderOrAncestor(of: showing, in: [folder("/a/b/c")]))
        #expect(FolderNavigation.containsFolderOrAncestor(of: showing, in: [folder("/a/b")]))
        #expect(FolderNavigation.containsFolderOrAncestor(of: showing, in: [folder("/x"), folder("/a")]))
        #expect(!FolderNavigation.containsFolderOrAncestor(of: showing, in: [folder("/a/b/c/d")]))
        #expect(!FolderNavigation.containsFolderOrAncestor(of: showing, in: [folder("/a/b2")]))
        #expect(!FolderNavigation.containsFolderOrAncestor(of: showing, in: []))
    }

    @Test("Matches /private/var and /var forms of the same folder")
    func containsFolderOrAncestorNormalizesPrivate() {
        #expect(FolderNavigation.containsFolderOrAncestor(of: folder("/private/var/t/a/b"), in: [folder("/var/t/a")]))
        #expect(FolderNavigation.containsFolderOrAncestor(of: folder("/var/t/a/b"), in: [folder("/private/var/t")]))
    }

    @Test("Returns the nearest existing ancestor and the shallowest vanished folder")
    func nearestExistingAncestor() throws {
        let existing: Set<String> = ["/", "/a"]
        let result = try #require(
            FolderNavigation.nearestExistingAncestor(of: folder("/a/b/c")) {
                existing.contains($0.standardizedFileURL.path)
            }
        )
        #expect(result.folder.standardizedFileURL.path == "/a")
        #expect(result.vanished.standardizedFileURL.path == "/a/b")
    }

    @Test("Returns the parent when it exists and nil when no ancestor exists")
    func nearestExistingAncestorBounds() throws {
        let parent = try #require(FolderNavigation.nearestExistingAncestor(of: folder("/a/b")) { _ in true })
        #expect(parent.folder.standardizedFileURL.path == "/a")
        #expect(parent.vanished.standardizedFileURL.path == "/a/b")
        #expect(FolderNavigation.nearestExistingAncestor(of: folder("/a/b")) { _ in false } == nil)
    }

    @Test("Keeps a vanished folder inside the deepest root that contains it")
    func staysInsideRoot() {
        let roots = [folder("/"), folder("/test-homes/me"), folder("/Volumes/Ext")]
        func stays(_ from: String, _ to: String, roots custom: [URL]? = nil) -> Bool {
            FolderNavigation.staysInsideRoot(from: folder(from), to: folder(to), roots: custom ?? roots)
        }
        #expect(stays("/Volumes/Ext/a/b", "/Volumes/Ext"))
        #expect(stays("/Volumes/Ext/a/b", "/Volumes/Ext/a"))
        #expect(!stays("/Volumes/Ext/a/b", "/Volumes"))
        #expect(!stays("/test-homes/me/a", "/test-homes"))
        #expect(stays("/opt/a", "/opt"))
        #expect(stays("/a/b", "/a", roots: []))
    }
}
