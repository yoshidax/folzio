import Foundation

/// Matches search keywords against file and folder names (FR-082, research.md R34).
///
/// - Normalizes both the keyword and the name to NFC and folds case before comparing. Does not distinguish
///   composed and decomposed dakuten or letter case. Distinguishes full-width/half-width and hiragana/katakana.
/// - A keyword without `*` or `?` matches a substring of the name (file names include the extension).
/// - A keyword with `*` (zero or more characters) or `?` (one character) matches the whole name. Characters are
///   `Character` (grapheme clusters).
/// - Treats `[`, `]`, `\`, and similar characters literally; there is no escaping. Matches names only, not
///   folder paths.
/// - Matches folder names against the whole name as well; a folder name containing "." (`2024.10_trip`,
///   `photos.jpg`) is not treated as having an extension (EC-97).
public struct SearchPattern: Sendable, Equatable {
    /// Input with leading and trailing whitespace removed. Never empty.
    public let keyword: String
    /// Whether the keyword contains `*` or `?`.
    public let usesWildcards: Bool

    /// Normalized keyword (created once in the initializer).
    private let normalizedKeyword: String
    private let keywordCharacters: [Character]
    /// The normalized keyword as bytes when it is ASCII and has no wildcards. Matching such a keyword against an ASCII
    /// name compares bytes without creating strings (SC-209).
    private let asciiKeyword: [UInt8]?

    /// Returns nil when the input is empty after removing leading and trailing whitespace (including newlines).
    /// The Search button is disabled and Return does nothing.
    public init?(keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.keyword = trimmed
        self.usesWildcards = trimmed.contains("*") || trimmed.contains("?")
        self.normalizedKeyword = Self.normalize(trimmed)
        self.keywordCharacters = Array(normalizedKeyword)
        let bytes = Array(normalizedKeyword.utf8)
        self.asciiKeyword = !usesWildcards && bytes.allSatisfy { $0 < 0x80 } ? bytes : nil
    }

    /// Matches a file name or folder name. Folder names also match against the whole name, and "." is not treated
    /// as an extension separator (FR-082, EC-97).
    public func matches(fileName: String) -> Bool {
        if let asciiKeyword, let found = Self.asciiContains(fileName, asciiKeyword) {
            return found
        }
        let name = Self.normalize(fileName)
        guard usesWildcards else {
            return name.contains(normalizedKeyword)
        }
        return Self.globMatches(keywordCharacters, Array(name))
    }

    /// Substring search that ignores ASCII letter case, without creating strings. Returns nil when the name is not
    /// ASCII, so the caller falls back to normalizing it. For an ASCII name this gives the same result as normalizing
    /// both strings and calling `contains`, because their normalization only lowercases letters.
    static func asciiContains(_ name: String, _ needle: [UInt8]) -> Bool? {
        var name = name
        name.makeContiguousUTF8()
        return name.utf8.withContiguousStorageIfAvailable { haystack -> Bool? in
            guard !haystack.contains(where: { $0 >= 0x80 }) else { return nil }
            let count = needle.count
            guard count > 0 else { return true }
            guard count <= haystack.count else { return false }
            candidates: for start in 0...(haystack.count - count) {
                for offset in 0..<count {
                    var byte = haystack[start + offset]
                    if byte >= 0x41, byte <= 0x5A {
                        byte += 0x20
                    }
                    if byte != needle[offset] {
                        continue candidates
                    }
                }
                return true
            }
            return false
        } ?? nil
    }

    /// NFC and case folding. An ASCII-only string is already NFC, and case folding only lowercases its letters, so
    /// `lowercased()` gives the same result much faster. This keeps the toolbar name filter responsive on large
    /// listings, where every keystroke matches every name again (SC-209).
    static func normalize(_ string: String) -> String {
        if string.utf8.allSatisfy({ $0 < 0x80 }) {
            return string.lowercased()
        }
        return string.precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive], locale: nil)
    }

    /// Iterative matching that remembers the last `*` position and backtracks. Does not recurse and finishes in
    /// at worst the name length times the keyword length.
    private static func globMatches(_ pattern: [Character], _ name: [Character]) -> Bool {
        var p = 0
        var n = 0
        var starIndex: Int?
        var starMatch = 0

        while n < name.count {
            if p < pattern.count, pattern[p] == "?" || (pattern[p] != "*" && pattern[p] == name[n]) {
                p += 1
                n += 1
            } else if p < pattern.count, pattern[p] == "*" {
                starIndex = p
                starMatch = n
                p += 1
            } else if let star = starIndex {
                p = star + 1
                starMatch += 1
                n = starMatch
            } else {
                return false
            }
        }

        while p < pattern.count, pattern[p] == "*" {
            p += 1
        }
        return p == pattern.count
    }
}
