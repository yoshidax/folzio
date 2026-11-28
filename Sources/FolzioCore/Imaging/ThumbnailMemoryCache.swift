import CoreGraphics
import Dispatch
import Foundation

/// Thumbnails kept in memory up to a byte limit. When the limit is passed, the thumbnails used longest ago are
/// removed first, so the ones on screen most recently stay (FR-447, TAK-129 research.md R12). `NSCache` does not
/// promise this order. Reading a thumbnail counts as using it. Safe to use from any thread.
///
/// The cache also empties itself when the system reports memory pressure, as `NSCache` does.
final class ThumbnailMemoryCache: @unchecked Sendable {
    private struct Entry {
        let image: CGImage
        let cost: Int
        var lastUse: UInt64
    }

    let costLimit: Int
    private let lock = NSLock()
    private var entries: [NSString: Entry] = [:]
    private var totalCost = 0
    private var clock: UInt64 = 0
    private var evictions = 0
    private var pressureSource: DispatchSourceMemoryPressure?

    /// - Parameter watchesMemoryPressure: False in tests, which must not be emptied by the system.
    init(costLimit: Int, watchesMemoryPressure: Bool = true) {
        self.costLimit = max(0, costLimit)
        guard watchesMemoryPressure else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in
            self?.removeAll()
            PerformanceLog.logger.debug("[thumb] memory pressure: removed all kept thumbnails")
        }
        source.resume()
        pressureSource = source
    }

    deinit {
        pressureSource?.cancel()
    }

    /// The kept thumbnail for `key`, which also becomes the most recently used.
    func image(forKey key: NSString) -> CGImage? {
        lock.withLock {
            guard var entry = entries[key] else { return nil }
            clock &+= 1
            entry.lastUse = clock
            entries[key] = entry
            return entry.image
        }
    }

    /// Keeps `image` as the most recently used, then removes the least recently used thumbnails while the total
    /// passes the limit. An image larger than the limit is not kept.
    func setImage(_ image: CGImage, forKey key: NSString, cost: Int) {
        let (count, bytes, evicted) = lock.withLock { () -> (Int, Int, Int) in
            if let old = entries.removeValue(forKey: key) {
                totalCost -= old.cost
            }
            guard cost <= costLimit else { return (entries.count, totalCost, 0) }
            clock &+= 1
            entries[key] = Entry(image: image, cost: cost, lastUse: clock)
            totalCost += cost
            var evicted = 0
            if totalCost > costLimit {
                // Few hundred entries at most, so sorting once per overflow is cheap.
                for (oldKey, entry) in entries.sorted(by: { $0.value.lastUse < $1.value.lastUse }) {
                    guard totalCost > costLimit else { break }
                    guard oldKey != key else { continue }
                    entries[oldKey] = nil
                    totalCost -= entry.cost
                    evicted += 1
                }
                evictions += evicted
            }
            return (entries.count, totalCost, evicted)
        }
        if evicted > 0 {
            PerformanceLog.logger.debug(
                "[thumb] evicted \(evicted) least recently used, kept \(count) (~\(bytes / 1_048_576) MB)"
            )
        }
    }

    func removeAll() {
        lock.withLock {
            entries.removeAll()
            totalCost = 0
        }
    }

    /// Number of kept thumbnails and their total cost, for tests and the debug log.
    var usage: (count: Int, cost: Int) {
        lock.withLock { (entries.count, totalCost) }
    }
}
