import Foundation
import FolzioLocalization
import Testing

@Suite("Regional Formatting")
struct FormattingTests {
    @Test("Preserves the region's number and time settings when the display language changes")
    func languageChangeKeepsRegionalFormatting() {
        for current in [Locale(identifier: "de_DE"), Locale(identifier: "ja_DE")] {
            let english = Localizer.forLanguage("en", currentLocale: current)
            let japanese = Localizer.forLanguage("ja", currentLocale: current)
            for localizer in [english, japanese] {
                #expect(localizer.locale.region?.identifier == "DE")
                #expect(localizer.locale.hourCycle == current.hourCycle)
                #expect(localizer.locale.firstDayOfWeek == current.firstDayOfWeek)
                #expect(localizer.count(1234) == "1.234")
                #expect(localizer.percent(125).replacingOccurrences(of: "\u{00a0}", with: " ") == "125 %")
                #expect(localizer.dateTime(nil) == "--")
            }
            #expect(english.locale.language.languageCode?.identifier == "en")
            #expect(japanese.locale.language.languageCode?.identifier == "ja")
        }
    }

    @Test("Uses the current locale unchanged when the display language is the same")
    func keepsCurrentLocale() {
        let current = Locale(identifier: "en_JP")
        #expect(FormattingLocale.resolve(current: current, displayLanguage: "en") == current)
        let withKeyword = Locale(identifier: "ja_US@hours=h23")
        #expect(FormattingLocale.resolve(current: withKeyword, displayLanguage: "ja") == withKeyword)
    }

    @Test("Replaces only the language and keeps the region, 24-hour setting, calendar, and numbering system")
    func replacesOnlyLanguage() {
        let japan = Locale(identifier: "ja_JP")
        let englishInJapan = FormattingLocale.resolve(current: japan, displayLanguage: "en")
        #expect(englishInJapan.language.languageCode?.identifier == "en")
        #expect(englishInJapan.region?.identifier == "JP")
        #expect(englishInJapan.hourCycle == japan.hourCycle)
        #expect(englishInJapan.calendar.identifier == japan.calendar.identifier)
        #expect(englishInJapan.numberingSystem == japan.numberingSystem)

        let unitedStates = Locale(identifier: "en_US")
        let japaneseInUS = FormattingLocale.resolve(current: unitedStates, displayLanguage: "ja")
        #expect(japaneseInUS.language.languageCode?.identifier == "ja")
        #expect(japaneseInUS.region?.identifier == "US")
        #expect(japaneseInUS.hourCycle == unitedStates.hourCycle)

        let france = Locale(identifier: "fr_FR")
        let japaneseInFrance = FormattingLocale.resolve(current: france, displayLanguage: "ja")
        #expect(japaneseInFrance.region?.identifier == "FR")
        #expect(japaneseInFrance.hourCycle == france.hourCycle)

        let forced24 = Locale(identifier: "ja_US@hours=h23")
        let japaneseForced24 = FormattingLocale.resolve(current: forced24, displayLanguage: "ja")
        #expect(japaneseForced24 == forced24)
    }

    @Test("Formats counts with the region's grouping separator")
    func counts() {
        #expect(FormattingLocale.count(1234, locale: Locale(identifier: "en_US")) == "1,234")
        #expect(FormattingLocale.count(1234, locale: Locale(identifier: "ja_JP")) == "1,234")
        #expect(FormattingLocale.count(1234, locale: Locale(identifier: "de_DE")) == "1.234")
    }

    @Test("Dates follow the region's order and 12/24-hour display; words follow the display language")
    func dateTime() throws {
        let date = try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: 2026, month: 10, day: 28, hour: 15, minute: 4)
            )
        )

        let englishInJapan = Localizer(
            bundle: LocalizationTestSupport.packageBundle,
            language: "en",
            development: "en",
            locale: FormattingLocale.resolve(current: Locale(identifier: "ja_JP"), displayLanguage: "en")
        )
        #expect(englishInJapan.locale.hourCycle == .zeroToTwentyThree)
        let japaneseOrder = englishInJapan.dateTime(date)
        #expect(japaneseOrder.contains("15:04") || japaneseOrder.contains("15:4"))
        #expect(!japaneseOrder.contains("AM"))
        #expect(!japaneseOrder.contains("PM"))
        #expect(!japaneseOrder.contains("午前"))
        #expect(!japaneseOrder.contains("午後"))
        #expect(englishInJapan.dateTime(nil) == "--")

        let japaneseInUS = Localizer(
            bundle: LocalizationTestSupport.packageBundle,
            language: "ja",
            development: "en",
            locale: FormattingLocale.resolve(current: Locale(identifier: "en_US"), displayLanguage: "ja")
        )
        #expect(japaneseInUS.locale.hourCycle == .oneToTwelve)
        let usOrder = japaneseInUS.dateTime(date)
        #expect(usOrder.contains("午後"))
        #expect(usOrder.contains("/"))

        let englishInGermany = Localizer(
            bundle: LocalizationTestSupport.packageBundle,
            language: "en",
            development: "en",
            locale: FormattingLocale.resolve(current: Locale(identifier: "de_DE"), displayLanguage: "en")
        )
        let germanOrder = englishInGermany.dateTime(date)
        #expect(germanOrder.contains("Oct"))
        #expect(!germanOrder.contains("Okt"))
        #expect(germanOrder.contains("15:04") || germanOrder.contains("15:4"))

        let forced24 = Localizer(
            bundle: LocalizationTestSupport.packageBundle,
            language: "ja",
            development: "en",
            locale: FormattingLocale.resolve(
                current: Locale(identifier: "ja_US@hours=h23"),
                displayLanguage: "ja"
            )
        )
        #expect(forced24.locale.hourCycle == .zeroToTwentyThree)
    }

    @Test("Formats percentages with the region's percent format")
    func percentages() {
        #expect(FormattingLocale.percent(125, locale: Locale(identifier: "en_US")) == "125%")
        #expect(FormattingLocale.percent(125, locale: Locale(identifier: "ja_JP")) == "125%")
        let german = FormattingLocale.percent(125, locale: Locale(identifier: "de_DE"))
        #expect(german.replacingOccurrences(of: "\u{00a0}", with: " ") == "125 %")
    }
}
