import CoreGraphics
import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("ImageDecoder")
struct ImageDecoderTests {
    @Test("Downsamples the long side to at most maxPixelSize")
    func downsamplesLargeImage() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("large.jpg")
        try ImageFixtures.jpeg(at: url, width: 4000, height: 3000)

        let decoder = ImageDecoder()
        let image = try await decoder.decode(url, maxPixelSize: 1000)

        #expect(max(image.pixelSize.width, image.pixelSize.height) <= 1000)
        #expect(image.originalPixelSize == CGSize(width: 4000, height: 3000))
        #expect(image.byteCost > 0)
    }

    @Test("Identifies only animated GIFs as animated")
    func detectsAnimation() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gif = root.appendingPathComponent("animation.gif")
        let png = root.appendingPathComponent("still.png")
        try ImageFixtures.animatedGIF(at: gif, frames: 4)
        try ImageFixtures.png(at: png, width: 32, height: 32)

        let decoder = ImageDecoder()
        #expect(decoder.isAnimated(gif))
        #expect(!decoder.isAnimated(png))
    }

    @Test("Does not crash on a corrupted file and returns an error or a valid image")
    func handlesBrokenFiles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        try FixtureSets.broken(in: root)
        let folder = root.appendingPathComponent("broken", isDirectory: true)
        let decoder = ImageDecoder()

        for name in ["truncated.jpg", "fake.jpg", "empty.mp4"] {
            let url = folder.appendingPathComponent(name)
            do {
                let image = try await decoder.decode(url, maxPixelSize: 512)
                #expect(image.pixelSize.width > 0)
                #expect(image.pixelSize.height > 0)
            } catch {
                continue
            }
        }
    }

    @Test("decode(data:) returns the same pixelSize as decoding a file URL", arguments: ["jpg", "png"])
    func decodesDataLikeFile(fileExtension: String) async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("image.\(fileExtension)")
        if fileExtension == "jpg" {
            try ImageFixtures.jpeg(at: url, width: 400, height: 300)
        } else {
            try ImageFixtures.png(at: url, width: 400, height: 300)
        }

        let decoder = ImageDecoder()
        let fromFile = try await decoder.decode(url, maxPixelSize: 200)
        let fromData = try await decoder.decode(data: Data(contentsOf: url), maxPixelSize: 200)

        #expect(fromData.pixelSize == fromFile.pixelSize)
        #expect(fromData.originalPixelSize == fromFile.originalPixelSize)
        #expect(fromData.byteCost == fromFile.byteCost)
    }

    @Test("Corrupted Data fails with corrupted or unreadable")
    func rejectsBrokenData() async {
        let decoder = ImageDecoder()
        for data in [Data(), Data([0x00, 0x01, 0x02, 0x03]), Data("not an image".utf8)] {
            do {
                _ = try await decoder.decode(data: data, maxPixelSize: 512)
                Issue.record("decode(data:) did not throw")
            } catch {
                #expect(error == .corrupted || error == .unreadable)
            }
        }
    }

    @Test("isAnimated(data:) is true only for animated GIFs")
    func detectsAnimationFromData() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gif = root.appendingPathComponent("animation.gif")
        let png = root.appendingPathComponent("still.png")
        try ImageFixtures.animatedGIF(at: gif, frames: 4)
        try ImageFixtures.png(at: png, width: 32, height: 32)

        let decoder = ImageDecoder()
        #expect(decoder.isAnimated(data: try Data(contentsOf: gif)))
        #expect(!decoder.isAnimated(data: try Data(contentsOf: png)))
        #expect(!decoder.isAnimated(data: Data()))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolzioTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
