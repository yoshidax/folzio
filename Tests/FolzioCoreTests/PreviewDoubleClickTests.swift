import CoreGraphics
import Foundation
import Testing
@testable import FolzioCore

@Suite("PreviewDoubleClick")
struct PreviewDoubleClickTests {
    private let url = URL(fileURLWithPath: "/tmp/media/a.mp4")

    @Test("Only an empty preview has no media; loading and unavailable content count as media (EC-149)")
    func hasMedia() throws {
        let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(context.makeImage())
        let decoded = DecodedImage(cgImage: image, pixelSize: CGSize(width: 1, height: 1),
            originalPixelSize: CGSize(width: 1, height: 1), byteCost: 4)

        #expect(PreviewContent.empty.hasMedia == false)
        let media: [PreviewContent] = [
            .loading(url),
            .image(decoded),
            .animatedImage(url),
            .animatedImageData(url, Data()),
            .video(url),
            .unavailable(name: "a.mp4", reason: .corrupted),
        ]
        for content in media {
            #expect(content.hasMedia, "\(content)")
        }
    }

    /// Expected values follow the table in specs/TAK-19-media-double-click-fullscreen/data-model.md.
    @Test("Double-click decision table (FR-220, EC-149, EC-150)", arguments: [
        // (isOverControl, isFullScreen, hasMedia, expected)
        (true, false, false, false),
        (true, false, true, false),
        (true, true, false, false),
        (true, true, true, false),
        (false, true, false, true),
        (false, true, true, true),
        (false, false, true, true),
        (false, false, false, false),
    ])
    func decision(isOverControl: Bool, isFullScreen: Bool, hasMedia: Bool, expected: Bool) {
        let actual = PreviewDoubleClick.togglesFullScreen(
            isFullScreen: isFullScreen,
            hasMedia: hasMedia,
            isOverControl: isOverControl
        )
        #expect(actual == expected)
    }
}
