import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
final class FileContextMenu: NSObject, NSMenuDelegate {
    let menu: NSMenu

    private weak var host: FileListViewController?
    private let copyItem = NSMenuItem()
    private let pasteItem = NSMenuItem()
    private let movePasteItem = NSMenuItem()
    private let openContainerItem = NSMenuItem()
    private let openWithItem = NSMenuItem()
    private let goUpItem = NSMenuItem()
    private let copyPathnameItem = NSMenuItem()
    private let newFolderItem = NSMenuItem()
    private let revealFolderItem = NSMenuItem()
    /// Items for a context click on a row or item, in display order (separators included).
    private var itemMenuItems: [NSMenuItem] = []
    /// Items for a context click on the background, targeting the displayed folder (FR-213).
    private var backgroundMenuItems: [NSMenuItem] = []
    private var showsBackgroundItems: Bool?

    init(host: FileListViewController) {
        self.host = host
        self.menu = NSMenu(title: "")
        super.init()
        buildMenu()
        menu.delegate = self
    }

    func install(listModeView: ListModeView, thumbnailModeView: ThumbnailModeView) {
        listModeView.contextMenu = menu
        thumbnailModeView.contextMenu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        // A click on the background shows the displayed folder's menu instead of the selection's (FR-213, R7).
        let isBackground = host?.isContextClickOnBackground ?? false
        if showsBackgroundItems != isBackground {
            showsBackgroundItems = isBackground
            menu.removeAllItems()
            for item in isBackground ? backgroundMenuItems : itemMenuItems {
                menu.addItem(item)
            }
        }
        MainMenu.refreshTitles(in: menu)
        if !isBackground {
            host?.updateOpenWithMenu(openWithItem)
        }
        let urls = host?.selectedFileURLs ?? []
        if urls.count == 1, let name = urls.first?.lastPathComponent {
            copyItem.title = l10n.text(.contextCopySingle, .text(name))
        } else if urls.count > 1 {
            copyItem.title = l10n.text(.contextCopyMultiple, .count(urls.count))
        } else {
            copyItem.title = l10n.text(.menuEditCopy)
        }

        // Show Go Up only when an enclosing level exists (inside a zip, or a regular folder that is not a tree root).
        // Leave enabling and disabling to validateMenuItem.
        goUpItem.isHidden = !(host?.focusedItemCommands.canGoUp ?? false)

        // Paste and Move Item Here are unavailable inside a zip (FR-073).
        let allowsPaste = host?.focusedItemCommands.allowsPaste ?? true
        let available = PasteboardImport.availability()
        pasteItem.isEnabled = allowsPaste && available.allowsPaste(move: false)
        movePasteItem.isEnabled = allowsPaste && available.allowsPaste(move: true)
    }

    private func buildMenu() {
        menu.autoenablesItems = true

        openContainerItem.title = l10n.text(.menuFileShowContents)
        MainMenu.bind(openContainerItem, .menuFileShowContents)
        openContainerItem.action = #selector(FileListViewController.openFocusedItem(_:))
        openContainerItem.keyEquivalent = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        openContainerItem.keyEquivalentModifierMask = [.command]
        openContainerItem.target = host
        menu.addItem(openContainerItem)
        MenuShortcutApplier.shared.register(openContainerItem, for: .showContents)

        goUpItem.title = l10n.text(.menuFileEnclosingFolder)
        MainMenu.bind(goUpItem, .menuFileEnclosingFolder)
        goUpItem.action = #selector(FileListViewController.goToEnclosingLevel(_:))
        goUpItem.keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        goUpItem.keyEquivalentModifierMask = [.command]
        goUpItem.target = host
        goUpItem.isHidden = true
        menu.addItem(goUpItem)
        MenuShortcutApplier.shared.register(goUpItem, for: .enclosingFolder)
        menu.addItem(.separator())

        addItem(
            key: .menuFileOpen,
            action: #selector(FileListViewController.open(_:)),
            keyEquivalent: "",
            modifiers: [.command]
        )
        openWithItem.title = l10n.text(.menuFileOpenWith)
        MainMenu.bind(openWithItem, .menuFileOpenWith)
        openWithItem.submenu = NSMenu(title: openWithItem.title)
        menu.addItem(openWithItem)
        menu.addItem(.separator())
        addItem(
            key: .menuFileTrash,
            action: #selector(FileListViewController.moveToTrash(_:)),
            keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!),
            modifiers: [.command],
            command: .trash
        )
        menu.addItem(.separator())
        addItem(
            key: .menuEditRename,
            action: #selector(FileListViewController.rename(_:)),
            keyEquivalent: "\r",
            modifiers: []
        )
        addItem(
            key: .menuEditDuplicate,
            action: #selector(FileListViewController.duplicate(_:)),
            keyEquivalent: "d",
            modifiers: [.command],
            command: .duplicate
        )
        menu.addItem(.separator())

        copyItem.title = l10n.text(.menuEditCopy)
        copyItem.action = #selector(FileListViewController.copy(_:))
        copyItem.keyEquivalent = "c"
        copyItem.keyEquivalentModifierMask = [.command]
        copyItem.target = host
        menu.addItem(copyItem)

        copyPathnameItem.title = l10n.text(.menuEditCopyPathname)
        MainMenu.bind(copyPathnameItem, .menuEditCopyPathname)
        copyPathnameItem.action = #selector(FileListViewController.copyPathname(_:))
        copyPathnameItem.keyEquivalent = "c"
        copyPathnameItem.keyEquivalentModifierMask = [.command, .option]
        copyPathnameItem.target = host
        menu.addItem(copyPathnameItem)
        MenuShortcutApplier.shared.register(copyPathnameItem, for: .copyPathname)

        pasteItem.title = l10n.text(.menuEditPaste)
        MainMenu.bind(pasteItem, .menuEditPaste)
        pasteItem.action = #selector(FileListViewController.paste(_:))
        pasteItem.keyEquivalent = "v"
        pasteItem.keyEquivalentModifierMask = [.command]
        pasteItem.target = host
        menu.addItem(pasteItem)

        movePasteItem.title = l10n.text(.menuEditMovePaste)
        MainMenu.bind(movePasteItem, .menuEditMovePaste)
        movePasteItem.action = #selector(FileListViewController.movePaste(_:))
        movePasteItem.keyEquivalent = "v"
        movePasteItem.keyEquivalentModifierMask = [.command, .option]
        movePasteItem.target = host
        menu.addItem(movePasteItem)
        MenuShortcutApplier.shared.register(movePasteItem, for: .movePaste)

        menu.addItem(.separator())
        addItem(
            key: .menuFileRevealInFinder,
            action: #selector(FileListViewController.revealInFinder(_:)),
            keyEquivalent: "",
            modifiers: [.command]
        )
        itemMenuItems = menu.items

        newFolderItem.title = l10n.text(.menuFileNewFolder)
        MainMenu.bind(newFolderItem, .menuFileNewFolder)
        newFolderItem.action = #selector(FileListViewController.newFolder(_:))
        newFolderItem.keyEquivalent = "N"
        newFolderItem.keyEquivalentModifierMask = [.command]
        newFolderItem.target = host
        MenuShortcutApplier.shared.register(newFolderItem, for: .newFolder)

        revealFolderItem.title = l10n.text(.menuFileRevealInFinder)
        MainMenu.bind(revealFolderItem, .menuFileRevealInFinder)
        revealFolderItem.action = #selector(FileListViewController.revealDisplayedFolderInFinder(_:))
        revealFolderItem.target = host

        // Paste and Move Item Here are shared with the item menu; only one of the two lists is in the menu at a time.
        backgroundMenuItems = [
            newFolderItem, .separator(), pasteItem, movePasteItem, .separator(), revealFolderItem,
        ]
        showsBackgroundItems = false
    }

    private func addItem(
        key: TextKey,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags,
        command: ShortcutCommandID? = nil
    ) {
        let item = NSMenuItem(title: l10n.text(key), action: action, keyEquivalent: keyEquivalent)
        MainMenu.bind(item, key)
        item.keyEquivalentModifierMask = modifiers
        item.target = host
        menu.addItem(item)
        if let command {
            MenuShortcutApplier.shared.register(item, for: command)
        }
    }
}
