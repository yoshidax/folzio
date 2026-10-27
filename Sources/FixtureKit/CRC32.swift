import Foundation

/// CRC-32 for zip (polynomial 0xEDB88320).
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index -> UInt32 in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
        }
        return value
    }

    public static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { update(0, $0) }
    }

    /// Returns the CRC after appending the bytes to an already computed CRC (0 at the start).
    public static func update(_ crc: UInt32, _ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var value = ~crc
        for byte in bytes {
            value = table[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8)
        }
        return ~value
    }
}
