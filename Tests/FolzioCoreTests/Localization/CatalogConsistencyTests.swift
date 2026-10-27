import Foundation
import FolzioLocalization
import Testing

@Suite("Localization Catalog Consistency")
struct CatalogConsistencyTests {
    @Test("The catalogs contain every TextKey case in both languages with no extras")
    func keysMatch() throws {
        for language in LocalizationTestSupport.languages {
            let strings = try LocalizationTestSupport.strings(language)
            let dict = try LocalizationTestSupport.stringsdict(language)
            let all = Set(strings.keys).union(dict.keys)
            let expected = Set(TextKey.allCases.map(\.rawValue))

            let missing = expected.subtracting(all).sorted()
            let unused = all.subtracting(expected).sorted()
            #expect(missing.isEmpty, "\(language): keys without translations \(missing)")
            #expect(unused.isEmpty, "\(language): keys not in TextKey \(unused)")

            for key in TextKey.allCases {
                let inStrings = strings[key.rawValue] != nil
                let inDict = dict[key.rawValue] != nil
                #expect(inStrings != inDict, "\(language): \(key.rawValue) must appear in only one of strings and stringsdict")
                let usesPlural = key.arguments.contains(.count)
                #expect(inDict == usesPlural, "\(language): plural keys must be in stringsdict (\(key.rawValue))")
            }
        }
    }

    @Test("Plural tables have one and other in English and other in Japanese")
    func pluralForms() throws {
        for language in LocalizationTestSupport.languages {
            let dict = try LocalizationTestSupport.stringsdict(language)
            for key in TextKey.allCases where key.arguments.contains(.count) {
                let entry = try #require(dict[key.rawValue], "\(language): \(key.rawValue)")
                #expect(entry["NSStringLocalizedFormatKey"] as? String == "%#@value@")
                let value = try #require(entry["value"] as? [String: Any], "\(language): \(key.rawValue)")
                #expect(value["NSStringFormatSpecTypeKey"] as? String == "NSStringPluralRuleType")
                #expect(value["NSStringFormatValueTypeKey"] as? String == "lld")
                #expect(value["other"] != nil, "\(language): \(key.rawValue) has no other")
                if language == "en" {
                    #expect(value["one"] != nil, "\(key.rawValue) has no one")
                }
            }
        }
    }

    @Test("Every translation's format specifiers match the TextKey arguments")
    func argumentsMatch() throws {
        for language in LocalizationTestSupport.languages {
            let strings = try LocalizationTestSupport.strings(language)
            let dict = try LocalizationTestSupport.stringsdict(language)

            for key in TextKey.allCases {
                let expected = LocalizationTestSupport.expectedSpecifiers(for: key)
                if let value = strings[key.rawValue] {
                    let actual = try #require(LocalizationTestSupport.specifiers(value), "\(language): \(key.rawValue) has invalid format specifiers")
                    #expect(Set(actual.map { $0.0 }) == Set(expected.map { $0.0 }), "\(language): positions in \(key.rawValue)")
                    #expect(actual.map(\.1).sorted() == expected.map(\.1).sorted(), "\(language): kinds in \(key.rawValue)")
                } else if let entry = dict[key.rawValue],
                          let value = entry["value"] as? [String: String] {
                    for (form, translation) in value where form != "NSStringFormatSpecTypeKey" && form != "NSStringFormatValueTypeKey" {
                        let actual = try #require(LocalizationTestSupport.specifiers(translation), "\(language): \(key.rawValue).\(form) has invalid format specifiers")
                        #expect(Set(actual.map { $0.0 }) == Set(expected.map { $0.0 }), "\(language): positions in \(key.rawValue).\(form)")
                        #expect(actual.map(\.1).sorted() == expected.map(\.1).sorted(), "\(language): kinds in \(key.rawValue).\(form)")
                    }
                }
            }
        }
    }

    @Test("Each case is referenced from outside the TextKey definition")
    func casesAreReferenced() throws {
        let sources = ["Sources/FolzioApp", "Sources/FolzioLocalization"]
        var text = ""
        for directory in sources {
            let base = LocalizationTestSupport.repositoryRoot.appendingPathComponent(directory)
            let files = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "TextKey.swift" } ?? []
            for file in files {
                text += (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            }
        }
        for key in TextKey.allCases {
            let name = String(describing: key)
            #expect(text.contains(".\(name)"), "\(name) is not referenced")
        }
    }

    @Test("Every translation unit has a translator-facing description")
    func commentsExist() {
        for key in TextKey.allCases {
            #expect(!key.comment.isEmpty, "Description of \(key.rawValue) is empty")
        }
    }
}
