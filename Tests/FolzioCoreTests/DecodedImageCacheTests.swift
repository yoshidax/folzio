import CoreGraphics
import Foundation
import Testing
@testable import FolzioCore

@Suite("DecodedImageCache")
struct DecodedImageCacheTests {
    @Test("Discards the oldest entry when over the limit")
    func evictsLeastRecentlyUsed() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.jpg")
        let c = URL(fileURLWithPath: "/tmp/c.jpg")

        await cache.put(image(cost: 60), for: a)
        await cache.put(image(cost: 60), for: b)
        #expect(await cache.totalCost == 60)
        #expect(await cache.get(a) == nil)
        #expect(await cache.get(b) != nil)

        await cache.put(image(cost: 60), for: c)
        #expect(await cache.get(b) == nil)
        #expect(await cache.get(c) != nil)
        #expect(await cache.totalCost <= 100)
    }

    @Test("get updates the usage order")
    func touchingRefreshesOrder() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.jpg")
        let c = URL(fileURLWithPath: "/tmp/c.jpg")

        await cache.put(image(cost: 50), for: a)
        await cache.put(image(cost: 50), for: b)
        _ = await cache.get(a)
        await cache.put(image(cost: 50), for: c)

        #expect(await cache.get(a) != nil)
        #expect(await cache.get(c) != nil)
        #expect(await cache.get(b) == nil)
    }

    @Test("Does not keep an image that exceeds the limit")
    func rejectsOversizedImage() async {
        let cache = DecodedImageCache(costLimitBytes: 50)
        let url = URL(fileURLWithPath: "/tmp/huge.jpg")

        await cache.put(image(cost: 60), for: url)
        #expect(await cache.get(url) == nil)
        #expect(await cache.totalCost == 0)
    }

    @Test("removeAll empties the cache")
    func removesAll() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")
        await cache.put(image(cost: 10), for: url)
        await cache.removeAll()
        #expect(await cache.get(url) == nil)
        #expect(await cache.totalCost == 0)
    }

    private func image(cost: Int) -> DecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return DecodedImage(
            cgImage: context.makeImage()!,
            pixelSize: CGSize(width: 1, height: 1),
            originalPixelSize: CGSize(width: 1, height: 1),
            byteCost: cost
        )
    }
}
