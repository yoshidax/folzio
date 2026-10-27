import Foundation
import FixtureKit
import FolzioLocalization
import Testing

@Suite("Fallback for Missing Translations")
struct FallbackTests {
    @Test("Falls back to English (development language) when the display language has no translation, without showing keys or blanks")
    func fallsBackToEnglish() throws {
        let url = try LocalizationFixtures.makeBundle(tables: [
            "en": ["error.searchRoot.empty": "Enter a folder to search in"],
            "ja": [:],
        ])
        defer { LocalizationFixtures.remove(url) }
        let bundle = try #require(Bundle(url: url))
        let localizer = Localizer(
            bundle: bundle,
            language: "ja",
            development: "en",
            locale: Locale(identifier: "ja_JP")
        )

        #expect(localizer.text(.errorSearchRootEmpty) == "Enter a folder to search in")
        #expect(localizer.text(.errorSearchRootEmpty) != "error.searchRoot.empty")
        #expect(!localizer.text(.errorSearchRootEmpty).isEmpty)
    }

    @Test("Prefers the display language translation when present")
    func prefersDisplayLanguage() throws {
        let url = try LocalizationFixtures.makeBundle(tables: [
            "en": ["error.searchRoot.empty": "Enter a folder to search in"],
            "ja": ["error.searchRoot.empty": "検索起点ディレクトリを入力してください"],
        ])
        defer { LocalizationFixtures.remove(url) }
        let bundle = try #require(Bundle(url: url))
        let localizer = Localizer(
            bundle: bundle,
            language: "ja",
            development: "en",
            locale: Locale(identifier: "ja_JP")
        )
        #expect(localizer.text(.errorSearchRootEmpty) == "検索起点ディレクトリを入力してください")
    }
}
