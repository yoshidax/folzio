import Foundation
import Testing
@testable import FolzioCore

@Suite("FavoriteName")
struct FavoriteNameTests {
    @Test("The limit is 255 characters")
    func maximumLengthIs255() {
        #expect(FavoriteName.maximumLength == 255)
    }

    @Test("normalized trims leading and trailing whitespace and newlines")
    func normalizedTrimsWhitespace() {
        #expect(FavoriteName.normalized("  2025 ") == "2025")
        #expect(FavoriteName.normalized("\n2025\n") == "2025")
    }

    @Test("normalized returns nil for empty or whitespace-only input")
    func normalizedReturnsNilForBlank() {
        #expect(FavoriteName.normalized("") == nil)
        #expect(FavoriteName.normalized("   ") == nil)
        #expect(FavoriteName.normalized(" \n\t ") == nil)
    }

    @Test("Removes internal newlines (\\n, \\r\\n, and U+2028)")
    func removesInnerNewlines() {
        for newline in ["\n", "\r\n", "\u{2028}"] {
            #expect(FavoriteName.normalized("a\(newline)b") == "ab", "\(newline.unicodeScalars.map(\.value))")
            #expect(FavoriteName.sanitizedForEditing("a\(newline)b") == "ab", "\(newline.unicodeScalars.map(\.value))")
        }
    }

    @Test("sanitizedForEditing preserves leading and trailing whitespace")
    func sanitizedKeepsSurroundingSpaces() {
        #expect(FavoriteName.sanitizedForEditing(" a ") == " a ")
    }

    @Test("Keeps exactly 255 characters and truncates longer input to the first 255")
    func truncatesAtMaximumLength() {
        let exact = String(repeating: "a", count: 255)
        #expect(FavoriteName.sanitizedForEditing(exact) == exact)
        #expect(FavoriteName.normalized(exact) == exact)

        for count in [256, 300] {
            let long = String(repeating: "a", count: count)
            #expect(FavoriteName.sanitizedForEditing(long) == exact, "\(count)")
            #expect(FavoriteName.normalized(long) == exact, "\(count)")
        }
    }

    @Test("Counts grapheme clusters and never splits one")
    func countsGraphemeClusters() {
        for unit in ["👨‍👩‍👧", "e\u{301}"] {
            let exact = String(repeating: unit, count: 255)
            #expect(FavoriteName.sanitizedForEditing(exact) == exact)

            let over = String(repeating: unit, count: 256)
            let truncated = FavoriteName.sanitizedForEditing(over)
            #expect(truncated == exact)
            #expect(truncated.count == 255)
            #expect(truncated.hasSuffix(unit))
        }
    }

    @Test("Accepts names containing / and : as-is")
    func acceptsSlashAndColon() {
        #expect(FavoriteName.normalized("a/b:c") == "a/b:c")
        #expect(FavoriteName.sanitizedForEditing("a/b:c") == "a/b:c")
    }
}
