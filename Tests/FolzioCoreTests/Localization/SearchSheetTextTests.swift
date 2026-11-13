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
                "Finds files and folders whose names match, in the folder you search in and all of its subfolders."
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
}
