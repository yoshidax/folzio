import AVFoundation
import Foundation
import ObjectiveC
import UniformTypeIdentifiers

/// Delegate that lets `AVURLAsset` read an mvzip URL (FR-072, research.md R25).
/// Returns content information and requested ranges from `ArchiveEntryStream` in 512 KB pieces. Creates no
/// temporary files. `stream(for:)` is created once per asset (this loader) and shared, so the cache and cursors
/// are per asset.
public final class ArchiveAssetLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    private static let responseChunkSize = 512 * 1024

    /// Wrapper that lets a non-Sendable `AVAssetResourceLoadingRequest` be passed to a task.
    private struct SendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    private let entryURL: URL
    private let reader: any ArchiveReading

    private let lock = NSLock()
    private var streamTask: Task<ArchiveEntryStream, any Error>?
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(entryURL: URL, reader: any ArchiveReading) {
        self.entryURL = entryURL
        self.reader = reader
    }

    /// Creates the task on the first request and shares it afterward (even when requests arrive concurrently).
    private func sharedStream() -> Task<ArchiveEntryStream, any Error> {
        lock.lock()
        defer { lock.unlock() }
        if let streamTask { return streamTask }
        let url = entryURL
        let reader = reader
        let task = Task.detached { () async throws -> ArchiveEntryStream in
            try await reader.stream(for: url)
        }
        streamTask = task
        return task
    }

    // MARK: - AVAssetResourceLoaderDelegate

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        let key = ObjectIdentifier(loadingRequest)
        let box = SendableBox(value: loadingRequest)
        let streamTask = sharedStream()
        let fileExtension = entryURL.pathExtension

        // Register before starting the task so removal on completion cannot happen before registration.
        lock.lock()
        let task = Task.detached { [weak self] in
            let request = box.value
            do {
                let stream = try await streamTask.value
                try Self.fill(request, from: stream, fileExtension: fileExtension)
                if Task.isCancelled { return }
                request.finishLoading()
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                let message = String(describing: error)
                request.finishLoading(with: NSError(
                    domain: "Folzio.Archive", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                ))
            }
            self?.forget(key)
        }
        tasks[key] = task
        lock.unlock()
        return true
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        let key = ObjectIdentifier(loadingRequest)
        lock.lock()
        let task = tasks.removeValue(forKey: key)
        lock.unlock()
        task?.cancel()
    }

    private func forget(_ key: ObjectIdentifier) {
        lock.lock()
        tasks.removeValue(forKey: key)
        lock.unlock()
    }

    // MARK: - Responding

    private static func fill(
        _ request: AVAssetResourceLoadingRequest, from stream: ArchiveEntryStream, fileExtension: String
    ) throws {
        if let info = request.contentInformationRequest {
            info.contentType = UTType(filenameExtension: fileExtension)?.identifier
            info.contentLength = Int64(clamping: stream.length)
            info.isByteRangeAccessSupported = true
        }
        guard let dataRequest = request.dataRequest else { return }

        var offset = UInt64(max(0, dataRequest.currentOffset))
        let end: UInt64
        if dataRequest.requestsAllDataToEndOfResource {
            end = stream.length
        } else {
            end = min(stream.length, UInt64(max(0, dataRequest.requestedOffset)) + UInt64(max(0, dataRequest.requestedLength)))
        }
        while offset < end {
            try Task.checkCancellation()
            let count = Int(min(UInt64(responseChunkSize), end - offset))
            let data = try stream.read(offset: offset, maxLength: count)
            guard !data.isEmpty else { break }
            dataRequest.respond(with: data)
            offset += UInt64(data.count)
        }
    }
}

/// Creates an `AVURLAsset` for playback and poster frames from an mvzip URL. Retains the loader while the asset
/// is alive (R25).
public enum ArchiveAssetFactory {
    /// `AVAssetResourceLoader` weakly references its delegate, so retain the loader by associating it with the asset.
    nonisolated(unsafe) private static var loaderKey: UInt8 = 0

    /// Dedicated serial queue for delegate callbacks
    private static let loaderQueue = DispatchQueue(label: "Folzio.ArchiveAssetLoader")

    public static func makeAsset(for entryURL: URL, reader: any ArchiveReading) -> AVURLAsset {
        let asset = AVURLAsset(url: entryURL)
        let loader = ArchiveAssetLoader(entryURL: entryURL, reader: reader)
        asset.resourceLoader.setDelegate(loader, queue: loaderQueue)
        objc_setAssociatedObject(asset, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN)
        return asset
    }
}
