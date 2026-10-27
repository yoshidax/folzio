import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("BrowserModel folder browsing")
@MainActor
struct BrowserModelFolderTests {
    // MARK: - Fixtures

    /// Temporary folder `root`. Contains `cover.jpg`, `trip/day1/1.jpg`, `trip/day2/`, `empty/`, and `only/inner/`.
    private struct Env {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let model: BrowserModel

        func url(_ path: String) -> URL {
            root.appendingPathComponent(path, isDirectory: true)
        }

        /// Row in the listing whose path is `path`.
        @MainActor
        func row(_ path: String) -> MediaFile? {
            let target = url(path).standardizedFileURL.path
            return model.listing.files.first { $0.url.standardizedFileURL.path == target }
        }

        /// Last saved folder (FR-003).
        var lastFolder: URL? {
            SettingsStore(defaults: defaults).viewSettings.lastFolder
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// `DirectoryLister` returns `/private/var/...` URLs, so create the temporary folder with the same form.
    private func makeEnv(roots: [String] = [""]) throws -> Env {
        var root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelFolderTests-\(UUID().uuidString)", isDirectory: true)
        if root.path.hasPrefix("/var/") {
            root = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        }
        let fileManager = FileManager.default
        for path in ["trip/day1", "trip/day2", "empty", "only/inner"] {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try ImageFixtures.jpeg(at: root.appendingPathComponent("cover.jpg"), width: 32, height: 24)
        try ImageFixtures.jpeg(at: root.appendingPathComponent("trip/day1/1.jpg"), width: 32, height: 24)

        let suite = "BrowserModelFolderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 50_000_000),
            settings: SettingsStore(defaults: defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames)
        )
        model.setNavigationRoots(roots.map { root.appendingPathComponent($0, isDirectory: true) })
        return Env(root: root, defaults: defaults, suite: suite, model: model)
    }

    private func path(_ url: URL?) -> String? {
        url?.standardizedFileURL.path
    }

    private func isEmptyPreview(_ preview: PreviewContent) -> Bool {
        if case .empty = preview { return true }
        return false
    }

    private func setPermissions(_ permissions: Int, of url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    // MARK: - Folder Rows and ..

    @Test("Changing kind names preserves the folder and selection and uses the new names in subsequent enumeration")
    func changingKindNamesPreservesSelectionAndUpdatesFutureListings() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        let trip = try #require(env.row("trip"))
        env.model.select([trip.url], focused: trip.url)
        env.model.setKindNames(KindNames(folder: "フォルダ", zipArchive: "ZIP アーカイブ"))
        env.model.setKindNames(FixtureKit.kindNames)
        env.model.setKindNames(KindNames(folder: "フォルダ", zipArchive: "ZIP アーカイブ"))
        #expect(await waitUntil { env.row("trip")?.typeDescription == "フォルダ" })
        #expect(env.model.selection.focused == trip.url)
        #expect(env.model.selection.selected == [trip.url])
        await env.model.selectFolder(env.url("trip"))
        #expect(env.row("trip/day1")?.typeDescription == "フォルダ")

        env.model.setKindNames(FixtureKit.kindNames)
        #expect(await waitUntil { env.row("trip/day1")?.typeDescription == FixtureKit.kindNames.folder })
    }

    @Test("A tree root lists folders and files by name without .. and ignores the go-up action")
    func rootHasNoParentRow() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)

        #expect(env.model.listing.files.map(\.name) == ["cover.jpg", "empty", "only", "trip"])
        #expect(env.row("trip")?.kind == .folder)
        #expect(!env.model.listing.files.contains { $0.kind == .parent })
        #expect(env.model.hasEnclosingLevel == false)

        await env.model.goToEnclosingLevel()
        #expect(path(env.model.listing.folder) == path(env.root))
        #expect(env.model.treeSyncRequest == nil)
    }

    @Test("Opening a folder row shows its listing with .. first and updates lastFolder and the synchronization request")
    func openingFolderNavigates() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        let trip = try #require(env.row("trip"))

        await env.model.openItem(trip.url)

        #expect(path(env.model.listing.folder) == path(env.url("trip")))
        let first = try #require(env.model.listing.files.first)
        #expect(first.kind == .parent)
        #expect(first.name == "..")
        #expect(ParentLink.isParentLink(first.url))
        #expect(env.model.listing.files.dropFirst().map(\.name) == ["day1", "day2"])
        #expect(env.model.selection.selected.isEmpty)
        #expect(isEmptyPreview(env.model.preview))
        #expect(path(env.lastFolder) == path(env.url("trip")))
        #expect(path(env.model.treeSyncRequest?.folder) == path(env.url("trip")))
        #expect(env.model.hasEnclosingLevel == true)
    }

    @Test("Both .. and goToEnclosingLevel return to the parent and select the folder just left")
    func goingUpSelectsPreviousFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(try #require(env.row("trip")).url)
        await env.model.openItem(try #require(env.row("trip/day1")).url)
        let idBeforeUp = try #require(env.model.treeSyncRequest?.id)

        await env.model.goToEnclosingLevel()

        #expect(path(env.model.listing.folder) == path(env.url("trip")))
        let day1 = try #require(env.row("trip/day1"))
        #expect(env.model.selection.selected == [day1.url])
        #expect(env.model.selection.focused == day1.url)
        #expect(path(env.model.treeSyncRequest?.folder) == path(env.url("trip")))
        #expect((env.model.treeSyncRequest?.id ?? 0) > idBeforeUp)
        #expect(path(env.lastFolder) == path(env.url("trip")))

        // Opening the `..` row gives the same result.
        await env.model.openItem(day1.url)
        let parent = try #require(env.model.listing.files.first { $0.kind == .parent })
        await env.model.openItem(parent.url)
        #expect(path(env.model.listing.folder) == path(env.url("trip")))
        #expect(env.model.selection.focused == env.row("trip/day1")?.url)

        // Going back again reaches the root, where trip is selected and there is no `..`.
        await env.model.goToEnclosingLevel()
        #expect(path(env.model.listing.folder) == path(env.root))
        #expect(env.model.selection.focused == env.row("trip")?.url)
        #expect(!env.model.listing.files.contains { $0.kind == .parent })
    }

    @Test("Selecting from the tree issues no synchronization request but shows .. outside the root")
    func selectFolderDoesNotRequestTreeSync() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("trip/day2"))

        #expect(env.model.treeSyncRequest == nil)
        #expect(env.model.hasEnclosingLevel == true)
        #expect(env.model.listing.files.map(\.kind) == [.parent])
    }

    @Test("An empty root has no ..; setNavigationRoots adds .. without reloading")
    func navigationRootsControlParentRow() async throws {
        let env = try makeEnv(roots: [])
        defer { env.cleanup() }
        await env.model.selectFolder(env.url("trip"))

        #expect(env.model.listing.files.map(\.name) == ["day1", "day2"])
        #expect(env.model.hasEnclosingLevel == false)

        env.model.setNavigationRoots([env.root])

        #expect(env.model.listing.files.map(\.name) == ["..", "day1", "day2"])
        #expect(env.model.hasEnclosingLevel == true)

        env.model.setNavigationRoots([env.url("trip")])
        #expect(env.model.listing.files.map(\.name) == ["day1", "day2"])
    }

    // MARK: - Empty Detection (FR-060) and Media Type Filter

    @Test("An empty folder is .empty with only ..; a folder containing only folders is .loaded")
    func emptyStates() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.url("empty"))
        #expect(env.model.listing.files.map(\.kind) == [.parent])
        #expect(env.model.listing.state == .empty)

        await env.model.selectFolder(env.url("only"))
        #expect(env.model.listing.files.map(\.name) == ["..", "inner"])
        #expect(env.model.listing.state == .loaded)
    }

    @Test("Media type filters preserve folders and keep levels originally without media .loaded")
    func filterKeepsFolders() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        env.model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))

        await env.model.selectFolder(env.url("trip"))
        #expect(env.model.listing.files.map(\.name) == ["..", "day1", "day2"])
        #expect(env.model.listing.state == .loaded)

        await env.model.selectFolder(env.url("trip/day1"))
        #expect(env.model.listing.files.map(\.kind) == [.parent])
        #expect(env.model.listing.state == .noMatches)
    }

    // MARK: - Unreadable Folders (FR-077)

    @Test("Entering a folder without permission leaves only .. and allows returning via ..")
    func deniedFolderKeepsParentRow() async throws {
        let env = try makeEnv()
        let locked = env.url("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try setPermissions(0o000, of: locked)
        defer {
            try? setPermissions(0o755, of: locked)
            env.cleanup()
        }
        await env.model.selectFolder(env.root)

        await env.model.openItem(try #require(env.row("locked")).url)

        #expect(env.model.listing.state == .denied)
        #expect(env.model.listing.files.map(\.kind) == [.parent])

        await env.model.openItem(try #require(env.model.listing.files.first).url)
        #expect(path(env.model.listing.folder) == path(env.root))
        #expect(env.model.selection.focused == env.row("locked")?.url)
    }

    @Test("Nonexistent folders and folders that become unreadable on reload also retain only ..")
    func failedFolderKeepsParentRow() async throws {
        let env = try makeEnv()
        let trip = env.url("trip")
        defer {
            try? setPermissions(0o755, of: trip)
            env.cleanup()
        }

        // standardizedFileURL removes leading /private only for existing paths, so create the missing folder
        // without it.
        let missing = env.root.standardizedFileURL.appendingPathComponent("missing", isDirectory: true)
        await env.model.selectFolder(missing)
        if case .failed = env.model.listing.state {} else {
            Issue.record("state should be failed, got \(env.model.listing.state)")
        }
        #expect(env.model.listing.files.map(\.kind) == [.parent])

        await env.model.selectFolder(trip)
        try setPermissions(0o000, of: trip)
        await env.model.reloadCurrentFolder()
        #expect(env.model.listing.state == .denied)
        #expect(env.model.listing.files.map(\.kind) == [.parent])
    }

    @Test("An unreadable root has no .. row")
    func deniedRootHasNoParentRow() async throws {
        let env = try makeEnv()
        defer {
            try? setPermissions(0o755, of: env.root)
            env.cleanup()
        }
        try setPermissions(0o000, of: env.root)

        await env.model.selectFolder(env.root)

        #expect(env.model.listing.state == .denied)
        #expect(env.model.listing.files.isEmpty)
    }

    // MARK: - Preview and Operation Targets

    @Test("Selecting a folder row clears the preview and stops any playing video")
    func selectingFolderClearsPreview() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let video = env.root.appendingPathComponent("clip.mp4")
        try Data().write(to: video)
        await env.model.selectFolder(env.root)

        let clip = try #require(env.model.listing.files.first { $0.name == "clip.mp4" })
        env.model.select([clip.url], focused: clip.url)
        guard case .video = env.model.preview else {
            Issue.record("preview should be video, got \(env.model.preview)")
            return
        }
        let before = env.model.stopPlaybackSignal

        let trip = try #require(env.row("trip"))
        env.model.select([trip.url], focused: trip.url)

        #expect(isEmptyPreview(env.model.preview))
        #expect(env.model.stopPlaybackSignal > before)
    }

    @Test("operableSelection follows listing order and excludes ..")
    func operableSelectionExcludesParent() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.url("trip"))
        let parent = try #require(env.model.listing.files.first { $0.kind == .parent })
        let day1 = try #require(env.row("trip/day1"))
        let day2 = try #require(env.row("trip/day2"))

        env.model.select([day2.url, parent.url, day1.url], focused: parent.url)
        #expect(env.model.operableSelection == [day1.url, day2.url])

        env.model.select([parent.url], focused: parent.url)
        #expect(env.model.operableSelection.isEmpty)
    }

    // MARK: - Paths That Do Not Emit Synchronization Requests

    @Test("Navigation inside a zip preserves the synchronization request and lastFolder")
    func archiveNavigationDoesNotRequestTreeSync() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let zip = env.root.appendingPathComponent("a.zip")
        try ZipFixtureWriter.write(
            [ZipFixtureEntry(name: "sub/x.png", content: .bytes(Data([0x89, 0x50])))],
            to: zip
        )
        env.model.setShowsZipFiles(true)
        await env.model.selectFolder(env.root)
        let lastFolder = env.lastFolder

        await env.model.openItem(try #require(env.model.listing.files.first { $0.name == "a.zip" }).url)
        #expect(env.model.isBrowsingArchive)
        await env.model.goToEnclosingLevel()

        #expect(env.model.treeSyncRequest == nil)
        #expect(path(env.lastFolder) == path(lastFolder))
    }

    @Test("Moving to the parent after the current folder is externally deleted issues no synchronization request")
    func fileSystemEventDoesNotRequestTreeSync() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.url("trip/day2"))
        try FileManager.default.removeItem(at: env.url("trip/day2"))

        await env.model.handleFileSystemEvent([env.model.listing.folder])

        #expect(path(env.model.listing.folder) == path(env.url("trip")))
        #expect(env.model.treeSyncRequest == nil)
    }

    // MARK: - Leaving Trashed Folders (FR-079)

    @Test("Deleting the current folder shows its parent, clears selection and preview, and increments the synchronization request")
    func leavingTrashedShowingFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(try #require(env.row("trip")).url)
        await env.model.openItem(try #require(env.row("trip/day1")).url)
        let idBefore = try #require(env.model.treeSyncRequest?.id)
        try FileManager.default.removeItem(at: env.url("trip/day1"))

        let moved = await env.model.leaveTrashedFolders([env.url("trip/day1")])

        #expect(moved == true)
        #expect(path(env.model.listing.folder) == path(env.url("trip")))
        #expect(env.model.listing.state == .loaded)
        #expect(env.model.selection.selected.isEmpty)
        #expect(env.model.selection.focused == nil)
        #expect(isEmptyPreview(env.model.preview))
        #expect(path(env.lastFolder) == path(env.url("trip")))
        #expect(path(env.model.treeSyncRequest?.folder) == path(env.url("trip")))
        #expect(try #require(env.model.treeSyncRequest?.id) > idBefore)
        #expect(env.row("trip/day1") == nil)
        #expect(env.row("trip/day2") != nil)
    }

    @Test("Deleting an ancestor of the current folder shows that ancestor's parent listing")
    func leavingTrashedAncestor() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(try #require(env.row("trip")).url)
        await env.model.openItem(try #require(env.row("trip/day1")).url)
        try FileManager.default.removeItem(at: env.url("trip"))

        let moved = await env.model.leaveTrashedFolders([env.url("trip")])

        #expect(moved == true)
        #expect(path(env.model.listing.folder) == path(env.root))
        #expect(env.row("trip") == nil)
    }

    @Test("Deleting unrelated folders returns false and preserves the listing, selection, and synchronization request")
    func leavingUnrelatedFolderDoesNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(try #require(env.row("trip")).url)
        await env.model.openItem(try #require(env.row("trip/day1")).url)
        let day1Image = try #require(env.model.listing.files.first { $0.name == "1.jpg" })
        env.model.select([day1Image.url], focused: day1Image.url)
        let requestBefore = env.model.treeSyncRequest
        let selectionBefore = env.model.selection.selected
        try FileManager.default.removeItem(at: env.url("empty"))

        let moved = await env.model.leaveTrashedFolders([env.url("empty")])

        #expect(moved == false)
        #expect(path(env.model.listing.folder) == path(env.url("trip/day1")))
        #expect(env.model.selection.selected == selectionBefore)
        #expect(env.model.treeSyncRequest == requestBefore)
    }

    @Test("An empty array returns false and changes nothing")
    func leavingNothingDoesNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(try #require(env.row("trip")).url)
        let requestBefore = env.model.treeSyncRequest

        let moved = await env.model.leaveTrashedFolders([])

        #expect(moved == false)
        #expect(path(env.model.listing.folder) == path(env.url("trip")))
        #expect(env.model.treeSyncRequest == requestBefore)
    }

    @Test("Deleting the current folder during video preview increments the stop signal")
    func leavingTrashedFolderStopsVideo() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        try VideoFixtures.mp4(at: env.url("trip/day1").appendingPathComponent("clip.mp4"), seconds: 0.5)
        await env.model.selectFolder(env.root)
        await env.model.openItem(try #require(env.row("trip")).url)
        await env.model.openItem(try #require(env.row("trip/day1")).url)
        let clip = try #require(env.model.listing.files.first { $0.name == "clip.mp4" })
        env.model.select([clip.url], focused: clip.url)
        guard case .video = env.model.preview else {
            Issue.record("preview should be video, got \(env.model.preview)")
            return
        }
        let before = env.model.stopPlaybackSignal
        try FileManager.default.removeItem(at: env.url("trip/day1"))

        let moved = await env.model.leaveTrashedFolders([env.url("trip/day1")])

        #expect(moved == true)
        #expect(env.model.stopPlaybackSignal > before)
        #expect(isEmptyPreview(env.model.preview))
    }

    @Test("Deleting the containing folder while browsing a zip discards zip state and shows the parent listing")
    func leavingTrashedFolderContainingOpenArchive() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let jpeg = env.root.appendingPathComponent("cover.jpg")
        try ZipFixtureWriter.write(
            [ZipFixtureEntry(name: "a.jpg", content: .bytes(try Data(contentsOf: jpeg)), method: .deflated)],
            to: env.url("trip").appendingPathComponent("photos.zip")
        )
        env.model.setShowsZipFiles(true)
        await env.model.selectFolder(env.root)
        await env.model.openItem(try #require(env.row("trip")).url)
        await env.model.openItem(try #require(env.row("trip/photos.zip")).url)
        #expect(env.model.isBrowsingArchive)
        try FileManager.default.removeItem(at: env.url("trip"))

        let moved = await env.model.leaveTrashedFolders([env.url("trip")])

        #expect(moved == true)
        #expect(env.model.isBrowsingArchive == false)
        #expect(path(env.model.listing.folder) == path(env.root))
    }

    // MARK: - Folder Renames (FR-104, R62)

    private func isImagePreview(_ preview: PreviewContent) -> Bool {
        if case .image = preview { return true }
        return false
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    /// Shows `trip/day1` with `1.jpg` previewed.
    private func showDay1Photo(_ env: Env) async throws -> URL {
        await env.model.selectFolder(env.url("trip/day1"))
        let photo = try #require(env.row("trip/day1/1.jpg")).url
        env.model.select([photo], focused: photo)
        #expect(await waitUntil { isImagePreview(env.model.preview) })
        return photo
    }

    private func rename(_ env: Env, _ from: String, to newName: String) throws -> (URL, URL) {
        let old = env.url(from)
        let new = old.deletingLastPathComponent().appendingPathComponent(newName, isDirectory: true)
        try FileManager.default.moveItem(at: old, to: new)
        return (old, new)
    }

    @Test("Renaming an ancestor updates the listing, selection, and lastFolder to the new location and preserves the preview")
    func renamingAncestorRebasesListing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        _ = try await showDay1Photo(env)
        let signal = env.model.stopPlaybackSignal

        let (old, new) = try rename(env, "trip", to: "trip2")
        env.model.didRenameFolder(from: old, to: new)

        #expect(path(env.model.listing.folder) == path(env.url("trip2/day1")))
        #expect(path(env.model.selection.focused) == path(env.url("trip2/day1/1.jpg")))
        #expect(env.model.selection.selected.map { path($0) } == [path(env.url("trip2/day1/1.jpg"))])
        #expect(env.row("trip2/day1/1.jpg") != nil)
        #expect(env.model.listing.files.first?.url == ParentLink.url(for: env.url("trip2/day1")))
        #expect(isImagePreview(env.model.preview))
        #expect(env.model.stopPlaybackSignal == signal)
        #expect(path(env.lastFolder) == path(env.url("trip2/day1")))

        // ⌘↑ returns to the folder under its new name (US1-AS40).
        await env.model.goToEnclosingLevel()
        #expect(path(env.model.listing.folder) == path(env.url("trip2")))
    }

    @Test("An event for the old location after renaming the current folder does not navigate to the parent")
    func renamingDisplayedFolderIgnoresOldEvents() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        _ = try await showDay1Photo(env)

        let (old, new) = try rename(env, "trip/day1", to: "day1x")
        env.model.didRenameFolder(from: old, to: new)
        await env.model.handleFileSystemEvent([old, env.url("trip")])

        #expect(path(env.model.listing.folder) == path(env.url("trip/day1x")))
        #expect(path(env.model.selection.focused) == path(env.url("trip/day1x/1.jpg")))
        #expect(env.row("trip/day1x/1.jpg") != nil)
        #expect(isImagePreview(env.model.preview))
    }

    @Test("Renaming a folder in its parent listing updates and repositions the row while preserving selection")
    func renamingFolderRowInParentListing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        let trip = try #require(env.row("trip")).url
        env.model.select([trip], focused: trip)

        let (old, new) = try rename(env, "trip", to: "a-trip")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.model.listing.files.map(\.name) == ["a-trip", "cover.jpg", "empty", "only"])
        #expect(env.row("a-trip")?.kind == .folder)
        #expect(path(env.model.selection.focused) == path(env.url("a-trip")))
    }

    @Test("Renaming the containing folder while browsing a zip preserves the listing and reads other entries at the new location (EC-50)")
    func renamingFolderContainingOpenArchive() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let jpeg = try Data(contentsOf: env.root.appendingPathComponent("cover.jpg"))
        try ZipFixtureWriter.write(
            [
                ZipFixtureEntry(name: "a.jpg", content: .bytes(jpeg), method: .deflated),
                ZipFixtureEntry(name: "b.jpg", content: .bytes(jpeg), method: .deflated),
            ],
            to: env.url("trip").appendingPathComponent("photos.zip")
        )
        env.model.setShowsZipFiles(true)
        await env.model.selectFolder(env.url("trip"))
        await env.model.openItem(try #require(env.row("trip/photos.zip")).url)
        let names = env.model.listing.files.map(\.name)

        let (old, new) = try rename(env, "trip", to: "trip2")
        env.model.didRenameFolder(from: old, to: new)

        let newZip = env.url("trip2").appendingPathComponent("photos.zip")
        #expect(path(env.model.listing.archive?.archive) == path(newZip))
        #expect(env.model.listing.files.map(\.name) == names)
        let b = try #require(env.model.listing.files.first { $0.name == "b.jpg" })
        #expect(ArchiveURL.parse(b.url).map { path($0.archive) } == path(newZip))
        env.model.select([b.url], focused: b.url)
        #expect(await waitUntil { isImagePreview(env.model.preview) })

        await env.model.goToEnclosingLevel()
        #expect(env.model.isBrowsingArchive == false)
        #expect(path(env.model.listing.folder) == path(env.url("trip2")))
        #expect(env.model.selection.focused.map { path($0) } == path(newZip))
    }

    @Test("Renaming an unrelated folder preserves the listing, selection, and lastFolder")
    func renamingUnrelatedFolderChangesNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let photo = try await showDay1Photo(env)
        let files = env.model.listing.files.map(\.url)

        let (old, new) = try rename(env, "empty", to: "empty2")
        env.model.didRenameFolder(from: old, to: new)

        #expect(env.model.listing.files.map(\.url) == files)
        #expect(env.model.selection.focused == photo)
        #expect(path(env.lastFolder) == path(env.url("trip/day1")))
    }
}
