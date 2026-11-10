import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageDataWriter {
    /// Reads metadata before decoding; callers run this work off the UI thread.
    public static func write(_ data: Data, to url: URL) -> Result<URL, ImportRejection> {
        guard data.count <= Int(ExpectedKind.image.byteLimit) else { return .failure(.tooLarge(limit: ExpectedKind.image.byteLimit)) }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?, let type = UTType(identifier),
              CGImageSourceGetCount(source) > 0 else { return .failure(.notImageOrVideo) }
        guard ImportPayloadPolicy.isRasterImage(type) else { return .failure(.unsupportedImageFormat) }
        do {
            if type == .png { try data.write(to: url, options: .withoutOverwriting) }
            else {
                guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                      width.doubleValue > 0, height.doubleValue > 0 else { return .failure(.notImageOrVideo) }
                guard width.doubleValue * height.doubleValue <= 100_000_000 else { return .failure(.tooManyPixels) }
                guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .failure(.notImageOrVideo) }
                let encoded = NSMutableData()
                guard let writer = CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil) else {
                    return .failure(.sourceFailed)
                }
                CGImageDestinationAddImage(writer, image, nil)
                guard CGImageDestinationFinalize(writer) else { return .failure(.sourceFailed) }
                guard encoded.length <= Int(ExpectedKind.image.byteLimit) else { return .failure(.tooLarge(limit: ExpectedKind.image.byteLimit)) }
                try (encoded as Data).write(to: url, options: .withoutOverwriting)
            }
            ImportInspector.ensureQuarantine(on: url)
            return .success(url)
        } catch { return .failure(.sourceFailed) }
    }
}
