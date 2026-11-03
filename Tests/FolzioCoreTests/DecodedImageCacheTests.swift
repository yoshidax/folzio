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

        await cache.put(image(cost: 60), for: a, version: v1)
        await cache.put(image(cost: 60), for: b, version: v1)
        #expect(await cache.totalCost == 60)
        #expect(await cache.get(a, version: v1) == nil)
        #expect(await cache.get(b, version: v1) != nil)

        await cache.put(image(cost: 60), for: c, version: v1)
        #expect(await cache.get(b, version: v1) == nil)
        #expect(await cache.get(c, version: v1) != nil)
        #expect(await cache.totalCost <= 100)
    }

    @Test("get updates the usage order")
    func touchingRefreshesOrder() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let a = URL(fileURLWithPath: "/tmp/a.jpg")
        let b = URL(fileURLWithPath: "/tmp/b.jpg")
        let c = URL(fileURLWithPath: "/tmp/c.jpg")

        await cache.put(image(cost: 50), for: a, version: v1)
        await cache.put(image(cost: 50), for: b, version: v1)
        _ = await cache.get(a, version: v1)
        await cache.put(image(cost: 50), for: c, version: v1)

        #expect(await cache.get(a, version: v1) != nil)
        #expect(await cache.get(c, version: v1) != nil)
        #expect(await cache.get(b, version: v1) == nil)
    }

    @Test("Does not keep an image that exceeds the limit")
    func rejectsOversizedImage() async {
        let cache = DecodedImageCache(costLimitBytes: 50)
        let url = URL(fileURLWithPath: "/tmp/huge.jpg")

        await cache.put(image(cost: 60), for: url, version: v1)
        #expect(await cache.get(url, version: v1) == nil)
        #expect(await cache.totalCost == 0)
    }

    @Test("removeAll empties the cache")
    func removesAll() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")
        await cache.put(image(cost: 10), for: url, version: v1)
        await cache.removeAll()
        #expect(await cache.get(url, version: v1) == nil)
        #expect(await cache.totalCost == 0)
    }

    @Test("A lookup with another content version misses and discards the entry (FR-230)")
    func missesOnDifferentVersion() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")

        await cache.put(image(cost: 10), for: url, version: v1)
        #expect(await cache.get(url, version: v2) == nil)
        #expect(await cache.totalCost == 0)
        #expect(await cache.get(url, version: v1) == nil)
    }

    @Test("An image stored later from the old version does not hit a lookup with the new version (EC-161)")
    func lateStoreOfOldVersionDoesNotHit() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")

        await cache.put(image(cost: 10), for: url, version: v2)
        await cache.put(image(cost: 10), for: url, version: v1)
        #expect(await cache.get(url, version: v2) == nil)
        #expect(await cache.totalCost == 0)
    }

    @Test("Keeps one entry per URL when versions change")
    func keepsOneEntryPerURL() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")

        await cache.put(image(cost: 30), for: url, version: v1)
        await cache.put(image(cost: 40), for: url, version: v2)
        #expect(await cache.totalCost == 40)
        #expect(await cache.get(url, version: v2) != nil)
    }

    @Test("Does not store or return images without a version")
    func ignoresMissingVersion() async {
        let cache = DecodedImageCache(costLimitBytes: 100)
        let url = URL(fileURLWithPath: "/tmp/a.jpg")

        await cache.put(image(cost: 10), for: url, version: nil)
        #expect(await cache.totalCost == 0)
        await cache.put(image(cost: 10), for: url, version: v1)
        #expect(await cache.get(url, version: nil) == nil)
    }

    private let v1 = FileContentVersion(fileSize: 10, modificationDate: Date(timeIntervalSince1970: 1), fileIdentifier: 1)
    private let v2 = FileContentVersion(fileSize: 20, modificationDate: Date(timeIntervalSince1970: 2), fileIdentifier: 1)

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
