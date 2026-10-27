import Foundation
import ImageIO
import Testing
@testable import FixtureKit

@Suite("PreviewZoomFixture")
struct PreviewZoomFixtureTests {
    @Test("zoom contains four items: a small image, a tiny image, a 24 MP wide image, and a tall image")
    func zoomSet() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FixtureSets.zoom(in: directory)

        let folder = directory.appendingPathComponent("zoom", isDirectory: true)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(names == [
            "01-small-16.png",
            "02-tiny-1.png",
            "03-landscape-24mp.jpg",
            "04-portrait.png",
        ])

        #expect(pixelSize(of: folder.appendingPathComponent("01-small-16.png")) == Size(width: 16, height: 16))
        #expect(pixelSize(of: folder.appendingPathComponent("02-tiny-1.png")) == Size(width: 1, height: 1))
        #expect(pixelSize(of: folder.appendingPathComponent("03-landscape-24mp.jpg")) == Size(width: 6000, height: 4000))
        #expect(pixelSize(of: folder.appendingPathComponent("04-portrait.png")) == Size(width: 1200, height: 2400))
    }

    private struct Size: Equatable {
        var width: Int
        var height: Int
    }

    private func pixelSize(of url: URL) -> Size? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return Size(width: width, height: height)
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewZoomFixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
