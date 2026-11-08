import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Drop operation cache")
@MainActor
struct DropOperationCacheTests {
    private func context(_ name: String, option: Bool = false) -> DropOperationCache.Context {
        DropOperationCache.Context(
            urls: [URL(fileURLWithPath: "/tmp/\(name).jpg")],
            destination: URL(fileURLWithPath: "/tmp/destination"),
            option: option,
            command: false,
            mask: 0
        )
    }

    /// Waits until the detached decision for the next stored context finishes.
    /// `start` must begin a decision that is not stored yet, so it returns nil.
    private func waitForOutcome(_ cache: DropOperationCache, start: () -> DropOperationCache.Outcome?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            cache.onOutcomeStored = { _ in
                cache.onOutcomeStored = nil
                continuation.resume()
            }
            #expect(start() == nil)
        }
    }

    @Test("Reads the URLs once per drag session and again for a new session (TAK-74)")
    func urlsAreReadOncePerSession() {
        let cache = DropOperationCache()
        var reads = 0
        let read: () -> [URL] = {
            reads += 1
            return [URL(fileURLWithPath: "/tmp/\(reads).jpg")]
        }
        let first = cache.urls(sequence: 1, read: read)
        #expect(cache.urls(sequence: 1, read: read) == first)
        #expect(reads == 1)
        let second = cache.urls(sequence: 2, read: read)
        #expect(second != first)
        #expect(reads == 2)
    }

    @Test("Returns nil until the decision finishes, then the stored decision without deciding again")
    func decisionIsCachedPerContext() async {
        let cache = DropOperationCache()
        let calls = Counter()
        let decide: DropOperationCache.Decide = { context in
            calls.increment()
            return context.option ? .accepted(.copy) : .rejected
        }
        let copy = context("a", option: true)
        #expect(cache.cachedOutcome(sequence: 1, context: copy) == nil)
        await waitForOutcome(cache) { cache.outcome(sequence: 1, context: copy, decide: decide) }
        #expect(cache.outcome(sequence: 1, context: copy, decide: decide) == .accepted(.copy))
        #expect(cache.cachedOutcome(sequence: 1, context: copy) == .accepted(.copy))
        #expect(calls.value == 1)

        let move = context("a", option: false)
        await waitForOutcome(cache) { cache.outcome(sequence: 1, context: move, decide: decide) }
        #expect(cache.cachedOutcome(sequence: 1, context: move) == .rejected)
        #expect(calls.value == 2)
    }

    @Test("Forgets decisions from the previous drag session")
    func newSessionDiscardsDecisions() async {
        let cache = DropOperationCache()
        let decide: DropOperationCache.Decide = { _ in .accepted(.move) }
        let target = context("a")
        await waitForOutcome(cache) { cache.outcome(sequence: 1, context: target, decide: decide) }
        #expect(cache.cachedOutcome(sequence: 1, context: target) == .accepted(.move))
        // A drop in another session must not reuse the old decision.
        #expect(cache.cachedOutcome(sequence: 2, context: target) == nil)
        #expect(cache.outcome(sequence: 2, context: target, decide: decide) == nil)
        #expect(cache.cachedOutcome(sequence: 1, context: target) == nil)
    }
}

@Suite("Drags to other apps")
@MainActor
struct DragsToOtherAppsTests {
    @Test("Offers copy, move, and the Command move outside the app, but not delete or alias (FR-344, A-206)")
    func operationMaskOutsideApp() {
        let mask = ExternalDrag.sourceOperationMaskOutsideApp
        #expect(mask.contains(.copy))
        #expect(mask.contains(.move))
        #expect(mask.contains(.generic))
        // The Dock Trash leaves the deletion to the drag source, which this app does not perform (T005).
        #expect(!mask.contains(.delete))
        #expect(!mask.contains(.link))
    }

    @Test("Remembers which drag session this app accepted, so a drag dropped outside the app is told apart (FR-219)")
    func acceptedSessions() {
        InternalDrag.markAccepted(101)
        #expect(InternalDrag.wasAccepted(101))
        // Another session, such as a later drag dropped on Finder, was not accepted by this app.
        #expect(!InternalDrag.wasAccepted(102))
        InternalDrag.markAccepted(102)
        #expect(InternalDrag.wasAccepted(102))
        #expect(!InternalDrag.wasAccepted(101))
    }
}

@Suite("File URLs on the pasteboard", .serialized)
@MainActor
struct PasteboardFileURLsTests {
    private let file = URL(fileURLWithPath: "/tmp/TAK-74/cat.jpg")

    /// Runs `body` with a private pasteboard, so the tests do not touch the general pasteboard.
    private func withPasteboard(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FolzioTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        body(pasteboard)
    }

    @Test("Reads file URLs (FR-348)")
    func fileURLs() {
        withPasteboard { pasteboard in
            pasteboard.writeObjects([file as NSURL])
            #expect(PasteboardFileURLs.fileURLs(in: pasteboard) == [file])
        }
    }

    @Test("Reads only the file URL when a drag also carries image data (FR-348)")
    func fileURLWithImageData() {
        withPasteboard { pasteboard in
            let item = NSPasteboardItem()
            item.setString(file.absoluteString, forType: .fileURL)
            item.setData(Data([0x4D, 0x4D, 0x00, 0x2A]), forType: .tiff)
            pasteboard.writeObjects([item])
            #expect(PasteboardFileURLs.fileURLs(in: pasteboard) == [file])
        }
    }

    @Test("Ignores drags without file URLs, such as web images, links, and text (FR-348, US76-AS6)")
    func nothingWithoutFileURLs() {
        withPasteboard { pasteboard in
            pasteboard.setData(Data([0x4D, 0x4D, 0x00, 0x2A]), forType: .tiff)
            #expect(PasteboardFileURLs.fileURLs(in: pasteboard).isEmpty)
        }
        withPasteboard { pasteboard in
            pasteboard.writeObjects([NSURL(string: "https://example.com/images/cat.jpg")!])
            #expect(PasteboardFileURLs.fileURLs(in: pasteboard).isEmpty)
        }
        withPasteboard { pasteboard in
            pasteboard.setString("cat.jpg", forType: .string)
            #expect(PasteboardFileURLs.fileURLs(in: pasteboard).isEmpty)
        }
    }
}

@Suite("Drops from other apps")
@MainActor
struct DropsFromOtherAppsTests {
    @Test("Shows a move as move when the source allows it, otherwise as the Command move (FR-346)")
    func dragOperationForMove() {
        #expect(ExternalDrag.dragOperation(.move, mask: [.copy, .move, .generic]) == .move)
        // While Command is held, the system narrows the source's mask to `.generic`.
        #expect(ExternalDrag.dragOperation(.move, mask: .generic) == .generic)
        #expect(ExternalDrag.dragOperation(.copy, mask: [.copy, .move]) == .copy)
    }
}

/// A thread-safe counter for decisions that run in a detached task.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
