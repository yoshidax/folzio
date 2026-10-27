import FixtureKit
import Foundation
import Testing

@testable import FolzioCore

@Suite("FileSystemWatcher")
struct FileSystemWatcherTests {
    @Test("Adding a file delivers an event for the watched folder within two seconds")
    func deliversEventForAddedFile() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let watcher = FileSystemWatcher()
        watcher.watch([folder])
        let (recorder, collector) = startCollector(watcher)
        defer { collector.cancel() }

        try Data("added".utf8).write(to: folder.appendingPathComponent("a.jpg"))

        let (event, observed) = await recorder.waitForEvent(after: 0)
        #expect(
            event != nil,
            "No event arrived within two seconds of adding a file. observed: \(describe(observed))"
        )
        if let event {
            #expect(
                containsFolder(event, folder),
                "Event does not include the watched folder. event: \(describe(event)), folder: \(folder.path)"
            )
        }

        await stopCollector(collector)
    }

    @Test("Renaming a file delivers an event for the watched folder within two seconds")
    func deliversEventForRenamedFile() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let original = folder.appendingPathComponent("a.jpg")
        try Data("renamed".utf8).write(to: original)

        let watcher = FileSystemWatcher()
        watcher.watch([folder])
        let (recorder, collector) = startCollector(watcher)
        defer { collector.cancel() }

        try FileManager.default.moveItem(
            at: original,
            to: folder.appendingPathComponent("b.jpg")
        )

        let (event, observed) = await recorder.waitForEvent(after: 0)
        #expect(
            event != nil,
            "No event arrived within two seconds of renaming a file. observed: \(describe(observed))"
        )
        if let event {
            #expect(
                containsFolder(event, folder),
                "Event does not include the watched folder. event: \(describe(event)), folder: \(folder.path)"
            )
        }

        await stopCollector(collector)
    }

    @Test("Deleting a file delivers an event for the watched folder within two seconds")
    func deliversEventForDeletedFile() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let file = folder.appendingPathComponent("a.jpg")
        try Data("deleted".utf8).write(to: file)

        let watcher = FileSystemWatcher()
        watcher.watch([folder])
        let (recorder, collector) = startCollector(watcher)
        defer { collector.cancel() }

        try FileManager.default.removeItem(at: file)

        let (event, observed) = await recorder.waitForEvent(after: 0)
        #expect(
            event != nil,
            "No event arrived within two seconds of deleting a file. observed: \(describe(observed))"
        )
        if let event {
            #expect(
                containsFolder(event, folder),
                "Event does not include the watched folder. event: \(describe(event)), folder: \(folder.path)"
            )
        }

        await stopCollector(collector)
    }

    @Test("Reflects external changes in the BrowserModel listing, selection, and preview")
    @MainActor
    func browserModelReflectsExternalChanges() async throws {
        let folder = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }

        let a = folder.appendingPathComponent("a.jpg")
        let b = folder.appendingPathComponent("b.jpg")
        let c = folder.appendingPathComponent("c.jpg")
        try ImageFixtures.jpeg(at: a, width: 32, height: 24)
        try ImageFixtures.jpeg(at: b, width: 32, height: 24)

        let suite = "FileSystemWatcherTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 32 * 1024 * 1024),
            settings: SettingsStore(defaults: defaults)
        )

        await model.selectFolder(folder)
        model.select([a], focused: a)

        let becameImage = await waitUntil(timeout: .seconds(2)) {
            if case .image = model.preview { return true }
            return false
        }
        #expect(
            becameImage,
            "The preview for a.jpg did not become an image. preview: \(describe(model.preview))"
        )

        let watcher = FileSystemWatcher()
        watcher.watch([folder])
        let (recorder, collector) = startCollector(watcher)
        defer { collector.cancel() }

        try FileManager.default.removeItem(at: a)
        try ImageFixtures.jpeg(at: c, width: 32, height: 24)

        let (event, observed) = await recorder.waitForEvent(after: 0)
        #expect(
            event != nil,
            "No event arrived within two seconds of an external change. observed: \(describe(observed))"
        )
        guard let event else {
            await stopCollector(collector)
            return
        }
        #expect(
            containsFolder(event, folder),
            "Event does not include the watched folder. event: \(describe(event)), folder: \(folder.path)"
        )

        await model.handleFileSystemEvent(event)

        let names = model.listing.files.map(\.name)
        #expect(names == ["b.jpg", "c.jpg"], "Listing was not updated. actual: \(names)")
        #expect(
            model.selection.focused == nil,
            "The deleted file remains focused. focused: \(model.selection.focused?.path ?? "nil")"
        )
        #expect(
            model.selection.selected.isEmpty,
            "The deleted file remains selected. selected: \(model.selection.selected.map(\.path).sorted())"
        )
        let previewIsEmpty: Bool = switch model.preview {
        case .empty: true
        default: false
        }
        #expect(
            previewIsEmpty,
            "The deleted file's preview remains visible. preview: \(describe(model.preview))"
        )

        await stopCollector(collector)
    }

    // MARK: - subtrees (Search Result Pruning, R38)

    @Test("subtrees emits changes at every descendant level as the changed path's parent folder")
    func subtreeDeliversDeepChanges() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let deep = root.appendingPathComponent("a/b/c", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(200))

        let watcher = FileSystemWatcher()
        watcher.watch([], subtrees: [root])
        let (recorder, collector) = startCollector(watcher)
        defer { collector.cancel() }

        let file = deep.appendingPathComponent("x.jpg")
        try Data("x".utf8).write(to: file)
        let observed1 = await recorder.waitForFolder(deep)
        let seen1 = await recorder.snapshot()
        #expect(observed1, "Create: \(describe(seen1))")

        let count = await recorder.snapshot().count
        try FileManager.default.removeItem(at: file)
        let observed2 = await recorder.waitForFolder(deep, after: count)
        let seen2 = await recorder.snapshot()
        #expect(observed2, "Delete: \(describe(seen2))")

        try Data("y".utf8).write(to: root.appendingPathComponent("y.jpg"))
        let observed3 = await recorder.waitForFolder(root)
        let seen3 = await recorder.snapshot()
        #expect(observed3, "Direct child: \(describe(seen3))")

        await stopCollector(collector)
    }

    @Test("Excludes changes outside subtrees and changes to grandchildren of folders")
    func subtreeIgnoresOutsideChanges() async throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("root", isDirectory: true)
        let other = base.appendingPathComponent("other", isDirectory: true)
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(200))

        let subtreeWatcher = FileSystemWatcher()
        subtreeWatcher.watch([], subtrees: [root])
        let (subtreeRecorder, subtreeCollector) = startCollector(subtreeWatcher)
        defer { subtreeCollector.cancel() }

        let folderWatcher = FileSystemWatcher()
        folderWatcher.watch([root.appendingPathComponent("a", isDirectory: true)])
        let (folderRecorder, folderCollector) = startCollector(folderWatcher)
        defer { folderCollector.cancel() }

        try Data("x".utf8).write(to: other.appendingPathComponent("x.jpg"))
        try Data("x".utf8).write(to: nested.appendingPathComponent("x.jpg"))
        try await Task.sleep(for: .milliseconds(1500))

        let subtreeEvents = await subtreeRecorder.snapshot()
        #expect(!subtreeEvents.contains { event in event.contains { $0.path.hasPrefix(other.path) } },
                "Outside subtrees: \(describe(subtreeEvents))")
        let folderEvents = await folderRecorder.snapshot()
        #expect(folderEvents.isEmpty, "folders grandchild: \(describe(folderEvents))")

        await stopCollector(subtreeCollector)
        await stopCollector(folderCollector)
    }

    @Test("Excludes changes inside hidden folders even under subtrees")
    func subtreeIgnoresHiddenFolders() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileManager = FileManager.default
        let cache = root.appendingPathComponent(".cache", isDirectory: true)
        let objects = root.appendingPathComponent("a/.git/objects", isDirectory: true)
        var hidden = root.appendingPathComponent("Hidden", isDirectory: true)
        for url in [cache, objects, hidden] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isHidden = true
        try hidden.setResourceValues(values)
        try await Task.sleep(for: .milliseconds(200))

        let watcher = FileSystemWatcher()
        watcher.watch([], subtrees: [root])
        let (recorder, collector) = startCollector(watcher)
        defer { collector.cancel() }

        for folder in [cache, objects, hidden] {
            let file = folder.appendingPathComponent("x.jpg")
            try Data("x".utf8).write(to: file)
            try fileManager.removeItem(at: file)
        }
        let a = root.appendingPathComponent("a", isDirectory: true)
        try Data("z".utf8).write(to: a.appendingPathComponent("z.jpg"))

        let observed4 = await recorder.waitForFolder(a)
        let seen4 = await recorder.snapshot()
        #expect(observed4, "root/a: \(describe(seen4))")
        try await Task.sleep(for: .milliseconds(500))
        let events = await recorder.snapshot()
        let hiddenPaths = [cache, objects, hidden].map(\.standardizedFileURL.path)
        #expect(!events.contains { event in
            event.contains { url in hiddenPaths.contains { url.standardizedFileURL.path.hasPrefix($0) } }
        }, "Hidden folder: \(describe(events))")
        #expect(!events.contains { $0.contains { $0.standardizedFileURL.path.contains("/.git") } })

        await stopCollector(collector)
    }

    @Test("Continuous changes emit within 1.5 seconds of the first change and keep emitting while changes continue")
    func continuousChangesAreNotStarved() async throws {
        for useSubtrees in [false, true] {
            let root = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let a = root.appendingPathComponent("a", isDirectory: true)
            try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
            try await Task.sleep(for: .milliseconds(200))

            let watcher = FileSystemWatcher()
            if useSubtrees {
                watcher.watch([], subtrees: [root])
            } else {
                watcher.watch([a])
            }
            let (recorder, collector) = startCollector(watcher)

            let start = ContinuousClock.now
            var index = 0
            while ContinuousClock.now - start < .seconds(3) {
                try Data("x".utf8).write(to: a.appendingPathComponent("f\(index).jpg"))
                index += 1
                try await Task.sleep(for: .milliseconds(100))
            }

            let instants = await recorder.instants(containing: a)
            #expect(instants.count >= 2, "subtrees=\(useSubtrees) count: \(instants.count)")
            if let first = instants.first {
                #expect(first - start < .milliseconds(1500), "subtrees=\(useSubtrees) first event: \(first - start)")
            }
            collector.cancel()
            await collector.value
        }
    }

    @Test("subtrees notifications preserve the supplied root URL representation without adding or removing /private")
    func subtreeKeepsGivenPathForm() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(root.path.hasPrefix("/var/"), "Temporary directory is not under /var: \(root.path)")
        let ab = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: ab, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(200))

        let watcher = FileSystemWatcher()
        watcher.watch([], subtrees: [root])
        let (recorder, collector) = startCollector(watcher)
        defer { collector.cancel() }

        try Data("x".utf8).write(to: ab.appendingPathComponent("x.jpg"))
        let observed5 = await recorder.waitForPath(root.appendingPathComponent("a/b").path)
        let seen5 = await recorder.snapshot()
        #expect(observed5, "Create: \(describe(seen5))")

        try FileManager.default.removeItem(at: ab)
        let observed6 = await recorder.waitForPath(root.appendingPathComponent("a").path)
        let seen6 = await recorder.snapshot()
        #expect(observed6, "Folder deletion: \(describe(seen6))")
        await stopCollector(collector)

        let privateRoot = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        let privateWatcher = FileSystemWatcher()
        privateWatcher.watch([], subtrees: [privateRoot])
        let (privateRecorder, privateCollector) = startCollector(privateWatcher)
        defer { privateCollector.cancel() }

        try Data("y".utf8).write(to: root.appendingPathComponent("a/y.jpg"))
        let observed7 = await privateRecorder.waitForPath(privateRoot.appendingPathComponent("a").path)
        let seen7 = await privateRecorder.snapshot()
        #expect(observed7, "/private form: \(describe(seen7))")
        await stopCollector(privateCollector)
    }

    // MARK: - Descriptor Usage (bug: fsevents-watchroot-fd-exhaustion)

    /// Number of file descriptors open in the process.
    private func openDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }

    @Test("Recreating many folder watches does not increase open descriptors in proportion to watch count")
    func watchingManyFoldersDoesNotExhaustDescriptors() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = try (0..<100).map { index -> URL in
            let folder = root.appendingPathComponent("f\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        let watcher = FileSystemWatcher()
        let before = openDescriptorCount()
        // Rebuild while changing the set, as when the tree is rebuilt on every selection or expansion.
        for round in 0..<4 {
            watcher.watch(Set(folders.dropLast(round)), subtrees: [])
        }
        let increase = openDescriptorCount() - before
        watcher.watch([], subtrees: [])

        // The GUI app limit is 256. WatchRoot would exceed 1,000 with 100 folders. Allow headroom for descriptors
        // opened by other tests.
        #expect(increase < 100, "Descriptors opened by watching 100 folders: +\(increase)")
    }

    @Test("Adding subtrees (WatchRoot) increases descriptors only by the number of roots")
    func subtreeWatchRootCostsOnlyForTheRoot() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let folders = try (0..<100).map { index -> URL in
            let folder = root.appendingPathComponent("f\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        let watcher = FileSystemWatcher()
        let before = openDescriptorCount()
        watcher.watch(Set(folders), subtrees: [root])
        // Changing only folders does not rebuild the subtrees stream.
        watcher.watch(Set(folders.dropLast()), subtrees: [root])
        let increase = openDescriptorCount() - before
        watcher.watch([], subtrees: [])

        #expect(increase < 150, "Descriptors opened by watching 100 folders and one root: +\(increase)")
    }

    @Test("Deleting or moving the root or its parent emits the root URL; folders-only watches do not emit the root itself")
    func subtreeReportsRootChanges() async throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let fileManager = FileManager.default

        func watchRoot(_ root: URL) -> (FileSystemWatcher, EventRecorder, Task<Void, Never>) {
            let watcher = FileSystemWatcher()
            watcher.watch([], subtrees: [root])
            let (recorder, collector) = startCollector(watcher)
            return (watcher, recorder, collector)
        }

        // Deletion
        let removed = base.appendingPathComponent("removed", isDirectory: true)
        try fileManager.createDirectory(at: removed.appendingPathComponent("a"), withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(200))
        let (w1, r1, c1) = watchRoot(removed)
        try fileManager.removeItem(at: removed)
        let observed8 = await r1.waitForPath(removed.path)
        let seen8 = await r1.snapshot()
        #expect(observed8, "Delete: \(describe(seen8))")
        await stopCollector(c1)
        _ = w1

        // Rename
        let renamed = base.appendingPathComponent("renamed", isDirectory: true)
        try fileManager.createDirectory(at: renamed, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(200))
        let (w2, r2, c2) = watchRoot(renamed)
        try fileManager.moveItem(at: renamed, to: base.appendingPathComponent("renamed-2", isDirectory: true))
        let observed9 = await r2.waitForPath(renamed.path)
        let seen9 = await r2.snapshot()
        #expect(observed9, "Move: \(describe(seen9))")
        await stopCollector(c2)
        _ = w2

        // Parent folder rename
        let parent = base.appendingPathComponent("parent", isDirectory: true)
        let child = parent.appendingPathComponent("child", isDirectory: true)
        try fileManager.createDirectory(at: child, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(200))
        let (w3, r3, c3) = watchRoot(child)
        try fileManager.moveItem(at: parent, to: base.appendingPathComponent("parent-2", isDirectory: true))
        let observed10 = await r3.waitForPath(child.path)
        let seen10 = await r3.snapshot()
        #expect(observed10, "Parent move: \(describe(seen10))")
        await stopCollector(c3)
        _ = w3

        // With folders only, do not emit deletion of the folder itself.
        let plain = base.appendingPathComponent("plain", isDirectory: true)
        let plainA = plain.appendingPathComponent("a", isDirectory: true)
        try fileManager.createDirectory(at: plainA, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(200))
        let folderWatcher = FileSystemWatcher()
        folderWatcher.watch([plainA])
        let (r4, c4) = startCollector(folderWatcher)
        try fileManager.removeItem(at: plainA)
        try await Task.sleep(for: .milliseconds(1500))
        let events = await r4.snapshot()
        #expect(!events.contains { containsFolder($0, plainA) }, "folders: \(describe(events))")
        await stopCollector(c4)
    }

    // MARK: - Helpers

    private func makeTemporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileSystemWatcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func startCollector(_ watcher: FileSystemWatcher) -> (EventRecorder, Task<Void, Never>) {
        let recorder = EventRecorder()
        let collector = Task {
            for await event in watcher.events {
                await recorder.record(event)
            }
        }
        return (recorder, collector)
    }

    private func stopCollector(_ collector: Task<Void, Never>) async {
        collector.cancel()
        await collector.value
    }

    private func containsFolder(_ event: Set<URL>, _ folder: URL) -> Bool {
        event.contains { $0.standardizedFileURL == folder.standardizedFileURL }
    }

    private func describe(_ events: [Set<URL>]) -> String {
        guard !events.isEmpty else { return "[]" }
        return events
            .map { describe($0) }
            .joined(separator: " | ")
    }

    private func describe(_ event: Set<URL>) -> String {
        "[" + event.map(\.path).sorted().joined(separator: ", ") + "]"
    }

    private func describe(_ preview: PreviewContent) -> String {
        switch preview {
        case .empty:
            return ".empty"
        case let .loading(url):
            return ".loading(\(url.lastPathComponent))"
        case let .image(image):
            return ".image(\(Int(image.pixelSize.width))x\(Int(image.pixelSize.height)))"
        case let .animatedImage(url):
            return ".animatedImage(\(url.lastPathComponent))"
        case let .animatedImageData(url, data):
            return ".animatedImageData(\(url.lastPathComponent), \(data.count) bytes)"
        case let .video(url):
            return ".video(\(url.lastPathComponent))"
        case let .unavailable(name, reason):
            return ".unavailable(\(name), \(reason))"
        }
    }

    @MainActor
    private func waitUntil(timeout: Duration, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private actor EventRecorder {
    private var events: [Set<URL>] = []
    private var times: [ContinuousClock.Instant] = []

    func record(_ event: Set<URL>) {
        events.append(event)
        times.append(.now)
    }

    func snapshot() -> [Set<URL>] {
        events
    }

    /// Times at which events containing `folder` arrived.
    func instants(containing folder: URL) -> [ContinuousClock.Instant] {
        let target = folder.standardizedFileURL
        return zip(events, times).filter { event, _ in
            event.contains { $0.standardizedFileURL == target }
        }.map(\.1)
    }

    /// Waits until an event at or after `after` contains `folder`.
    func waitForFolder(_ folder: URL, after index: Int = 0, timeout: Duration = .seconds(3)) async -> Bool {
        let target = folder.standardizedFileURL
        return await waitFor(after: index, timeout: timeout) { $0.standardizedFileURL == target }
    }

    /// Waits until a URL whose path string equals `path` is emitted (also compares the path form).
    func waitForPath(_ path: String, timeout: Duration = .seconds(3)) async -> Bool {
        await waitFor(after: 0, timeout: timeout) { $0.path == path }
    }

    private func waitFor(after index: Int, timeout: Duration, _ matches: (URL) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        repeat {
            if events.dropFirst(index).contains(where: { $0.contains(where: matches) }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(20))
        } while ContinuousClock.now < deadline
        return false
    }

    func waitForEvent(
        after index: Int,
        timeout: Duration = .seconds(2)
    ) async -> (event: Set<URL>?, observed: [Set<URL>]) {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if events.count > index {
                return (events[index], events)
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return (events.count > index ? events[index] : nil, events)
    }
}
