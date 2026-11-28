import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

/// Overlapping search roots on a real file system produce no duplicate rows (FR-437, SC-250; TAK-104).
@Suite("Overlapping search roots")
struct SearchRootOverlapTests {
    private struct Fixture {
        let base: URL
        let parent: URL

        func path(_ relative: String) -> String {
            parent.appendingPathComponent(relative).path
        }
    }

    /// parent/
    ///   cat_a.jpg
    ///   cat_child/ (cat_b.jpg)
    ///   .hidden/inner/ (cat_c.jpg)
    /// link -> parent
    private func makeFixture() throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchRootOverlapTests-\(UUID().uuidString)", isDirectory: true)
        let parent = base.appendingPathComponent("parent", isDirectory: true)
        let fileManager = FileManager.default
        for folder in ["cat_child", ".hidden/inner"] {
            try fileManager.createDirectory(
                at: parent.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        for file in ["cat_a.jpg", "cat_child/cat_b.jpg", ".hidden/inner/cat_c.jpg"] {
            try ImageFixtures.jpeg(at: parent.appendingPathComponent(file), width: 8, height: 8)
        }
        try fileManager.createSymbolicLink(
            at: base.appendingPathComponent("link", isDirectory: true),
            withDestinationURL: parent
        )
        return Fixture(base: base, parent: parent)
    }

    /// Validates and organizes the rows like the search sheet, then enumerates the roots one at a time.
    private func search(_ inputs: [String]) async throws -> (roots: [URL], paths: [String]) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let validated = try await SearchRootList.validate(inputs.map(SearchRootInput.typed), home: home).get()
        let roots = SearchRootList.organize(validated)
        let pattern = try #require(SearchPattern(keyword: "cat"))
        let searcher = FileNameSearcher(kindNames: FixtureKit.kindNames)
        var paths: [String] = []
        for root in roots {
            for await batch in searcher.search(in: root, matching: pattern) {
                paths += batch.map { SearchPath.normalized($0.url.resolvingSymlinksInPath()) }
            }
        }
        return (roots, paths)
    }

    @Test("The same folder twice, written differently, through a link, and with a child root gives the outer root's results")
    func coveredRootsMatchTheOuterRoot() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let outer = try await search([fixture.parent.path])
        #expect(Set(outer.paths) == Set([fixture.path("cat_a.jpg"), fixture.path("cat_child"), fixture.path("cat_child/cat_b.jpg")]
            .map { SearchPath.normalized(URL(fileURLWithPath: $0).resolvingSymlinksInPath()) }))

        let cases: [[String]] = [
            [fixture.parent.path, fixture.parent.path],
            [fixture.parent.path, fixture.parent.path + "/./"],
            [fixture.parent.path, fixture.base.appendingPathComponent("link").path],
            [fixture.parent.path, fixture.path("cat_child")],
        ]
        for inputs in cases {
            let result = try await search(inputs)
            #expect(result.roots.count == 1, "Roots for \(inputs): \(result.roots.map(\.path))")
            #expect(result.paths.count == Set(result.paths).count, "Duplicate rows for \(inputs)")
            #expect(Set(result.paths) == Set(outer.paths), "Rows for \(inputs)")
        }
    }

    @Test("A root inside a hidden folder of another root is searched too, without duplicates")
    func rootBehindHiddenFolder() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let result = try await search([fixture.parent.path, fixture.path(".hidden/inner")])
        #expect(result.roots.count == 2)
        #expect(result.paths.count == Set(result.paths).count)
        #expect(result.paths.count == 4)
        #expect(result.paths.contains { $0.hasSuffix("/.hidden/inner/cat_c.jpg") })
    }
}
