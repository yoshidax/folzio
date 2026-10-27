import Foundation
import FolzioLocalization
import Testing

@Suite("Display Language Selection")
struct DisplayLanguageTests {
    @Test("Uses English for an unsaved or unknown language")
    func missingOrUnknownUsesEnglish() {
        for value in [nil, "", "fr", "ja-JP", "en-GB"] as [String?] {
            #expect(DisplayLanguage.resolve(saved: value, supported: ["ja", "en"]) == "en")
        }
    }

    @Test("Uses the saved supported language")
    func supportedSettingIsRestored() {
        #expect(DisplayLanguage.resolve(saved: "ja", supported: ["ja", "en"]) == "ja")
        #expect(DisplayLanguage.resolve(saved: "en", supported: ["ja", "en"]) == "en")
    }

    @Test("A switched localizer returns text in the selected language")
    func selectedLocalizerUsesSelectedLanguage() {
        let japanese = Localizer.forLanguage("ja", currentLocale: Locale(identifier: "en_US"))
        let english = Localizer.forLanguage("en", currentLocale: Locale(identifier: "en_US"))
        #expect(japanese.text(.kindFolder) == "フォルダ")
        #expect(english.text(.kindFolder) == "Folder")
        #expect(japanese.language == "ja")
        #expect(english.language == "en")
    }
}
