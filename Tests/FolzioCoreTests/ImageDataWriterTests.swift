import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FolzioCore

@Suite("Image data writer")
struct ImageDataWriterTests {
    @Test func writesPNGAndFirstTIFFFrame() throws {
        try ImportTestFiles.directory { root in
            let png = try ImportTestFiles.image()
            let output = root.appendingPathComponent("out.png")
            _ = try ImageDataWriter.write(png, to: output).get()
            #expect(try Data(contentsOf: output) == png)
            try FileManager.default.removeItem(at: output)
            _ = try ImageDataWriter.write(ImportTestFiles.image(.tiff, frames: 2), to: output).get()
            let source = try #require(CGImageSourceCreateWithURL(output as CFURL, nil))
            #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
            #expect(CGImageSourceGetCount(source) == 1)
        }
    }
    @Test func rejectsBadLargeAndHighPixelData() throws {
        try ImportTestFiles.directory { root in
            let output = root.appendingPathComponent("out.png")
            #expect(ImageDataWriter.write(Data([1, 2, 3]), to: output) == .failure(.notImageOrVideo))
            #expect(ImageDataWriter.write(Data(count: 256_000_001), to: output) == .failure(.tooLarge(limit: 256_000_000)))
            let large = try ImportTestFiles.largeTIFF()
            let metadata = try #require(CGImageSourceCreateWithData(large as CFData, nil))
            let properties = try #require(CGImageSourceCopyPropertiesAtIndex(metadata, 0, nil) as? [CFString: Any])
            #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 10_001)
            #expect((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == 10_000)
            #expect(ImageDataWriter.write(large, to: output) == .failure(.tooManyPixels))
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }
}
