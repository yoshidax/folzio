import CoreGraphics
import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

/// Content replaced at the same path is shown in the preview and reported to the file list (TAK-14, FR-228–232).
@Suite("BrowserModel replaced content")
@MainActor
struct BrowserModelContentRefreshTests {
    // MARK: - Folder Listing (US41)

    @Test("Reloads the focused preview after the file is overwritten, keeping the selection (US41-AS1, FR-229)")
    func reloadsFocusedPreviewAfterOverwrite() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let photo = try env.png("photo.png", width: 40, height: 20)
        let other = try env.png("other.png", width: 30, height: 30)

        await env.model.selectFolder(env.root)
        env.model.select([photo], focused: photo)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 40, height: 20) })
        let generation = env.model.contentChangeGeneration

        _ = try env.png("photo.png", width: 20, height: 40)
        await env.model.handleFileSystemEvent([env.root])

        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 20, height: 40) })
        #expect(env.model.selection.focused == photo)
        #expect(env.model.selection.selected == [photo])
        #expect(env.model.contentChangeGeneration == generation + 1)
        #expect(env.model.changedContentURLs == [photo])
        #expect(!env.model.changedContentURLs.contains(other))
    }

    @Test("Shows the new content when a file overwritten while not selected is selected (US41-AS3, FR-230)")
    func showsNewContentWhenSelectedAfterOverwrite() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let photo = try env.png("photo.png", width: 40, height: 20)
        let other = try env.png("other.png", width: 30, height: 30)

        await env.model.selectFolder(env.root)
        env.model.select([photo], focused: photo)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 40, height: 20) })
        env.model.select([other], focused: other)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 30, height: 30) })

        _ = try env.png("photo.png", width: 20, height: 40)
        await env.model.handleFileSystemEvent([env.root])
        #expect(env.model.changedContentURLs == [photo])

        env.model.select([photo], focused: photo)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 20, height: 40) })
    }

    @Test("Does not report changes when the reported folder has no replaced files (SC-116)")
    func unchangedFilesAreNotReported() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let photo = try env.png("photo.png", width: 40, height: 20)

        await env.model.selectFolder(env.root)
        env.model.select([photo], focused: photo)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 40, height: 20) })
        let generation = env.model.contentChangeGeneration

        _ = try env.png("added.png", width: 10, height: 10)
        await env.model.handleFileSystemEvent([env.root])

        #expect(env.model.listing.files.contains { $0.name == "added.png" })
        #expect(env.model.contentChangeGeneration == generation)
        #expect(previewSize(env.model.preview) == CGSize(width: 40, height: 20))
    }

    @Test("Shows the failure for a focused file replaced with broken content without crashing (EC-159)")
    func showsFailureForBrokenReplacement() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let photo = try env.png("photo.png", width: 40, height: 20)

        await env.model.selectFolder(env.root)
        env.model.select([photo], focused: photo)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 40, height: 20) })

        try Data("broken".utf8).write(to: photo)
        await env.model.handleFileSystemEvent([env.root])

        #expect(await waitUntil {
            if case .unavailable = env.model.preview { return true }
            return false
        })
        #expect(env.model.selection.focused == photo)
    }

    @Test("Rows from the lister get a new content version only for the overwritten file (FR-228)")
    func listerReportsNewVersionForOverwrittenFile() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let photo = try env.png("photo.png", width: 40, height: 20)
        let other = try env.png("other.png", width: 30, height: 30)
        let lister = DirectoryLister(kindNames: FixtureKit.kindNames)

        let before = try await lister.mediaFiles(in: env.root)
        _ = try env.png("photo.png", width: 20, height: 40)
        let after = try await lister.mediaFiles(in: env.root)

        func version(_ url: URL, in files: [MediaFile]) -> FileContentVersion? {
            files.first { $0.url.standardizedFileURL.path == url.standardizedFileURL.path }?.contentVersion
        }
        let photoBefore = try #require(version(photo, in: before))
        let photoAfter = try #require(version(photo, in: after))
        #expect(photoBefore != photoAfter)
        #expect(version(other, in: before) != nil)
        #expect(version(other, in: before) == version(other, in: after))
        #expect(BrowserModel.replacedContentURLs(old: before, new: after).map(\.lastPathComponent) == ["photo.png"])
    }

    // MARK: - Zip (US42)

    @Test("Shows the new content of a zip replaced at the same path when it is opened again (US42-AS1, FR-231)")
    func showsNewContentOfReplacedZip() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let zip = env.root.appendingPathComponent("photos.zip")
        try ZipFixtureWriter.write([
            ZipFixtureEntry(name: "a.png", content: .bytes(try env.pngData(width: 40, height: 20))),
        ], to: zip)
        let entry = ArchiveURL.entry(archive: zip, path: "a.png")

        await env.model.selectFolder(env.root)
        env.model.setShowsZipFiles(true)
        await env.model.openItem(zip)
        env.model.select([entry], focused: entry)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 40, height: 20) })
        await env.model.openItem(ArchiveURL.parentLink(of: ArchiveLocation(archive: zip, directory: "")))
        #expect(!env.model.isBrowsingArchive)

        let replacement = env.root.appendingPathComponent("replacement.tmp")
        try ZipFixtureWriter.write([
            ZipFixtureEntry(name: "a.png", content: .bytes(try env.pngData(width: 20, height: 40))),
        ], to: replacement)
        _ = try FileManager.default.replaceItemAt(zip, withItemAt: replacement)
        await env.model.handleFileSystemEvent([env.root])

        await env.model.openItem(zip)
        env.model.select([entry], focused: entry)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 20, height: 40) })
    }

    // MARK: - Search Results (US43)

    @Test("Reloads a search result overwritten while shown, keeping the order and selection (US43-AS1, FR-232)")
    func reloadsOverwrittenSearchResult() async throws {
        let env = try makeEnv()
        defer { env.cleanup() }
        let folder = env.root.appendingPathComponent("trip", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try env.png("trip/photo.png", width: 40, height: 20)
        _ = try env.png("trip/photo-2.png", width: 30, height: 30)

        await env.model.selectFolder(env.root)
        env.model.startSearch(SearchPattern(keyword: "photo")!, root: env.root)
        #expect(await waitUntil {
            env.model.listing.search?.phase != .searching
                && env.model.listing.files.filter { $0.kind.isMedia }.count == 2
        })
        let order = env.model.listing.files.map(\.url)
        let result = try #require(env.model.listing.files.first { $0.name == "photo.png" }?.url)
        env.model.select([result], focused: result)
        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 40, height: 20) })

        _ = try env.png("trip/photo.png", width: 20, height: 40)
        await env.model.handleFileSystemEvent([result.deletingLastPathComponent()])

        #expect(await waitUntil { previewSize(env.model.preview) == CGSize(width: 20, height: 40) })
        #expect(env.model.isShowingSearchResults)
        #expect(env.model.listing.files.map(\.url) == order)
        #expect(env.model.selection.focused == result)
        #expect(env.model.changedContentURLs == [result])
    }

    // MARK: - Comparison

    @Test("Compares content versions of media rows present in both listings")
    func replacedContentURLsComparesMediaRows() {
        let folder = URL(fileURLWithPath: "/tmp/compare", isDirectory: true)
        let v1 = FileContentVersion(fileSize: 1, modificationDate: Date(timeIntervalSince1970: 1), fileIdentifier: 1)
        let v2 = FileContentVersion(fileSize: 1, modificationDate: Date(timeIntervalSince1970: 1), fileIdentifier: 2)
        func media(_ name: String, _ version: FileContentVersion?) -> MediaFile {
            MediaFile(
                url: folder.appendingPathComponent(name), name: name, kind: .media(.png), typeDescription: "PNG",
                creationDate: nil, fileSize: 1, contentVersion: version
            )
        }
        let folderRow = DirectoryLister.folderRow(
            at: folder.appendingPathComponent("sub", isDirectory: true),
            creationDate: nil,
            kindNames: FixtureKit.kindNames
        )

        let old = [media("same.png", v1), media("replaced.png", v1), media("gone.png", v1), folderRow]
        let new = [media("same.png", v1), media("replaced.png", v2), media("added.png", v1), folderRow]
        #expect(BrowserModel.replacedContentURLs(old: old, new: new) == [folder.appendingPathComponent("replaced.png")])
        #expect(BrowserModel.replacedContentURLs(old: [], new: new).isEmpty)
    }

    // MARK: - Fixtures

    private struct Env {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        let model: BrowserModel

        /// Writes a PNG at `path` (replacing any file there) and returns its URL.
        func png(_ path: String, width: Int, height: Int) throws -> URL {
            let url = root.appendingPathComponent(path)
            try ImageFixtures.png(at: url, width: width, height: height)
            return url
        }

        func pngData(width: Int, height: Int) throws -> Data {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("BrowserModelContentRefreshTests-work-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: work) }
            try ImageFixtures.png(at: work, width: width, height: height)
            return try Data(contentsOf: work)
        }

        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }

    /// `DirectoryLister` returns `/private/var/...` URLs, so create the temporary folder with the same form.
    private func makeEnv() throws -> Env {
        var root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrowserModelContentRefreshTests-\(UUID().uuidString)", isDirectory: true)
        if root.path.hasPrefix("/var/") {
            root = URL(fileURLWithPath: "/private" + root.path, isDirectory: true)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let suite = "BrowserModelContentRefreshTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(costLimitBytes: 50_000_000),
            settings: SettingsStore(defaults: defaults),
            archiveReader: ZipArchiveReader(kindNames: FixtureKit.kindNames)
        )
        model.setNavigationRoots([root])
        return Env(root: root, defaults: defaults, suite: suite, model: model)
    }

    private func previewSize(_ preview: PreviewContent) -> CGSize? {
        guard case let .image(image) = preview else { return nil }
        return image.originalPixelSize
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
