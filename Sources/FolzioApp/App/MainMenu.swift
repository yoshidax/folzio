import AppKit
import FolzioCore
import FolzioLocalization

/// Refreshes File and Edit menu state when AppKit requests an update. The tree can change the Trash title during
/// validation, and the Open With submenu depends on the current file list selection.
@MainActor
private final class FileMenuUpdater: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(FileListViewController.moveToTrash(_:)) {
            item.title = l10n.text(.menuFileTrash)
        }
        if menu.identifier?.rawValue == "menu.file",
           let openWithItem = menu.items.first(where: { $0.identifier?.rawValue == "localization.\(TextKey.menuFileOpenWith.rawValue)" }) {
            let target = NSApp.target(forAction: #selector(FileListViewController.open(_:)), to: nil, from: nil)
                as? FileListViewController
            target?.updateOpenWithMenu(openWithItem)
            if target == nil {
                openWithItem.submenu?.removeAllItems()
                openWithItem.isEnabled = false
            }
        }
    }
}

@MainActor
final class MainMenu {
    /// Retained because NSMenu.delegate is weak.
    private static let fileMenuUpdater = FileMenuUpdater()

    static func bind(_ item: NSMenuItem, _ key: TextKey) {
        item.identifier = NSUserInterfaceItemIdentifier("localization.\(key.rawValue)")
    }

    static func refreshTitles(in menu: NSMenu? = NSApp.mainMenu) {
        guard let menu else { return }
        for item in menu.items {
            if let identifier = item.identifier?.rawValue,
               identifier.hasPrefix("localization."),
               let key = TextKey(rawValue: String(identifier.dropFirst("localization.".count))) {
                item.title = l10n.text(key)
                item.submenu?.title = item.title
            }
            refreshTitles(in: item.submenu)
        }
    }

    /// `zoomTarget` is the target of Zoom In, Zoom Out, and Zoom to Fit in the View menu.
    /// Passed explicitly so the actions operate on the main window's preview regardless of which window has key
    /// focus (FR-135, A-73).
    static func install(zoomTarget: AppDelegate) {
        let mainMenu = MainApplicationMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Folzio")
        appMenu.identifier = NSUserInterfaceItemIdentifier("menu.app")
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: l10n.text(.menuAppAbout),
            action: #selector(AppDelegate.showAbout(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = nil
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: l10n.text(.menuAppSettings),
            action: #selector(AppDelegate.showSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = nil
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: l10n.text(.menuAppQuit),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: l10n.text(.menuFile))
        fileMenu.identifier = NSUserInterfaceItemIdentifier("menu.file")
        fileMenuItem.submenu = fileMenu

        // ⇧⌘N, as in Finder. Both FileListViewController and DirectoryTreeViewController implement newFolder(_:); the
        // responder chain sends it to the focused pane, which decides the destination (FR-208, research.md R6).
        let newFolderItem = NSMenuItem(
            title: l10n.text(.menuFileNewFolder),
            action: #selector(FileListViewController.newFolder(_:)),
            keyEquivalent: "N"
        )
        newFolderItem.keyEquivalentModifierMask = [.command]
        newFolderItem.target = nil
        fileMenu.addItem(newFolderItem)
        fileMenu.addItem(.separator())

        let openItem = NSMenuItem(
            title: l10n.text(.menuFileOpen),
            action: #selector(FileListViewController.open(_:)),
            keyEquivalent: "o"
        )
        openItem.target = nil
        fileMenu.addItem(openItem)

        let openWithItem = NSMenuItem(title: l10n.text(.menuFileOpenWith), action: nil, keyEquivalent: "")
        openWithItem.submenu = NSMenu(title: openWithItem.title)
        fileMenu.addItem(openWithItem)

        let openContainerItem = NSMenuItem(
            title: l10n.text(.menuFileShowContents),
            action: #selector(FileListViewController.openFocusedItem(_:)),
            keyEquivalent: String(UnicodeScalar(NSDownArrowFunctionKey)!)
        )
        openContainerItem.keyEquivalentModifierMask = [.command]
        openContainerItem.target = nil
        fileMenu.addItem(openContainerItem)

        let goUpItem = NSMenuItem(
            title: l10n.text(.menuFileEnclosingFolder),
            action: #selector(FileListViewController.goToEnclosingLevel(_:)),
            keyEquivalent: String(UnicodeScalar(NSUpArrowFunctionKey)!)
        )
        goUpItem.keyEquivalentModifierMask = [.command]
        goUpItem.target = nil
        fileMenu.addItem(goUpItem)

        let revealItem = NSMenuItem(
            title: l10n.text(.menuFileRevealInFinder),
            action: #selector(FileListViewController.revealInFinder(_:)),
            keyEquivalent: ""
        )
        revealItem.target = nil
        fileMenu.addItem(revealItem)

        let addFavoriteItem = NSMenuItem(
            title: l10n.text(.menuFileAddToFavorites),
            action: #selector(MainSplitViewController.addSelectedFolderToFavorites(_:)),
            keyEquivalent: "t"
        )
        addFavoriteItem.keyEquivalentModifierMask = [.command, .control]
        addFavoriteItem.target = nil
        fileMenu.addItem(addFavoriteItem)

        // ⌥⌘F. Distinguished from ⌘F (Filter by Name), ⇧⌘F (Go to Favorites), and ⌃⌘F (full screen) by modifiers
        // (FR-080, R39). The keys of the two search commands were swapped in TAK-86.
        let searchItem = NSMenuItem(
            title: l10n.text(.menuFileFind),
            action: #selector(MainSplitViewController.showSearch(_:)),
            keyEquivalent: "f"
        )
        searchItem.keyEquivalentModifierMask = [.option, .command]
        searchItem.target = nil
        fileMenu.addItem(searchItem)

        // ⌘F. Moves the focus to the toolbar name filter field (FR-391).
        let filterByNameItem = NSMenuItem(
            title: l10n.text(.menuFileFilterByName),
            action: #selector(MainSplitViewController.filterByName(_:)),
            keyEquivalent: "f"
        )
        filterByNameItem.keyEquivalentModifierMask = [.command]
        filterByNameItem.target = nil
        fileMenu.addItem(filterByNameItem)
        let shortcutsItem = NSMenuItem(
            title: l10n.text(.menuFileShortcuts),
            action: #selector(AppDelegate.showShortcuts(_:)),
            keyEquivalent: "/"
        )
        shortcutsItem.keyEquivalentModifierMask = [.command]
        shortcutsItem.target = zoomTarget
        fileMenu.addItem(shortcutsItem)
        fileMenu.addItem(.separator())

        let fileTrashItem = NSMenuItem(
            title: l10n.text(.menuFileTrash),
            action: #selector(FileListViewController.moveToTrash(_:)),
            keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!)
        )
        fileTrashItem.target = nil
        fileMenu.addItem(fileTrashItem)
        fileMenu.delegate = fileMenuUpdater
        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(
            title: l10n.text(.menuFileClose),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = nil
        fileMenu.addItem(closeItem)

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: l10n.text(.menuEdit))
        editMenu.identifier = NSUserInterfaceItemIdentifier("menu.edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(NSMenuItem(
            title: l10n.text(.menuEditUndo),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))
        let redoItem = NSMenuItem(
            title: l10n.text(.menuEditRedo),
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(
            title: l10n.text(.menuEditCut),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))
        editMenu.addItem(NSMenuItem(
            title: l10n.text(.menuEditCopy),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        editMenu.addItem(NSMenuItem(
            title: l10n.text(.menuEditPaste),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))

        let movePasteItem = NSMenuItem(
            title: l10n.text(.menuEditMovePaste),
            action: #selector(FileListViewController.movePaste(_:)),
            keyEquivalent: "v"
        )
        movePasteItem.keyEquivalentModifierMask = [.command, .option]
        movePasteItem.target = nil
        editMenu.addItem(movePasteItem)
        let cancelReceiving = NSMenuItem(title: l10n.cancelReceivingTitle,
            action: #selector(ImportSessionManager.cancelReceiving(_:)), keyEquivalent: ".")
        cancelReceiving.keyEquivalentModifierMask = [.command]
        cancelReceiving.target = ImportSessionManager.shared
        editMenu.addItem(cancelReceiving)

        // Both FileListViewController and DirectoryTreeViewController implement copyPathname(_:); the responder
        // chain picks the focused pane's (FR-184).
        let copyPathnameItem = NSMenuItem(
            title: l10n.text(.menuEditCopyPathname),
            action: #selector(FileListViewController.copyPathname(_:)),
            keyEquivalent: "c"
        )
        copyPathnameItem.keyEquivalentModifierMask = [.command, .option]
        copyPathnameItem.target = nil
        editMenu.addItem(copyPathnameItem)
        editMenu.addItem(.separator())

        let duplicateItem = NSMenuItem(
            title: l10n.text(.menuEditDuplicate),
            action: #selector(FileListViewController.duplicate(_:)),
            keyEquivalent: "d"
        )
        duplicateItem.target = nil
        editMenu.addItem(duplicateItem)

        let renameItem = NSMenuItem(
            title: l10n.text(.menuEditRename),
            action: #selector(FileListViewController.rename(_:)),
            keyEquivalent: "\r"
        )
        renameItem.keyEquivalentModifierMask = []
        renameItem.target = nil
        editMenu.addItem(renameItem)

        let editTrashItem = NSMenuItem(
            title: l10n.text(.menuFileTrash),
            action: #selector(FileListViewController.moveToTrash(_:)),
            keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!)
        )
        editTrashItem.target = nil
        editMenu.addItem(editTrashItem)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(
            title: l10n.text(.menuEditSelectAll),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))
        editMenu.delegate = fileMenuUpdater

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: l10n.text(.menuView))
        viewMenu.identifier = NSUserInterfaceItemIdentifier("menu.view")
        viewMenuItem.submenu = viewMenu

        let toolbarItem = NSMenuItem(
            title: l10n.text(.menuViewShowToolbar),
            action: #selector(MainWindowController.toggleMainToolbar(_:)),
            keyEquivalent: "T"
        )
        toolbarItem.target = nil
        viewMenu.addItem(toolbarItem)
        viewMenu.addItem(.separator())

        let fullScreenItem = NSMenuItem(
            title: l10n.text(.menuViewFullScreen),
            action: #selector(MainSplitViewController.togglePreviewFullScreen),
            keyEquivalent: "f"
        )
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        fullScreenItem.target = nil
        viewMenu.addItem(fullScreenItem)
        viewMenu.addItem(.separator())

        // Preview zoom (FR-135). ⌘+ includes Shift in the `+` keystroke.
        let zoomInItem = NSMenuItem(
            title: l10n.text(.menuViewZoomIn),
            action: #selector(AppDelegate.previewZoomIn(_:)),
            keyEquivalent: "+"
        )
        zoomInItem.keyEquivalentModifierMask = [.command]
        zoomInItem.target = zoomTarget
        viewMenu.addItem(zoomInItem)

        // Also zoom in with ⌘= without Shift (A-72). Keep it hidden so the displayed shortcut stays ⌘+.
        // A hidden item does not respond to its key equivalent unless allowsKeyEquivalentWhenHidden is true.
        let zoomInAlternateItem = NSMenuItem(
            title: l10n.text(.menuViewZoomIn),
            action: #selector(AppDelegate.previewZoomIn(_:)),
            keyEquivalent: "="
        )
        zoomInAlternateItem.keyEquivalentModifierMask = [.command]
        zoomInAlternateItem.target = zoomTarget
        zoomInAlternateItem.isHidden = true
        zoomInAlternateItem.allowsKeyEquivalentWhenHidden = true
        viewMenu.addItem(zoomInAlternateItem)

        let zoomOutItem = NSMenuItem(
            title: l10n.text(.menuViewZoomOut),
            action: #selector(AppDelegate.previewZoomOut(_:)),
            keyEquivalent: "-"
        )
        zoomOutItem.keyEquivalentModifierMask = [.command]
        zoomOutItem.target = zoomTarget
        viewMenu.addItem(zoomOutItem)

        let zoomToFitItem = NSMenuItem(
            title: l10n.text(.menuViewZoomToFit),
            action: #selector(AppDelegate.previewZoomToFit(_:)),
            keyEquivalent: "0"
        )
        zoomToFitItem.keyEquivalentModifierMask = [.command]
        zoomToFitItem.target = zoomTarget
        viewMenu.addItem(zoomToFitItem)

        // An uppercase S makes this ⇧⌘S.
        let slideshowItem = NSMenuItem(
            title: l10n.text(.menuViewStartSlideshow),
            action: #selector(MainSplitViewController.startSlideshow(_:)),
            keyEquivalent: "S"
        )
        slideshowItem.keyEquivalentModifierMask = [.command]
        slideshowItem.target = nil
        viewMenu.addItem(slideshowItem)

        let navigateMenuItem = NSMenuItem()
        mainMenu.addItem(navigateMenuItem)
        let navigateMenu = NSMenu(title: l10n.text(.menuGo))
        navigateMenu.identifier = NSUserInterfaceItemIdentifier("menu.go")
        navigateMenuItem.submenu = navigateMenu

        let backItem = NSMenuItem(
            title: l10n.text(.menuGoBack),
            action: #selector(MainSplitViewController.goBack(_:)),
            keyEquivalent: "["
        )
        backItem.target = nil
        navigateMenu.addItem(backItem)

        let forwardItem = NSMenuItem(
            title: l10n.text(.menuGoForward),
            action: #selector(MainSplitViewController.goForward(_:)),
            keyEquivalent: "]"
        )
        forwardItem.target = nil
        navigateMenu.addItem(forwardItem)

        let bindings: [(NSMenuItem, TextKey)] = [
            (aboutItem, .menuAppAbout), (settingsItem, .menuAppSettings), (quitItem, .menuAppQuit),
            (fileMenuItem, .menuFile), (newFolderItem, .menuFileNewFolder), (openItem, .menuFileOpen),
            (openWithItem, .menuFileOpenWith),
            (openContainerItem, .menuFileShowContents), (goUpItem, .menuFileEnclosingFolder),
            (revealItem, .menuFileRevealInFinder), (addFavoriteItem, .menuFileAddToFavorites),
            (searchItem, .menuFileFind), (filterByNameItem, .menuFileFilterByName), (fileTrashItem, .menuFileTrash),
            (shortcutsItem, .menuFileShortcuts), (closeItem, .menuFileClose),
            (editMenuItem, .menuEdit), (redoItem, .menuEditRedo),
            (movePasteItem, .menuEditMovePaste), (cancelReceiving, .menuCancelReceiving),
            (copyPathnameItem, .menuEditCopyPathname), (duplicateItem, .menuEditDuplicate),
            (renameItem, .menuEditRename), (editTrashItem, .menuFileTrash),
            (viewMenuItem, .menuView), (toolbarItem, .menuViewShowToolbar),
            (fullScreenItem, .menuViewFullScreen), (zoomInItem, .menuViewZoomIn),
            (zoomInAlternateItem, .menuViewZoomIn), (zoomOutItem, .menuViewZoomOut),
            (zoomToFitItem, .menuViewZoomToFit), (slideshowItem, .menuViewStartSlideshow),
            (navigateMenuItem, .menuGo), (backItem, .menuGoBack), (forwardItem, .menuGoForward),
        ]
        for (item, key) in bindings { bind(item, key) }

        // Keys come from the shortcut assignments, not from the literals above (FR-261). Return (Rename) and the
        // app and system keys (⌘Q, ⌘W, ⌘,, and the Edit menu basics) are not customizable (FR-256).
        let shortcutBindings: [(NSMenuItem, ShortcutCommandID)] = [
            (newFolderItem, .newFolder), (openItem, .open), (openContainerItem, .showContents),
            (goUpItem, .enclosingFolder), (addFavoriteItem, .addToFavorites), (searchItem, .find),
            (filterByNameItem, .filterByName),
            (shortcutsItem, .shortcuts), (fileTrashItem, .trash), (editTrashItem, .trash),
            (movePasteItem, .movePaste), (copyPathnameItem, .copyPathname), (duplicateItem, .duplicate),
            (toolbarItem, .toolbar), (fullScreenItem, .fullScreen), (zoomInItem, .zoomIn), (zoomOutItem, .zoomOut),
            (zoomToFitItem, .zoomToFit), (slideshowItem, .startSlideshow), (backItem, .back), (forwardItem, .forward),
        ]
        for (item, command) in shortcutBindings {
            MenuShortcutApplier.shared.register(item, for: command)
        }
        MenuShortcutApplier.shared.register(zoomInAlternateItem, for: .zoomIn, isAlternate: true)
        let editBindings: [(Selector, TextKey)] = [
            (Selector(("undo:")), .menuEditUndo), (#selector(NSText.cut(_:)), .menuEditCut),
            (#selector(NSText.copy(_:)), .menuEditCopy), (#selector(NSText.paste(_:)), .menuEditPaste),
            (#selector(NSText.selectAll(_:)), .menuEditSelectAll),
        ]
        for (action, key) in editBindings {
            if let item = editMenu.items.first(where: { $0.action == action }) { bind(item, key) }
        }
        NSApp.mainMenu = mainMenu
    }
}
