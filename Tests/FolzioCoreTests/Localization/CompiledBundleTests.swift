import Foundation
import FolzioLocalization
import Testing

@Suite("Compiled Translations")
struct CompiledBundleTests {
    @Test("All keys resolve from both language lproj files (does not return keys, empty strings, or sentinels)")
    func lookups() throws {
        for language in LocalizationTestSupport.languages {
            let table = try #require(
                LocalizationBundle.table(language: language, in: LocalizationTestSupport.packageBundle)
            )
            for key in TextKey.allCases {
                let sentinel = "__MISSING_\(key.rawValue)__"
                let value = table.localizedString(forKey: key.rawValue, value: sentinel, table: nil)
                #expect(value != key.rawValue, "\(language): \(key.rawValue) is still the key")
                #expect(value != sentinel, "\(language): \(key.rawValue) is missing")
                #expect(!value.isEmpty, "\(language): \(key.rawValue) is empty")
            }
        }
    }

    @Test("No unsubstituted % remains after formatting")
    func formattedValuesHaveNoPlaceholders() {
        for language in LocalizationTestSupport.languages {
            let localizer = LocalizationTestSupport.localizer(language)
            for key in TextKey.allCases {
                let value = sampleValue(for: key, localizer: localizer)
                #expect(!value.contains("%"), "\(language): \(key.rawValue) -> \(value)")
            }
        }
    }

    private func sampleValue(for key: TextKey, localizer: Localizer) -> String {
        let values: [TextValue] = key.arguments.map { argument in
            switch argument {
            case .text: return .text("sample")
            case .count: return .count(2)
            case .number: return .number(2)
            }
        }
        return localizer.text(key, values)
    }
}
