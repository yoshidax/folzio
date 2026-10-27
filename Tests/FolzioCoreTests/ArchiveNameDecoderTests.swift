import CoreFoundation
import Foundation
import Testing
@testable import FolzioCore

@Suite("ArchiveNameDecoder")
struct ArchiveNameDecoderTests {
    private static let cp932 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
        )
    )

    private func cp932Bytes(_ text: String) throws -> Data {
        try #require(text.data(using: Self.cp932))
    }

    @Test("Reads UTF-8 as-is when the UTF-8 flag is set")
    func utf8WithFlag() {
        let bytes = Data("写真.jpg".utf8)
        #expect(ArchiveNameDecoder.decode(bytes, utf8Flag: true) == "写真.jpg")
    }

    @Test("Returns replacement characters for invalid bytes when the UTF-8 flag is set")
    func utf8FlagWithInvalidBytes() {
        var bytes = Data("ab".utf8)
        bytes.append(contentsOf: [0xFF, 0xFE])
        bytes.append(contentsOf: Array("c.png".utf8))
        let decoded = ArchiveNameDecoder.decode(bytes, utf8Flag: true)
        #expect(decoded.contains("\u{FFFD}"))
        #expect(decoded.hasPrefix("ab"))
        #expect(decoded.hasSuffix("c.png"))
    }

    @Test("Reads as UTF-8 without the flag when the bytes are valid UTF-8")
    func utf8WithoutFlag() {
        let bytes = Data("日本語/画像.png".utf8)
        #expect(ArchiveNameDecoder.decode(bytes, utf8Flag: false) == "日本語/画像.png")
    }

    @Test("Reads CP932 without the UTF-8 flag")
    func cp932WithoutFlag() throws {
        let bytes = try cp932Bytes("写真①.jpg")
        #expect(ArchiveNameDecoder.decode(bytes, utf8Flag: false) == "写真①.jpg")
    }

    @Test("Does not corrupt CP932 characters whose second byte is 0x5C")
    func cp932WithBackslashTrailByte() throws {
        let bytes = try cp932Bytes("表示.png")
        #expect(bytes.contains(0x5C))
        #expect(ArchiveNameDecoder.decode(bytes, utf8Flag: false) == "表示.png")
    }

    @Test("Reads bytes that are neither UTF-8 nor CP932 as CP437")
    func cp437Fallback() {
        let decoded = ArchiveNameDecoder.decode(Data([0x80, 0xFF, 0x41]), utf8Flag: false)
        #expect(decoded == "\u{00C7}\u{00A0}A")
        #expect(decoded.count == 3)
    }

    @Test("ASCII-only names produce the same result with or without the flag")
    func asciiIsIndependentOfFlag() {
        let bytes = Data("dir/photo 1.jpg".utf8)
        #expect(ArchiveNameDecoder.decode(bytes, utf8Flag: true) == "dir/photo 1.jpg")
        #expect(ArchiveNameDecoder.decode(bytes, utf8Flag: false) == "dir/photo 1.jpg")
    }

    @Test("Empty bytes produce an empty string")
    func emptyBytes() {
        #expect(ArchiveNameDecoder.decode(Data(), utf8Flag: true) == "")
        #expect(ArchiveNameDecoder.decode(Data(), utf8Flag: false) == "")
    }
}
