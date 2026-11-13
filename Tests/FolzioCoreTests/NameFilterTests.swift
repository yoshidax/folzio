import Foundation
import Testing
@testable import FolzioCore

@Suite("NameFilter")
struct NameFilterTests {
    private func file(_ name: String, _ kind: ListItemKind) -> MediaFile {
        MediaFile(
            url: URL(fileURLWithPath: "/tmp/NameFilterTests").appendingPathComponent(name),
            name: name,
            kind: kind,
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
    }

    private var rows: [MediaFile] {
        [
            file("cat01.jpg", .media(.jpeg)),
            file("Cat02.png", .media(.png)),
            file("dog.png", .media(.png)),
            file("cats", .folder),
            file("catalog.zip", .archive),
            file("cat_dir", .directory),
            file("bird.mov", .media(.mov)),
        ]
    }

    private func names(_ filter: NameFilter) -> [String] {
        filter.apply(to: rows).map(\.name)
    }

    @Test("The default filter and empty or whitespace-only text do not filter (FR-381, EC-252)")
    func emptyTextDoesNotFilter() {
        #expect(NameFilter().isFiltering == false)
        #expect(NameFilter().text == "")
        for text in ["", " ", "  \t", "\n"] {
            let filter = NameFilter(text: text)
            #expect(filter.isFiltering == false, "text=\(text.debugDescription)")
            #expect(filter.apply(to: rows) == rows)
        }
    }

    @Test("Text without wildcards matches a substring of the name, ignoring case (FR-381)")
    func substringMatch() {
        #expect(names(NameFilter(text: "cat")) == ["cat01.jpg", "Cat02.png", "cats", "catalog.zip", "cat_dir"])
        #expect(names(NameFilter(text: "PNG")) == ["Cat02.png", "dog.png"])
    }

    @Test("Text with * or ? matches the whole name (FR-381)")
    func wildcardMatch() {
        #expect(names(NameFilter(text: "*.png")) == ["Cat02.png", "dog.png"])
        #expect(names(NameFilter(text: "cat??.*")) == ["cat01.jpg", "Cat02.png"])
        #expect(names(NameFilter(text: "cat*")) == ["cat01.jpg", "Cat02.png", "cats", "catalog.zip", "cat_dir"])
        // A name with "cat" in the middle matches the substring but not "cat*", which must match from the start.
        let middle = [file("my_cat.png", .media(.png))]
        #expect(NameFilter(text: "cat").apply(to: middle).map(\.name) == ["my_cat.png"])
        #expect(NameFilter(text: "cat*").apply(to: middle).isEmpty)
    }

    @Test("Composed and decomposed dakuten are not distinguished (FR-381)")
    func normalization() {
        let decomposed = "が.png".decomposedStringWithCanonicalMapping
        let rows = [file(decomposed, .media(.png)), file("か.png", .media(.png))]
        #expect(NameFilter(text: "が").apply(to: rows).map(\.name) == [decomposed])
    }

    @Test("Folders, zip files, and directories inside a zip are matched by name like media files (FR-381)")
    func everyKindIsMatched() {
        let filtered = NameFilter(text: "cat").apply(to: rows)
        #expect(filtered.contains { $0.kind == .folder })
        #expect(filtered.contains { $0.kind == .archive })
        #expect(filtered.contains { $0.kind == .directory })
        #expect(NameFilter(text: "zzz").apply(to: rows).isEmpty)
    }

    @Test("Matching agrees with the search modal's SearchPattern (SC-208)")
    func agreesWithSearchPattern() throws {
        for text in ["cat", "*.png", "c?t*", "CAT", "が"] {
            let pattern = try #require(SearchPattern(keyword: text))
            let expected = rows.filter { pattern.matches(fileName: $0.name) }
            #expect(NameFilter(text: text).apply(to: rows) == expected, "text=\(text)")
        }
    }

    @Test("The text is kept exactly as typed, including surrounding whitespace")
    func keepsTypedText() {
        let filter = NameFilter(text: " cat ")
        #expect(filter.text == " cat ")
        #expect(filter.isFiltering)
        #expect(names(filter) == names(NameFilter(text: "cat")))
        #expect(NameFilter(text: "cat") != NameFilter(text: "cat "))
    }
}
