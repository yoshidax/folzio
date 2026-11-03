import Foundation
import Testing
@testable import FolzioCore

/// Yields until `condition` holds. Records an issue instead of hanging when it never does.
private func waitUntil(
    _ description: String,
    _ condition: @escaping @Sendable () async -> Bool
) async {
    for _ in 0..<20_000 {
        if await condition() { return }
        await Task.yield()
    }
    Issue.record("Timed out waiting for: \(description)")
}

@Suite("ImageLoadScheduler")
struct ImageLoadSchedulerTests {
    @Test("Never holds more slots than the limit and serves the next waiter after a release")
    func respectsLimit() async {
        let scheduler = ImageLoadScheduler(limit: 2, prefetchLimit: 1)

        #expect(await scheduler.acquire(.preview))
        #expect(await scheduler.acquire(.preview))
        #expect(await scheduler.runningCount == 2)

        let third = Task { await scheduler.acquire(.preview) }
        await waitUntil("third request waits") { await scheduler.waitingCount == 1 }
        #expect(await scheduler.runningCount == 2)

        await scheduler.release(.preview)
        #expect(await third.value)
        #expect(await scheduler.runningCount == 2)
        #expect(await scheduler.peakRunning == 2)
    }

    @Test("Runs at most one prefetch at a time and keeps a slot for a preview")
    func limitsPrefetches() async {
        let scheduler = ImageLoadScheduler(limit: 2, prefetchLimit: 1)

        #expect(await scheduler.acquire(.prefetch))
        let secondPrefetch = Task { await scheduler.acquire(.prefetch) }
        await waitUntil("second prefetch waits") { await scheduler.waitingCount == 1 }
        #expect(await scheduler.runningCount == 1)

        // The preview takes the free slot without waiting for the prefetch.
        #expect(await scheduler.acquire(.preview))
        #expect(await scheduler.runningCount == 2)

        secondPrefetch.cancel()
        #expect(await secondPrefetch.value == false)
        #expect(await scheduler.peakRunning == 2)
    }

    @Test("Serves a waiting preview before a waiting prefetch")
    func servesPreviewFirst() async {
        let scheduler = ImageLoadScheduler(limit: 2, prefetchLimit: 1)
        #expect(await scheduler.acquire(.preview))
        #expect(await scheduler.acquire(.preview))

        let prefetch = Task { await scheduler.acquire(.prefetch) }
        await waitUntil("prefetch waits") { await scheduler.waitingCount == 1 }
        let preview = Task { await scheduler.acquire(.preview) }
        await waitUntil("preview waits") { await scheduler.waitingCount == 2 }

        await scheduler.release(.preview)
        #expect(await preview.value)
        #expect(await scheduler.waitingCount == 1)

        await scheduler.release(.preview)
        #expect(await prefetch.value)
        #expect(await scheduler.waitingCount == 0)
        #expect(await scheduler.peakRunning == 2)
    }

    @Test("A request cancelled while waiting takes no slot and does not block later requests")
    func cancelledWaiterTakesNoSlot() async {
        let scheduler = ImageLoadScheduler(limit: 2, prefetchLimit: 1)
        #expect(await scheduler.acquire(.preview))
        #expect(await scheduler.acquire(.preview))

        let waiter = Task { await scheduler.acquire(.preview) }
        await waitUntil("waiter waits") { await scheduler.waitingCount == 1 }
        waiter.cancel()

        #expect(await waiter.value == false)
        #expect(await scheduler.waitingCount == 0)
        #expect(await scheduler.runningCount == 2)

        await scheduler.release(.preview)
        await scheduler.release(.preview)
        #expect(await scheduler.runningCount == 0)
        #expect(await scheduler.acquire(.preview))
    }

    @Test("A request cancelled before it asks for a slot gets none")
    func cancelledBeforeAcquire() async {
        let scheduler = ImageLoadScheduler()

        let task = Task { () -> Bool in
            while !Task.isCancelled {
                await Task.yield()
            }
            return await scheduler.acquire(.preview)
        }
        task.cancel()

        #expect(await task.value == false)
        #expect(await scheduler.runningCount == 0)
    }

    @Test("Slots are returned after every release so later requests are never starved")
    func slotsAreReturned() async {
        let scheduler = ImageLoadScheduler(limit: 2, prefetchLimit: 1)

        for _ in 0..<10 {
            #expect(await scheduler.acquire(.prefetch))
            #expect(await scheduler.acquire(.preview))
            await scheduler.release(.prefetch)
            await scheduler.release(.preview)
        }

        #expect(await scheduler.runningCount == 0)
        #expect(await scheduler.peakRunning == 2)
    }
}
