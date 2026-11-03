import Foundation
import Testing
@testable import FolzioCore

@Suite("QuickLookTargets")
struct QuickLookTargetsTests {
    private static func file(_ name: String, _ kind: ListItemKind, url: URL? = nil) -> MediaFile {
        MediaFile(
            url: url ?? URL(fileURLWithPath: "/tmp/folder/\(name)"),
            name: name,
            kind: kind,
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
    }

    private static let files: [MediaFile] = [
        file("sub", .folder),
        file("a.jpg", .media(.jpeg)),
        file("b.zip", .archive),
        file("c.mov", .media(.mov)),
        file("d.png", .media(.png)),
    ]

    private static func urls(_ names: String...) -> Set<URL> {
        Set(names.map { URL(fileURLWithPath: "/tmp/folder/\($0)") })
    }

    // MARK: - Targets

    @Test("A single selected image or video is the only target")
    func singleSelection() {
        let image = QuickLookTargets.urls(files: Self.files, selected: Self.urls("a.jpg"), isBrowsingArchive: false)
        let video = QuickLookTargets.urls(files: Self.files, selected: Self.urls("c.mov"), isBrowsingArchive: false)
        #expect(image == [URL(fileURLWithPath: "/tmp/folder/a.jpg")])
        #expect(video == [URL(fileURLWithPath: "/tmp/folder/c.mov")])
    }

    @Test("Multiple selected media are returned in listing order, not selection order")
    func listingOrder() {
        let result = QuickLookTargets.urls(
            files: Self.files, selected: Self.urls("d.png", "a.jpg", "c.mov"), isBrowsingArchive: false
        )
        #expect(result.map(\.lastPathComponent) == ["a.jpg", "c.mov", "d.png"])
    }

    @Test("Folders and zip files in the selection are excluded")
    func mixedSelection() {
        let result = QuickLookTargets.urls(
            files: Self.files, selected: Self.urls("sub", "a.jpg", "b.zip"), isBrowsingArchive: false
        )
        #expect(result.map(\.lastPathComponent) == ["a.jpg"])
    }

    // MARK: - Empty Results

    @Test("A selection without media, or no selection, returns nothing")
    func noMedia() {
        #expect(QuickLookTargets.urls(files: Self.files, selected: Self.urls("sub", "b.zip"), isBrowsingArchive: false).isEmpty)
        #expect(QuickLookTargets.urls(files: Self.files, selected: [], isBrowsingArchive: false).isEmpty)
    }

    @Test("Selected URLs that are not in the listing are ignored")
    func missingFromListing() {
        let result = QuickLookTargets.urls(files: Self.files, selected: Self.urls("gone.jpg"), isBrowsingArchive: false)
        #expect(result.isEmpty)
    }

    @Test("Nothing is returned while browsing a zip (A-150)")
    func insideArchive() {
        let archive = URL(fileURLWithPath: "/tmp/folder/b.zip")
        let entry = ArchiveURL.entry(archive: archive, path: "x.jpg")
        let files = [Self.file("x.jpg", .media(.jpeg), url: entry)]
        #expect(QuickLookTargets.urls(files: files, selected: [entry], isBrowsingArchive: true).isEmpty)
    }

    @Test("An archive entry URL is excluded even when the listing is not flagged as a zip")
    func archiveEntryURLInRegularListing() {
        let archive = URL(fileURLWithPath: "/tmp/folder/b.zip")
        let entry = ArchiveURL.entry(archive: archive, path: "x.jpg")
        let files = [Self.file("x.jpg", .media(.jpeg), url: entry)]
        #expect(QuickLookTargets.urls(files: files, selected: [entry], isBrowsingArchive: false).isEmpty)
    }

    // MARK: - Default App

    @Test("Only media outside a zip opens in the default app on double-click")
    func opensInDefaultApp() {
        #expect(ListItemKind.media(.jpeg).opensInDefaultApp(isBrowsingArchive: false))
        #expect(ListItemKind.media(.mov).opensInDefaultApp(isBrowsingArchive: false))
        #expect(!ListItemKind.media(.jpeg).opensInDefaultApp(isBrowsingArchive: true))
        for kind in [ListItemKind.archive, .folder, .directory, .parent] {
            #expect(!kind.opensInDefaultApp(isBrowsingArchive: false))
            #expect(!kind.opensInDefaultApp(isBrowsingArchive: true))
        }
    }
}
