import Foundation
import Testing
@testable import FolzioCore

@Suite("SearchPattern")
struct SearchPatternTests {
    private let nfdGa = "か\u{3099}.png".decomposedStringWithCanonicalMapping

    private func pattern(_ keyword: String) throws -> SearchPattern {
        try #require(SearchPattern(keyword: keyword))
    }

    @Test("Returns nil for empty or whitespace-only keywords; trims whitespace and records wildcard presence")
    func initTrimsAndRejectsEmpty() throws {
        #expect(SearchPattern(keyword: "") == nil)
        #expect(SearchPattern(keyword: "  ") == nil)
        #expect(SearchPattern(keyword: "\n\t") == nil)
        #expect(try pattern(" cat ").keyword == "cat")
        #expect(try pattern("cat").usesWildcards == false)
        #expect(try pattern("*.png").usesWildcards == true)
        #expect(try pattern("IMG_?.jpg").usesWildcards == true)
        #expect(try pattern("[1].jpg").usesWildcards == false)
    }

    @Test("Without wildcards, matches a substring of the file name including the extension, case-insensitively")
    func substringMatch() throws {
        let cat = try pattern("cat")
        #expect(cat.matches(fileName: "Cat01.jpg"))
        #expect(cat.matches(fileName: "my_cat.mov"))
        #expect(cat.matches(fileName: "CAT.PNG"))
        #expect(!cat.matches(fileName: "dog.png"))
        #expect(try pattern("png").matches(fileName: "a.png"))
    }

    @Test("Ignores NFC/NFD differences but distinguishes dakuten, full-width, and hiragana/katakana")
    func normalization() throws {
        #expect(nfdGa.unicodeScalars.contains("\u{3099}"))
        #expect(try pattern("が").matches(fileName: nfdGa))
        #expect(try pattern("が".decomposedStringWithCanonicalMapping).matches(fileName: "が.png"))
        #expect(!(try pattern("か").matches(fileName: "が.png")))
        #expect(!(try pattern("ｃａｔ").matches(fileName: "cat.jpg")))
        #expect(!(try pattern("ネコ").matches(fileName: "ねこ.jpg")))
    }

    @Test("With wildcards, matches the whole file name")
    func wildcardMatch() throws {
        let png = try pattern("*.png")
        #expect(png.matches(fileName: "a.png"))
        #expect(!png.matches(fileName: "a.png.txt"))
        #expect(!png.matches(fileName: "a.PNG.bak"))
        #expect(try pattern("*.PNG").matches(fileName: "a.png"))

        let img = try pattern("IMG_????.jpg")
        #expect(img.matches(fileName: "IMG_0001.jpg"))
        #expect(!img.matches(fileName: "IMG_12.jpg"))
        #expect(!img.matches(fileName: "IMG_00001.jpg"))

        let star = try pattern("*")
        #expect(star.matches(fileName: "a.jpg"))
        #expect(star.matches(fileName: "x"))

        let abc = try pattern("a*b*c")
        #expect(abc.matches(fileName: "aXbYc"))
        #expect(abc.matches(fileName: "abc"))
        #expect(!abc.matches(fileName: "acb"))

        #expect(try pattern("**.jpg").matches(fileName: "x.jpg"))
        #expect(try pattern("?.png").matches(fileName: nfdGa))
        #expect(!(try pattern("cat*").matches(fileName: "my_cat.mov")))
    }

    @Test("Treats symbols as literal characters")
    func symbolsAreLiteral() throws {
        let bracket = try pattern("[1].jpg")
        #expect(bracket.matches(fileName: "[1].jpg"))
        #expect(!bracket.matches(fileName: "1.jpg"))
        #expect(try pattern("a\\b").matches(fileName: "a\\b.jpg"))
    }

    @Test("Returns a non-match quickly even with a long name and many *")
    func longNameDoesNotHang() throws {
        let name = String(repeating: "a", count: 200)
        #expect(!(try pattern("*a*a*a*a*b").matches(fileName: name)))
        #expect(try pattern("*a*a*a*a*").matches(fileName: name))
    }
}
