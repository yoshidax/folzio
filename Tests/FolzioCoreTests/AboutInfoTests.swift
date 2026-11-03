import Foundation
import Testing
import FolzioCore

@Suite("About info")
struct AboutInfoTests {
    @Test("Returns a version string trimmed of surrounding whitespace", arguments: [
        ("1.0.0", "1.0.0"),
        ("  1.0.0\n", "1.0.0"),
        ("2.3.4", "2.3.4"),
    ])
    func validVersion(raw: String, expected: String) {
        #expect(AboutInfo.displayVersion(from: raw) == expected)
    }

    @Test("Returns nil when the version is missing, empty, blank, or not a string")
    func missingVersion() {
        #expect(AboutInfo.displayVersion(from: nil) == nil)
        #expect(AboutInfo.displayVersion(from: "") == nil)
        #expect(AboutInfo.displayVersion(from: " \n\t ") == nil)
        #expect(AboutInfo.displayVersion(from: 1) == nil)
        #expect(AboutInfo.displayVersion(from: NSNull()) == nil)
    }

    @Test("The repository link points at the public Folzio repository")
    func repositoryURL() {
        #expect(AboutInfo.repositoryURL.absoluteString == "https://github.com/yoshidax/folzio")
    }
}
