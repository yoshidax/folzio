import FolzioLocalization
import Testing

/// The heading and note of the search sheet, which tell it from the toolbar name filter (FR-394, TAK-86).
@Suite("Search Sheet Localization")
struct SearchSheetTextTests {
    @Test("The heading and its note have the approved wording in both languages and take no argument")
    func headingAndNote() throws {
        let expected: [String: (heading: String, note: String)] = [
            "ja": (
                "サブフォルダを含めて検索",
                "検索起点ディレクトリとその下のすべてのサブフォルダから、名前が一致するファイルとフォルダを探します。"
            ),
            "en": (
                "Search Including Subfolders",
                "Finds files and folders whose names match, in the folders you search in and all of their subfolders."
            ),
        ]
        #expect(TextKey.searchHeading.arguments.isEmpty)
        #expect(TextKey.searchDescription.arguments.isEmpty)
        for language in LocalizationTestSupport.languages {
            let localizer = LocalizationTestSupport.localizer(language)
            let texts = try #require(expected[language], "\(language)")
            #expect(localizer.text(.searchHeading) == texts.heading)
            #expect(localizer.text(.searchDescription) == texts.note)
        }
    }

    /// The wildcard note below the keyword field (FR-441, TAK-104).
    @Test("The wildcard note has the approved wording in both languages and takes no argument")
    func wildcardNote() throws {
        let expected = [
            "ja": "* は0文字以上の任意の文字、? は任意の1文字に一致します。* か ? を含むときは、名前全体と一致するものを探します。",
            "en": "* matches any number of characters and ? matches one character. With * or ?, the whole name must match.",
        ]
        #expect(TextKey.searchWildcardHint.arguments.isEmpty)
        for language in LocalizationTestSupport.languages {
            let localizer = LocalizationTestSupport.localizer(language)
            #expect(localizer.text(.searchWildcardHint) == expected[language])
        }
    }

    /// Row numbers and the search bar summary for several roots (FR-435, FR-436, FR-439, TAK-104).
    @Test("Numbered labels, the numbered reason, and the several-roots summary insert their values")
    func severalRootTexts() {
        let ja = LocalizationTestSupport.localizer("ja")
        #expect(ja.text(.searchRootNumbered, .number(2)) == "検索起点ディレクトリ 2")
        #expect(ja.text(.searchErrorNumbered, .number(3), .text("理由")) == "3 番目の検索起点: 理由")
        #expect(ja.text(.searchBarMultipleRoots, .text("Photos"), .number(2)) == "Photos ほか 2 か所")
        let en = LocalizationTestSupport.localizer("en")
        #expect(en.text(.searchRemoveRootNumbered, .number(2)) == "Remove Folder 2")
        #expect(en.text(.searchBarMultipleRoots, .text("Photos"), .number(1)) == "Photos and 1 more")
    }
}
