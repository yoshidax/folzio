import CoreGraphics
import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

/// Verifies the limit on concurrent image loads and the cancellation of unneeded prefetches (FR-282 to FR-286).
@Suite("BrowserModel image loading")
@MainActor
struct BrowserModelImageLoadTests {
    // MARK: - Folder images

    @Test("40 consecutive selections never hold more than two load slots and end on the last image")
    func consecutiveSelectionsRespectTheLimit() async {
        let folder = makeFolderURL()
        let files = (0..<45).map { file("img\($0).jpg", in: folder) }
        let gate = DecodeGate()
        let scheduler = ImageLoadScheduler()
        let env = makeModel(folders: [folder: files], gate: gate, scheduler: scheduler)
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(folder)
        // The first preview and the first prefetch start and hold both slots (US57-AS1).
        model.select([files[0].url], focused: files[0].url)
        #expect(await eventually { await gate.blockedCount == 2 })

        for index in 1..<40 {
            model.select([files[index].url], focused: files[index].url)
            await Task.yield()
        }
        #expect(await gate.blockedCount == 2)
        #expect(await scheduler.runningCount == 2)

        await gate.releaseAll()
        // Only the last image is shown, never an image passed on the way (FR-286, US57-AS2).
        #expect(await eventually { self.previewWidth(of: model) == 40 })
        #expect(await eventually { await self.isIdle(scheduler) })

        // Nothing but the first two loads and the neighbors of the last selection started (SC-146, US57-AS3, AS4).
        let started = Set(await gate.started)
        #expect(started.isSubset(of: ["img0.jpg", "img1.jpg", "img38.jpg", "img39.jpg", "img40.jpg"]))
        #expect(started.contains("img39.jpg"))
        #expect(await scheduler.peakRunning <= ImageLoadScheduler.defaultLimit)
        #expect(await gate.maxRunning <= ImageLoadScheduler.defaultLimit)
    }

    @Test("Selecting an image that is being prefetched reuses the prefetch instead of decoding it again")
    func previewReusesRunningPrefetch() async {
        let folder = makeFolderURL()
        let files = (0..<6).map { file("img\($0).jpg", in: folder) }
        let gate = DecodeGate()
        let env = makeModel(folders: [folder: files], gate: gate, scheduler: ImageLoadScheduler())
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(folder)
        model.select([files[1].url], focused: files[1].url)
        #expect(await eventually { await gate.blockedCount == 2 })
        #expect(await gate.hasStarted("img2.jpg"))

        model.select([files[2].url], focused: files[2].url)
        await gate.releaseAll()

        #expect(await eventually { self.previewWidth(of: model) == 3 })
        #expect(await gate.startCount("img2.jpg") == 1)
    }

    @Test("A preview starts without waiting for a running prefetch, and only one prefetch runs at a time")
    func previewIsNotBlockedByPrefetch() async {
        let folder = makeFolderURL()
        let files = (0..<10).map { file("img\($0).jpg", in: folder) }
        let gate = DecodeGate()
        let scheduler = ImageLoadScheduler()
        let env = makeModel(folders: [folder: files], gate: gate, scheduler: scheduler)
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(folder)
        model.select([files[4].url], focused: files[4].url)
        #expect(await eventually { await gate.blockedCount == 2 })
        await gate.release("img4.jpg")
        #expect(await eventually { self.previewWidth(of: model) == 5 })

        // The prefetch of img5 still runs. A far image gets the free slot at once (US59-AS2, FR-284).
        model.select([files[8].url], focused: files[8].url)
        #expect(await eventually { await gate.hasStarted("img8.jpg") })
        // The next prefetch waits for the running one.
        #expect(!(await gate.hasStarted("img9.jpg")))
        #expect(await scheduler.runningCount == 2)

        await gate.releaseAll()
        #expect(await eventually { self.previewWidth(of: model) == 9 })
        #expect(await scheduler.peakRunning <= ImageLoadScheduler.defaultLimit)
    }

    @Test("A failed load returns its slot so that the next image is shown")
    func failedLoadReturnsSlot() async {
        let folder = makeFolderURL()
        let files = (0..<4).map { file("img\($0).jpg", in: folder) }
        let gate = DecodeGate()
        await gate.releaseAll()
        let scheduler = ImageLoadScheduler()
        let env = makeModel(
            folders: [folder: files],
            gate: gate,
            scheduler: scheduler,
            failingNames: ["img1.jpg"]
        )
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(folder)
        model.select([files[1].url], focused: files[1].url)
        #expect(await eventually {
            if case .unavailable = model.preview { return true }
            return false
        })

        model.select([files[2].url], focused: files[2].url)
        #expect(await eventually { self.previewWidth(of: model) == 3 })
        #expect(await eventually { await self.isIdle(scheduler) })
    }

    @Test("Leaving the folder cancels the prefetches that have not started")
    func navigationCancelsWaitingPrefetches() async {
        let first = makeFolderURL()
        let second = makeFolderURL()
        let firstFiles = (0..<6).map { file("img\($0).jpg", in: first) }
        let secondFiles = (20..<22).map { file("img\($0).jpg", in: second) }
        let gate = DecodeGate()
        let scheduler = ImageLoadScheduler()
        let env = makeModel(folders: [first: firstFiles, second: secondFiles], gate: gate, scheduler: scheduler)
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(first)
        model.select([firstFiles[2].url], focused: firstFiles[2].url)
        #expect(await eventually { await gate.blockedCount == 2 })

        // img1 waits for a slot as the previous neighbor. It never starts after the folder changes (EC-199).
        await model.selectFolder(second)
        await gate.releaseAll()
        #expect(await eventually { await self.isIdle(scheduler) })
        #expect(!(await gate.hasStarted("img1.jpg")))

        model.select([secondFiles[0].url], focused: secondFiles[0].url)
        #expect(await eventually { self.previewWidth(of: model) == 21 })
    }

    @Test("Videos are not prefetched and do not use a load slot")
    func videosAreNotPrefetched() async {
        let folder = makeFolderURL()
        // The list is sorted by name, so both neighbors of img0.jpg are videos.
        let files = [file("clip.mp4", in: folder), file("img0.jpg", in: folder), file("zzz.mp4", in: folder)]
        let gate = DecodeGate()
        await gate.releaseAll()
        let scheduler = ImageLoadScheduler()
        let env = makeModel(folders: [folder: files], gate: gate, scheduler: scheduler)
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(folder)
        #expect(model.listing.files.map(\.name) == ["clip.mp4", "img0.jpg", "zzz.mp4"])
        model.select([files[1].url], focused: files[1].url)
        #expect(await eventually { self.previewWidth(of: model) == 1 })
        #expect(await eventually { await scheduler.runningCount == 0 })

        #expect(await gate.started == ["img0.jpg"])
    }

    @Test("A prefetched neighbor is shown from the cache without using a load slot")
    func prefetchedNeighborUsesNoSlot() async {
        let folder = makeFolderURL()
        let files = (0..<5).map { file("img\($0).jpg", in: folder) }
        let gate = DecodeGate()
        await gate.releaseAll()
        let scheduler = ImageLoadScheduler()
        let env = makeModel(folders: [folder: files], gate: gate, scheduler: scheduler)
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(folder)
        model.select([files[1].url], focused: files[1].url)
        #expect(await eventually { await env.cache.containsEntry(for: files[2].url) })
        #expect(await eventually { await self.isIdle(scheduler) })

        model.select([files[2].url], focused: files[2].url)
        #expect(await eventually { self.previewWidth(of: model) == 3 })
        // The image was served from the cache: its own decode did not start again (EC-197, US59-AS1).
        #expect(await gate.startCount("img2.jpg") == 1)
    }

    // MARK: - Images inside a zip

    @Test("40 consecutive selections inside a zip never hold more than two load slots")
    func consecutiveArchiveSelectionsRespectTheLimit() async throws {
        let env = try makeArchiveEnvironment(entryCount: 45)
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(env.root)
        await model.openItem(env.zip)
        model.select([env.entry(0)], focused: env.entry(0))
        #expect(await eventually { await env.gate.blockedCount == 2 })

        for index in 1..<40 {
            model.select([env.entry(index)], focused: env.entry(index))
            await Task.yield()
        }
        #expect(await env.scheduler.runningCount == 2)

        await env.gate.releaseAll()
        #expect(await eventually {
            if case .image = model.preview { return true }
            return false
        })
        #expect(await eventually { await self.isIdle(env.scheduler) })
        #expect(await env.scheduler.peakRunning <= ImageLoadScheduler.defaultLimit)
        #expect(await env.gate.maxRunning <= ImageLoadScheduler.defaultLimit)
        // The first two loads and the neighbors of the last selection: at most five decodes (SC-146).
        #expect(await env.gate.started.count <= 5)
    }

    @Test("Leaving a zip cancels the prefetches that have not started")
    func leavingArchiveCancelsWaitingPrefetches() async throws {
        let env = try makeArchiveEnvironment(entryCount: 12)
        defer { env.cleanup() }
        let model = env.model

        await model.selectFolder(env.root)
        await model.openItem(env.zip)
        model.select([env.entry(5)], focused: env.entry(5))
        #expect(await eventually { await env.gate.blockedCount == 2 })

        await model.openItem(ArchiveURL.parentLink(of: ArchiveLocation(archive: env.zip, directory: "")))
        await env.gate.releaseAll()
        #expect(await eventually { await self.isIdle(env.scheduler) })

        // Only the preview and the running prefetch decoded; the waiting prefetch was cancelled (US58-AS2).
        #expect(await env.gate.started.count == 2)
    }

    // MARK: - Helpers

    private struct ModelEnvironment {
        let model: BrowserModel
        let cache: DecodedImageCache
        let defaults: UserDefaults
        let suite: String

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private struct ArchiveEnvironment {
        let model: BrowserModel
        let gate: DecodeGate
        let scheduler: ImageLoadScheduler
        let root: URL
        let zip: URL
        let defaults: UserDefaults
        let suite: String

        func entry(_ index: Int) -> URL {
            ArchiveURL.entry(archive: zip, path: Self.entryName(index))
        }

        static func entryName(_ index: Int) -> String {
            String(format: "e%02d.jpg", index)
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFolderURL() -> URL {
        URL(fileURLWithPath: "/tmp/imageload-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeModel(
        folders: [URL: [MediaFile]],
        gate: DecodeGate,
        scheduler: ImageLoadScheduler,
        failingNames: Set<String> = []
    ) -> ModelEnvironment {
        let suite = "BrowserModelImageLoadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let cache = DecodedImageCache(costLimitBytes: 50_000_000)
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: StubLister(responses: folders),
            decoder: GatedDecoder(gate: gate, failingNames: failingNames),
            cache: cache,
            settings: SettingsStore(defaults: defaults),
            loadScheduler: scheduler
        )
        return ModelEnvironment(model: model, cache: cache, defaults: defaults, suite: suite)
    }

    private func makeArchiveEnvironment(entryCount: Int) throws -> ArchiveEnvironment {
        var root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelImageLoadTests-\(UUID().uuidString)", isDirectory: true)
        if root.path.hasPrefix("/var/") {
            root = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let jpegURL = root.appendingPathComponent("source.jpg")
        try ImageFixtures.jpeg(at: jpegURL, width: 8, height: 8)
        let jpeg = try Data(contentsOf: jpegURL)
        try FileManager.default.removeItem(at: jpegURL)

        let zip = root.appendingPathComponent("photos.zip")
        let entries = (0..<entryCount).map {
            ZipFixtureEntry(name: ArchiveEnvironment.entryName($0), content: .bytes(jpeg))
        }
        try ZipFixtureWriter.write(entries, to: zip)

        let suite = "BrowserModelImageLoadTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "view.showsZipFiles")
        let gate = DecodeGate()
        let scheduler = ImageLoadScheduler()
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: GatedDecoder(gate: gate),
            cache: DecodedImageCache(costLimitBytes: 50_000_000),
            settings: SettingsStore(defaults: defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames),
            loadScheduler: scheduler
        )
        return ArchiveEnvironment(
            model: model,
            gate: gate,
            scheduler: scheduler,
            root: root,
            zip: zip,
            defaults: defaults,
            suite: suite
        )
    }

    private func file(_ name: String, in folder: URL) -> MediaFile {
        MediaFile(
            url: folder.appendingPathComponent(name),
            name: name,
            kind: .media(MediaKind(fileExtension: (name as NSString).pathExtension) ?? .jpeg),
            typeDescription: "JPEG",
            creationDate: nil,
            fileSize: 0,
            contentVersion: FileContentVersion(fileSize: 0, modificationDate: nil, fileIdentifier: 1)
        )
    }

    /// The pixel width of the previewed image, or nil when no still image is shown.
    private func previewWidth(of model: BrowserModel) -> Int? {
        if case let .image(image) = model.preview {
            return Int(image.pixelSize.width)
        }
        return nil
    }

    private func isIdle(_ scheduler: ImageLoadScheduler) async -> Bool {
        let running = await scheduler.runningCount
        let waiting = await scheduler.waitingCount
        return running == 0 && waiting == 0
    }

    /// Polls until `condition` holds or five seconds pass.
    private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }
}

/// Holds decodes until the test releases them, and records which decodes started and how many wait at once.
private actor DecodeGate {
    private var releasedNames: Set<String> = []
    private var allReleased = false
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private(set) var running = 0
    private(set) var maxRunning = 0
    private(set) var started: [String] = []

    var blockedCount: Int {
        waiters.values.reduce(0) { $0 + $1.count }
    }

    func hasStarted(_ name: String) -> Bool {
        started.contains(name)
    }

    func startCount(_ name: String) -> Int {
        started.filter { $0 == name }.count
    }

    func enter(_ name: String) async {
        started.append(name)
        if allReleased || releasedNames.contains(name) { return }
        running += 1
        maxRunning = max(maxRunning, running)
        await withCheckedContinuation { continuation in
            waiters[name, default: []].append(continuation)
        }
    }

    func release(_ name: String) {
        releasedNames.insert(name)
        let blocked = waiters.removeValue(forKey: name) ?? []
        running -= blocked.count
        for continuation in blocked {
            continuation.resume()
        }
    }

    func releaseAll() {
        allReleased = true
        let blocked = waiters.values.flatMap { $0 }
        waiters.removeAll()
        running -= blocked.count
        for continuation in blocked {
            continuation.resume()
        }
    }
}

/// A decoder that waits at the gate. It ignores cancellation, like a decode of ImageIO that already started.
/// The width of the returned image is the number in the file name plus one, so a test tells which image is shown.
private struct GatedDecoder: ImageDecoding {
    let gate: DecodeGate
    var failingNames: Set<String> = []

    func decode(_ url: URL, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        let name = url.lastPathComponent
        await gate.enter(name)
        if failingNames.contains(name) {
            throw DecodeError.corrupted
        }
        let digits = name.filter(\.isNumber)
        return Self.makeImage(width: (Int(digits) ?? 0) + 1)
    }

    func isAnimated(_ url: URL) -> Bool { false }

    func decode(data: Data, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        await gate.enter("zip-entry")
        return Self.makeImage(width: 3)
    }

    func isAnimated(data: Data) -> Bool { false }

    private static func makeImage(width: Int) -> DecodedImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return DecodedImage(
            cgImage: context.makeImage()!,
            pixelSize: CGSize(width: width, height: 2),
            originalPixelSize: CGSize(width: width, height: 2),
            byteCost: width * 8
        )
    }
}

private actor StubLister: DirectoryListing {
    private let responses: [URL: [MediaFile]]

    init(responses: [URL: [MediaFile]]) {
        self.responses = responses
    }

    func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] {
        guard let files = responses[folder] else {
            throw ListingError.notFound
        }
        return files
    }

    func subfolders(of folder: URL) async throws(ListingError) -> [URL] {
        []
    }
}
