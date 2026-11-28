import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

/// Fixtures for the maintainer checks of several search roots (TAK-104 quickstart.md).
@Suite("Multi-Root Search Fixtures")
struct MultiRootSearchFixtureTests {
    @Test("Creates the roots, the nested and hidden roots, the link, same-named roots, and ten row roots")
    func layout() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("MultiRootSearchFixtureTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        try FixtureSets.multiRootSearch(in: base)
        let root = base.appendingPathComponent("multi-root-search", isDirectory: true)
        func url(_ path: String) -> URL { root.appendingPathComponent(path) }
        func expectDirectory(_ path: String) {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url(path).path, isDirectory: &isDirectory)
            #expect(exists && isDirectory.boolValue, "Folder is missing: \(path)")
        }
        func expectFile(_ path: String) {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: url(path).path, isDirectory: &isDirectory)
            #expect(exists && !isDirectory.boolValue, "File is missing: \(path)")
        }

        for path in ["A/kyoto_folder_a", "A/C", "A/.hidden/D", "B/kyoto_folder_b",
                     "same-name/tmp1/Photos", "same-name/tmp2/photos"] {
            expectDirectory(path)
        }
        for path in ["A/kyoto_a.jpg", "A/other_a.jpg", "A/C/kyoto_c.jpg", "A/.hidden/D/kyoto_d.jpg",
                     "B/kyoto_b.jpg", "B/other_b.jpg", "B/kyoto_folder_b/kyoto_b2.png",
                     "same-name/tmp1/Photos/kyoto_p1.jpg", "same-name/tmp2/photos/kyoto_p2.jpg"] {
            expectFile(path)
        }
        for index in 1...10 {
            expectFile(String(format: "rows/%02d/kyoto_row%02d.jpg", index, index))
        }

        let link = url("link-to-A")
        let destination = try fileManager.destinationOfSymbolicLink(atPath: link.path)
        #expect(destination.hasSuffix("/A"), "Link destination: \(destination)")
    }

    @Test("A and B find their own matches, and A/C is covered by A while A/.hidden/D is not")
    func searchableLayout() async throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("MultiRootSearchFixtureTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }
        try FixtureSets.multiRootSearch(in: base)
        let root = base.appendingPathComponent("multi-root-search", isDirectory: true)
        let home = fileManager.homeDirectoryForCurrentUser

        let rows = ["A", "B", "A/C", "A/.hidden/D", "link-to-A"].map {
            SearchRootInput.typed(root.appendingPathComponent($0).path)
        }
        let validated = try await SearchRootList.validate(rows, home: home).get()
        let organized = SearchRootList.organize(validated)
        #expect(organized.map(\.lastPathComponent) == ["A", "B", "D"])

        let pattern = try #require(SearchPattern(keyword: "kyoto"))
        let searcher = FileNameSearcher(kindNames: FixtureKit.kindNames)
        var names: [String] = []
        for searchRoot in organized {
            for await batch in searcher.search(in: searchRoot, matching: pattern) {
                names += batch.map(\.name)
            }
        }
        #expect(names.sorted() == [
            "kyoto_a.jpg", "kyoto_b.jpg", "kyoto_b2.png", "kyoto_c.jpg", "kyoto_d.jpg",
            "kyoto_folder_a", "kyoto_folder_b",
        ])
    }
}
