import Foundation
import FolzioLocalization
import Testing

enum LocalizationTestSupport {
    static let languages = ["ja", "en"]

    static var packageBundle: Bundle { LocalizationBundle.packageBundle }

    static func localizer(_ language: String, localeIdentifier: String? = nil) -> Localizer {
        Localizer(
            bundle: packageBundle,
            language: language,
            development: "en",
            locale: Locale(identifier: localeIdentifier ?? (language == "ja" ? "ja_JP" : "en_US"))
        )
    }

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func resourceURL(_ language: String, _ name: String, _ ext: String) -> URL {
        repositoryRoot
            .appendingPathComponent("Sources/FolzioLocalization/Resources")
            .appendingPathComponent("\(language).lproj")
            .appendingPathComponent("\(name).\(ext)")
    }

    static func strings(_ language: String) throws -> [String: String] {
        let data = try Data(contentsOf: resourceURL(language, "Localizable", "strings"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: String])
    }

    static func stringsdict(_ language: String) throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: resourceURL(language, "Localizable", "stringsdict"))
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return try #require(plist as? [String: [String: Any]])
    }

    /// Converts format specifiers into a sequence of (position, kind). Returns nil when `%` appears outside a
    /// specifier.
    static func specifiers(_ value: String) -> [(Int, String)]? {
        var result: [(Int, String)] = []
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] != "%" {
                index = value.index(after: index)
                continue
            }
            if value[index...].hasPrefix("%%") {
                index = value.index(index, offsetBy: 2)
                continue
            }
            var cursor = value.index(after: index)
            var digits = ""
            while cursor < value.endIndex, value[cursor].isNumber {
                digits.append(value[cursor])
                cursor = value.index(after: cursor)
            }
            guard !digits.isEmpty, cursor < value.endIndex, value[cursor] == "$" else { return nil }
            cursor = value.index(after: cursor)
            guard cursor < value.endIndex else { return nil }
            if value[cursor...].hasPrefix("lld") {
                result.append((Int(digits)!, "lld"))
                cursor = value.index(cursor, offsetBy: 3)
            } else if value[cursor] == "@" {
                result.append((Int(digits)!, "@"))
                cursor = value.index(after: cursor)
            } else {
                return nil
            }
            index = cursor
        }
        return result
    }

    /// Format specifiers expected in the translation. The integer count is consumed by stringsdict, so it does not
    /// appear in the translation.
    static func expectedSpecifiers(for key: TextKey) -> [(Int, String)] {
        let displayedCounts: Set<TextKey> = [.contextCopyMultiple, .searchBarCount, .searchBarCountLimited]
        var expected: [(Int, String)] = []
        var position = 1
        for argument in key.arguments {
            switch argument {
            case .text, .number:
                expected.append((position, "@"))
                position += 1
            case .count:
                if displayedCounts.contains(key) {
                    expected.append((position + 1, "@"))
                }
                position += 2
            }
        }
        return expected
    }
}
