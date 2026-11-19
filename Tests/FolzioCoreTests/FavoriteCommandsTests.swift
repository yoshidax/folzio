import Foundation
import Testing
@testable import FolzioCore

@Suite("FavoriteCommands")
struct FavoriteCommandsTests {
    private let folder = URL(fileURLWithPath: "/tmp/fav/folder")
    private let registered = URL(fileURLWithPath: "/tmp/fav/registered")
    private var favorites: FavoriteFolders { FavoriteFolders(urls: [registered]) }

    @Test("canAdd is true only for an unregistered .folder")
    func canAddOnlyForUnregisteredFolder() {
        #expect(FavoriteCommands.canAdd(.folder(folder), favorites: favorites))
        #expect(!FavoriteCommands.canAdd(.folder(registered), favorites: favorites))
        #expect(!FavoriteCommands.canAdd(.favorite(registered), favorites: favorites))
        #expect(!FavoriteCommands.canAdd(.favoritesHeader, favorites: favorites))
        #expect(!FavoriteCommands.canAdd(nil, favorites: favorites))
    }

    @Test("removalTarget returns a URL only for .favorite")
    func removalTargetOnlyForFavorite() {
        #expect(FavoriteCommands.removalTarget(.favorite(registered)) == registered)
        #expect(FavoriteCommands.removalTarget(.folder(folder)) == nil)
        #expect(FavoriteCommands.removalTarget(.favoritesHeader) == nil)
        #expect(FavoriteCommands.removalTarget(nil) == nil)
    }

    @Test("Folders share the common operation order and virtual favorites retain their menu")
    func contextMenuItems() {
        #expect(FavoriteCommands.contextMenu(for: .folder(folder)) == FolderContextMenu.items(allowsModification: false))
        #expect(FavoriteCommands.contextMenu(for: .favorite(registered)) == [.newFolder, .separator, .renameFavorite, .removeFromFavorites, .separator, .copyPathname])
        #expect(FavoriteCommands.contextMenu(for: .favoritesHeader).isEmpty)
    }

    @Test("pathnameTarget returns a URL for folders (including roots) and favorites, and nil otherwise (FR-182)")
    func pathnameTargetRoles() {
        #expect(FavoriteCommands.pathnameTarget(.folder(folder)) == folder)
        #expect(FavoriteCommands.pathnameTarget(.favorite(registered)) == registered)
        #expect(FavoriteCommands.pathnameTarget(.favoritesHeader) == nil)
        #expect(FavoriteCommands.pathnameTarget(nil) == nil)
    }

    @Test("Copy as Pathname is offered for every row role except the heading (FR-182)")
    func copyPathnameInContextMenus() {
        let roots = [URL(fileURLWithPath: "/test-homes/me")]
        for role in [TreeItemRole.folder(folder), .favorite(registered)] {
            #expect(FavoriteCommands.contextMenu(for: role, roots: roots).contains(.copyPathname))
        }
        #expect(!FavoriteCommands.contextMenu(for: .favoritesHeader, roots: roots).contains(.copyPathname))
    }

    // MARK: Renaming Favorites (FR-099)

    @Test("renameTarget returns favorites and non-root folders; roots, headings, and no selection return nil (FR-099, FR-103)")
    func renameTargetForFavoriteAndFolder() {
        let a = URL(fileURLWithPath: "/test-homes/me/a")
        #expect(FavoriteCommands.renameTarget(.favorite(a), roots: roots) == .favorite(a))
        #expect(FavoriteCommands.renameTarget(.folder(a), roots: roots) == .folder(a))
        #expect(FavoriteCommands.renameTarget(.folder(URL(fileURLWithPath: "/test-homes/me")), roots: roots) == nil)
        #expect(FavoriteCommands.renameTarget(.folder(URL(fileURLWithPath: "/")), roots: roots) == nil)
        #expect(FavoriteCommands.renameTarget(.favoritesHeader, roots: roots) == nil)
        #expect(FavoriteCommands.renameTarget(nil, roots: roots) == nil)
        #expect(FavoriteCommands.renameTarget(.folder(a), roots: []) == nil)
        #expect(FavoriteCommands.renameTarget(.favorite(a), roots: []) == .favorite(a))
    }

    @Test("Rename is absent from .folder menus including roots and from heading menus")
    func renameFavoriteIsOnlyInFavoriteMenu() {
        let a = URL(fileURLWithPath: "/test-homes/me/a")
        let root = URL(fileURLWithPath: "/test-homes/me")
        #expect(!FavoriteCommands.contextMenu(for: .folder(a), roots: roots).contains(.renameFavorite))
        #expect(!FavoriteCommands.contextMenu(for: .folder(root), roots: roots).contains(.renameFavorite))
        #expect(!FavoriteCommands.contextMenu(for: .folder(a)).contains(.renameFavorite))
        #expect(!FavoriteCommands.contextMenu(for: .favoritesHeader, roots: roots).contains(.renameFavorite))
    }

    @Test("Selection resolves the folder to display and returns nil for headings")
    func folderToShowForRoles() {
        #expect(FavoriteCommands.folderToShow(for: .folder(folder)) == folder)
        #expect(FavoriteCommands.folderToShow(for: .favorite(registered)) == registered)
        #expect(FavoriteCommands.folderToShow(for: .favoritesHeader) == nil)
    }

    @Test("Only .folder accepts drops and paste")
    func acceptsFilesOnlyForFolder() {
        #expect(FavoriteCommands.acceptsFiles(.folder(folder)))
        #expect(!FavoriteCommands.acceptsFiles(.favorite(registered)))
        #expect(!FavoriteCommands.acceptsFiles(.favoritesHeader))
    }

    // MARK: Moving Tree Folders to the Trash (FR-079)

    private let roots = [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/test-homes/me")]

    @Test("trashTarget returns regular folder URLs, including folders under volumes whose roots contain /")
    func trashTargetForOrdinaryFolder() {
        let home = URL(fileURLWithPath: "/test-homes/me/a")
        let volume = URL(fileURLWithPath: "/Volumes/Ext/a")
        #expect(FavoriteCommands.trashTarget(.folder(home), roots: roots) == home)
        #expect(FavoriteCommands.trashTarget(.folder(volume), roots: roots) == volume)
    }

    @Test("trashTarget is nil for roots, favorites, headings, no selection, and an empty roots list")
    func trashTargetIsNilForOthers() {
        let a = URL(fileURLWithPath: "/test-homes/me/a")
        #expect(FavoriteCommands.trashTarget(.folder(URL(fileURLWithPath: "/test-homes/me")), roots: roots) == nil)
        #expect(FavoriteCommands.trashTarget(.folder(URL(fileURLWithPath: "/")), roots: roots) == nil)
        #expect(FavoriteCommands.trashTarget(.folder(URL(fileURLWithPath: "/test-homes/me/")), roots: roots) == nil)
        #expect(FavoriteCommands.trashTarget(.favorite(a), roots: roots) == nil)
        #expect(FavoriteCommands.trashTarget(.favoritesHeader, roots: roots) == nil)
        #expect(FavoriteCommands.trashTarget(nil, roots: roots) == nil)
        #expect(FavoriteCommands.trashTarget(.folder(a), roots: []) == nil)
    }

    @Test("Only non-root folder menus offer Trash and Rename")
    func contextMenuProtection() {
        let a = URL(fileURLWithPath: "/test-homes/me/a")
        #expect(FavoriteCommands.contextMenu(for: .folder(a), roots: roots) == FolderContextMenu.items(allowsModification: true))
        #expect(FavoriteCommands.contextMenu(for: .folder(roots[1]), roots: roots) == FolderContextMenu.items(allowsModification: false))
        #expect(FavoriteCommands.contextMenu(for: .folder(a)) == FolderContextMenu.items(allowsModification: false))
    }
    // MARK: New folder (FR-208)

    @Test("newFolderTarget returns the folder for regular folders, roots, and favorites, and nil otherwise (FR-208)")
    func newFolderTargetRoles() {
        let root = URL(fileURLWithPath: "/test-homes/me")
        #expect(FavoriteCommands.newFolderTarget(.folder(folder)) == folder)
        #expect(FavoriteCommands.newFolderTarget(.folder(root)) == root)
        #expect(FavoriteCommands.newFolderTarget(.favorite(registered)) == registered)
        #expect(FavoriteCommands.newFolderTarget(.favoritesHeader) == nil)
        #expect(FavoriteCommands.newFolderTarget(nil) == nil)
    }

    @Test("New Folder is retained only for virtual favorite menus")
    func newFolderMenuScope() {
        #expect(!FavoriteCommands.contextMenu(for: .folder(folder), roots: roots).contains(.newFolder))
        #expect(FavoriteCommands.contextMenu(for: .favorite(registered)).first == .newFolder)
    }
}
