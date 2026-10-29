import AppKit
import FolzioLocalization

@MainActor
final class FileContextMenu: NSObject, NSMenuDelegate {
    let menu: NSMenu

    private weak var host: FileListViewController?
    private let copyItem = NSMenuItem()
    private let pasteItem = NSMenuItem()
    private let movePasteItem = NSMenuItem()
    private let openContainerItem = NSMenuItem()
    private let goUpItem = NSMenuItem()
    private let copyPathnameItem = NSMenuItem()

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

    static func pasteboardHasFileURLs() -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        return NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self],
            options: options
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MainMenu.refreshTitles(in: menu)
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
        let canPaste = allowsPaste && Self.pasteboardHasFileURLs()
        pasteItem.isEnabled = canPaste
        movePasteItem.isEnabled = canPaste
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

        goUpItem.title = l10n.text(.menuFileEnclosingFolder)
        MainMenu.bind(goUpItem, .menuFileEnclosingFolder)
        goUpItem.action = #selector(FileListViewController.goToEnclosingLevel(_:))
        goUpItem.keyEquivalent = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        goUpItem.keyEquivalentModifierMask = [.command]
        goUpItem.target = host
        goUpItem.isHidden = true
        menu.addItem(goUpItem)
        menu.addItem(.separator())

        addItem(
            key: .menuFileOpen,
            action: #selector(FileListViewController.open(_:)),
            keyEquivalent: "",
            modifiers: [.command]
        )
        menu.addItem(.separator())
        addItem(
            key: .menuFileTrash,
            action: #selector(FileListViewController.moveToTrash(_:)),
            keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!),
            modifiers: [.command]
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
            modifiers: [.command]
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

        menu.addItem(.separator())
        addItem(
            key: .menuFileRevealInFinder,
            action: #selector(FileListViewController.revealInFinder(_:)),
            keyEquivalent: "",
            modifiers: [.command]
        )
    }

    private func addItem(
        key: TextKey,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags
    ) {
        let item = NSMenuItem(title: l10n.text(key), action: action, keyEquivalent: keyEquivalent)
        MainMenu.bind(item, key)
        item.keyEquivalentModifierMask = modifiers
        item.target = host
        menu.addItem(item)
    }
}
