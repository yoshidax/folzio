import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FixtureError: Error, CustomStringConvertible {
    case cannotCreateContext(width: Int, height: Int)
    case cannotCreateImage
    case cannotCreateDestination(URL)
    case writeFailed(URL)
    case missingBundledWebP(String)
    case cannotCreatePixelBuffer
    case videoWriterFailed(String)

    public var description: String {
        switch self {
        case let .cannotCreateContext(width, height):
            return "cannot create \(width)x\(height) bitmap context"
        case .cannotCreateImage:
            return "cannot create CGImage"
        case let .cannotCreateDestination(url):
            return "cannot create image destination for \(url.path)"
        case let .writeFailed(url):
            return "cannot write image to \(url.path)"
        case let .missingBundledWebP(name):
            return "bundled WebP fixture \(name) is missing"
        case .cannotCreatePixelBuffer:
            return "cannot create pixel buffer"
        case let .videoWriterFailed(reason):
            return "video writer failed: \(reason)"
        }
    }
}

public enum ImageFixtures {
    public static func jpeg(at url: URL, width: Int, height: Int) throws {
        try write(image: makeRGBImage(width: width, height: height, variant: 0), to: url, type: UTType.jpeg.identifier)
    }

    public static func png(at url: URL, width: Int, height: Int) throws {
        try write(image: makeRGBImage(width: width, height: height, variant: 1), to: url, type: UTType.png.identifier)
    }

    public static func animatedGIF(at url: URL, frames: Int = 6, width: Int = 320, height: Int = 240) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.gif.identifier as CFString,
            max(1, frames),
            nil
        ) else {
            throw FixtureError.cannotCreateDestination(url)
        }

        let gifProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFLoopCount: 0,
            ] as [CFString: Any],
        ]
        CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

        let frameProperties: [CFString: Any] = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: 0.12,
            ] as [CFString: Any],
        ]
        for index in 0..<max(1, frames) {
            let image = try makeRGBImage(width: width, height: height, variant: index)
            CGImageDestinationAddImage(destination, image, frameProperties as CFDictionary)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.writeFailed(url)
        }
    }

    public static func grayscalePNG(at url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw FixtureError.cannotCreateContext(width: width, height: height)
        }

        let steps = 16
        for step in 0..<steps {
            let level = CGFloat(step) / CGFloat(steps - 1)
            context.setFillColor(gray: level, alpha: 1)
            context.fill(CGRect(
                x: 0,
                y: CGFloat(step) * CGFloat(height) / CGFloat(steps),
                width: CGFloat(width),
                height: CGFloat(height) / CGFloat(steps) + 1
            ))
        }

        guard let image = context.makeImage() else {
            throw FixtureError.cannotCreateImage
        }
        try write(image: image, to: url, type: UTType.png.identifier)
    }

    static func makeRGBImage(width: Int, height: Int, variant: Int) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw FixtureError.cannotCreateContext(width: width, height: height)
        }

        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.23, 0.55, 0.85),
            (0.85, 0.40, 0.25),
            (0.25, 0.70, 0.45),
            (0.70, 0.45, 0.80),
            (0.90, 0.75, 0.25),
            (0.30, 0.75, 0.80),
        ]
        let color = palette[variant % palette.count]

        context.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.45)
        let inset = CGFloat(min(width, height)) * 0.2
        context.fillEllipse(in: CGRect(
            x: inset + CGFloat(variant) * inset * 0.4,
            y: inset,
            width: CGFloat(width) - inset * 2,
            height: CGFloat(height) - inset * 2
        ))

        context.setStrokeColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.6)
        context.setLineWidth(CGFloat(max(2, min(width, height) / 80)))
        context.stroke(CGRect(x: 2, y: 2, width: width - 4, height: height - 4))

        guard let image = context.makeImage() else {
            throw FixtureError.cannotCreateImage
        }
        return image
    }

    static func write(image: CGImage, to url: URL, type: String) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil) else {
            throw FixtureError.cannotCreateDestination(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.writeFailed(url)
        }
    }
}
