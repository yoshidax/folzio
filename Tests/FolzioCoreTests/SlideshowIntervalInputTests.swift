import Testing
@testable import FolzioCore

@Suite("SlideshowIntervalInput")
struct SlideshowIntervalInputTests {
    @Test(arguments: [
        ("10", 10),
        ("１５", 15),
        (" 15 ", 15),
        ("\u{3000}15\u{3000}", 15),
        ("007", 7),
        ("1", 1),
        ("3600", 3600),
    ] as [(String, Int)])
    func accepts(text: String, expected: Int) {
        #expect(SlideshowIntervalInput.parse(text) == expected)
    }

    @Test(arguments: [
        "", "  ", "0", "-1", "+5", "2.5", "abc", "1,000",
        "3601", "99999999999999999999", "１.５",
    ])
    func rejects(text: String) {
        #expect(SlideshowIntervalInput.parse(text) == nil)
    }
}
