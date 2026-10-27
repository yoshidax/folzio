import CoreGraphics
import Foundation
import ImageIO

public enum WebPFixtures {
    public static let typeIdentifier = "org.webmproject.webp"

    public static func staticImage(at url: URL) throws {
        if canWriteWithImageIO {
            let image = try ImageFixtures.makeRGBImage(width: 320, height: 240, variant: 0)
            try write(image: image, to: url)
        } else {
            try copyBundled(named: "static", to: url)
        }
    }

    public static func animatedImage(at url: URL) throws {
        if canWriteWithImageIO {
            try writeAnimated(to: url)
        } else {
            try copyBundled(named: "animated", to: url)
        }
    }

    private static var canWriteWithImageIO: Bool {
        let identifiers = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return identifiers.contains(typeIdentifier)
    }

    private static func copyBundled(named name: String, to url: URL) throws {
        guard let bundled = Bundle.module.url(forResource: name, withExtension: "webp") else {
            throw FixtureError.missingBundledWebP("\(name).webp")
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: bundled, to: url)
    }

    private static func write(image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            typeIdentifier as CFString,
            1,
            nil
        ) else {
            throw FixtureError.cannotCreateDestination(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.writeFailed(url)
        }
    }

    private static func writeAnimated(to url: URL) throws {
        let frameCount = 6
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            typeIdentifier as CFString,
            frameCount,
            nil
        ) else {
            throw FixtureError.cannotCreateDestination(url)
        }

        for index in 0..<frameCount {
            let image = try ImageFixtures.makeRGBImage(width: 320, height: 240, variant: index)
            CGImageDestinationAddImage(destination, image, nil)
        }

        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.writeFailed(url)
        }
    }
}
