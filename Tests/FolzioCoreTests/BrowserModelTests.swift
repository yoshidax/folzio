import CoreGraphics
import Foundation
import Testing
@testable import FolzioCore
import FixtureKit

@Suite("BrowserModel")
struct BrowserModelTests {
    @Test("Enumeration started before a language change also displays the new kind names")
    @MainActor
    func languageChangeDuringListing() async {
        let folder = URL(fileURLWithPath: "/tmp/localization-\(UUID().uuidString)", isDirectory: true)
        let row = MediaFile(url: folder.appendingPathComponent("child"), name: "child", kind: .folder,
                            typeDescription: "Folder", creationDate: nil, fileSize: 0, kindNameSource: .folder)
        let lister = FakeLister(responses: [folder: .init(files: [row], delay: .milliseconds(100))])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        let load = Task { await model.selectFolder(folder) }
        try? await Task.sleep(for: .milliseconds(20))
        model.setKindNames(KindNames(folder: "フォルダ", zipArchive: "ZIP アーカイブ"))
        await load.value
        // If the sleep above overshoots on a busy runner, the language changes after the listing has loaded. The
        // kind names are then applied asynchronously, so wait for the update instead of reading right after the load.
        for _ in 0..<100 where model.listing.files.first?.typeDescription != "フォルダ" {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.listing.files.first?.typeDescription == "フォルダ")
    }

    @Test("Changing kind names resorts only kind sorting and preserves OS-provided names and selection")
    @MainActor
    func changingLanguageResortsKindNames() async {
        let folder = URL(fileURLWithPath: "/tmp/localization-sort-\(UUID().uuidString)", isDirectory: true)
        let child = MediaFile(url: folder.appendingPathComponent("child"), name: "child", kind: .folder,
                              typeDescription: "Folder", creationDate: nil, fileSize: 0, kindNameSource: .folder)
        let image = MediaFile(url: folder.appendingPathComponent("photo.jpg"), name: "photo.jpg", kind: .media(.jpeg),
                              typeDescription: "Middle", creationDate: nil, fileSize: 0)
        let lister = FakeLister(responses: [folder: .init(files: [child, image], delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.sortOrder = SortOrder(column: .kind, ascending: true)
        await model.selectFolder(folder)
        model.select([child.url], focused: child.url)
        model.setKindNames(KindNames(folder: "Z Folder", zipArchive: "Z Zip"))
        for _ in 0..<100 where model.listing.files.first?.url != image.url {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.listing.files.map(\.url) == [image.url, child.url])
        #expect(model.listing.files.first?.typeDescription == "Middle")
        #expect(model.listing.files.last?.typeDescription == "Z Folder")
        #expect(model.selection.focused == child.url)
    }

    @Test("Rapid folder switches retain only the last listing")
    @MainActor
    func keepsOnlyLastFolder() async {
        let first = URL(fileURLWithPath: "/tmp/first-\(UUID().uuidString)", isDirectory: true)
        let second = URL(fileURLWithPath: "/tmp/second-\(UUID().uuidString)", isDirectory: true)

        let lister = FakeLister(responses: [
            first: .init(files: [file("a.jpg", in: first)], delay: .milliseconds(200)),
            second: .init(files: [file("b.jpg", in: second)], delay: .zero),
        ])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        let firstTask = Task { await model.selectFolder(first) }
        try? await Task.sleep(for: .milliseconds(20))
        let secondTask = Task { await model.selectFolder(second) }
        await firstTask.value
        await secondTask.value

        #expect(model.listing.folder == second)
        #expect(model.listing.files.map(\.name) == ["b.jpg"])
        #expect(model.listing.state == .loaded)
        #expect(defaults.string(forKey: "view.lastFolderPath") == second.path)
    }

    @Test("Overlapping reloads keep the newest success or failure")
    @MainActor
    func overlappingReloads() async throws {
        let folder = URL(fileURLWithPath: "/tmp/reload-\(UUID().uuidString)", isDirectory: true)
        let old = file("old.jpg", in: folder)
        let current = file("current.jpg", in: folder)

        for scenario in 0..<3 {
            let lister = ControlledLister()
            let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
            defer { defaults.removePersistentDomain(forName: suite) }
            let initial = Task { await model.selectFolder(folder) }
            try await lister.waitForCalls(1)
            await lister.complete(0, with: .success([old]))
            await initial.value

            let first = Task { await model.reloadCurrentFolder() }
            try await lister.waitForCalls(2)
            let second = Task { await model.reloadCurrentFolder() }
            try await lister.waitForCalls(3)
            if scenario == 2 {
                await lister.complete(2, with: .failure(.accessDenied))
            } else {
                await lister.complete(2, with: .success([current]))
            }
            await second.value
            if scenario != 2 {
                model.select([current.url], focused: current.url)
            }
            if scenario == 1 {
                await lister.complete(1, with: .failure(.notFound))
            } else {
                await lister.complete(1, with: .success([old]))
            }
            await first.value

            if scenario == 2 {
                #expect(model.listing.state == .denied)
                #expect(model.listing.files.isEmpty)
                #expect(model.selection.focused == nil)
                if case .empty = model.preview {} else { Issue.record("Expected empty preview") }
            } else {
                #expect(model.listing.state == .loaded)
                #expect(model.listing.files.map(\.url) == [current.url])
                #expect(model.selection.focused == current.url)
                #expect(model.selection.selected == [current.url])
                if case .empty = model.preview { Issue.record("The selected preview was cleared") }
            }
        }
    }

    @Test("A reload supersedes a pending initial folder enumeration")
    @MainActor
    func reloadSupersedesInitialLoad() async throws {
        let folder = URL(fileURLWithPath: "/tmp/reload-initial-\(UUID().uuidString)", isDirectory: true)
        let old = file("old.jpg", in: folder)
        let current = file("current.jpg", in: folder)
        let lister = ControlledLister()
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        let initial = Task { await model.selectFolder(folder) }
        try await lister.waitForCalls(1)
        let reload = Task { await model.reloadCurrentFolder() }
        try await lister.waitForCalls(2)
        await lister.complete(1, with: .success([current]))
        await reload.value
        await lister.complete(0, with: .success([old]))
        await initial.value
        #expect(model.listing.state == .loaded)
        #expect(model.listing.files.map(\.url) == [current.url])
    }

    @Test("Reflects empty-folder and access-denied states")
    @MainActor
    func reflectsEmptyAndDenied() async {
        let emptyFolder = URL(fileURLWithPath: "/tmp/empty-\(UUID().uuidString)", isDirectory: true)
        let deniedFolder = URL(fileURLWithPath: "/tmp/denied-\(UUID().uuidString)", isDirectory: true)

        let lister = FakeLister(responses: [
            emptyFolder: .init(files: [], delay: .zero),
            deniedFolder: .init(files: [], delay: .zero, error: .accessDenied),
        ])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(emptyFolder)
        #expect(model.listing.state == .empty)
        #expect(model.listing.files.isEmpty)

        await model.selectFolder(deniedFolder)
        #expect(model.listing.state == .denied)
        #expect(model.listing.files.isEmpty)
    }

    @Test("moveFocus stops at the ends")
    @MainActor
    func moveFocusStopsAtEdges() async {
        let folder = URL(fileURLWithPath: "/tmp/move-\(UUID().uuidString)", isDirectory: true)
        let files = [file("a.jpg", in: folder), file("b.jpg", in: folder), file("c.jpg", in: folder)]

        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(folder)
        model.select([files[0].url], focused: files[0].url)
        model.moveFocus(.previous)
        #expect(model.selection.focused == files[0].url)

        model.moveFocus(.next)
        #expect(model.selection.focused == files[1].url)
        model.moveFocus(.next)
        #expect(model.selection.focused == files[2].url)
        model.moveFocus(.next)
        #expect(model.selection.focused == files[2].url)

        model.moveFocus(.previous)
        #expect(model.selection.focused == files[1].url)
    }

    @Test("Caches one item before and after the focused item")
    @MainActor
    func prefetchesNeighbors() async {
        let folder = URL(fileURLWithPath: "/tmp/prefetch-\(UUID().uuidString)", isDirectory: true)
        let files = [file("a.jpg", in: folder), file("b.jpg", in: folder), file("c.jpg", in: folder)]
        let cache = DecodedImageCache(costLimitBytes: 10_000_000)

        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder(), cache: cache)
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(folder)
        model.select([files[1].url], focused: files[1].url)

        #expect(await waitForCache(cache, files[0].url))
        #expect(await waitForCache(cache, files[2].url))
    }

    @Test("Decode failure becomes unavailable")
    @MainActor
    func reportsDecodeFailure() async {
        let folder = URL(fileURLWithPath: "/tmp/failure-\(UUID().uuidString)", isDirectory: true)
        let bad = file("bad.jpg", in: folder)

        let lister = FakeLister(responses: [folder: .init(files: [bad], delay: .zero)])
        let decoder = FakeDecoder(failingURLs: [bad.url])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: decoder)
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(folder)
        model.select([bad.url], focused: bad.url)

        let isUnavailable = await waitUntil {
            if case let .unavailable(name, _) = model.preview {
                return name == "bad.jpg"
            }
            return false
        }
        #expect(isUnavailable)
    }

    // MARK: - Media Type Filter

    @MainActor
    private func filterFolder() -> (URL, [MediaFile]) {
        let folder = URL(fileURLWithPath: "/tmp/filter-\(UUID().uuidString)", isDirectory: true)
        let files = ["a.jpg", "b.mov", "c.png", "d.mp4"].map { file($0, in: folder) }
        return (folder, files)
    }

    @MainActor
    private func isImagePreview(_ model: BrowserModel) -> Bool {
        if case .image = model.preview { return true }
        return false
    }

    @MainActor
    private func isLoadingPreview(_ model: BrowserModel) -> Bool {
        if case .loading = model.preview { return true }
        return false
    }

    @MainActor
    private func isEmptyPreview(_ model: BrowserModel) -> Bool {
        if case .empty = model.preview { return true }
        return false
    }

    @Test("Both media type filters default to off and show all items")
    @MainActor
    func filterDefaultShowsAll() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(model.mediaTypeFilter == MediaTypeFilter())
        await model.selectFolder(folder)
        #expect(model.listing.files.count == 4)
        #expect(model.listing.state == .loaded)
    }

    @Test("Switches media type filters between images only, videos only, and both enabled")
    @MainActor
    func filterSwitchesKinds() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.selectFolder(folder)

        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))
        #expect(model.listing.files.map(\.name) == ["a.jpg", "c.png"])

        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        #expect(model.listing.files.map(\.name) == ["b.mov", "d.mp4"])

        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true, videosOnly: true))
        #expect(model.listing.files.map(\.name) == ["a.jpg", "b.mov", "c.png", "d.mp4"])

        // US3-13: Turn off only "Images only" from both on.
        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        #expect(model.listing.files.map(\.name) == ["b.mov", "d.mp4"])
    }

    @Test("Distinguishes no matches from an empty folder")
    @MainActor
    func filterDistinguishesNoMatchesAndEmpty() async {
        let imageFolder = URL(fileURLWithPath: "/tmp/filter-img-\(UUID().uuidString)", isDirectory: true)
        let emptyFolder = URL(fileURLWithPath: "/tmp/filter-empty-\(UUID().uuidString)", isDirectory: true)
        let lister = FakeLister(responses: [
            imageFolder: .init(files: [file("a.jpg", in: imageFolder), file("c.png", in: imageFolder)], delay: .zero),
            emptyFolder: .init(files: [], delay: .zero),
        ])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(imageFolder)
        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        #expect(model.listing.state == .noMatches)
        #expect(model.listing.files.isEmpty)

        model.setMediaTypeFilter(MediaTypeFilter())
        #expect(model.listing.state == .loaded)
        #expect(model.listing.files.count == 2)

        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        await model.selectFolder(emptyFolder)
        #expect(model.listing.state == .empty)
        #expect(model.listing.files.isEmpty)
    }

    @Test("Navigating between folders preserves media type filters")
    @MainActor
    func filterPersistsAcrossFolders() async {
        let (folder, files) = filterFolder()
        let other = URL(fileURLWithPath: "/tmp/filter-other-\(UUID().uuidString)", isDirectory: true)
        let otherFiles = ["x.jpg", "y.mov", "z.mp4"].map { file($0, in: other) }
        let lister = FakeLister(responses: [
            folder: .init(files: files, delay: .zero),
            other: .init(files: otherFiles, delay: .zero),
        ])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(folder)
        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        await model.selectFolder(other)

        #expect(model.mediaTypeFilter.videosOnly)
        #expect(model.listing.files.map(\.name) == ["y.mov", "z.mp4"])
    }

    @Test("Sorting while filtering preserves the filter and the no-matches state")
    @MainActor
    func filterWithSortOrder() async {
        let (folder, files) = filterFolder()
        let imageFolder = URL(fileURLWithPath: "/tmp/filter-img-\(UUID().uuidString)", isDirectory: true)
        let lister = FakeLister(responses: [
            folder: .init(files: files, delay: .zero),
            imageFolder: .init(files: [file("a.jpg", in: imageFolder)], delay: .zero),
        ])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(folder)
        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        model.sortOrder = SortOrder(column: .name, ascending: false)
        #expect(model.listing.files.map(\.name) == ["d.mp4", "b.mov"])

        await model.selectFolder(imageFolder)
        #expect(model.listing.state == .noMatches)
        model.sortOrder = SortOrder(column: .name, ascending: true)
        #expect(model.listing.state == .noMatches)
        #expect(model.listing.files.isEmpty)
    }

    @Test("Reloading while filtering also filters new files")
    @MainActor
    func filterAppliesOnReload() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        await model.selectFolder(folder)
        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))

        await lister.setResponse(
            .init(files: files + [file("e.mov", in: folder)], delay: .zero),
            for: folder
        )
        await model.reloadCurrentFolder()
        #expect(model.listing.files.map(\.name) == ["b.mov", "d.mp4", "e.mov"])
    }

    @Test("Hiding the focused item reconciles selection and switches the preview")
    @MainActor
    func filterRestrictsSelectionWhenFocusHidden() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.selectFolder(folder)

        let a = files[0].url
        let b = files[1].url
        model.select([a, b], focused: b)
        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))

        #expect(model.selection.selected == [a])
        #expect(model.selection.focused == a)
        let isImage = await waitUntil { isImagePreview(model) }
        #expect(isImage)
    }

    @Test("Keeping the focused item visible updates only selection without reloading the preview")
    @MainActor
    func filterKeepsPreviewWhenFocusVisible() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.selectFolder(folder)

        let a = files[0].url
        let b = files[1].url
        model.select([a, b], focused: a)
        let loaded = await waitUntil { isImagePreview(model) }
        #expect(loaded)

        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))

        #expect(model.selection.selected == [a])
        #expect(model.selection.focused == a)
        #expect(!isLoadingPreview(model))
        #expect(isImagePreview(model))
    }

    @Test("No remaining selected items clears selection, and removing the filter does not restore it")
    @MainActor
    func filterClearsSelectionWhenNothingRemains() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.selectFolder(folder)

        let b = files[1].url
        model.select([b], focused: b)
        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))

        #expect(model.selection.selected.isEmpty)
        #expect(model.selection.focused == nil)
        #expect(isEmptyPreview(model))

        model.setMediaTypeFilter(MediaTypeFilter())
        #expect(model.selection.selected.isEmpty)
        #expect(model.selection.focused == nil)
    }

    @Test("Reapplying the same media type filter preserves the listing and selection")
    @MainActor
    func filterSameValueIsNoOp() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.selectFolder(folder)

        let a = files[0].url
        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))
        model.select([a], focused: a)
        let listingBefore = model.listing
        let selectionBefore = model.selection
        let signalBefore = model.stopPlaybackSignal

        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))

        #expect(model.listing.files.map(\.url) == listingBefore.files.map(\.url))
        #expect(model.listing.state == listingBefore.state)
        #expect(model.listing.folder == listingBefore.folder)
        #expect(model.selection.selected == selectionBefore.selected)
        #expect(model.selection.focused == selectionBefore.focused)
        #expect(model.stopPlaybackSignal == signalBefore)
    }

    @Test("Media type filters are not saved in settings")
    @MainActor
    func filterIsNotPersisted() async {
        let (folder, files) = filterFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.selectFolder(folder)

        let keysBefore = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])
        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))
        model.setMediaTypeFilter(MediaTypeFilter(videosOnly: true))
        let keysAfter = Set(defaults.persistentDomain(forName: suite)?.keys.map { $0 } ?? [])

        #expect(keysBefore == keysAfter)
    }

    // MARK: - Zip File Visibility

    /// Folder containing `a.jpg`, `b.zip`, `c.png`, and subfolder `sub`.
    @MainActor
    private func zipFolder() -> (URL, [MediaFile]) {
        let folder = URL(fileURLWithPath: "/tmp/zipvis-\(UUID().uuidString)", isDirectory: true)
        let files = [
            file("a.jpg", in: folder),
            row("b.zip", .archive, in: folder),
            file("c.png", in: folder),
            row("sub", .folder, in: folder),
        ]
        return (folder, files)
    }

    @Test("Zip files default to hidden; only zip rows are excluded and .. stays first")
    @MainActor
    func zipDefaultHidesArchiveRows() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setNavigationRoots([folder.deletingLastPathComponent()])

        #expect(model.showsZipFiles == false)
        await model.selectFolder(folder)

        #expect(model.listing.files.map(\.name) == ["..", "sub", "a.jpg", "c.png"])
        #expect(model.listing.state == .loaded)
    }

    @Test("Showing zip files restores their sorted positions without enumerating again")
    @MainActor
    func zipShowRestoresRowsWithoutRelisting() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setNavigationRoots([folder.deletingLastPathComponent()])
        await model.selectFolder(folder)
        let callsBefore = await lister.callCount

        model.setShowsZipFiles(true)

        #expect(model.showsZipFiles == true)
        #expect(model.listing.files.map(\.name) == ["..", "sub", "a.jpg", "b.zip", "c.png"])
        #expect(model.listing.state == .loaded)
        #expect(await lister.callCount == callsBefore)
        #expect(defaults.object(forKey: "view.showsZipFiles") as? Bool == true)
    }

    @Test("Hiding and showing zip files restores the same order without setResponse")
    @MainActor
    func zipHideThenShowAgain() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setNavigationRoots([folder.deletingLastPathComponent()])
        await model.selectFolder(folder)
        let callsBefore = await lister.callCount

        model.setShowsZipFiles(true)
        let shown = model.listing.files.map(\.url)
        model.setShowsZipFiles(false)
        #expect(!model.listing.files.contains { $0.kind == .archive })
        #expect(model.listing.files.map(\.name) == ["..", "sub", "a.jpg", "c.png"])
        #expect(defaults.object(forKey: "view.showsZipFiles") as? Bool == false)

        model.setShowsZipFiles(true)
        #expect(model.listing.files.map(\.url) == shown)
        #expect(await lister.callCount == callsBefore)
    }

    @Test("Zip visibility combines independently with media type filters")
    @MainActor
    func zipVisibilityComposesWithMediaTypeFilter() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setNavigationRoots([folder.deletingLastPathComponent()])
        await model.selectFolder(folder)

        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))
        model.setShowsZipFiles(true)
        #expect(model.listing.files.map(\.name) == ["..", "sub", "a.jpg", "b.zip", "c.png"])

        model.setShowsZipFiles(false)
        #expect(model.listing.files.map(\.name) == ["..", "sub", "a.jpg", "c.png"])
    }

    @Test("Hiding a focused zip moves focus and preview to a remaining selected item")
    @MainActor
    func zipHideMovesFocusToRemainingSelection() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setShowsZipFiles(true)
        await model.selectFolder(folder)

        let a = files[0].url
        let zip = files[1].url
        model.select([zip, a], focused: zip)
        model.setShowsZipFiles(false)

        #expect(model.selection.selected == [a])
        #expect(model.selection.focused == a)
        let isImage = await waitUntil { isImagePreview(model) }
        #expect(isImage)
    }

    @Test("Keeping the focused item visible preserves selection and the loaded preview")
    @MainActor
    func zipHideKeepsPreviewWhenFocusVisible() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setShowsZipFiles(true)
        await model.selectFolder(folder)

        let a = files[0].url
        let zip = files[1].url
        model.select([a, zip], focused: a)
        let loaded = await waitUntil { isImagePreview(model) }
        #expect(loaded)
        let signalBefore = model.stopPlaybackSignal

        model.setShowsZipFiles(false)

        #expect(model.selection.selected == [a])
        #expect(model.selection.focused == a)
        #expect(!isLoadingPreview(model))
        #expect(isImagePreview(model))
        #expect(model.stopPlaybackSignal == signalBefore)
    }

    @Test("Hiding zip files when only zip files are selected clears selection without restoring it when shown again")
    @MainActor
    func zipHideClearsSelectionWhenNothingRemains() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setShowsZipFiles(true)
        await model.selectFolder(folder)

        let zip = files[1].url
        model.select([zip], focused: zip)
        model.setShowsZipFiles(false)

        #expect(model.selection.selected.isEmpty)
        #expect(model.selection.focused == nil)
        #expect(isEmptyPreview(model))

        model.setShowsZipFiles(true)
        #expect(model.selection.selected.isEmpty)
        #expect(model.selection.focused == nil)
    }

    @Test("Hiding a folder's only zip files gives .empty without a separate state and leaves only ..")
    @MainActor
    func zipOnlyFolderBecomesEmpty() async {
        let folder = URL(fileURLWithPath: "/tmp/ziponly-\(UUID().uuidString)", isDirectory: true)
        let zips = [row("a.zip", .archive, in: folder), row("b.zip", .archive, in: folder)]
        let lister = FakeLister(responses: [folder: .init(files: zips, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setShowsZipFiles(true)
        model.setNavigationRoots([folder.deletingLastPathComponent()])
        await model.selectFolder(folder)
        #expect(model.listing.state == .loaded)
        #expect(model.listing.files.map(\.name) == ["..", "a.zip", "b.zip"])

        model.setShowsZipFiles(false)
        #expect(model.listing.state == .empty)
        #expect(model.listing.files.map(\.name) == [".."])

        // At a tree root, the listing is empty with no `..`.
        model.setNavigationRoots([folder])
        #expect(model.listing.state == .empty)
        #expect(model.listing.files.isEmpty)

        model.setShowsZipFiles(true)
        #expect(model.listing.state == .loaded)
        #expect(model.listing.files.map(\.name) == ["a.zip", "b.zip"])
    }

    @Test("Reapplying the same zip visibility preserves the listing and selection")
    @MainActor
    func zipSameValueIsNoOp() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        await model.selectFolder(folder)
        let a = files[0].url
        model.select([a], focused: a)
        let listingBefore = model.listing
        let selectionBefore = model.selection
        let signalBefore = model.stopPlaybackSignal

        model.setShowsZipFiles(false)

        #expect(model.listing.files.map(\.url) == listingBefore.files.map(\.url))
        #expect(model.listing.state == listingBefore.state)
        #expect(model.selection.selected == selectionBefore.selected)
        #expect(model.selection.focused == selectionBefore.focused)
        #expect(model.stopPlaybackSignal == signalBefore)
    }

    @Test("Zip visibility is saved and restored by a BrowserModel created with the same settings")
    @MainActor
    func zipVisibilityIsRestored() async {
        let (folder, files) = zipFolder()
        let lister = FakeLister(responses: [folder: .init(files: files, delay: .zero)])
        let (model, defaults, suite) = makeModel(lister: lister, decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }

        model.setShowsZipFiles(true)

        let restored = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: lister,
            decoder: FakeDecoder(),
            cache: DecodedImageCache(costLimitBytes: 10_000_000),
            settings: SettingsStore(defaults: defaults)
        )
        #expect(restored.showsZipFiles == true)
        await restored.selectFolder(folder)
        #expect(restored.listing.files.map(\.name) == ["sub", "a.jpg", "b.zip", "c.png"])
    }

    @MainActor
    @Test("Shows and hides list columns and restores them in a new model")
    func columnVisibilityIsPersisted() {
        let (model, defaults, suite) = makeModel(lister: FakeLister(responses: [:]), decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(model.visibleColumns == [.creationDate, .kind])

        model.setColumn(.size, visible: true)
        model.setColumn(.kind, visible: false)
        #expect(model.visibleColumns == [.creationDate, .size])

        let restored = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: FakeLister(responses: [:]),
            decoder: FakeDecoder(),
            cache: DecodedImageCache(costLimitBytes: 10_000_000),
            settings: SettingsStore(defaults: defaults)
        )
        #expect(restored.visibleColumns == [.creationDate, .size])
    }

    @MainActor
    @Test("Hiding the sorted column falls back to name in its last direction, and keeps other sorts")
    func hidingSortedColumnFallsBackToName() {
        let (model, defaults, suite) = makeModel(lister: FakeLister(responses: [:]), decoder: FakeDecoder())
        defer { defaults.removePersistentDomain(forName: suite) }
        model.setColumn(.size, visible: true)

        // Never sorted by name in descending order: falls back to ascending.
        model.sortOrder = SortOrder(column: .size, ascending: false)
        model.setColumn(.size, visible: false)
        #expect(model.sortOrder == SortOrder(column: .name, ascending: true))

        // Hiding a column that is not the sorted one does not change the sort.
        model.sortOrder = SortOrder(column: .name, ascending: false)
        model.sortOrder = SortOrder(column: .creationDate, ascending: true)
        model.setColumn(.kind, visible: false)
        #expect(model.sortOrder == SortOrder(column: .creationDate, ascending: true))

        // Uses the direction the name sort last had, and the direction survives a restart.
        model.setColumn(.creationDate, visible: false)
        #expect(model.sortOrder == SortOrder(column: .name, ascending: false))
        #expect(SettingsStore(defaults: defaults).viewSettings.sortOrder == SortOrder(column: .name, ascending: false))
    }

    @MainActor
    private func makeModel(
        lister: any DirectoryListing,
        decoder: FakeDecoder,
        cache: DecodedImageCache = DecodedImageCache(costLimitBytes: 10_000_000)
    ) -> (BrowserModel, UserDefaults, String) {
        let suite = "BrowserModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: lister,
            decoder: decoder,
            cache: cache,
            settings: SettingsStore(defaults: defaults)
        )
        return (model, defaults, suite)
    }

    @MainActor
    private func file(_ name: String, in folder: URL) -> MediaFile {
        MediaFile(
            url: folder.appendingPathComponent(name),
            name: name,
            kind: .media(MediaKind(fileExtension: (name as NSString).pathExtension) ?? .jpeg),
            typeDescription: "JPEG イメージ",
            creationDate: nil,
            fileSize: 0,
            // Rows from DirectoryLister always carry a content version; the cache keys images by it (FR-230).
            contentVersion: FileContentVersion(fileSize: 0, modificationDate: nil, fileIdentifier: 1)
        )
    }

    @MainActor
    private func row(_ name: String, _ kind: ListItemKind, in folder: URL) -> MediaFile {
        MediaFile(
            url: folder.appendingPathComponent(name),
            name: name,
            kind: kind,
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func waitForCache(_ cache: DecodedImageCache, _ url: URL) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await cache.containsEntry(for: url) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private actor ControlledLister: DirectoryListing {
    private var pending: [CheckedContinuation<Result<[MediaFile], ListingError>, Never>] = []

    func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] {
        let result = await withCheckedContinuation { continuation in
            pending.append(continuation)
        }
        switch result {
        case let .success(files): return files
        case let .failure(error): throw error
        }
    }

    func subfolders(of folder: URL) async throws(ListingError) -> [URL] { [] }

    func complete(_ index: Int, with result: Result<[MediaFile], ListingError>) {
        pending[index].resume(returning: result)
    }

    func waitForCalls(_ count: Int) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while pending.count < count && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(pending.count >= count)
    }
}

private actor FakeLister: DirectoryListing {
    struct Response: Sendable {
        var files: [MediaFile]
        var delay: Duration
        var error: ListingError?
    }

    private var responses: [URL: Response]
    /// Number of `mediaFiles(in:)` calls (used to verify the directory is not re-enumerated).
    private(set) var callCount = 0

    init(responses: [URL: Response]) {
        self.responses = responses
    }

    func setResponse(_ response: Response, for folder: URL) {
        responses[folder] = response
    }

    func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] {
        callCount += 1
        guard let response = responses[folder] else {
            throw ListingError.notFound
        }
        if response.delay != .zero {
            try? await Task.sleep(for: response.delay)
        }
        if let error = response.error {
            throw error
        }
        return response.files
    }

    func subfolders(of folder: URL) async throws(ListingError) -> [URL] {
        []
    }
}

private struct FakeDecoder: ImageDecoding {
    var animatedURLs: Set<URL> = []
    var failingURLs: Set<URL> = []

    func decode(_ url: URL, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        if failingURLs.contains(url) {
            throw DecodeError.corrupted
        }
        return Self.makeImage()
    }

    func isAnimated(_ url: URL) -> Bool {
        animatedURLs.contains(url)
    }

    func decode(data: Data, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        Self.makeImage()
    }

    func isAnimated(data: Data) -> Bool { false }

    private static func makeImage() -> DecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return DecodedImage(
            cgImage: context.makeImage()!,
            pixelSize: CGSize(width: 2, height: 2),
            originalPixelSize: CGSize(width: 2, height: 2),
            byteCost: 16
        )
    }
}
