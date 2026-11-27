import Testing
import FolzioCore

@Suite("App version")
struct AppVersionTests {
    @Test("Parses three dot-separated decimal numbers", arguments: [
        ("1.0.0", 1, 0, 0),
        ("1.7.0", 1, 7, 0),
        ("0.0.1", 0, 0, 1),
        ("10.20.30", 10, 20, 30),
        ("01.02.03", 1, 2, 3),
    ])
    func parses(raw: String, major: Int, minor: Int, patch: Int) {
        #expect(AppVersion(raw) == AppVersion(major: major, minor: minor, patch: patch))
    }

    @Test("Rejects anything that is not exactly three decimal numbers", arguments: [
        "", "1", "1.0", "1.0.0.0", "v1.0.0", " 1.0.0", "1.0.0\n", "1..0", "1.0.", ".1.0",
        "-1.0.0", "+1.0.0", "1.a.0", "1.0.0-beta", "1.0.0+1", "１.０.０", "1.0.99999999999999999999",
    ])
    func rejects(raw: String) {
        #expect(AppVersion(raw) == nil)
    }

    @Test("Compares each part as a number", arguments: [
        ("1.9.0", "1.10.0"),
        ("1.99.99", "2.0.0"),
        ("1.2.9", "1.2.10"),
        ("0.0.0", "0.0.1"),
        ("1.7.0", "1.7.1"),
    ])
    func comparesNumerically(older: String, newer: String) throws {
        let olderVersion = try #require(AppVersion(older))
        let newerVersion = try #require(AppVersion(newer))
        #expect(olderVersion < newerVersion)
        #expect(!(newerVersion < olderVersion))
        #expect(olderVersion != newerVersion)
    }

    @Test("Treats leading zeros as the same number")
    func leadingZeros() throws {
        let plain = try #require(AppVersion("1.7.0"))
        let padded = try #require(AppVersion("01.7.0"))
        #expect(plain == padded)
        #expect(!(plain < padded))
    }

    @Test("Describes itself without leading zeros")
    func description() {
        #expect(AppVersion(major: 1, minor: 10, patch: 0).description == "1.10.0")
        #expect(AppVersion("01.02.03")?.description == "1.2.3")
    }
}
