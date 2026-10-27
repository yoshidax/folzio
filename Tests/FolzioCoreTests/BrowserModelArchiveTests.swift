import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("BrowserModel zip browsing")
@MainActor
struct BrowserModelArchiveTests {
    @Test("Folder names use the selected language after changing language inside a zip and navigating further")
    func changingLanguageUpdatesArchiveDirectories() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        env.model.setKindNames(KindNames(folder: "フォルダ", zipArchive: "ZIP アーカイブ"))
        for _ in 0..<100 where env.model.listing.files.first(where: { $0.name == "sub" })?.typeDescription != "フォルダ" {
            try await Task.sleep(for: .milliseconds(10))
        }
        let sub = try #require(env.model.listing.files.first(where: { $0.name == "sub" }))
        #expect(sub.typeDescription == "フォルダ")
        await env.model.openItem(sub.url)
        #expect(env.model.listing.files.first(where: { $0.name == "deep" })?.typeDescription == "フォルダ")
    }

    // MARK: - Fixtures

    /// Temporary folder. Contains `cover.jpg` and `photos.zip` (`sub/deep/a.jpg`, `b.png`, `anim.gif`, `readme.txt`).
    private struct Env {
        let root: URL
        let zip: URL
        let defaults: UserDefaults
        let suite: String
        let model: BrowserModel

        func entry(_ path: String) -> URL {
            ArchiveURL.entry(archive: zip, path: path)
        }

        func parentLink(directory: String = "") -> URL {
            ArchiveURL.parentLink(of: ArchiveLocation(archive: zip, directory: directory))
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// `DirectoryLister` returns `/private/var/...` URLs, so create the temporary folder with the same form.
    private func makeRootDirectory() throws -> URL {
        var root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelArchiveTests-\(UUID().uuidString)", isDirectory: true)
        if root.path.hasPrefix("/var/") {
            root = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Zip files are hidden by default (FR-095), so tests that handle zip rows start with `showsZipFiles` on.
    private func makeEnv(entries: [ZipFixtureEntry]? = nil, showsZipFiles: Bool = true) throws -> Env {
        let root = try makeRootDirectory()

        try ImageFixtures.jpeg(at: root.appendingPathComponent("cover.jpg"), width: 32, height: 24)

        let zip = root.appendingPathComponent("photos.zip")
        let zipEntries: [ZipFixtureEntry]
        if let entries {
            zipEntries = entries
        } else {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("BrowserModelArchiveTests-work-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }
            let jpeg = work.appendingPathComponent("a.jpg")
            let png = work.appendingPathComponent("b.png")
            let gif = work.appendingPathComponent("anim.gif")
            try ImageFixtures.jpeg(at: jpeg, width: 40, height: 30)
            try ImageFixtures.png(at: png, width: 20, height: 10)
            try ImageFixtures.animatedGIF(at: gif, frames: 3, width: 16, height: 16)
            zipEntries = [
                ZipFixtureEntry(name: "sub/deep/a.jpg", content: .bytes(try Data(contentsOf: jpeg)), method: .deflated),
                ZipFixtureEntry(name: "b.png", content: .bytes(try Data(contentsOf: png))),
                ZipFixtureEntry(name: "anim.gif", content: .bytes(try Data(contentsOf: gif))),
                ZipFixtureEntry(name: "readme.txt", content: .bytes(Data("hello".utf8))),
            ]
        }
        try ZipFixtureWriter.write(zipEntries, to: zip)

        let suite = "BrowserModelArchiveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(showsZipFiles, forKey: "view.showsZipFiles")
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 50_000_000),
            settings: SettingsStore(defaults: defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames)
        )
        return Env(root: root, zip: zip, defaults: defaults, suite: suite, model: model)
    }

    private func smallJPEG() throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelArchiveTests-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageFixtures.jpeg(at: url, width: 8, height: 8)
        return try Data(contentsOf: url)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func isEmptyPreview(_ preview: PreviewContent) -> Bool {
        if case .empty = preview { return true }
        return false
    }

    // MARK: - Folder Listing

    @Test("Folder listings include zip files and images")
    func folderListsArchiveAndImage() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }

        await env.model.selectFolder(env.root)

        #expect(env.model.listing.state == .loaded)
        #expect(env.model.listing.archive == nil)
        #expect(env.model.listing.files.map(\.name) == ["cover.jpg", "photos.zip"])
        #expect(env.model.listing.files.last?.kind == .archive)
        #expect(env.model.isBrowsingArchive == false)
    }

    @Test("Selecting a zip row keeps the preview empty")
    func selectingArchiveRowKeepsPreviewEmpty() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)

        env.model.select([env.zip], focused: env.zip)

        #expect(isEmptyPreview(env.model.preview))
    }

    @Test("Moving to a zip row during video playback increments the stop signal")
    func movingFromVideoToArchiveStopsPlayback() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let video = env.root.appendingPathComponent("clip.mp4")
        try Data().write(to: video)
        await env.model.selectFolder(env.root)

        env.model.select([video], focused: video)
        guard case .video = env.model.preview else {
            Issue.record("preview should be video, got \(env.model.preview)")
            return
        }
        let before = env.model.stopPlaybackSignal

        env.model.select([env.zip], focused: env.zip)

        #expect(env.model.stopPlaybackSignal > before)
        #expect(isEmptyPreview(env.model.preview))
    }

    // MARK: - Navigating Inside

    @Test("Opening a zip row shows the top-level listing")
    func openArchiveShowsTopLevel() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        env.model.select([env.zip], focused: env.zip)

        await env.model.openItem(env.zip)

        let model = env.model
        #expect(model.listing.archive == ArchiveLocation(archive: env.zip, directory: ""))
        #expect(model.isBrowsingArchive)
        #expect(model.listing.folder == env.root)
        #expect(model.listing.state == .loaded)
        #expect(model.listing.files[0].kind == .parent)
        #expect(model.listing.files[0].url == env.parentLink())
        // Directories and media are interleaved in natural name order.
        #expect(model.listing.files.dropFirst().map(\.name) == ["anim.gif", "b.png", "sub"])
        #expect(model.listing.files.filter { $0.kind == .parent }.count == 1)
        #expect(model.selection.selected.isEmpty)
        #expect(model.selection.focused == nil)
        #expect(isEmptyPreview(model.preview))
    }

    @Test("Changing the sort order keeps exactly one ... row at the start")
    func parentRowStaysFirstAfterSort() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)

        env.model.sortOrder = SortOrder(column: .name, ascending: false)

        #expect(env.model.listing.files.map(\.name) == ["..", "sub", "b.png", "anim.gif"])
    }

    @Test("Returning through directories selects the directory just left each time")
    func navigateDownAndUp() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)

        let sub = env.entry("sub/")
        let deep = env.entry("sub/deep/")
        let model = env.model

        await model.openItem(sub)
        #expect(model.listing.archive == ArchiveLocation(archive: env.zip, directory: "sub/"))
        #expect(model.listing.files.map(\.name) == ["..", "deep"])
        #expect(model.selection.selected.isEmpty)

        await model.openItem(deep)
        #expect(model.listing.archive?.directory == "sub/deep/")
        #expect(model.listing.files.map(\.name) == ["..", "a.jpg"])

        await model.goToEnclosingLevel()
        #expect(model.listing.archive?.directory == "sub/")
        #expect(model.selection.selected == [deep])
        #expect(model.selection.focused == deep)

        await model.goToEnclosingLevel()
        #expect(model.listing.archive?.directory == "")
        #expect(model.selection.selected == [sub])
        #expect(model.selection.focused == sub)

        await model.goToEnclosingLevel()
        #expect(model.listing.archive == nil)
        #expect(model.listing.folder == env.root)
        #expect(model.listing.files.map(\.name) == ["cover.jpg", "photos.zip"])
        #expect(model.selection.selected == [env.zip])
        #expect(model.selection.focused == env.zip)

        await model.goToEnclosingLevel()
        #expect(model.listing.archive == nil)
        #expect(model.selection.selected == [env.zip])
    }

    @Test("Opening the .. row has the same result as goToEnclosingLevel")
    func openParentRowGoesUp() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        await env.model.openItem(env.entry("sub/"))

        await env.model.openItem(env.parentLink(directory: "sub/"))

        #expect(env.model.listing.archive?.directory == "")
        #expect(env.model.selection.selected == [env.entry("sub/")])

        await env.model.openItem(env.parentLink())
        #expect(env.model.listing.archive == nil)
        #expect(env.model.selection.selected == [env.zip])
    }

    @Test("openItem does nothing for media rows and URLs absent from the listing")
    func openMediaDoesNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        let cover = env.root.appendingPathComponent("cover.jpg")

        await env.model.openItem(cover)
        #expect(env.model.listing.archive == nil)
        #expect(env.model.listing.files.map(\.name) == ["cover.jpg", "photos.zip"])

        await env.model.openItem(env.zip)
        let before = env.model.listing.files.map(\.url)
        await env.model.openItem(env.entry("b.png"))
        await env.model.openItem(env.entry("missing/"))
        #expect(env.model.listing.files.map(\.url) == before)
        #expect(env.model.listing.archive?.directory == "")
    }

    @Test("lastFolder remains the temporary folder when entering and leaving a zip")
    func lastFolderStaysAtContainingFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        #expect(env.defaults.string(forKey: "view.lastFolderPath") == env.root.path)

        await env.model.openItem(env.zip)
        await env.model.openItem(env.entry("sub/"))
        #expect(env.defaults.string(forKey: "view.lastFolderPath") == env.root.path)

        await env.model.goToEnclosingLevel()
        await env.model.goToEnclosingLevel()
        await env.model.goToEnclosingLevel()
        #expect(env.defaults.string(forKey: "view.lastFolderPath") == env.root.path)
    }

    @Test("Selecting another folder while inside a zip shows that folder listing")
    func selectFolderLeavesArchive() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let other = env.root.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try ImageFixtures.png(at: other.appendingPathComponent("x.png"), width: 4, height: 4)
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)

        await env.model.selectFolder(other)

        #expect(env.model.listing.archive == nil)
        #expect(env.model.listing.folder == other)
        #expect(env.model.listing.files.map(\.name) == ["x.png"])
        #expect(env.model.isBrowsingArchive == false)
    }

    // MARK: - Preview

    @Test("Still images inside a zip become .image and animated images become .animatedImageData")
    func previewImageAndAnimated() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        let model = env.model

        let png = env.entry("b.png")
        model.select([png], focused: png)
        if case .loading(let url) = model.preview {
            #expect(url == png)
        } else {
            Issue.record("preview should be loading right after select, got \(model.preview)")
        }
        let isImage = await waitUntil {
            if case .image = model.preview { return true }
            return false
        }
        #expect(isImage)

        let gif = env.entry("anim.gif")
        model.select([gif], focused: gif)
        let isAnimated = await waitUntil {
            if case .animatedImageData(let url, let data) = model.preview {
                return url == gif && !data.isEmpty
            }
            return false
        }
        #expect(isAnimated)
    }

    @Test("Selecting directories or ... inside a zip clears the preview")
    func previewEmptyForDirectoryAndParent() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        let model = env.model

        let png = env.entry("b.png")
        model.select([png], focused: png)
        _ = await waitUntil {
            if case .image = model.preview { return true }
            return false
        }

        let sub = env.entry("sub/")
        model.select([sub], focused: sub)
        #expect(isEmptyPreview(model.preview))

        model.select([png], focused: png)
        model.select([env.parentLink()], focused: env.parentLink())
        #expect(isEmptyPreview(model.preview))
    }

    @Test("Encrypted images and images with unsupported methods become unavailable")
    func previewEncryptedEntry() async throws {
        let env = try makeEnv(entries: [
            ZipFixtureEntry(name: "secret.jpg", content: .bytes(Data(repeating: 1, count: 32)), encryptedFlag: true),
            ZipFixtureEntry(name: "odd.png", content: .bytes(Data(repeating: 1, count: 32)), method: .raw(99)),
        ])
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        let model = env.model

        let secret = env.entry("secret.jpg")
        model.select([secret], focused: secret)
        let isUnavailable = await waitUntil {
            if case .unavailable(let name, let reason) = model.preview {
                return name == "secret.jpg" && reason == .archive(.entryEncrypted)
            }
            return false
        }
        #expect(isUnavailable)

        let odd = env.entry("odd.png")
        model.select([odd], focused: odd)
        let isUnsupported = await waitUntil {
            if case .unavailable(let name, let reason) = model.preview {
                if case .archive(.unsupportedMethod(99)) = reason { return name == "odd.png" }
                return false
            }
            return false
        }
        #expect(isUnsupported)
    }

    @Test("Prefetches images inside a zip immediately before and after the focused item")
    func prefetchesArchiveNeighbors() async throws {
        let jpeg = try smallJPEG()
        let env = try makeEnv(entries: [
            ZipFixtureEntry(name: "a.jpg", content: .bytes(jpeg)),
            ZipFixtureEntry(name: "b.jpg", content: .bytes(jpeg)),
            ZipFixtureEntry(name: "c.jpg", content: .bytes(jpeg)),
        ])
        defer { env.cleanup() }
        let cache = DecodedImageCache(costLimitBytes: 50_000_000)
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: cache,
            settings: SettingsStore(defaults: env.defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames)
        )
        await model.selectFolder(env.root)
        await model.openItem(env.zip)

        let b = env.entry("b.jpg")
        model.select([b], focused: b)

        var cached = false
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            let a = await cache.get(env.entry("a.jpg"))
            let c = await cache.get(env.entry("c.jpg"))
            if a != nil, c != nil { cached = true; break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(cached)
    }

    // MARK: - Empty Detection

    @Test("A zip without readable entries is .empty with only ... remaining")
    func archiveWithoutMediaIsEmpty() async throws {
        let env = try makeEnv(entries: [
            ZipFixtureEntry(name: "readme.txt", content: .bytes(Data("hi".utf8))),
        ])
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)

        await env.model.openItem(env.zip)

        #expect(env.model.listing.files.map(\.kind) == [.parent])
        #expect(env.model.listing.state == .empty)
    }

    @Test("A zip containing only directories is .loaded")
    func archiveWithOnlyDirectoryIsLoaded() async throws {
        let env = try makeEnv(entries: [
            ZipFixtureEntry(name: "docs/readme.txt", content: .bytes(Data("hi".utf8))),
            ZipFixtureEntry(name: "empty/", isDirectory: true),
        ])
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)

        await env.model.openItem(env.zip)

        #expect(env.model.listing.files.map(\.name) == ["..", "docs", "empty"])
        #expect(env.model.listing.state == .loaded)
    }

    @Test("A zip containing only images becomes .noMatches when filtered to videos")
    func videosOnlyOnImageArchiveIsNoMatches() async throws {
        let jpeg = try smallJPEG()
        let env = try makeEnv(entries: [
            ZipFixtureEntry(name: "a.jpg", content: .bytes(jpeg)),
            ZipFixtureEntry(name: "dir/b.jpg", content: .bytes(jpeg)),
        ])
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        #expect(env.model.listing.state == .loaded)

        env.model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))

        #expect(env.model.listing.files.map(\.name) == ["..", "dir"])
        #expect(env.model.listing.state == .noMatches)

        env.model.setMediaTypeFilter(MediaTypeFilter())
        #expect(env.model.listing.files.map(\.name) == ["..", "a.jpg", "dir"])
        #expect(env.model.listing.state == .loaded)
    }

    @Test("A folder containing only zip files is .loaded")
    func folderWithOnlyArchiveIsLoaded() async throws {
        let root = try makeRootDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try ZipFixtureWriter.write([ZipFixtureEntry(name: "a.txt")], to: root.appendingPathComponent("only.zip"))
        let suite = "BrowserModelArchiveTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "view.showsZipFiles")
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 1_000_000),
            settings: SettingsStore(defaults: defaults)
        )

        await model.selectFolder(root)

        #expect(model.listing.files.map(\.name) == ["only.zip"])
        #expect(model.listing.state == .loaded)

        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))
        #expect(model.listing.files.map(\.name) == ["only.zip"])
        #expect(model.listing.state == .loaded)
    }

    // MARK: - Failures

    @Test("A damaged zip is .failed and allows returning via ...")
    func brokenArchiveFails() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let broken = env.root.appendingPathComponent("broken.zip")
        try Data("this is not a zip file at all".utf8).write(to: broken)
        await env.model.selectFolder(env.root)

        await env.model.openItem(broken)

        guard case .failed(let message) = env.model.listing.state else {
            Issue.record("state should be failed, got \(env.model.listing.state)")
            return
        }
        #expect(message == .archive(.notAZip))
        #expect(env.model.listing.files.map(\.kind) == [.parent])
        #expect(env.model.listing.archive == ArchiveLocation(archive: broken, directory: ""))

        await env.model.goToEnclosingLevel()

        #expect(env.model.listing.archive == nil)
        #expect(env.model.listing.state == .loaded)
        #expect(env.model.selection.selected == [broken])
    }

    // MARK: - FSEvents and Reloading

    @Test("Returns to the containing folder listing when the zip is overwritten")
    func changedArchiveReturnsToFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        let png = env.entry("b.png")
        env.model.select([png], focused: png)

        try ZipFixtureWriter.write(
            [ZipFixtureEntry(name: "new.png", content: .bytes(Data(repeating: 2, count: 4096)))],
            to: env.zip
        )
        await env.model.handleFileSystemEvent([env.root])

        #expect(env.model.listing.archive == nil)
        #expect(env.model.listing.folder == env.root)
        #expect(env.model.listing.files.map(\.name) == ["cover.jpg", "photos.zip"])
        #expect(env.model.selection.selected.isEmpty)
        #expect(isEmptyPreview(env.model.preview))
    }

    @Test("Stays inside the zip when it is unchanged")
    func unchangedArchiveStays() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        await env.model.openItem(env.entry("sub/"))
        let before = env.model.listing.files.map(\.url)

        await env.model.handleFileSystemEvent([env.root])

        #expect(env.model.listing.archive == ArchiveLocation(archive: env.zip, directory: "sub/"))
        #expect(env.model.listing.files.map(\.url) == before)
    }

    @Test("Returns to the containing folder listing when the zip is deleted")
    func deletedArchiveReturnsToFolder() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)

        try FileManager.default.removeItem(at: env.zip)
        await env.model.handleFileSystemEvent([env.root])

        #expect(env.model.listing.archive == nil)
        #expect(env.model.listing.files.map(\.name) == ["cover.jpg"])
        #expect(isEmptyPreview(env.model.preview))
    }

    @Test("reloadCurrentFolder inside a zip leaves the listing unchanged")
    func reloadInsideArchiveKeepsListing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        let before = env.model.listing.files.map(\.url)

        await env.model.reloadCurrentFolder()

        #expect(env.model.listing.archive == ArchiveLocation(archive: env.zip, directory: ""))
        #expect(env.model.listing.files.map(\.url) == before)
        #expect(env.model.listing.state == .loaded)
    }

    // MARK: - Zip File Visibility (FR-098)

    @Test("Hiding zip files while browsing a zip preserves the listing, selection, and preview and only saves the setting")
    func hidingZipFilesInsideArchiveOnlySavesSetting() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        let png = env.entry("b.png")
        env.model.select([png], focused: png)
        let loaded = await waitUntil {
            if case .image = env.model.preview { return true }
            return false
        }
        #expect(loaded)
        let location = env.model.listing.archive
        let folder = env.model.listing.folder
        let files = env.model.listing.files.map(\.url)
        let signalBefore = env.model.stopPlaybackSignal

        env.model.setShowsZipFiles(false)

        #expect(env.model.showsZipFiles == false)
        #expect(env.defaults.object(forKey: "view.showsZipFiles") as? Bool == false)
        #expect(env.model.listing.folder == folder)
        #expect(env.model.listing.archive == location)
        #expect(env.model.listing.files.map(\.url) == files)
        #expect(env.model.listing.state == .loaded)
        #expect(env.model.selection.selected == [png])
        #expect(env.model.selection.focused == png)
        if case .image = env.model.preview {} else {
            Issue.record("preview should stay an image, got \(env.model.preview)")
        }
        #expect(env.model.stopPlaybackSignal == signalBefore)

        // The contents listing has no zip file rows, so turning visibility back on changes nothing.
        env.model.setShowsZipFiles(true)
        #expect(env.defaults.object(forKey: "view.showsZipFiles") as? Bool == true)
        #expect(env.model.listing.archive == location)
        #expect(env.model.listing.files.map(\.url) == files)
        #expect(env.model.selection.selected == [png])
    }

    @Test("Returning after hiding zip files removes the zip row and leaves no selection or preview")
    func returningAfterHidingZipFilesSelectsNothing() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        await env.model.selectFolder(env.root)
        await env.model.openItem(env.zip)
        let png = env.entry("b.png")
        env.model.select([png], focused: png)

        env.model.setShowsZipFiles(false)
        await env.model.goToEnclosingLevel()

        #expect(env.model.listing.archive == nil)
        #expect(env.model.listing.folder == env.root)
        #expect(env.model.listing.files.map(\.name) == ["cover.jpg"])
        #expect(!env.model.listing.files.contains { $0.kind == .archive })
        #expect(env.model.selection.selected.isEmpty)
        #expect(env.model.selection.focused == nil)
        #expect(isEmptyPreview(env.model.preview))
    }

    @Test("Selecting a folder containing zip files while they are hidden shows no zip rows")
    func hiddenZipFilesAreAbsentFromFolderListing() async throws {
        let env = try makeEnv(showsZipFiles: false)
        defer { env.cleanup() }

        await env.model.selectFolder(env.root)

        #expect(env.model.showsZipFiles == false)
        #expect(env.model.listing.files.map(\.name) == ["cover.jpg"])
        #expect(env.model.listing.state == .loaded)
    }
}
