import Foundation
import Testing
import UniformTypeIdentifiers
@testable import FolzioCore

@Suite("Imported file names")
struct ImportedFileNameTests {
    @Test("Rejects control, direction, path and hidden names", arguments: [
        "", " ", ".hidden", "..", "a/b", "a:b", "a\u{202e}.png", "a\u{2066}.png", "a\u{200e}.png", "a\0.png", "a\n.png",
    ])
    func invalid(_ name: String) { #expect(!ImportedFileName.isAcceptable(name)) }

    @Test func byteBoundary() {
        #expect(ImportedFileName.isAcceptable(String(repeating: "a", count: 200)))
        #expect(!ImportedFileName.isAcceptable(String(repeating: "a", count: 201)))
        #expect(ImportedFileName.isAcceptable("全角の名前.png"))
        #expect(!ImportedFileName.isAcceptable(String(repeating: "猫", count: 67)))
    }

    @Test func urlNames() {
        #expect(ImportedFileName.nameFromURL("https://example.com/a/cat.jpg?w=1") == "cat.png")
        #expect(ImportedFileName.nameFromURL("HTTP://example.com/%E7%8C%AB.jpeg") == "猫.png")
        for url in ["https://example.com/a%2Fb.jpg", "https://example.com/a%00.jpg", "https://example.com", "https://example.com/", "https://example.com/..", "https:cat.jpg", "data:image/png;base64,x", "blob:abc", "file:///tmp/cat.jpg", "ftp://example.com/cat.jpg"] {
            #expect(ImportedFileName.nameFromURL(url) == nil, "\(url)")
        }
    }

    @Test func correctedExtensions() {
        for (name, expected) in [("cat.png", "cat.jpg"), ("photo.jpg_large", "photo.jpg"), ("download", "download.jpg"), ("photo.jpg.command", "photo.jpg.jpg"), ("cat.JPG", "cat.JPG"), ("cat.jpeg", "cat.jpeg"), ("cat.jfif", "cat.jpg"), ("cat.jpe", "cat.jpg")] {
            #expect(ImportedFileName.corrected(name: name, contentType: .jpeg) == expected)
        }
        #expect(ImportedFileName.corrected(name: "movie.png", contentType: .quickTimeMovie) == "movie.mov")
        #expect(ImportedFileName.corrected(name: "movie", contentType: .mpeg4Movie) == "movie.mp4")
        #expect(!ImportedFileName.corrected(name: ".jpeg", contentType: .jpeg).hasPrefix("."))
        #expect(ImportedFileName.uniqueNames(["a.jpg", "A.JPG", "a.jpg"]) == ["a.jpg", "A 2.JPG", "a 3.jpg"])
    }

    @Test func deterministicDate() {
        let date = Date(timeIntervalSince1970: 0)
        let utc = TimeZone(secondsFromGMT: 0)!
        let tokyo = TimeZone(secondsFromGMT: 9 * 3600)!
        for locale in ["ja_JP", "ar"] {
            #expect(ImportedFileName.datedName(prefix: "画像", date: date, extension: "png", timeZone: utc, locale: Locale(identifier: locale)) == "画像 1970-01-01 00.00.00.png")
            #expect(ImportedFileName.datedName(prefix: "Image", date: date, extension: "png", timeZone: tokyo, locale: Locale(identifier: locale)) == "Image 1970-01-01 09.00.00.png")
        }
    }
}
