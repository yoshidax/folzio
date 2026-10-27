import Foundation

public actor DecodedImageCache {
    private struct Entry {
        var image: DecodedImage
        var lastUsed: UInt64
    }

    private var entries: [URL: Entry] = [:]
    private var clock: UInt64 = 0

    public let costLimitBytes: Int
    public private(set) var totalCost: Int = 0

    public init(costLimitBytes: Int = MemoryLimits.previewCacheBytes) {
        self.costLimitBytes = max(0, costLimitBytes)
    }

    public func get(_ url: URL) -> DecodedImage? {
        guard var entry = entries[url] else { return nil }
        clock += 1
        entry.lastUsed = clock
        entries[url] = entry
        return entry.image
    }

    public func put(_ image: DecodedImage, for url: URL) {
        if let existing = entries.removeValue(forKey: url) {
            totalCost -= existing.image.byteCost
        }

        guard image.byteCost <= costLimitBytes else { return }

        clock += 1
        entries[url] = Entry(image: image, lastUsed: clock)
        totalCost += image.byteCost

        while totalCost > costLimitBytes {
            guard let oldest = entries.min(by: { $0.value.lastUsed < $1.value.lastUsed }) else {
                totalCost = 0
                break
            }
            entries.removeValue(forKey: oldest.key)
            totalCost -= oldest.value.image.byteCost
        }
    }

    public func removeAll() {
        entries.removeAll()
        totalCost = 0
    }
}
