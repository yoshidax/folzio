import Foundation
import Testing
@testable import FolzioCore

@Suite("Folder context menu policy")
struct FolderContextMenuTests {
    let parent = URL(fileURLWithPath: "/folders")
    var a: URL { parent.appendingPathComponent("a") }
    var b: URL { parent.appendingPathComponent("b") }

    func item(_ url: URL, _ kind: ListItemKind = .folder) -> MediaFile {
        MediaFile(url: url, name: url.lastPathComponent, kind: kind, typeDescription: "", creationDate: nil, fileSize: 0)
    }

    @Test("A context paste targets the clicked folder while keys and the background target the displayed folder")
    func pasteRoutes() {
        let policy = FolderContextMenu(files: [item(a), item(b)], targets: [a], isBrowsingArchive: false, roots: [parent])
        #expect(policy.singleFolder == a)
        #expect(policy.pasteDestination(isItemMenu: true, displayedFolder: parent, isShowingSearchResults: false) == a)
        #expect(policy.pasteDestination(isItemMenu: false, displayedFolder: parent, isShowingSearchResults: false) == parent)
        #expect(policy.pasteDestination(isItemMenu: true, displayedFolder: parent, isShowingSearchResults: true) == a)
        #expect(policy.pasteDestination(isItemMenu: false, displayedFolder: parent, isShowingSearchResults: true) == nil)
    }

    @Test("Multiple folders, mixed items, and missing targets never fall back to the displayed folder")
    func invalidPasteTargets() {
        for files in [[item(a), item(b)], [item(a), item(b, .media(.png))] ] {
            let policy = FolderContextMenu(files: files, targets: [a, b], isBrowsingArchive: false, roots: [parent])
            #expect(policy.singleFolder == nil)
            #expect(policy.pasteDestination(isItemMenu: true, displayedFolder: parent, isShowingSearchResults: false) == nil)
        }
        let stale = FolderContextMenu(files: [item(b)], targets: [a], isBrowsingArchive: false, roots: [parent])
        #expect(stale.pasteDestination(isItemMenu: true, displayedFolder: parent, isShowingSearchResults: false) == nil)
    }

    @Test("Parent rows count toward the full selection and archive directories are not real folders")
    func nonFolderTargets() {
        for kind in [ListItemKind.parent, .directory, .archive] {
            let policy = FolderContextMenu(files: [item(a), item(b, kind)], targets: [a, b], isBrowsingArchive: false, roots: [parent])
            #expect(policy.singleFolder == nil)
            #expect(!policy.onlyFolders)
        }
        let archive = FolderContextMenu(files: [item(a)], targets: [a], isBrowsingArchive: true, roots: [parent])
        #expect(archive.singleFolder == nil)
        #expect(archive.pasteDestination(isItemMenu: true, displayedFolder: parent, isShowingSearchResults: false) == nil)
        #expect(archive.pasteDestination(isItemMenu: false, displayedFolder: parent, isShowingSearchResults: false) == nil)
    }

    @Test("Item menus without folders keep pasting into the displayed folder, except in search results and zips")
    func nonFolderItemPaste() {
        let media = parent.appendingPathComponent("c.png")
        for kind in [ListItemKind.media(.png), .archive, .parent] {
            let policy = FolderContextMenu(files: [item(media, kind)], targets: [media], isBrowsingArchive: false, roots: [parent])
            #expect(policy.pasteDestination(isItemMenu: true, displayedFolder: parent, isShowingSearchResults: false) == parent)
            #expect(policy.pasteDestination(isItemMenu: true, displayedFolder: parent, isShowingSearchResults: true) == nil)
        }
        let none = FolderContextMenu(files: [], targets: [], isBrowsingArchive: true, roots: [parent])
        #expect(none.pasteDestination(isItemMenu: false, displayedFolder: parent, isShowingSearchResults: false) == nil)
    }

    @Test("Root protection applies to mixed selections and ordinary folders share one ordered menu")
    func rootAndOrder() {
        let root = FolderContextMenu(files: [item(parent), item(a, .archive)], targets: [parent, a], isBrowsingArchive: false, roots: [parent])
        #expect(root.containsProtectedFolder)
        let common: [TreeContextMenuItem] = [.pasteHere, .movePasteHere, .separator, .moveToTrash, .separator,
            .renameFolder, .duplicate, .separator, .copy, .copyPathname, .separator, .addToFavorites, .separator, .revealInFinder]
        #expect(FolderContextMenu.items(allowsModification: true) == common)
        let protected = FolderContextMenu.items(allowsModification: false)
        #expect(!protected.contains(.moveToTrash))
        #expect(!protected.contains(.renameFolder))
        #expect(protected.contains(.copy) && protected.contains(.duplicate))
        #expect(!protected.contains(.newFolder))
        #expect(protected.first != .separator && protected.last != .separator)
    }

    @Test("Tree copying includes roots but rejects virtual rows as a whole")
    func treeTargets() {
        #expect(TreeBatchTargets(selection: [.folder(parent), .folder(a)]).folderURLs == [parent, a])
        #expect(TreeBatchTargets(selection: [.folder(a), .favorite(b)]).folderURLs == nil)
        #expect(TreeBatchTargets(selection: [.favoritesHeader]).folderURLs == nil)
        #expect(TreeBatchTargets(selection: []).folderURLs == nil)
    }

    @Test("Both folder menus use the tree protection rules, including out-of-root folders")
    func sharedProtection() {
        for url in [parent, a, URL(fileURLWithPath: "/folders-other/a")] {
            let policy = FolderContextMenu(files: [item(url)], targets: [url], isBrowsingArchive: false, roots: [parent])
            #expect(policy.containsProtectedFolder == (FavoriteCommands.trashTarget(.folder(url), roots: [parent]) == nil))
        }
    }
}
