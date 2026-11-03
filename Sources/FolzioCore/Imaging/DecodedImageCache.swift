import Foundation

/// Decoded preview images keyed by URL. Each entry records the content version it was decoded from, and a lookup
/// with a different version misses, so images of replaced content are not shown (FR-230, research.md R2).
public actor DecodedImageCache {
    private struct Entry {
        var image: DecodedImage
        var version: FileContentVersion
        var lastUsed: UInt64
    }

    private var entries: [URL: Entry] = [:]
    private var clock: UInt64 = 0

    public let costLimitBytes: Int
    public private(set) var totalCost: Int = 0

    public init(costLimitBytes: Int = MemoryLimits.previewCacheBytes) {
        self.costLimitBytes = max(0, costLimitBytes)
    }

    /// Returns the image for `url` decoded from `version`. Discards an entry of another version and returns nil.
    /// Always returns nil when `version` is nil.
    public func get(_ url: URL, version: FileContentVersion?) -> DecodedImage? {
        guard let version, var entry = entries[url] else { return nil }
        guard entry.version == version else {
            remove(url)
            return nil
        }
        clock += 1
        entry.lastUsed = clock
        entries[url] = entry
        return entry.image
    }

    /// Stores the image decoded from `version`, replacing any entry for `url`. Does not store when `version` is nil.
    public func put(_ image: DecodedImage, for url: URL, version: FileContentVersion?) {
        guard let version else { return }
        remove(url)

        guard image.byteCost <= costLimitBytes else { return }

        clock += 1
        entries[url] = Entry(image: image, version: version, lastUsed: clock)
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

    /// Whether an entry of any version exists for `url`. Does not change the usage order. For tests.
    func containsEntry(for url: URL) -> Bool {
        entries[url] != nil
    }

    private func remove(_ url: URL) {
        if let existing = entries.removeValue(forKey: url) {
            totalCost -= existing.image.byteCost
        }
    }

    public func removeAll() {
        entries.removeAll()
        totalCost = 0
    }
}
