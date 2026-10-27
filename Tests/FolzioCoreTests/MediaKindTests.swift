import Testing
@testable import FolzioCore

@Suite("MediaKind")
struct MediaKindTests {
    @Test("Recognizes supported extensions case-insensitively", arguments: [
        ("jpg", MediaKind.jpeg),
        ("JPG", .jpeg),
        ("Jpeg", .jpeg),
        ("jPeG", .jpeg),
        ("png", .png),
        ("PNG", .png),
        ("gif", .gif),
        ("GIF", .gif),
        ("webp", .webp),
        ("WEBP", .webp),
        ("mp4", .mp4),
        ("MP4", .mp4),
        ("mov", .mov),
        ("MOV", .mov),
    ])
    func recognizesSupportedExtensions(fileExtension: String, expected: MediaKind) {
        #expect(MediaKind(fileExtension: fileExtension) == expected)
    }

    @Test("Returns nil for unsupported extensions", arguments: ["txt", "pdf", "heic", ""])
    func rejectsUnsupportedExtensions(fileExtension: String) {
        #expect(MediaKind(fileExtension: fileExtension) == nil)
    }

    @Test("isVideo is true only for videos")
    func marksVideos() {
        #expect(MediaKind.mp4.isVideo)
        #expect(MediaKind.mov.isVideo)
        #expect(!MediaKind.jpeg.isVideo)
        #expect(!MediaKind.png.isVideo)
        #expect(!MediaKind.gif.isVideo)
        #expect(!MediaKind.webp.isVideo)
    }
}
