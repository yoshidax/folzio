import Foundation
import FixtureKit
import FolzioLocalization
import Testing

@Suite("Localization Bundle Resolution")
struct LocalizationBundleTests {
    @Test("Uses the main bundle when it has an .app lproj")
    func resolvesMainBundle() throws {
        let url = try LocalizationFixtures.makeBundle(tables: [
            "en": ["error.searchRoot.empty": "Enter a folder to search in"],
            "ja": ["error.searchRoot.empty": "検索起点ディレクトリを入力してください"],
        ])
        defer { LocalizationFixtures.remove(url) }
        let bundle = try #require(Bundle(url: url))
        #expect(LocalizationBundle.resolve(main: bundle) == bundle)
    }

    @Test("Uses the package bundle when no lproj exists")
    func resolvesPackageBundle() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolzioEmptyBundle-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent("Contents/Resources", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { LocalizationFixtures.remove(url) }
        let bundle = try #require(Bundle(url: url))
        #expect(LocalizationBundle.resolve(main: bundle) == LocalizationBundle.packageBundle)
    }

    @Test("A Localizer created from the package bundle returns no internal keys in either language")
    func packageBundleLocalizer() {
        for language in LocalizationTestSupport.languages {
            let localizer = LocalizationTestSupport.localizer(language)
            for key in TextKey.allCases {
                let value = localizer.text(key, key.arguments.map { argument -> TextValue in
                    switch argument {
                    case .text: return .text("x")
                    case .count: return .count(1)
                    case .number: return .number(1)
                    }
                })
                #expect(!value.hasPrefix("\(key.rawValue)"), "\(language): \(key.rawValue)")
                #expect(!value.isEmpty)
            }
        }
    }
}
