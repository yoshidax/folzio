import CoreGraphics
import Foundation
import Testing
@testable import FolzioCore

@Suite("ThumbnailMemoryCache")
struct ThumbnailMemoryCacheTests {
    private func image() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try #require(context.makeImage())
    }

    @Test("Passing the limit removes the least recently used thumbnails first, and reading counts as use (FR-447)")
    func removesLeastRecentlyUsedFirst() throws {
        let cache = ThumbnailMemoryCache(costLimit: 30, watchesMemoryPressure: false)
        let picture = try image()
        cache.setImage(picture, forKey: "a", cost: 10)
        cache.setImage(picture, forKey: "b", cost: 10)
        cache.setImage(picture, forKey: "c", cost: 10)
        // Using "a" makes "b" the least recently used.
        #expect(cache.image(forKey: "a") === picture)

        cache.setImage(picture, forKey: "d", cost: 10)
        #expect(cache.image(forKey: "b") == nil)
        #expect(cache.image(forKey: "a") === picture)
        #expect(cache.image(forKey: "c") === picture)
        #expect(cache.image(forKey: "d") === picture)
        #expect(cache.usage.count == 3)
        #expect(cache.usage.cost == 30)

        // A large thumbnail removes as many old ones as needed. "a", "c", "d" were used in that order above.
        cache.setImage(picture, forKey: "e", cost: 25)
        #expect(cache.image(forKey: "a") == nil)
        #expect(cache.image(forKey: "c") == nil)
        #expect(cache.image(forKey: "d") == nil)
        #expect(cache.image(forKey: "e") === picture)
        #expect(cache.usage.cost == 25)
    }

    @Test("Setting the same key again replaces it without counting it twice, and an oversized image is not kept")
    func replacesAndSkipsOversized() throws {
        let cache = ThumbnailMemoryCache(costLimit: 20, watchesMemoryPressure: false)
        let picture = try image()
        cache.setImage(picture, forKey: "a", cost: 10)
        cache.setImage(picture, forKey: "a", cost: 15)
        #expect(cache.usage.count == 1)
        #expect(cache.usage.cost == 15)

        cache.setImage(picture, forKey: "big", cost: 21)
        #expect(cache.image(forKey: "big") == nil)
        #expect(cache.image(forKey: "a") === picture)

        cache.removeAll()
        #expect(cache.usage.count == 0)
        #expect(cache.image(forKey: "a") == nil)
    }
}
