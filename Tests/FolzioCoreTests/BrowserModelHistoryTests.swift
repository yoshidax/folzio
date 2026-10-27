import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("BrowserModel location notifications")
@MainActor
struct BrowserModelHistoryTests {
    @MainActor
    private struct Env {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let model: BrowserModel
        let recorder: Recorder

        func url(_ path: String) -> URL {
            root.appendingPathComponent(path, isDirectory: true)
        }

        var events: [LocationEvent] { recorder.events }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    @MainActor
    private final class Recorder {
        var events: [LocationEvent] = []
    }

    private func makeEnv() throws -> Env {
        var root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelHistoryTests-\(UUID().uuidString)", isDirectory: true)
        if root.path.hasPrefix("/var/") {
            root = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        }
        let fileManager = FileManager.default
        for path in ["A", "A/Sub", "B", "C"] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try ImageFixtures.jpeg(at: root.appendingPathComponent("A/cover.jpg"), width: 16, height: 12)
        try ImageFixtures.jpeg(at: root.appendingPathComponent("A/Sub/inner.jpg"), width: 16, height: 12)
        try ImageFixtures.jpeg(at: root.appendingPathComponent("B/photo.jpg"), width: 16, height: 12)

        let work = fileManager.temporaryDirectory
            .appendingPathComponent("BrowserModelHistoryTests-work-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        let jpeg = work.appendingPathComponent("photo.jpg")
        try ImageFixtures.jpeg(at: jpeg, width: 16, height: 12)
        try ZipFixtureWriter.write(
            [ZipFixtureEntry(name: "sub/photo.jpg", content: .bytes(try Data(contentsOf: jpeg)))],
            to: root.appendingPathComponent("A/album.zip")
        )

        let suite = "BrowserModelHistoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "view.showsZipFiles")
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 50_000_000),
            settings: SettingsStore(defaults: defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames)
        )
        model.setNavigationRoots([root])
        let recorder = Recorder()
        model.onLocationEvent = { event in
            recorder.events.append(event)
        }
        return Env(root: root, defaults: defaults, suite: suite, model: model, recorder: recorder)
    }

    private func path(_ url: URL?) -> String? {
        url?.standardizedFileURL.path
    }

    private func lastNavigated(_ env: Env) -> URL? {
        for event in env.events.reversed() {
            if case let .navigated(leavingFocus) = event {
                return leavingFocus
            }
        }
        return nil
    }

    @Test("selectFolder emits navigated once before loading and passes the previously focused row")
    func selectFolderEmitsNavigated() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        #expect(env.events.count == 1)
        #expect(lastNavigated(env) == nil)

        let cover = try #require(env.model.listing.files.first { $0.name == "cover.jpg" })
        env.model.select([cover.url], focused: cover.url)
        env.recorder.events.removeAll()

        await env.model.selectFolder(env.url("B"))
        #expect(env.events.count == 1)
        #expect(lastNavigated(env) == cover.url)
        #expect(path(env.model.listing.folder) == path(env.url("B")))
    }

    @Test("Opening a folder emits navigated exactly once with the opened folder as its location")
    func openingFolderEmitsOnce() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        env.recorder.events.removeAll()

        await env.model.openItem(env.url("A/Sub"))
        #expect(env.events.filter { if case .navigated = $0 { true } else { false } }.count == 1)
        #expect(path(env.model.historyLocation?.folder) == path(env.url("A/Sub")))
    }

    @Test("Opening a zip, navigating inside it, and going up each emit navigated")
    func archiveNavigationEmitsNavigated() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        let zip = try #require(env.model.listing.files.first { $0.name == "album.zip" })
        env.recorder.events.removeAll()

        await env.model.openItem(zip.url)
        #expect(env.events.count == 1)
        #expect(env.model.historyLocation?.archive?.archive == zip.url)
        #expect(env.model.historyLocation?.archive?.directory == "")

        let sub = try #require(env.model.listing.files.first { $0.name == "sub" })
        await env.model.openItem(sub.url)
        #expect(env.events.count == 2)
        #expect(env.model.historyLocation?.archive?.directory == "sub/")

        await env.model.goToEnclosingLevel()
        #expect(env.events.count == 3)
        #expect(env.model.historyLocation?.archive?.directory == "")

        await env.model.goToEnclosingLevel()
        #expect(env.events.count == 4)
        #expect(env.model.listing.archive == nil)
        #expect(path(env.model.historyLocation?.folder) == path(env.url("A")))
    }

    @Test("Going up in a regular folder emits navigated and selects the folder just left")
    func goingUpEmitsNavigated() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A/Sub"))
        env.recorder.events.removeAll()

        await env.model.goToEnclosingLevel()
        #expect(env.events.count == 1)
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(env.model.selection.focused?.lastPathComponent == "Sub")
    }

    @Test("External deletion of the current folder navigates to its parent and emits relocated")
    func deletedFolderRelocates() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A/Sub"))
        env.recorder.events.removeAll()
        try FileManager.default.removeItem(at: env.url("A/Sub"))

        await env.model.handleFileSystemEvent([env.url("A/Sub")])
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(env.events == [.relocated(vanished: [env.url("A/Sub")])])
    }

    @Test("External deletion of the open zip returns to its containing folder and emits relocated")
    func deletedArchiveRelocates() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        let zip = try #require(env.model.listing.files.first { $0.name == "album.zip" })
        await env.model.openItem(zip.url)
        env.recorder.events.removeAll()
        try FileManager.default.removeItem(at: zip.url)

        await env.model.handleFileSystemEvent([env.url("A")])
        #expect(env.model.listing.archive == nil)
        #expect(path(env.model.listing.folder) == path(env.url("A")))
        #expect(env.events == [.relocated(vanished: [zip.url])])
    }

    @Test("A folder missing on reload emits notFound and sets historyLocation to nil")
    func reloadNotFoundEmits() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        env.recorder.events.removeAll()
        try FileManager.default.removeItem(at: env.url("A"))

        await env.model.reloadCurrentFolder()
        #expect(env.events == [.notFound(HistoryLocation(folder: env.url("A")))])
        #expect(env.model.historyLocation == nil)
    }

    @Test("The renamed folder view follows the new location without emitting a notification")
    func renamedFolderFollows() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        env.recorder.events.removeAll()
        let newURL = env.url("A2")
        try FileManager.default.moveItem(at: env.url("A"), to: newURL)

        env.model.didRenameFolder(from: env.url("A"), to: newURL)
        #expect(env.events.isEmpty)
        #expect(path(env.model.listing.folder) == path(newURL))
        #expect(path(env.model.historyLocation?.folder) == path(newURL))
    }

    private func resolved(_ resolution: HistoryLocationResolution) -> ResolvedHistoryLocation? {
        if case let .available(resolved) = resolution { return resolved }
        return nil
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func waitForListing(_ model: BrowserModel) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while model.listing.state == .loading, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("resolveHistoryLocation checks regular folder existence and show displays it without notifications")
    func resolveAndShowNormalFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        let bLocation = HistoryLocation(folder: env.url("B"))
        let resolvedB = try #require(resolved(await env.model.resolveHistoryLocation(bLocation)))
        #expect(resolvedB.location == bLocation)

        env.recorder.events.removeAll()
        let photo = env.root.appendingPathComponent("B/photo.jpg")
        env.model.showHistoryLocation(resolvedB, focusing: photo)
        await waitForListing(env.model)
        let focused = await waitUntil { env.model.selection.focused == photo }
        #expect(env.events.isEmpty)
        #expect(path(env.model.listing.folder) == path(env.url("B")))
        #expect(focused)

        let resolvedAgain = try #require(resolved(await env.model.resolveHistoryLocation(bLocation)))
        env.model.showHistoryLocation(resolvedAgain, focusing: env.url("B/missing.jpg"))
        await waitForListing(env.model)
        let cleared = await waitUntil { env.model.selection.focused == nil }
        #expect(cleared)
        #expect(isEmptyPreview(env.model.preview))

        if case .missing = await env.model.resolveHistoryLocation(HistoryLocation(folder: env.url("Missing"))) {
            // Expected.
        } else {
            Issue.record("A missing folder did not resolve to missing")
        }
    }

    private func isEmptyPreview(_ preview: PreviewContent) -> Bool {
        if case .empty = preview { return true }
        return false
    }

    @Test("Resolves and displays locations inside a zip and reports absent directories as missing (EC-64)")
    func resolveAndShowArchiveFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        let zip = try #require(env.model.listing.files.first { $0.name == "album.zip" })
        let top = HistoryLocation(
            folder: env.url("A"),
            archive: ArchiveLocation(archive: zip.url, directory: "")
        )
        let sub = HistoryLocation(
            folder: env.url("A"),
            archive: ArchiveLocation(archive: zip.url, directory: "sub/")
        )
        let missing = HistoryLocation(
            folder: env.url("A"),
            archive: ArchiveLocation(archive: zip.url, directory: "nothing/")
        )

        let resolvedTop = try #require(resolved(await env.model.resolveHistoryLocation(top)))
        env.recorder.events.removeAll()
        env.model.showHistoryLocation(resolvedTop, focusing: nil)
        #expect(env.events.isEmpty)
        #expect(env.model.listing.archive?.directory == "")

        let resolvedSub = try #require(resolved(await env.model.resolveHistoryLocation(sub)))
        env.model.showHistoryLocation(resolvedSub, focusing: nil)
        #expect(env.events.isEmpty)
        #expect(env.model.listing.archive?.directory == "sub/")
        let photo = try #require(env.model.listing.files.first { $0.name == "photo.jpg" })
        let resolvedFocused = try #require(resolved(await env.model.resolveHistoryLocation(sub)))
        env.model.showHistoryLocation(resolvedFocused, focusing: photo.url)
        #expect(env.model.selection.focused == photo.url)

        if case .missing = await env.model.resolveHistoryLocation(missing) {
            // Expected.
        } else {
            Issue.record("A directory not in the zip did not resolve to missing")
        }
    }

    @Test("A damaged zip is not skipped and show displays an error (EC-56, EC-64)")
    func showBrokenArchive() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        let brokenURL = env.url("A").appendingPathComponent("broken.zip")
        try Data("not a zip".utf8).write(to: brokenURL)
        await env.model.selectFolder(env.url("A"))
        let broken = HistoryLocation(
            folder: env.url("A"),
            archive: ArchiveLocation(archive: brokenURL, directory: "")
        )
        let resolvedBroken = try #require(resolved(await env.model.resolveHistoryLocation(broken)))

        env.recorder.events.removeAll()
        env.model.showHistoryLocation(resolvedBroken, focusing: nil)
        #expect(env.events.isEmpty)
        #expect(env.model.listing.archive?.archive == brokenURL)
        if case let .failed(message) = env.model.listing.state {
            #expect(message == .archive(.notAZip))
        } else {
            Issue.record("A corrupted zip did not become .failed: \(env.model.listing.state)")
        }
    }

    @Test("historyLocation is nil in search results; selecting a folder ends the search and emits navigated")
    func searchEndsOnFolderSelection() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("A"))
        let pattern = try #require(SearchPattern(keyword: "photo"))
        env.model.startSearch(pattern, root: env.root)
        #expect(env.model.isShowingSearchResults)
        #expect(env.model.historyLocation == nil)

        env.recorder.events.removeAll()
        await env.model.selectFolder(env.url("B"))
        #expect(env.model.isShowingSearchResults == false)
        #expect(env.events.count == 1)
        #expect(path(env.model.listing.folder) == path(env.url("B")))
    }
}
