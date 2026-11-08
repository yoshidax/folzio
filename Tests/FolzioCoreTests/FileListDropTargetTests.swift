import Foundation
import Testing
@testable import FolzioCore

@Suite("File list drop target")
struct FileListDropTargetTests {
    private func resolve(
        _ kind: ListItemKind?,
        index: Int? = 3,
        isBrowsingArchive: Bool = false,
        isShowingSearchResults: Bool = false,
        state: FolderListing.State = .loaded
    ) -> FileListDropTarget? {
        FileListDropTarget.resolve(
            kind: kind,
            index: kind == nil ? nil : index,
            isBrowsingArchive: isBrowsingArchive,
            isShowingSearchResults: isShowingSearchResults,
            state: state
        )
    }

    @Test("A folder item is the destination itself (FR-163)")
    func folderItem() {
        #expect(resolve(.folder) == .folder(3))
        // Folder rows of search results stay destinations (FR-087).
        #expect(resolve(.folder, isShowingSearchResults: true) == .folder(3))
    }

    @Test("Files, zip files, and empty space go into the displayed folder (FR-349, A-207)")
    func backgroundGoesToDisplayedFolder() {
        #expect(resolve(.media(.jpeg)) == .displayedFolder)
        #expect(resolve(.media(.mp4)) == .displayedFolder)
        #expect(resolve(.archive) == .displayedFolder)
        #expect(resolve(nil) == .displayedFolder)
        // A listing that is loading, empty, or filtered to nothing still has a destination folder.
        #expect(resolve(nil, state: .loading) == .displayedFolder)
        #expect(resolve(nil, state: .empty) == .displayedFolder)
        #expect(resolve(nil, state: .noMatches) == .displayedFolder)
    }

    @Test("The `..` row takes no drops (FR-163)")
    func parentRow() {
        #expect(resolve(.parent) == nil)
    }

    @Test("Nothing inside a zip takes drops, including its directories (FR-073)")
    func insideArchive() {
        #expect(resolve(.directory, isBrowsingArchive: true) == nil)
        #expect(resolve(.media(.jpeg), isBrowsingArchive: true) == nil)
        #expect(resolve(nil, isBrowsingArchive: true) == nil)
        #expect(resolve(.parent, isBrowsingArchive: true) == nil)
    }

    @Test("Search results and unreadable folders have no displayed folder to drop into (FR-087, FR-349)")
    func noDisplayedFolder() {
        #expect(resolve(nil, isShowingSearchResults: true) == nil)
        #expect(resolve(.media(.jpeg), isShowingSearchResults: true) == nil)
        #expect(resolve(nil, state: .denied) == nil)
        #expect(resolve(nil, state: .failed(.folderNotFound)) == nil)
        #expect(resolve(.media(.jpeg), state: .failed(.systemFailure(systemReason: "x"))) == nil)
    }
}
