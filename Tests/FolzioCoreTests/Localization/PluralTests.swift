import Foundation
import FolzioLocalization
import Testing

@Suite("Plurals and Count Formatting")
struct PluralTests {
    private let en = LocalizationTestSupport.localizer("en", localeIdentifier: "en_US")
    private let ja = LocalizationTestSupport.localizer("ja", localeIdentifier: "ja_JP")

    @Test("English uses different wording for one versus all other counts, including zero; Japanese does not")
    func pluralRules() {
        for key in TextKey.allCases where key.arguments.contains(.count) {
            let oneEN = normalized(en, key, 1)
            let twoEN = normalized(en, key, 2)
            #expect(oneEN != twoEN, "\(key.rawValue): English singular and plural are the same")
            #expect(normalized(en, key, 0) == twoEN, "\(key.rawValue): zero uses the plural form")
            #expect(normalized(en, key, 1000) == twoEN, "\(key.rawValue): 1000 uses the plural form")

            #expect(normalized(ja, key, 1) == normalized(ja, key, 2), "\(key.rawValue): Japanese wording changed")
            #expect(normalized(ja, key, 0) == normalized(ja, key, 2), "\(key.rawValue): Japanese wording changed")
        }

        for key in [TextKey.contextCopyMultiple, .searchBarCount, .searchBarCountLimited] {
            #expect(value(en, key, 1000).contains("1,000"), "\(key.rawValue): grouping separator")
            #expect(value(ja, key, 1000).contains("1,000"), "\(key.rawValue): grouping separator")
        }
    }

    /// Wording with numeric differences removed.
    private func normalized(_ localizer: Localizer, _ key: TextKey, _ count: Int) -> String {
        value(localizer, key, count)
            .replacingOccurrences(of: localizer.count(count), with: "<n>")
    }

    private func value(_ localizer: Localizer, _ key: TextKey, _ count: Int) -> String {
        let values = key.arguments.map { argument -> TextValue in
            switch argument {
            case .text: return .text("3")
            case .count: return .count(count)
            case .number: return .number(count)
            }
        }
        return localizer.text(key, values)
    }

    @Test("English count sentences")
    func englishForms() {
        #expect(en.text(.contextCopyMultiple, .count(1)) == "Copy 1 Item")
        #expect(en.text(.contextCopyMultiple, .count(3)) == "Copy 3 Items")
        #expect(en.text(.searchBarCount, .count(1)) == "1 item")
        #expect(en.text(.searchBarCount, .count(0)) == "0 items")
        #expect(en.text(.searchBarCount, .count(1000)) == "1,000 items")
        #expect(en.text(.searchBarCountLimited, .count(1000), .text("2")) == "Showing 2 of 1,000 items")
        #expect(en.text(.searchBarCountLimited, .count(1), .text("1")) == "Showing 1 of 1 item")
        #expect(en.text(.dialogConfirmCopy, .count(1)) == "Copy this item?")
        #expect(en.text(.dialogConfirmCopy, .count(3)) == "Copy these items?")
        #expect(en.text(.dialogConfirmMove, .count(1)) == "Move this item?")
        #expect(en.text(.dialogConfirmMove, .count(3)) == "Move these items?")
    }

    @Test("Japanese count sentences")
    func japaneseForms() {
        #expect(ja.text(.contextCopyMultiple, .count(3)) == "3 項目をコピー")
        #expect(ja.text(.searchBarCount, .count(1000)) == "1,000 件")
        #expect(ja.text(.searchBarCountLimited, .count(1000), .text("2")) == "1,000 件中 2 件を表示")
        #expect(ja.text(.dialogConfirmCopy, .count(1)) == "コピーしますか？")
        #expect(ja.text(.dialogConfirmCopy, .count(3)) == "コピーしますか？")
        #expect(ja.text(.dialogConfirmMove, .count(3)) == "移動しますか？")
    }

    @Test("Uses the formatted value for counts whose wording does not change")
    func numberArguments() {
        let keys: [TextKey] = [
            .dialogConfirmItems, .dialogConfirmMore, .dialogConflictItems, .dialogOperationMore,
        ]
        for key in keys {
            for count in [0, 1, 2, 1000] {
                let value = LocalizationTestSupport.localizer("en").text(key, .number(count))
                #expect(!value.contains("%"), "\(key.rawValue)")
                #expect(value.contains(LocalizationTestSupport.localizer("en", localeIdentifier: "en_US").count(count)))
            }
        }
        #expect(en.text(.dialogOperationSummary, .number(3), .number(1000))
            == "Succeeded: 3 / Failed: 1,000")
        #expect(ja.text(.dialogOperationSummary, .number(3), .number(1000))
            == "成功 3 件 / 失敗 1,000 件")
        #expect(en.text(.dialogConfirmMore, .number(1000)) == "and 1,000 more")
        #expect(ja.text(.dialogConfirmMore, .number(1000)) == "ほか 1,000 件")
    }
}
