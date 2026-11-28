import Foundation
import Testing
@testable import FolzioCore

@Suite("SearchRootList validation and organization")
struct SearchRootListTests {
    private let home = URL(fileURLWithPath: "/test-homes/me", isDirectory: true)

    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Accepts every path except those listed as failures.
    private func validator(
        failing: [String: SearchRootError] = [:]
    ) -> @Sendable (URL) async -> Result<URL, SearchRootError> {
        { url in
            if let error = failing[url.path] { return .failure(error) }
            return .success(url)
        }
    }

    @Test("Returns every valid row in order")
    func validatesAllRows() async {
        let result = await SearchRootList.validate(
            [.typed("/a"), .typed("~/b"), .picked(folder("/c "))],
            home: home,
            validate: validator()
        )
        #expect(result == .success([folder("/a").standardizedFileURL, folder("/test-homes/me/b").standardizedFileURL, folder("/c ")]))
    }

    @Test("Fails at the topmost invalid row with its index and the row count", arguments: [
        SearchRootError.notFound, .notAFolder, .accessDenied,
    ])
    func failsAtTopmostInvalidRow(error: SearchRootError) async {
        let result = await SearchRootList.validate(
            [.typed("/a"), .typed("/missing"), .typed("/other-missing")],
            home: home,
            validate: validator(failing: ["/missing": error, "/other-missing": .notFound])
        )
        #expect(result == .failure(SearchRootList.Failure(row: 1, rowCount: 3, error: error)))
    }

    @Test("A relative path fails without reading the disk")
    func relativePathFails() async {
        let result = await SearchRootList.validate(
            [.typed("/a"), .typed("relative")],
            home: home,
            validate: validator()
        )
        #expect(result == .failure(SearchRootList.Failure(row: 1, rowCount: 2, error: .notAbsolute)))
    }

    @Test("Ignores blank rows and keeps the original index of later rows")
    func ignoresBlankRows() async {
        let ok = await SearchRootList.validate([.typed("  "), .typed("/a"), .typed("")], home: home, validate: validator())
        #expect(ok == .success([folder("/a").standardizedFileURL]))

        let failed = await SearchRootList.validate(
            [.typed(" "), .typed("/missing")],
            home: home,
            validate: validator(failing: ["/missing": .notFound])
        )
        #expect(failed == .failure(SearchRootList.Failure(row: 1, rowCount: 2, error: .notFound)))
    }

    @Test("Fails with empty when every row is blank")
    func allBlankRows() async {
        let result = await SearchRootList.validate([.typed(" "), .typed("")], home: home, validate: validator())
        #expect(result == .failure(SearchRootList.Failure(row: 0, rowCount: 2, error: .empty)))
    }

    @Test("A picked row with only whitespace in its name is not blank")
    func pickedIsNotBlank() {
        #expect(!SearchRootList.isBlank(.picked(folder("/ "))))
        #expect(SearchRootList.isBlank(.typed(" \n")))
        #expect(!SearchRootList.isBlank(.typed(" /a ")))
    }

    @Test("Merges the same folder written differently and keeps the first position")
    func mergesDuplicates() {
        let organized = SearchRootList.organize(
            [folder("/b"), folder("/a/"), folder("/a/x/.."), folder("/b")],
            isSkipped: { _ in false }
        )
        #expect(organized.map(\.path) == ["/b", "/a"])
    }

    @Test("Removes a root below another root when nothing between them is skipped")
    func removesCoveredRoot() {
        let organized = SearchRootList.organize(
            [folder("/p/c/d"), folder("/q"), folder("/p")],
            isSkipped: { _ in false }
        )
        #expect(organized.map(\.path) == ["/q", "/p"])
    }

    @Test("Keeps a root below another root when a level between them, or the root itself, is skipped")
    func keepsRootBehindSkippedLevel() {
        let skipped: Set<String> = ["/p/.hidden", "/p/Lib.bundle", "/p/x/HiddenRoot"]
        let isSkipped: (URL) -> Bool = { skipped.contains($0.path) }

        let hidden = SearchRootList.organize([folder("/p"), folder("/p/.hidden/d")], isSkipped: isSkipped)
        #expect(hidden.map(\.path) == ["/p", "/p/.hidden/d"])

        let package = SearchRootList.organize([folder("/p/Lib.bundle/inner"), folder("/p")], isSkipped: isSkipped)
        #expect(package.map(\.path) == ["/p/Lib.bundle/inner", "/p"])

        let itself = SearchRootList.organize([folder("/p"), folder("/p/x/HiddenRoot")], isSkipped: isSkipped)
        #expect(itself.map(\.path) == ["/p", "/p/x/HiddenRoot"])
    }

    @Test("A sibling with a shared name prefix is not treated as below the root")
    func siblingPrefixIsNotCovered() {
        let organized = SearchRootList.organize([folder("/p"), folder("/p2")], isSkipped: { _ in false })
        #expect(organized.map(\.path) == ["/p", "/p2"])
    }

    @Test("The filesystem root covers other roots unless a hidden level is between them")
    func filesystemRoot() {
        let organized = SearchRootList.organize(
            [folder("/a/b"), folder("/"), folder("/private/var/x")],
            isSkipped: { $0.path == "/private" }
        )
        #expect(organized.map(\.path) == ["/", "/private/var/x"])
    }

    @Test("Detects names starting with a dot without reading the disk")
    func dotNamesAreSkipped() {
        #expect(SearchRootList.isSkippedByEnumeration(folder("/nonexistent-folzio-test/.hidden")))
        #expect(!SearchRootList.isSkippedByEnumeration(folder("/nonexistent-folzio-test/visible")))
    }
}
