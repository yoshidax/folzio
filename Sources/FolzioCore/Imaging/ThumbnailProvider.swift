import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import QuickLookThumbnailing

public protocol ThumbnailProviding: Sendable {
    func thumbnail(for url: URL, pointSize: Double, scale: Double) async -> CGImage?
    func cancel(for url: URL, pointSize: Double, scale: Double)
}

public final class ThumbnailProvider: ThumbnailProviding, @unchecked Sendable {
    private static let sizeSteps = [64, 128, 256, 512]

    public static func pixelSize(forPointSize pointSize: Double, scale: Double) -> Int {
        let target = pointSize * scale
        guard target.isFinite else { return sizeSteps[0] }
        for step in sizeSteps where target <= Double(step) {
            return step
        }
        return sizeSteps[sizeSteps.count - 1]
    }

    private final class CachedEntry {
        let image: CGImage

        init(image: CGImage) {
            self.image = image
        }
    }

    /// Wrapper that lets a non-Sendable QuickLook request be captured by a cancellation closure.
    private struct SendableBox<Value>: @unchecked Sendable {
        let value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    private struct InFlightRequest {
        let url: URL
        let pixelSize: Int
        /// Cancellation of the QuickLook request or of the zip retrieval task
        let cancel: @Sendable () -> Void
    }

    /// Number of concurrent retrievals from zips (research.md R24)
    static let maxConcurrentArchiveReads = 4
    /// Number of concurrent poster frames generated for videos in zips (separate from images; research.md R24, R25)
    static let maxConcurrentArchiveVideoReads = 2

    private let generator: QLThumbnailGenerator
    private let archiveReader: (any ArchiveReading)?
    private let archiveLimiter = ConcurrencyLimiter(limit: ThumbnailProvider.maxConcurrentArchiveReads)
    private let archiveVideoLimiter = ConcurrencyLimiter(limit: ThumbnailProvider.maxConcurrentArchiveVideoReads)
    private let cache = NSCache<NSString, CachedEntry>()
    private let lock = NSLock()
    private var inFlight: [UUID: InFlightRequest] = [:]

    public init(archiveReader: (any ArchiveReading)? = nil) {
        generator = QLThumbnailGenerator.shared
        self.archiveReader = archiveReader
        cache.totalCostLimit = MemoryLimits.thumbnailCacheBytes
    }

    public func thumbnail(for url: URL, pointSize: Double, scale: Double) async -> CGImage? {
        let pixelSize = Self.pixelSize(forPointSize: pointSize, scale: scale)
        let key = Self.cacheKey(for: url, pixelSize: pixelSize)

        if let cached = cache.object(forKey: key) {
            return cached.image
        }

        if let location = ArchiveURL.parse(url) {
            return await archiveThumbnail(for: url, path: location.path, pixelSize: pixelSize, key: key)
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: pixelSize, height: pixelSize),
            scale: 1,
            representationTypes: .thumbnail
        )
        let identifier = UUID()
        lock.withLock {
            inFlight[identifier] = InFlightRequest(
                url: url,
                pixelSize: pixelSize,
                cancel: { [box = SendableBox((generator, request))] in box.value.0.cancel(box.value.1) }
            )
        }
        defer {
            lock.withLock {
                inFlight[identifier] = nil
            }
        }

        do {
            let representation = try await generator.generateBestRepresentation(for: request)
            let image = representation.cgImage
            let cost = image.width * image.height * 4
            cache.setObject(CachedEntry(image: image), forKey: key, cost: cost)
            return image
        } catch {
            return nil
        }
    }

    public func cancel(for url: URL, pointSize: Double, scale: Double) {
        let pixelSize = Self.pixelSize(forPointSize: pointSize, scale: scale)
        let cancellations: [@Sendable () -> Void] = lock.withLock {
            let matches = inFlight.filter {
                $0.value.url == url && $0.value.pixelSize == pixelSize
            }
            for identifier in matches.keys {
                inFlight[identifier] = nil
            }
            return matches.values.map(\.cancel)
        }

        for cancel in cancellations {
            cancel()
        }
    }

    /// Images and videos inside a zip. Does not use QuickLook. Creates a downscaled image from `Data` with
    /// ImageIO, and a first frame for videos with `AVAssetImageGenerator`. Returns nil for encrypted entries,
    /// unsupported methods, and failures.
    private func archiveThumbnail(for url: URL, path: String, pixelSize: Int, key: NSString) async -> CGImage? {
        guard let archiveReader,
              let kind = MediaKind(fileExtension: (path as NSString).pathExtension)
        else { return nil }

        let isVideo = kind.isVideo
        let limiter = isVideo ? archiveVideoLimiter : archiveLimiter
        let task = Task.detached(priority: .utility) { () -> CGImage? in
            guard await limiter.acquire() else { return nil }
            let image: CGImage?
            if isVideo {
                image = await Self.makeArchiveVideoThumbnail(url: url, pixelSize: pixelSize, reader: archiveReader)
            } else {
                image = await Self.makeArchiveThumbnail(url: url, pixelSize: pixelSize, reader: archiveReader)
            }
            await limiter.release()
            return image
        }

        let identifier = UUID()
        lock.withLock {
            inFlight[identifier] = InFlightRequest(
                url: url,
                pixelSize: pixelSize,
                cancel: { task.cancel() }
            )
        }
        defer {
            lock.withLock {
                inFlight[identifier] = nil
            }
        }

        let image = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard let image, !task.isCancelled else { return nil }
        cache.setObject(CachedEntry(image: image), forKey: key, cost: image.width * image.height * 4)
        return image
    }

    private static func makeArchiveThumbnail(
        url: URL,
        pixelSize: Int,
        reader: any ArchiveReading
    ) async -> CGImage? {
        guard !Task.isCancelled,
              let data = try? await reader.data(for: url, limit: MemoryLimits.archiveImageBytes),
              !Task.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// First frame of a video inside a zip. The asset retains the loader, so keep the asset until generation finishes.
    private static func makeArchiveVideoThumbnail(
        url: URL,
        pixelSize: Int,
        reader: any ArchiveReading
    ) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let asset = ArchiveAssetFactory.makeAsset(for: url, reader: reader)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: pixelSize, height: pixelSize)
        let box = SendableBox((generator, asset))
        return await withTaskCancellationHandler {
            let image = try? await box.value.0.image(at: .zero).image
            withExtendedLifetime(box.value.1) {}
            return image
        } onCancel: {
            box.value.0.cancelAllCGImageGeneration()
        }
    }

    private static func cacheKey(for url: URL, pixelSize: Int) -> NSString {
        "\(url.absoluteString)#\(pixelSize)" as NSString
    }
}

/// Simple semaphore that limits concurrency. `acquire()` returns false when cancelled while waiting.
private actor ConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    init(limit: Int) {
        self.limit = limit
    }

    /// True when a slot was acquired; the caller must call `release()` when done. False when no slot was acquired.
    func acquire() async -> Bool {
        if Task.isCancelled { return false }
        if running < limit {
            running += 1
            return true
        }
        let id = UUID()
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
        if granted && Task.isCancelled {
            release()
            return false
        }
        return granted
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().continuation.resume(returning: true)
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }
}
