import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FolzioCore

enum ImportTestFiles {
    static func directory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Folzio-Import-Test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    static func image(_ type: UTType = .png, frames: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 4, height: 3, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let writer = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, frames, nil))
        for _ in 0..<frames { CGImageDestinationAddImage(writer, image, nil) }
        #expect(CGImageDestinationFinalize(writer))
        return data as Data
    }

    static func sparse(_ url: URL, header: Data, size: Int64) throws {
        try header.write(to: url)
        let fd = open(url.path, O_WRONLY)
        #expect(fd >= 0)
        defer { close(fd) }
        #expect(ftruncate(fd, off_t(size)) == 0)
    }

    static func largeTIFF() throws -> Data {
        // A valid PackBits stream keeps the fixture small without allocating the decoded pixels.
        let row: [UInt8] = Array(repeating: [UInt8(129), UInt8(0)], count: 78).flatMap { $0 } + [UInt8(240), UInt8(0)]
        let pixels: [UInt8] = Array(repeating: row, count: 10_000).flatMap { $0 }
        var bytes: [UInt8] = [0x49, 0x49, 42, 0, 8, 0, 0, 0, 9, 0]
        func append(_ value: UInt32, count: Int) {
            for index in 0..<count { bytes.append(UInt8((value >> (index * 8)) & 255)) }
        }
        func entry(_ tag: UInt32, _ type: UInt32, _ value: UInt32) {
            append(tag, count: 2); append(type, count: 2); append(1, count: 4); append(value, count: 4)
        }
        entry(256, 4, 10_001); entry(257, 4, 10_000); entry(258, 3, 8); entry(259, 3, 32_773)
        entry(262, 3, 1); entry(273, 4, 122); entry(277, 3, 1); entry(278, 4, 10_000); entry(279, 4, UInt32(pixels.count))
        append(0, count: 4)
        return Data(bytes + pixels)
    }
}
