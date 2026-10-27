import CoreFoundation
import Foundation

/// Detects the character encoding of a name inside a zip (FR-074, research.md R27).
public enum ArchiveNameDecoder {
    private static let cp932 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
        )
    )

    private static let cp437 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)
        )
    )

    /// 1. If the UTF-8 flag (bit 11 of the general purpose flags) is set, use UTF-8 (invalid bytes become the
    ///    replacement character).
    /// 2. If the bytes are valid UTF-8, use UTF-8.
    /// 3. CP932
    /// 4. CP437 (every byte is defined, so this always succeeds)
    public static func decode(_ bytes: Data, utf8Flag: Bool) -> String {
        if utf8Flag {
            return String(decoding: bytes, as: UTF8.self)
        }
        if let text = String(validating: bytes, as: UTF8.self) {
            return text
        }
        if let text = String(data: bytes, encoding: cp932) {
            return text
        }
        if let text = String(data: bytes, encoding: cp437) {
            return text
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
