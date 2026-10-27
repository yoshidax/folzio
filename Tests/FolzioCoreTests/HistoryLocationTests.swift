import Foundation
import Testing
@testable import FolzioCore

@Suite("HistoryLocation")
struct HistoryLocationTests {
    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    private func state(
        displayMode: DisplayMode = .list,
        thumbnailSize: Double = 128,
        paneLayout: PaneLayout = .all,
        filter: MediaTypeFilter = MediaTypeFilter(),
        showsZipFiles: Bool = false
    ) -> HistoryViewState {
        HistoryViewState(
            presentation: HistoryPresentation(
                displayMode: displayMode,
                thumbnailSize: thumbnailSize,
                paneLayout: paneLayout
            ),
            mediaTypeFilter: filter,
            showsZipFiles: showsZipFiles
        )
    }

    @Test("Compares locations ignoring a trailing /, ., and .., and distinguishes different locations")
    func equalityNormalizesPaths() {
        #expect(HistoryLocation(folder: folder("/tmp/h/A")) == HistoryLocation(folder: folder("/tmp/h/A/")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A")) == HistoryLocation(folder: folder("/tmp/h/./A")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A")) == HistoryLocation(folder: folder("/tmp/h/x/../A")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A")) != HistoryLocation(folder: folder("/tmp/h/B")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A")) != HistoryLocation(folder: folder("/tmp/h/A2")))
    }

    @Test("Treats a regular folder and a location inside a zip as different")
    func equalitySeparatesArchive() {
        let normal = HistoryLocation(folder: folder("/tmp/h/A"))
        let archive = HistoryLocation(
            folder: folder("/tmp/h/A"),
            archive: ArchiveLocation(archive: file("/tmp/h/A/t.zip"), directory: "d/")
        )
        #expect(normal != archive)
        #expect(archive == HistoryLocation(
            folder: folder("/tmp/h/A"),
            archive: ArchiveLocation(archive: file("/tmp/h/A/./t.zip"), directory: "d/")
        ))
        #expect(archive != HistoryLocation(
            folder: folder("/tmp/h/A"),
            archive: ArchiveLocation(archive: file("/tmp/h/A/t.zip"), directory: "e/")
        ))
    }

    @Test("Compares paths that do not exist")
    func equalityDoesNotNeedExistingPaths() {
        #expect(HistoryLocation(folder: folder("/tmp/n/missing")) == HistoryLocation(folder: folder("/tmp/n/missing/")))
        #expect(HistoryLocation(folder: folder("/tmp/n/missing")) != HistoryLocation(folder: folder("/tmp/n/other")))
    }

    @Test("isWithin matches itself and descendants without confusing siblings with a shared prefix")
    func isWithinUsesPathComponents() {
        let photo = HistoryLocation(folder: folder("/tmp/h/Photo"))
        #expect(photo.isWithin(folder("/tmp/h/Photos")) == false)
        #expect(photo.isWithin(folder("/tmp/h/Photo")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A/B")).isWithin(folder("/tmp/h/A")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A/B")).isWithin(folder("/tmp/h/A/B")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A/B")).isWithin(folder("/tmp/h/A/B/C")) == false)
        #expect(HistoryLocation(folder: folder("/tmp/h/A")).isWithin(folder("/")) == true)
        #expect(HistoryLocation(folder: folder("/tmp/h/A")).isWithin(folder("/tmp/other")) == false)
    }

    @Test("For a location inside a zip, determines containment from the zip file")
    func isWithinArchiveUsesArchiveFile() {
        let location = HistoryLocation(
            folder: folder("/tmp/h/A"),
            archive: ArchiveLocation(archive: file("/tmp/h/A/t.zip"), directory: "d/")
        )
        #expect(location.isWithin(file("/tmp/h/A/t.zip")))
        #expect(location.isWithin(folder("/tmp/h/A")))
        #expect(location.isWithin(file("/tmp/h/A/t.zip/child")) == false)
        #expect(location.isWithin(folder("/tmp/h/Other")) == false)
        #expect(location.isWithin(folder("/")) == true)
    }

    @Test("rebased rebases both the folder and the zip")
    func rebasedFollowsRename() {
        let renamed = RenamedFolder(from: folder("/tmp/h/A"), to: folder("/tmp/h/A2"))
        #expect(HistoryLocation(folder: folder("/tmp/h/A")).rebased(by: renamed)
            == HistoryLocation(folder: folder("/tmp/h/A2")))
        #expect(HistoryLocation(folder: folder("/tmp/h/A/B")).rebased(by: renamed)
            == HistoryLocation(folder: folder("/tmp/h/A2/B")))
        #expect(HistoryLocation(
            folder: folder("/tmp/h/A"),
            archive: ArchiveLocation(archive: file("/tmp/h/A/t.zip"), directory: "d/")
        ).rebased(by: renamed) == HistoryLocation(
            folder: folder("/tmp/h/A2"),
            archive: ArchiveLocation(archive: file("/tmp/h/A2/t.zip"), directory: "d/")
        ))
        #expect(HistoryLocation(folder: folder("/tmp/h/Other")).rebased(by: renamed) == nil)
        #expect(HistoryLocation(folder: folder("/tmp/h/A3")).rebased(by: renamed) == nil)
    }

    @Test("hasSameState compares only the location and presentation state")
    func hasSameStateIgnoresFocus() {
        let location = HistoryLocation(folder: folder("/tmp/h/A"))
        let base = HistoryEntry(location: location, viewState: state())
        let focused = HistoryEntry(location: location, viewState: state(), focusedItem: file("/tmp/h/A/1.jpg"))
        #expect(base.hasSameState(as: focused))

        let variations = [
            HistoryViewState(
                presentation: HistoryPresentation(displayMode: .thumbnails, thumbnailSize: 128, paneLayout: .all),
                mediaTypeFilter: MediaTypeFilter(),
                showsZipFiles: false
            ),
            HistoryViewState(
                presentation: HistoryPresentation(displayMode: .list, thumbnailSize: 256, paneLayout: .all),
                mediaTypeFilter: MediaTypeFilter(),
                showsZipFiles: false
            ),
            HistoryViewState(
                presentation: HistoryPresentation(displayMode: .list, thumbnailSize: 128, paneLayout: .previewOnly),
                mediaTypeFilter: MediaTypeFilter(),
                showsZipFiles: false
            ),
            HistoryViewState(
                presentation: HistoryPresentation(displayMode: .list, thumbnailSize: 128, paneLayout: .all),
                mediaTypeFilter: MediaTypeFilter(imagesOnly: true),
                showsZipFiles: false
            ),
            HistoryViewState(
                presentation: HistoryPresentation(displayMode: .list, thumbnailSize: 128, paneLayout: .all),
                mediaTypeFilter: MediaTypeFilter(),
                showsZipFiles: true
            ),
        ]
        for variation in variations {
            #expect(base.hasSameState(as: HistoryEntry(location: location, viewState: variation)) == false)
        }
    }
}
