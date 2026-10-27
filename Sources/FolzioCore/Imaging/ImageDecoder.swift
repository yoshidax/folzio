import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum DecodeError: Error, Sendable, Equatable {
    case unreadable
    case unsupported
    case corrupted
}

public protocol ImageDecoding: Sendable {
    func decode(_ url: URL, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage
    /// File URLs only (synchronous). Do not call with an mvzip URL.
    func isAnimated(_ url: URL) -> Bool
    /// For images inside a zip. Pass the content read by `ArchiveReading.data(for:)` (research.md R24).
    func decode(data: Data, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage
    func isAnimated(data: Data) -> Bool
}

public struct ImageDecoder: ImageDecoding {
    public init() {}

    public func decode(_ url: URL, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try Self.decodeSynchronously(url, maxPixelSize: maxPixelSize)
            }.value
        } catch let error as DecodeError {
            throw error
        } catch {
            throw DecodeError.corrupted
        }
    }

    public func decode(data: Data, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try Self.decodeSynchronously(data: data, maxPixelSize: maxPixelSize)
            }.value
        } catch let error as DecodeError {
            throw error
        } catch {
            throw DecodeError.corrupted
        }
    }

    public func isAnimated(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return false
        }
        return Self.isAnimated(source)
    }

    public func isAnimated(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        return Self.isAnimated(source)
    }

    private static func isAnimated(_ source: CGImageSource) -> Bool {
        CGImageSourceGetCount(source) > 1
    }

    private static func decodeSynchronously(_ url: URL, maxPixelSize: Int) throws(DecodeError) -> DecodedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw DecodeError.unreadable
        }
        return try decode(source, maxPixelSize: maxPixelSize)
    }

    private static func decodeSynchronously(data: Data, maxPixelSize: Int) throws(DecodeError) -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw DecodeError.unreadable
        }
        return try decode(source, maxPixelSize: maxPixelSize)
    }

    /// Shared logic for file URLs and Data (supported type, frame count, thumbnail options, and byteCost)
    private static func decode(_ source: CGImageSource, maxPixelSize: Int) throws(DecodeError) -> DecodedImage {
        guard let typeIdentifier = CGImageSourceGetType(source) as String? else {
            throw DecodeError.unreadable
        }
        guard supportedTypeIdentifiers.contains(typeIdentifier) else {
            throw DecodeError.unsupported
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw DecodeError.corrupted
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw DecodeError.corrupted
        }

        let pixelSize = CGSize(width: image.width, height: image.height)
        let originalPixelSize = CGSize(
            width: pixelWidth ?? image.width,
            height: pixelHeight ?? image.height
        )
        let byteCost = image.width * image.height * 4

        return DecodedImage(
            cgImage: image,
            pixelSize: pixelSize,
            originalPixelSize: originalPixelSize,
            byteCost: byteCost
        )
    }

    private static let supportedTypeIdentifiers: Set<String> = [
        UTType.jpeg.identifier,
        UTType.png.identifier,
        UTType.gif.identifier,
        "org.webmproject.webp",
    ]
}
