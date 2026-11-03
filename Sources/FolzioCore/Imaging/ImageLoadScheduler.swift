import Foundation

/// Which kind of request is asking for a load slot.
public enum ImageLoadPriority: Sendable {
    /// Loading the image of the focused row for the preview.
    case preview
    /// Loading a neighbor of the focused row ahead of time.
    case prefetch
}

/// Limits how many image loads (reading and decoding) run at the same time (FR-282).
///
/// The preview and the prefetch share the slots. The preview is served first when a slot becomes free, and only
/// `prefetchLimit` prefetches run at once, so prefetches alone never fill every slot (FR-284). A request cancelled
/// while waiting leaves the queue without taking a slot (EC-198).
public actor ImageLoadScheduler {
    public static let defaultLimit = 2
    public static let defaultPrefetchLimit = 1

    private struct Waiter {
        let id: UUID
        let priority: ImageLoadPriority
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private let prefetchLimit: Int
    private var running = 0
    private var runningPrefetches = 0
    private var peak = 0
    private var previewWaiters: [Waiter] = []
    private var prefetchWaiters: [Waiter] = []

    public init(
        limit: Int = ImageLoadScheduler.defaultLimit,
        prefetchLimit: Int = ImageLoadScheduler.defaultPrefetchLimit
    ) {
        let limit = max(1, limit)
        self.limit = limit
        self.prefetchLimit = max(1, min(prefetchLimit, limit))
    }

    /// The largest number of slots held at the same time since the scheduler was created.
    public var peakRunning: Int { peak }

    /// The number of slots held now.
    public var runningCount: Int { running }

    /// The number of requests waiting for a slot now.
    public var waitingCount: Int { previewWaiters.count + prefetchWaiters.count }

    /// Waits for a slot and returns whether the caller got one.
    ///
    /// Returns false, without holding a slot, when the calling task is cancelled before or while waiting.
    /// A caller that gets a slot must call `release(_:)` with the same priority when it finishes, whether the load
    /// succeeded, failed, or was cancelled.
    public func acquire(_ priority: ImageLoadPriority) async -> Bool {
        if Task.isCancelled { return false }
        if canStartImmediately(priority) {
            take(priority)
            return true
        }

        let id = UUID()
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled {
                    continuation.resume(returning: false)
                    return
                }
                let waiter = Waiter(id: id, priority: priority, continuation: continuation)
                switch priority {
                case .preview:
                    previewWaiters.append(waiter)
                case .prefetch:
                    prefetchWaiters.append(waiter)
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }

        if granted && Task.isCancelled {
            release(priority)
            return false
        }
        return granted
    }

    /// Returns a slot taken by `acquire(_:)` and hands it to the next waiter, previews first.
    public func release(_ priority: ImageLoadPriority) {
        running -= 1
        if priority == .prefetch {
            runningPrefetches -= 1
        }
        dispatchWaiters()
    }

    private func canStartImmediately(_ priority: ImageLoadPriority) -> Bool {
        guard running < limit else { return false }
        switch priority {
        case .preview:
            return previewWaiters.isEmpty
        case .prefetch:
            return previewWaiters.isEmpty && prefetchWaiters.isEmpty && runningPrefetches < prefetchLimit
        }
    }

    private func take(_ priority: ImageLoadPriority) {
        running += 1
        if priority == .prefetch {
            runningPrefetches += 1
        }
        peak = max(peak, running)
    }

    private func dispatchWaiters() {
        while running < limit {
            if !previewWaiters.isEmpty {
                let waiter = previewWaiters.removeFirst()
                take(.preview)
                waiter.continuation.resume(returning: true)
            } else if runningPrefetches < prefetchLimit, !prefetchWaiters.isEmpty {
                let waiter = prefetchWaiters.removeFirst()
                take(.prefetch)
                waiter.continuation.resume(returning: true)
            } else {
                break
            }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        if let index = previewWaiters.firstIndex(where: { $0.id == id }) {
            previewWaiters.remove(at: index).continuation.resume(returning: false)
        } else if let index = prefetchWaiters.firstIndex(where: { $0.id == id }) {
            prefetchWaiters.remove(at: index).continuation.resume(returning: false)
        }
    }
}
