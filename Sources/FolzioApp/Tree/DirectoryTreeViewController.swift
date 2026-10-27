import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
private final class DragAwareOutlineView: NSOutlineView {
    var isTrackingMouse = false
    var beganDrag = false
    var trackingEnded: ((Bool, Int, Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let previousRow = selectedRow
        isTrackingMouse = true
        beganDrag = false
        super.mouseDown(with: event)
        isTrackingMouse = false
        trackingEnded?(beganDrag, previousRow, clickedRow)
    }
}

@MainActor
final class DirectoryTreeViewController: NSViewController {
    final class Node {
        var folder: FolderNode
        var children: [Node]?
        var isLoading = false

        init(folder: FolderNode) {
            self.folder = folder
        }

        var url: URL { folder.url }
    }

    /// Favorites heading at the top of the tree. A virtual row that does not exist on the file system
    /// (FR-061).
    final class FavoritesHeader {}

    /// Item below the heading. Has no disclosure triangle (FR-063).
    final class FavoriteEntry {
        let url: URL
        /// Display name. Equal to `defaultName` when unchanged (FR-101).
        var name: String
        /// Name of the registered folder (the volume name for a root). Fallback when an empty name is committed
        /// (FR-100).
        var defaultName: String
        var kind: FolderNode.Kind
        var availability: FavoriteAvailability = .unknown

        init(url: URL, name: String, defaultName: String, kind: FolderNode.Kind) {
            self.url = url
            self.name = name
            self.defaultName = defaultName
            self.kind = kind
        }
    }

    private let model: BrowserModel
    private let lister: any DirectoryListing
    private let volumes: any VolumeProviding
    private let coordinator: FileOperationCoordinator
    private let watcher: any FileSystemWatching
    /// Removes locations that disappeared due to external changes from history (FR-109).
    weak var historyNavigator: HistoryNavigator?
    private let settings: SettingsStore
    private let confirmation: ConfirmationPresenter
    private let outlineView = DragAwareOutlineView()
    private let scrollView = NSScrollView()

    private var roots: [Node] = []
    private let favoritesHeader = FavoritesHeader()
    private var favorites = FavoriteFolders()
    private var favoriteEntries: [FavoriteEntry] = []
    private var volumeTask: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    /// Event number of the click whose mouseDown changed the selection. For the `action` sent by mouseUp for the
    /// same click, does not call `selectFolder` again after the selection-change call.
    private var selectionChangeClickNumber: Int?
    private var eventTask: Task<Void, Never>?
    private var favoriteProbeTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var didReveal = false
    private var isRestoringSelection = false
    /// Whether to scroll a renamed folder (or a descendant) into view after the parent reload changes its position,
    /// when that folder was selected (FR-104).
    private var needsRevealSelectionAfterRename = false

    /// Target of inline editing. Favorites display names and regular folder names share the editing mechanism
    /// (R60).
    private enum EditingTarget {
        case favorite(FavoriteEntry)
        case folder(Node)

        var item: AnyObject {
            switch self {
            case .favorite(let entry): entry
            case .folder(let node): node
            }
        }

        var name: String {
            switch self {
            case .favorite(let entry): entry.name
            case .folder(let node): node.folder.name
            }
        }
    }

    /// Row being renamed. A non-nil value means renaming is in progress (FR-102).
    private var editingTarget: EditingTarget?
    private var editingOriginalName: String?
    private var isFinishingEdit = false
    private var needsReloadAfterEdit = false
    private let favoriteNameFormatter = FavoriteNameFormatter()

    private enum ProbeKey: Hashable {
        case roots
        case children(ObjectIdentifier)
        case recheck(ObjectIdentifier)
    }

    private struct ProbeEntry {
        let id: Int
        let task: Task<Void, Never>
    }

    private var probeTasks: [ProbeKey: ProbeEntry] = [:]
    private var nextProbeID = 0

    init(
        model: BrowserModel,
        lister: any DirectoryListing,
        volumes: any VolumeProviding,
        coordinator: FileOperationCoordinator,
        watcher: any FileSystemWatching,
        settings: SettingsStore,
        confirmation: ConfirmationPresenter
    ) {
        self.model = model
        self.lister = lister
        self.volumes = volumes
        self.coordinator = coordinator
        self.watcher = watcher
        self.settings = settings
        self.confirmation = confirmation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var primaryFocusView: NSView { outlineView }

    func scrollSelectedRowToVisible() {
        let row = outlineView.selectedRow
        guard row >= 0 else { return }
        outlineView.scrollRowToVisible(row)
    }

    private var selectedNode: Node? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? Node
    }

    private func role(for item: Any?) -> TreeItemRole? {
        switch item {
        case is FavoritesHeader:
            return .favoritesHeader
        case let entry as FavoriteEntry:
            return .favorite(entry.url)
        case let node as Node:
            return .folder(node.url)
        default:
            return nil
        }
    }

    /// Rebuilds items in registration order. Reuses existing items for the same location and preserves the checked
    /// availability and selection.
    private func rebuildFavoriteEntries() {
        let existing = Dictionary(
            favoriteEntries.map { ($0.url.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        favoriteEntries = favorites.urls.map { url in
            let key = url.standardizedFileURL.path
            let root = roots.first { $0.url.standardizedFileURL.path == key }
            let defaultName = root?.folder.name ?? url.lastPathComponent
            let name = favorites.displayName(for: url, defaultName: defaultName)
            let kind = root?.folder.kind ?? .folder
            if let entry = existing[key] {
                entry.name = name
                entry.defaultName = defaultName
                entry.kind = kind
                return entry
            }
            return FavoriteEntry(url: url, name: name, defaultName: defaultName, kind: kind)
        }
    }

    private var rootURLs: [URL] { roots.map(\.url) }

    private var selectedItem: Any? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row)
    }

    /// Target of ⌘⌫. Returns an item only when a favorite item is selected (FR-064).
    private var selectedFavoriteEntry: FavoriteEntry? {
        let item = selectedItem
        guard FavoriteCommands.removalTarget(role(for: item)) != nil else { return nil }
        return item as? FavoriteEntry
    }

    /// Returns the right-clicked row for a context menu item, or the selected row for a keyboard command.
    private func targetItem(for sender: Any?) -> Any? {
        if let menuItem = sender as? NSMenuItem, let represented = menuItem.representedObject {
            return represented
        }
        return selectedItem
    }

    /// Target of paste and Reveal in Finder. Nil for the heading and favorite items.
    private func fileTargetNode(for sender: Any?) -> Node? {
        let item = targetItem(for: sender)
        guard let role = role(for: item), FavoriteCommands.acceptsFiles(role) else { return nil }
        return item as? Node
    }

    /// Items are rebuilt in menuNeedsUpdate according to the target row's role.
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: "")
        menu.delegate = self
        return menu
    }

    private func makeContextMenuItem(
        _ kind: TreeContextMenuItem,
        representing item: Any
    ) -> NSMenuItem {
        let menuItem: NSMenuItem
        switch kind {
        case .pasteHere:
            menuItem = NSMenuItem(title: l10n.text(.contextPasteHere), action: #selector(paste(_:)), keyEquivalent: "")
        case .movePasteHere:
            menuItem = NSMenuItem(title: l10n.text(.contextMovePasteHere), action: #selector(movePaste(_:)), keyEquivalent: "")
        case .addToFavorites:
            menuItem = NSMenuItem(
                title: l10n.text(.menuFileAddToFavorites),
                action: #selector(addToFavorites(_:)),
                keyEquivalent: "t"
            )
            menuItem.keyEquivalentModifierMask = [.command, .control]
        case .revealInFinder:
            menuItem = NSMenuItem(title: l10n.text(.menuFileRevealInFinder), action: #selector(revealInFinder(_:)), keyEquivalent: "")
        case .removeFromFavorites:
            menuItem = NSMenuItem(
                title: l10n.text(.menuFileRemoveFromFavorites),
                action: #selector(removeFavoriteFromMenu(_:)),
                keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!)
            )
            menuItem.keyEquivalentModifierMask = [.command]
        case .moveToTrash:
            menuItem = NSMenuItem(
                title: l10n.text(.menuFileTrash),
                action: #selector(trashFolderFromMenu(_:)),
                keyEquivalent: String(UnicodeScalar(NSBackspaceCharacter)!)
            )
            menuItem.keyEquivalentModifierMask = [.command]
        case .renameFavorite:
            menuItem = NSMenuItem(
                title: l10n.text(.menuEditRename),
                action: #selector(renameFavoriteFromMenu(_:)),
                keyEquivalent: "\r"
            )
            menuItem.keyEquivalentModifierMask = []
        case .renameFolder:
            menuItem = NSMenuItem(
                title: l10n.text(.menuEditRename),
                action: #selector(renameFolderFromMenu(_:)),
                keyEquivalent: "\r"
            )
            menuItem.keyEquivalentModifierMask = []
        case .separator:
            return .separator()
        }
        menuItem.target = self
        menuItem.representedObject = item
        return menuItem
    }

    @objc func paste(_ sender: Any?) {
        guard let node = fileTargetNode(for: sender) else { return }
        let destination = node.url
        Task { @MainActor in
            await coordinator.paste(into: destination, move: false)
        }
    }

    @objc func movePaste(_ sender: Any?) {
        guard let node = fileTargetNode(for: sender) else { return }
        let destination = node.url
        Task { @MainActor in
            await coordinator.paste(into: destination, move: true)
        }
    }

    /// ⌘⌫. Removes a favorite item from Favorites (FR-064), or moves a non-root folder to the Trash (FR-079).
    @objc func moveToTrash(_ sender: Any?) {
        if let entry = selectedFavoriteEntry {
            Task { [weak self] in
                await self?.removeFavorite(entry)
            }
            return
        }
        guard let url = FavoriteCommands.trashTarget(role(for: selectedItem), roots: rootURLs) else { return }
        // Trash from the tree always confirms, regardless of the skip setting (FR-079, R66).
        Task { @MainActor [coordinator] in
            await coordinator.trash([url], origin: .tree)
        }
    }

    /// Move to Trash in the context menu. Targets the right-clicked row and does not move keyboard focus (R33).
    @objc private func trashFolderFromMenu(_ sender: Any?) {
        let role = role(for: targetItem(for: sender))
        guard let url = FavoriteCommands.trashTarget(role, roots: rootURLs) else { return }
        Task { @MainActor [coordinator] in
            await coordinator.trash([url], origin: .tree)
        }
    }

    @objc private func addToFavorites(_ sender: Any?) {
        addFavorite(for: targetItem(for: sender))
    }

    @objc private func removeFavoriteFromMenu(_ sender: Any?) {
        guard let item = (sender as? NSMenuItem)?.representedObject,
              FavoriteCommands.removalTarget(role(for: item)) != nil,
              let entry = item as? FavoriteEntry else {
            return
        }
        Task { [weak self] in
            await self?.removeFavorite(entry)
        }
    }

    /// ⌃⌘T. Called from MainSplitViewController regardless of which pane has focus (FR-062).
    func addSelectedFolderToFavorites() {
        addFavorite(for: selectedItem)
    }

    var canAddSelectedFolderToFavorites: Bool {
        FavoriteCommands.canAdd(role(for: selectedItem), favorites: favorites)
    }

    /// ⇧⌘F. Only selects the heading; does not change the file list or preview (FR-065).
    func focusFavoritesHeader() {
        let row = outlineView.row(forItem: favoritesHeader)
        guard row >= 0 else { return }
        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
        if !outlineView.isItemExpanded(favoritesHeader) {
            outlineView.expandItem(favoritesHeader)
        }
        view.window?.makeFirstResponder(outlineView)
    }

    /// Return and Edit > Rename when the tree has focus. Starts editing the display name for a favorite item
    /// (FR-099), or the actual folder name for a non-root regular folder (FR-103).
    /// Does not inspect `BrowserModel` state while inside a zip or showing search results (EC-46).
    @objc func rename(_ sender: Any?) {
        guard let target = editingTarget(for: selectedItem) else { return }
        beginEditing(target)
    }

    /// Rename in the context menu for a favorite item. Does not change the tree selection (A-21, FR-099).
    @objc private func renameFavoriteFromMenu(_ sender: Any?) {
        let item = (sender as? NSMenuItem)?.representedObject
        guard let target = editingTarget(for: item), case .favorite = target else { return }
        beginEditingFromMenu(target)
    }

    /// Rename in the context menu for a regular folder. Does not change the tree selection (A-21, A-36; FR-103).
    @objc private func renameFolderFromMenu(_ sender: Any?) {
        let item = (sender as? NSMenuItem)?.representedObject
        guard let target = editingTarget(for: item), case .folder = target else { return }
        beginEditingFromMenu(target)
    }

    /// Editing target for the row when its name can be changed (R59).
    private func editingTarget(for item: Any?) -> EditingTarget? {
        switch FavoriteCommands.renameTarget(role(for: item), roots: rootURLs) {
        case .favorite:
            return (item as? FavoriteEntry).map(EditingTarget.favorite)
        case .folder:
            return (item as? Node).map(EditingTarget.folder)
        case nil:
            return nil
        }
    }

    private func beginEditingFromMenu(_ target: EditingTarget) {
        if !beginEditing(target) {
            // makeFirstResponder can fail during menu tracking, so defer to the next turn (R52).
            Task { @MainActor [weak self] in
                self?.beginEditing(target)
            }
        }
    }

    @discardableResult
    private func beginEditing(_ target: EditingTarget) -> Bool {
        guard editingTarget == nil else { return false }
        guard let window = outlineView.window else { return false }
        let row = outlineView.row(forItem: target.item)
        guard row >= 0 else { return false }

        outlineView.scrollRowToVisible(row)
        outlineView.layoutSubtreeIfNeeded()
        guard let cell = outlineView.view(
            atColumn: 0,
            row: row,
            makeIfNecessary: true
        ) as? NSTableCellView,
            let field = cell.textField else {
            return false
        }

        let name = target.name
        editingTarget = target
        editingOriginalName = name
        needsReloadAfterEdit = false
        field.stringValue = name
        configureEditingField(field, for: target)

        guard window.makeFirstResponder(field) else {
            editingTarget = nil
            editingOriginalName = nil
            resetEditingState(of: cell)
            field.stringValue = name
            return false
        }
        if let editor = field.currentEditor() as? NSTextView {
            // Select all for Favorites (FR-099); for folders, select before the last "." as in the file list
            // (FR-103).
            let selected: String
            switch target {
            case .favorite:
                selected = field.stringValue
            case .folder:
                selected = (field.stringValue as NSString).deletingPathExtension
            }
            editor.selectedRange = NSRange(location: 0, length: (selected as NSString).length)
        }
        return true
    }

    /// Finishes inline editing. Returns keyboard focus to the tree when `restoresFocus` is true (R51).
    private func finishEditing(commit: Bool, restoresFocus: Bool) {
        guard !isFinishingEdit, let target = editingTarget else { return }
        isFinishingEdit = true
        defer { isFinishingEdit = false }

        let originalName = editingOriginalName ?? target.name
        editingTarget = nil
        editingOriginalName = nil

        let row = outlineView.row(forItem: target.item)
        var field: NSTextField?
        var input = originalName
        if row >= 0,
           let cell = outlineView.view(
               atColumn: 0,
               row: row,
               makeIfNecessary: false
           ) as? NSTableCellView,
           let textField = cell.textField {
            field = textField
            input = textField.stringValue
            resetEditingState(of: cell)
            textField.stringValue = originalName
        }

        if let window = outlineView.window {
            if restoresFocus {
                window.makeFirstResponder(outlineView)
            } else if let field, field.currentEditor() != nil {
                // Do not change focus at the click target (A-31).
                window.endEditing(for: field)
            }
        }

        if commit {
            switch target {
            case .favorite(let entry):
                if favorites.commitDisplayName(input, for: entry.url, defaultName: entry.defaultName) {
                    settings.favorites = favorites
                    rebuildFavoriteEntries()
                }
            case .folder(let node):
                // Do nothing for an empty name or the same name as before editing (EC-48). The coordinator handles
                // validation, confirmation, and failure display as in the file list (R60).
                let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name != originalName {
                    let url = node.url
                    Task { @MainActor [coordinator] in
                        await coordinator.rename(url, to: name, origin: .tree)
                    }
                }
            }
        }

        if row >= 0 {
            outlineView.reloadItem(target.item)
        }
        needsReloadAfterEdit = false
    }

    /// Checks whether the edit field had focus when the tree commits editing (R51).
    private var editingFieldHasFocus: Bool {
        guard let target = editingTarget else { return false }
        let row = outlineView.row(forItem: target.item)
        guard row >= 0,
              let cell = outlineView.view(
                  atColumn: 0,
                  row: row,
                  makeIfNecessary: false
              ) as? NSTableCellView,
              let field = cell.textField else {
            return false
        }
        return field.currentEditor() != nil
    }

    /// Adds a Formatter to limit newlines and length for Favorites. Does not add one for folders, matching the
    /// file list edit field (R60).
    private func configureEditingField(_ field: NSTextField, for target: EditingTarget) {
        switch target {
        case .favorite:
            field.formatter = favoriteNameFormatter
            field.setAccessibilityLabel(l10n.text(.treeA11yFavoriteName))
        case .folder:
            field.formatter = nil
            field.setAccessibilityLabel(l10n.text(.treeA11yFolderName))
        }
        field.delegate = self
        setEditingAppearance(field, editing: true)
    }

    private func setEditingAppearance(_ field: NSTextField, editing: Bool) {
        field.isEditable = editing
        field.isSelectable = editing
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = editing
        field.backgroundColor = editing ? .textBackgroundColor : .clear
        field.focusRingType = editing ? .default : .none
    }

    private func resetEditingState(of cell: NSTableCellView) {
        guard let field = cell.textField else { return }
        setEditingAppearance(field, editing: false)
        field.formatter = nil
        field.delegate = nil
        field.setAccessibilityLabel(nil)
    }

    /// Cells are shared between rows, so reset the editing state on every display (R51, R54).
    /// Only the row being edited keeps its in-progress value.
    private func prepareCell(_ cell: NSTableCellView, for item: Any) {
        guard let field = cell.textField else { return }
        if let target = editingTarget,
           (item as AnyObject) === target.item,
           field.currentEditor() != nil {
            configureEditingField(field, for: target)
            return
        }
        resetEditingState(of: cell)
    }

    private func addFavorite(for item: Any?) {
        let role = role(for: item)
        guard FavoriteCommands.canAdd(role, favorites: favorites),
              case .folder(let url) = role else {
            return
        }
        // Do not change the heading's expansion state.
        favorites.add(url)
        settings.favorites = favorites
        rebuildFavoriteEntries()
        reloadFavorites()
        updateWatchSet()
        refreshFavoriteAvailability()
    }

    /// Removes only the registration and does not touch the actual folder (FR-064).
    private func removeFavorite(_ entry: FavoriteEntry) async {
        guard await confirmation.confirmRemovingFavorite(named: entry.name, path: entry.url.path) else { return }
        guard favorites.contains(entry.url) else { return }

        // Select the heading first so another item is not selected at the removed row's position and switches the
        // list.
        if selectedItem as? FavoriteEntry === entry {
            let headerRow = outlineView.row(forItem: favoritesHeader)
            if headerRow >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: headerRow), byExtendingSelection: false)
            }
        }

        favorites.remove(entry.url)
        settings.favorites = favorites
        rebuildFavoriteEntries()
        reloadFavorites()
        updateWatchSet()
    }

    /// Reloads the heading's children and restores the selection to the same item when rows are added or removed.
    private func reloadFavorites() {
        let previous = selectedItem
        isRestoringSelection = true
        defer { isRestoringSelection = false }

        outlineView.reloadItem(favoritesHeader, reloadChildren: true)
        if let previous {
            let row = outlineView.row(forItem: previous)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
    }

    /// Returns to the folder listing when the selected folder row is clicked while showing search results (FR-086).
    /// Does nothing for the disclosure triangle or the Favorites heading. Clicks that change the selection are left
    /// to outlineViewSelectionDidChange.
    @objc private func clickedRow(_ sender: Any?) {
        guard !outlineView.isTrackingMouse else { return }
        let event = NSApp.currentEvent
        defer { selectionChangeClickNumber = nil }
        guard model.isShowingSearchResults else { return }
        let row = outlineView.clickedRow
        guard row >= 0, row == outlineView.selectedRow else { return }
        if let event, let number = selectionChangeClickNumber, event.eventNumber == number { return }
        if let event {
            let point = outlineView.convert(event.locationInWindow, from: nil)
            if outlineView.frameOfOutlineCell(atRow: row).contains(point) { return }
        }
        guard let role = role(for: outlineView.item(atRow: row)),
              let url = FavoriteCommands.folderToShow(for: role) else { return }
        revealTask?.cancel()
        revealTask = nil
        Task { [weak self] in
            await self?.model.selectFolder(url)
        }
    }

    @objc private func toggleClickedFolder(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0 else { return }
        let item = outlineView.item(atRow: row)

        // The first click changes the selection in outlineViewSelectionDidChange. Favorite items do not expand.
        let isExpandable: Bool
        switch item {
        case is FavoritesHeader:
            isExpandable = true
        case let node as Node:
            isExpandable = node.folder.isExpandable
        default:
            return
        }

        switch FolderDisclosure.doubleClickToggle(
            isExpandable: isExpandable,
            isExpanded: outlineView.isItemExpanded(item)
        ) {
        case .expand:
            outlineView.expandItem(item)
        case .collapse:
            outlineView.collapseItem(item)
        case .none:
            break
        }
    }

    @objc private func revealInFinder(_ sender: Any?) {
        guard let node = fileTargetNode(for: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    override func loadView() {
        let container = NSView()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.trackingEnded = { [weak self] dragged, previousRow, clickedRow in
            guard let self else { return }
            if dragged {
                self.isRestoringSelection = true
                if previousRow >= 0, previousRow < self.outlineView.numberOfRows {
                    self.outlineView.selectRowIndexes(IndexSet(integer: previousRow), byExtendingSelection: false)
                } else { self.outlineView.deselectAll(nil) }
                self.isRestoringSelection = false
                return
            }
            if previousRow != self.outlineView.selectedRow {
                self.outlineViewSelectionDidChange(Notification(name: NSOutlineView.selectionDidChangeNotification, object: self.outlineView))
            } else if clickedRow >= 0 {
                self.clickedRow(self.outlineView)
            }
        }
        outlineView.registerForDraggedTypes([.fileURL])
        outlineView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        InternalDrag.register(outlineView)
        outlineView.menu = makeContextMenu()
        outlineView.target = self
        outlineView.doubleAction = #selector(toggleClickedFolder(_:))
        // Clicking the selected row does not report a selection change, so use action to end search results
        // (FR-086, R37).
        outlineView.action = #selector(clickedRow(_:))

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("folder"))
        column.title = l10n.text(.treeColumn)
        column.width = 200
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView
        container.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )

        roots = volumes.rootNodes().map { Node(folder: $0) }
        favorites = settings.favorites
        rebuildFavoriteEntries()
        outlineView.reloadData()
        startProbes(for: roots, key: .roots)
        refreshFavoriteAvailability()

        volumeTask = Task { [weak self] in
            guard let self else { return }
            for await newRoots in self.volumes.changes {
                self.applyRoots(newRoots)
                await self.historyNavigator?.revalidateAll()
                // Remove search results that no longer exist when a volume containing the root is removed
                // (Edge Cases, R38).
                if self.model.isShowingSearchResults {
                    await self.model.reloadCurrentFolder()
                }
            }
        }

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await changed in self.watcher.events {
                await self.model.handleFileSystemEvent(changed)
                await self.historyNavigator?.handleFileSystemEvent(changed)
                await self.refreshFolders(changed)
            }
        }

        // The tree lives until the app quits, so do not unregister this observer, as with volumeTask and eventTask.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFavoriteAvailability()
            }
        }

        observeDisplayedFolder()
        observeTreeSyncRequest()
        updateWatchSet()
    }

    @objc private func displayLanguageDidChange() {
        outlineView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("folder"))?.title = l10n.text(.treeColumn)
        let row = outlineView.row(forItem: favoritesHeader)
        if row >= 0,
           let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView {
            cell.textField?.stringValue = l10n.text(.treeFavorites)
        }
        let visible = outlineView.rows(in: outlineView.visibleRect)
        if visible.location != NSNotFound {
            for index in visible.location..<min(visible.location + visible.length, outlineView.numberOfRows) {
                guard let cell = outlineView.view(atColumn: 0, row: index, makeIfNecessary: false) as? NSTableCellView else { continue }
                if let node = outlineView.item(atRow: index) as? Node,
                   node.folder.accessState == .denied || node.folder.accessState == .unavailable {
                    cell.toolTip = l10n.text(.treeTooltipNotAccessible)
                } else if let entry = outlineView.item(atRow: index) as? FavoriteEntry, entry.availability == .missing {
                    cell.toolTip = l10n.text(.treeTooltipNotFound)
                }
            }
        }
        if let editingTarget {
            let label: String
            switch editingTarget {
            case .favorite: label = l10n.text(.treeA11yFavoriteName)
            case .folder: label = l10n.text(.treeA11yFolderName)
            }
            (outlineView.window?.firstResponder as? NSTextView)?.setAccessibilityLabel(label)
            let editingRow = outlineView.row(forItem: editingTarget.item)
            if editingRow >= 0,
               let cell = outlineView.view(atColumn: 0, row: editingRow, makeIfNecessary: false) as? NSTableCellView {
                cell.textField?.setAccessibilityLabel(label)
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !didReveal else { return }
        didReveal = true

        let target = model.listing.folder
        revealTask = Task { [weak self] in
            await self?.reveal(target)
        }
    }

    private func applyRoots(_ newRoots: [FolderNode]) {
        // reloadData recreates all row cells, so commit the name being edited first (R51, EC-43, quickstart 24).
        if editingTarget != nil {
            finishEditing(commit: true, restoresFocus: editingFieldHasFocus)
        }
        let existing = Dictionary(
            roots.map { ($0.url.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        roots = newRoots.map { folder in
            let node = Node(folder: folder)
            if let previous = existing[folder.url.standardizedFileURL] {
                node.children = previous.children
                node.folder.subfolderState = previous.folder.subfolderState
                node.folder.accessState = previous.folder.accessState
            }
            return node
        }
        rebuildFavoriteEntries()

        // Preserve the heading expansion state and the selected favorite row across volume changes (FR-061).
        let headerWasExpanded = outlineView.isItemExpanded(favoritesHeader)
        let selected = selectedItem
        let keepsFavoriteSelection = selected is FavoritesHeader || selected is FavoriteEntry
        isRestoringSelection = keepsFavoriteSelection
        outlineView.reloadData()
        if headerWasExpanded {
            outlineView.expandItem(favoritesHeader)
        }
        if keepsFavoriteSelection, let selected {
            let row = outlineView.row(forItem: selected)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        }
        isRestoringSelection = false

        startProbes(for: roots, key: .roots)
        updateWatchSet()
        refreshFavoriteAvailability()
        model.setNavigationRoots(roots.map(\.url))
    }

    /// Checks whether each registered location still has a folder and redraws only changed rows (FR-067).
    /// Performs stat inside the FavoriteProbe task.
    private func refreshFavoriteAvailability() {
        favoriteProbeTask?.cancel()
        favoriteProbeTask = nil
        let urls = favoriteEntries.map(\.url)
        guard !urls.isEmpty else { return }

        favoriteProbeTask = Task { [weak self] in
            for await result in FavoriteProbe.results(for: urls) {
                guard let self, !Task.isCancelled else { return }
                self.applyFavoriteProbe(result)
            }
        }
    }

    private func applyFavoriteProbe(_ result: FavoriteProbeResult) {
        let key = result.url.standardizedFileURL.path
        let availability: FavoriteAvailability = result.exists ? .available : .missing
        for entry in favoriteEntries
        where entry.url.standardizedFileURL.path == key && entry.availability != availability {
            entry.availability = availability
            if entry === editingTarget?.item {
                // Do not redraw the row being edited; reflect dimming in reloadItem when editing ends (R51, EC-43).
                needsReloadAfterEdit = true
            } else if outlineView.row(forItem: entry) >= 0 {
                outlineView.reloadItem(entry)
            }
        }
    }

    /// Rechecks only when the changed folders include a parent or ancestor of a registered folder. Renaming or
    /// restoring an ancestor also changes the not-found display (FR-106, R65).
    private func refreshFavoriteAvailabilityIfNeeded(in changed: Set<URL>) {
        let changedComponents = changed.map(\.standardizedFileURL.pathComponents)
        let affected = favorites.urls.contains { url in
            let components = url.standardizedFileURL.pathComponents
            return changedComponents.contains { components.count > $0.count && components.starts(with: $0) }
        }
        if affected {
            refreshFavoriteAvailability()
        }
    }

    /// Rebases loaded node locations after a successful folder rename. Does not recreate node objects and preserves
    /// expansion state, selection, and subfolder check results. The following parent reload moves the node to its
    /// sorted position (FR-104, 106; R64, R65).
    func didRenameFolder(from oldURL: URL, to newURL: URL) {
        let renamed = RenamedFolder(from: oldURL, to: newURL)
        let oldPath = oldURL.standardizedFileURL.path
        let selected = selectedNode
        var changedNodes: [Node] = []
        let nodes = flattenedNodes(from: roots)
        for node in nodes {
            guard let url = renamed.rebase(node.url) else { continue }
            if node.url.standardizedFileURL.path == oldPath {
                node.folder.name = newURL.lastPathComponent
                changedNodes.append(node)
                if let selected, renamed.rebase(selected.url) != nil {
                    needsRevealSelectionAfterRename = true
                }
            }
            node.folder.url = url
        }
        for node in nodes where node.children != nil {
            node.folder.children = node.children?.map(\.folder)
        }
        for node in changedNodes where outlineView.row(forItem: node) >= 0 {
            outlineView.reloadItem(node, reloadChildren: false)
        }
        updateWatchSet()
        refreshFavoriteAvailability()
    }

    /// Parent of each registered folder. Excludes `/` because it has no parent.
    private func favoriteParentFolders() -> [URL] {
        favorites.urls.compactMap { url in
            let standardized = url.standardizedFileURL
            guard standardized.path != "/" else { return nil }
            return standardized.deletingLastPathComponent().standardizedFileURL
        }
    }

    /// Reloads children, subfolder presence, and favorite existence for changed folders. Called from both FSEvents
    /// batches and file operation completion (applied without waiting for FSEvents; FR-027, R32).
    func refreshFolders(_ changed: Set<URL>) async {
        await reloadExpandedNodes(in: changed)
        recheckCollapsedNodes(in: changed)
        updateWatchSet()
        refreshFavoriteAvailabilityIfNeeded(in: changed)
    }

    private func reveal(_ target: URL) async {
        guard let node = await expandAncestors(of: target) else { return }
        let row = outlineView.row(forItem: node)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }

    /// Loads and expands each level's children from a root to the target folder. Returns the deepest node reached
    /// (nil when cancelled).
    private func expandAncestors(of target: URL) async -> Node? {
        let targetComponents = target.standardizedFileURL.pathComponents

        // Start from the deepest root containing the target (do not traverse home from the boot volume; R30).
        var root = roots
            .filter { targetComponents.starts(with: $0.url.standardizedFileURL.pathComponents) }
            .max { $0.url.standardizedFileURL.pathComponents.count < $1.url.standardizedFileURL.pathComponents.count }
        if root == nil {
            root = roots.first { $0.folder.kind == .home }
        }
        guard var current = root else { return nil }

        await loadAndExpand(current)
        guard !Task.isCancelled else { return nil }

        let rootComponents = current.url.standardizedFileURL.pathComponents
        if targetComponents.count > rootComponents.count {
            for component in targetComponents[rootComponents.count...] {
                guard let next = current.children?.first(where: {
                    $0.url.lastPathComponent == component
                }) else {
                    break
                }
                await loadAndExpand(next)
                guard !Task.isCancelled else { return nil }
                current = next
            }
        }
        return current
    }

    /// Reflects file list navigation (opening a folder or going back) in the tree selection (FR-078, R31).
    private func observeTreeSyncRequest() {
        withObservationTracking {
            _ = model.treeSyncRequest
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let request = self.model.treeSyncRequest {
                    self.syncSelection(to: request)
                }
                self.observeTreeSyncRequest()
            }
        }
    }

    /// Expands to the request's folder in the actual hierarchy, selects its row, and scrolls minimally.
    /// Does not call selectFolder back from the selection change or move keyboard focus.
    private func syncSelection(to request: TreeSyncRequest) {
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            guard let self else { return }
            let node = await self.expandAncestors(of: request.folder)
            // Do not let an older synchronization overwrite the selection when a newer request, tree selection, or
            // other file list navigation exists.
            guard !Task.isCancelled,
                  let node,
                  self.model.treeSyncRequest?.id == request.id,
                  self.model.listing.folder.standardizedFileURL == request.folder.standardizedFileURL else {
                return
            }
            let row = self.outlineView.row(forItem: node)
            guard row >= 0 else { return }
            self.isRestoringSelection = true
            self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            self.isRestoringSelection = false
            self.outlineView.scrollRowToVisible(row)
            self.updateWatchSet()
            // When a folder opened from search results is not in the tree, Core saves the nearest ancestor that could
            // be selected (EC-102).
            self.model.completeSearchResultTreeSync(request, selectedFolder: node.url)
        }
    }

    /// expandItem on an unloaded node is ignored because isItemExpandable is false, so load children first.
    private func loadAndExpand(_ node: Node) async {
        await loadChildrenIfNeeded(node)
        if node.folder.isExpandable, !outlineView.isItemExpanded(node) {
            outlineView.expandItem(node)
        }
    }

    private func loadChildrenIfNeeded(_ node: Node) async {
        guard node.children == nil, !node.isLoading else { return }
        node.isLoading = true
        defer { node.isLoading = false }

        let requested = node.url
        let result: Result<[URL], ListingError>
        do {
            result = .success(try await lister.subfolders(of: requested))
        } catch {
            result = .failure(error)
        }
        // Do not apply results from the old location to a node renamed during loading. Read the new location on the
        // next expansion (R64).
        guard node.url == requested else { return }
        applyListing(result, to: node)
        updateWatchSet()
    }

    private func applyListing(_ result: Result<[URL], ListingError>, to node: Node) {
        switch result {
        case .success(let urls):
            // Recreating rows removes the edit field, so commit any child being edited first (R51).
            if case .folder(let editing) = editingTarget, node.children?.contains(where: { $0 === editing }) == true {
                finishEditing(commit: true, restoresFocus: editingFieldHasFocus)
            }
            let previous = Dictionary(
                (node.children ?? []).map { ($0.url.standardizedFileURL, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            // Reuse nodes for the same location and preserve expansion state and loaded children (renamed nodes are
            // already rebased; R64).
            let children = urls.map { url -> Node in
                if let old = previous[url.standardizedFileURL] {
                    old.folder.url = url
                    old.folder.name = url.lastPathComponent
                    return old
                }
                return Node(folder: FolderNode(
                    url: url,
                    name: url.lastPathComponent,
                    kind: .folder,
                    accessState: .accessible
                ))
            }
            node.children = children
            node.folder.children = children.map(\.folder)
            node.folder.applySubfolderListing(.success(children.count))
            outlineView.reloadItem(node, reloadChildren: true)
            if node.folder.isExpandable {
                outlineView.expandItem(node)
            } else {
                outlineView.collapseItem(node)
            }
            startProbes(for: children, key: .children(ObjectIdentifier(node)))
        case .failure(let error):
            node.folder.applySubfolderListing(.failure(error))
            // For access denied, settle on empty; otherwise reload on the next expansion.
            node.children = node.folder.accessState == .denied ? [] : nil
            outlineView.reloadItem(node, reloadChildren: true)
            outlineView.collapseItem(node)
        }
    }

    private func startProbes(for nodes: [Node], key: ProbeKey, force: Bool = false) {
        let targets = force ? nodes : nodes.filter {
            $0.folder.subfolderState == .unknown && $0.folder.accessState != .denied
        }
        probeTasks[key]?.task.cancel()
        probeTasks[key] = nil
        guard !targets.isEmpty else { return }

        let lookup = Dictionary(
            targets.map { ($0.url.standardizedFileURL, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let urls = targets.map(\.url)
        let lister = self.lister
        nextProbeID += 1
        let id = nextProbeID

        let task = Task { [weak self] in
            for await result in SubfolderProbe.results(for: urls, lister: lister) {
                guard let self, !Task.isCancelled else { return }
                guard let node = lookup[result.url.standardizedFileURL] else { continue }
                node.folder.applySubfolderProbe(result.result)
                if self.outlineView.row(forItem: node) >= 0 {
                    self.outlineView.reloadItem(node, reloadChildren: false)
                }
            }
            if let self, self.probeTasks[key]?.id == id {
                self.probeTasks[key] = nil
            }
        }
        probeTasks[key] = ProbeEntry(id: id, task: task)
    }

    private func observeDisplayedFolder() {
        withObservationTracking {
            _ = model.listing.folder
            // Replace the subtree watch below the search root when a search starts or ends.
            _ = model.listing.search?.root
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateWatchSet()
                self?.observeDisplayedFolder()
            }
        }
    }

    private func updateWatchSet() {
        var folders: Set<URL> = [model.listing.folder.standardizedFileURL]
        for node in flattenedNodes(from: roots) where outlineView.isItemExpanded(node) {
            folders.insert(node.url.standardizedFileURL)
        }
        // Also watch collapsed visible folders to update the disclosure triangle when subfolders are added or
        // removed.
        for node in displayedNodes() {
            folders.insert(node.url.standardizedFileURL)
        }
        // Receive moves and deletions of favorite folders as changes to their parent folders (FR-067).
        folders.formUnion(favoriteParentFolders())
        // While showing search results, receive changes at every level below the root and remove results that
        // disappear (FR-087, R38).
        watcher.watch(folders, subtrees: model.listing.search.map { [$0.root.standardizedFileURL] } ?? [])
    }

    private func displayedNodes() -> [Node] {
        var result: [Node] = []
        func visit(_ nodes: [Node]) {
            for node in nodes {
                result.append(node)
                if outlineView.isItemExpanded(node), let children = node.children {
                    visit(children)
                }
            }
        }
        visit(roots)
        return result
    }

    private func recheckCollapsedNodes(in changed: Set<URL>) {
        let changedURLs = Set(changed.map(\.standardizedFileURL))
        let targets = displayedNodes().filter { node in
            !outlineView.isItemExpanded(node) && changedURLs.contains(node.url.standardizedFileURL)
        }
        for node in targets {
            if node.children != nil {
                // Discard loaded children so changes while collapsed are reflected on the next expansion.
                node.children = nil
                node.folder.children = nil
                outlineView.reloadItem(node, reloadChildren: true)
            }
            startProbes(for: [node], key: .recheck(ObjectIdentifier(node)), force: true)
        }
    }

    private func reloadExpandedNodes(in changed: Set<URL>) async {
        let changedURLs = Set(changed.map(\.standardizedFileURL))
        let targets = flattenedNodes(from: roots).filter { node in
            node.children != nil
                && outlineView.isItemExpanded(node)
                && changedURLs.contains(node.url.standardizedFileURL)
        }
        for node in targets {
            await reloadChildren(of: node)
        }
    }

    private func reloadChildren(of node: Node) async {
        let requested = node.url
        let result: Result<[URL], ListingError>
        do {
            result = .success(try await lister.subfolders(of: requested))
        } catch {
            result = .failure(error)
        }
        guard node.url == requested else { return }
        let selectedURL = selectedNode?.url

        // Apply changes and reselect while isRestoringSelection is true so selectFolder is not called when the
        // selected row disappears during a reload (R33).
        isRestoringSelection = true
        defer { isRestoringSelection = false }
        applyListing(result, to: node)

        guard let selectedURL else { return }
        // When there is no selected row, select the nearest remaining ancestor.
        var candidate: URL? = selectedURL
        while let url = candidate {
            if let row = rowForURL(url) {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                if needsRevealSelectionAfterRename {
                    needsRevealSelectionAfterRename = false
                    outlineView.scrollRowToVisible(row)
                }
                return
            }
            let parent = url.deletingLastPathComponent()
            candidate = parent.standardizedFileURL.path == url.standardizedFileURL.path ? nil : parent
        }
    }

    private func flattenedNodes(from nodes: [Node]) -> [Node] {
        var result: [Node] = []
        for node in nodes {
            result.append(node)
            if let children = node.children {
                result.append(contentsOf: flattenedNodes(from: children))
            }
        }
        return result
    }

    private func rowForURL(_ url: URL) -> Int? {
        let target = url.standardizedFileURL
        guard let node = flattenedNodes(from: roots).first(where: {
            $0.url.standardizedFileURL == target
        }) else {
            return nil
        }
        let row = outlineView.row(forItem: node)
        return row >= 0 ? row : nil
    }
}

extension DirectoryTreeViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case let node as Node:
            return node.children?.count ?? 0
        case is FavoritesHeader:
            return favoriteEntries.count
        case nil:
            // The top level is [heading] + roots.
            return roots.count + 1
        default:
            return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? Node {
            return node.children![index]
        }
        if item is FavoritesHeader {
            return favoriteEntries[index]
        }
        return index == 0 ? favoritesHeader : roots[index - 1]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        // The heading can expand even with no registrations. Favorite items have no triangle.
        if item is FavoritesHeader { return true }
        guard let node = item as? Node else { return false }
        return node.folder.isExpandable
    }

    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        self.outlineView.beganDrag = true
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? Node,
              FavoriteCommands.trashTarget(role(for: node), roots: rootURLs) != nil else { return nil }
        return node.url as NSURL
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: any NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        if InternalDrag.urls(info) != nil {
            guard index == NSOutlineViewDropOnItemIndex else { return [] }
            let destination: URL
            if let node = item as? Node, node.folder.accessState != .denied {
                destination = node.url
            } else if let favorite = item as? FavoriteEntry, favorite.availability == .available {
                destination = favorite.url
            } else { return [] }
            let operation = InternalDrag.operation(info, destination: destination)
            if !operation.isEmpty { outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex) }
            return operation
        }
        // Existing behavior for external drags.
        guard let role = role(for: item), FavoriteCommands.acceptsFiles(role) else { return [] }
        guard let node = item as? Node,
              node.folder.accessState != .denied,
              let urls = fileURLs(from: info.draggingPasteboard) else {
            return []
        }
        // A folder cannot be dropped onto itself or a descendant (spec Edge Cases, R32).
        let destination = node.url.standardizedFileURL.pathComponents
        if urls.contains(where: { destination.starts(with: $0.standardizedFileURL.pathComponents) }) {
            return []
        }

        outlineView.setDropItem(node, dropChildIndex: NSOutlineViewDropOnItemIndex)

        let mask = info.draggingSourceOperationMask
        let preferred: NSDragOperation = NSEvent.modifierFlags.contains(.option)
            ? .copy
            : .move
        if mask.contains(preferred) {
            return preferred
        }
        return mask.contains(.copy) ? .copy : []
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: any NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        if let urls = InternalDrag.urls(info) {
            guard index == NSOutlineViewDropOnItemIndex else { return false }
            let destination: URL
            if let node = item as? Node, node.folder.accessState != .denied {
                destination = node.url
            } else if let favorite = item as? FavoriteEntry, favorite.availability == .available {
                destination = favorite.url
            } else { return false }
            guard !InternalDrag.operation(info, destination: destination).isEmpty else { return false }
            let copy = NSEvent.modifierFlags.contains(.option)
            Task { @MainActor in
                await coordinator.internalDrop(urls, to: destination, copy: copy)
            }
            return true
        }
        guard let role = role(for: item), FavoriteCommands.acceptsFiles(role) else { return false }
        guard let node = item as? Node,
              node.folder.accessState != .denied,
              let urls = fileURLs(from: info.draggingPasteboard),
              !urls.isEmpty else {
            return false
        }

        let destination = node.url
        let shouldCopy = NSEvent.modifierFlags.contains(.option)
        Task { @MainActor in
            if shouldCopy {
                await coordinator.copy(urls, to: destination)
            } else {
                await coordinator.move(urls, to: destination)
            }
        }
        return true
    }

    private func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        guard pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: options
        ) else {
            return nil
        }
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL]
        return objects?.map { $0 as URL }
    }
}

extension DirectoryTreeViewController: NSOutlineViewDelegate {
    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        switch item {
        case let node as Node:
            let cell = makeFolderCell(in: outlineView)
            prepareCell(cell, for: item)
            cell.imageView?.image = IconCatalog.treeIcon(for: node.folder.kind)
            if node !== editingTarget?.item {
                cell.textField?.stringValue = node.folder.name
            }
            cell.textField?.toolTip = node.folder.name
            if node.folder.accessState == .denied || node.folder.accessState == .unavailable {
                cell.textField?.textColor = .disabledControlTextColor
                cell.toolTip = l10n.text(.treeTooltipNotAccessible)
            } else {
                cell.textField?.textColor = .labelColor
                cell.toolTip = nil
            }
            return cell
        case is FavoritesHeader:
            let cell = makeFolderCell(in: outlineView)
            prepareCell(cell, for: item)
            cell.imageView?.image = IconCatalog.favoritesIcon()
            cell.textField?.stringValue = l10n.text(.treeFavorites)
            cell.textField?.toolTip = nil
            cell.textField?.textColor = .labelColor
            cell.toolTip = nil
            return cell
        case let entry as FavoriteEntry:
            let cell = makeFolderCell(in: outlineView)
            prepareCell(cell, for: item)
            cell.imageView?.image = IconCatalog.treeIcon(for: entry.kind)
            if entry !== editingTarget?.item {
                cell.textField?.stringValue = entry.name
            }
            cell.textField?.toolTip = entry.name
            if entry.availability == .missing {
                cell.textField?.textColor = .disabledControlTextColor
                cell.toolTip = l10n.text(.treeTooltipNotFound)
            } else {
                cell.textField?.textColor = .labelColor
                cell.toolTip = nil
            }
            return cell
        default:
            return nil
        }
    }

    private func makeFolderCell(in outlineView: NSOutlineView) -> NSTableCellView {
        let identifier = NSUserInterfaceItemIdentifier("FolderCell")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyDown
            icon.setAccessibilityElement(false)
            cell.addSubview(icon)
            cell.imageView = icon

            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            cell.addSubview(text)
            cell.textField = text

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),

                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let node = notification.userInfo?["NSObject"] as? Node else { return }
        Task { [weak self] in
            await self?.loadChildrenIfNeeded(node)
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isRestoringSelection, !outlineView.isTrackingMouse else { return }
        if let event = NSApp.currentEvent, event.type == .leftMouseDown {
            selectionChangeClickNumber = event.eventNumber
        }
        updateWatchSet()
        let row = outlineView.selectedRow
        guard row >= 0, let role = role(for: outlineView.item(atRow: row)) else { return }
        if case .favorite = role {
            refreshFavoriteAvailability()
        }
        // Do not switch the list for the heading (FR-065). Do not navigate the actual hierarchy for favorite items
        // (FR-063).
        guard let url = FavoriteCommands.folderToShow(for: role) else { return }
        // Selection from the tree does not change treeSyncRequest, so cancel an in-progress synchronization so it
        // does not overwrite the user's selection (R31).
        revealTask?.cancel()
        revealTask = nil
        Task { [weak self] in
            await self?.model.selectFolder(url)
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        updateWatchSet()
    }

    func outlineViewItemWillCollapse(_ notification: Notification) {
        // Clicking the disclosure button sometimes does not change the first responder. Commit before the row
        // disappears (R51).
        guard let target = editingTarget,
              let collapsing = notification.userInfo?["NSObject"] as AnyObject? else {
            return
        }
        var ancestor = outlineView.parent(forItem: target.item) as AnyObject?
        while let current = ancestor {
            if current === collapsing {
                finishEditing(commit: true, restoresFocus: true)
                return
            }
            ancestor = outlineView.parent(forItem: current) as AnyObject?
        }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        updateWatchSet()
    }
}

extension DirectoryTreeViewController: NSTextFieldDelegate {
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard editingTarget != nil else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing(commit: true, restoresFocus: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Esc restores the display name from before editing (US1-AS32).
            finishEditing(commit: false, restoresFocus: true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        // Commit on a click elsewhere. Do not change focus at the click target (A-31).
        guard editingTarget != nil, !isFinishingEdit else { return }
        finishEditing(commit: true, restoresFocus: false)
    }
}

extension DirectoryTreeViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Menu key equivalents process Return and ⌘⌫ before the field editor. Unless disabled, Return would not
        // commit while editing and ⌘⌫ would remove the favorite (R53, FR-102).
        if editingTarget != nil {
            switch menuItem.action {
            case #selector(rename(_:)),
                 #selector(renameFavoriteFromMenu(_:)),
                 #selector(renameFolderFromMenu(_:)),
                 #selector(moveToTrash(_:)),
                 #selector(trashFolderFromMenu(_:)),
                 #selector(paste(_:)),
                 #selector(movePaste(_:)),
                 #selector(revealInFinder(_:)),
                 #selector(addToFavorites(_:)),
                 #selector(removeFavoriteFromMenu(_:)):
                return false
            default:
                break
            }
        }

        switch menuItem.action {
        case #selector(rename(_:)):
            // Only favorite items and non-root folders. Disabled for the heading, roots, and no selection
            // (US1-AS35, US1-AS45; FR-099, FR-103).
            return editingTarget(for: selectedItem) != nil
        case #selector(renameFavoriteFromMenu(_:)):
            if case .favorite = editingTarget(for: menuItem.representedObject) { return true }
            return false
        case #selector(renameFolderFromMenu(_:)):
            if case .folder = editingTarget(for: menuItem.representedObject) { return true }
            return false
        case #selector(paste(_:)), #selector(movePaste(_:)):
            return fileTargetNode(for: menuItem) != nil
                && FileContextMenu.pasteboardHasFileURLs()
        case #selector(revealInFinder(_:)):
            return fileTargetNode(for: menuItem) != nil
        case #selector(moveToTrash(_:)):
            // For a favorite item, ⌘⌫ is Remove from Favorites (FR-064); for a non-root folder, it is Move to Trash
            // (FR-079).
            if selectedFavoriteEntry != nil {
                menuItem.title = l10n.text(.menuFileRemoveFromFavorites)
                return true
            }
            menuItem.title = l10n.text(.menuFileTrash)
            return FavoriteCommands.trashTarget(role(for: selectedItem), roots: rootURLs) != nil
        case #selector(trashFolderFromMenu(_:)):
            return FavoriteCommands.trashTarget(role(for: targetItem(for: menuItem)), roots: rootURLs) != nil
        case #selector(addToFavorites(_:)):
            return FavoriteCommands.canAdd(role(for: targetItem(for: menuItem)), favorites: favorites)
        case #selector(removeFavoriteFromMenu(_:)):
            return FavoriteCommands.removalTarget(role(for: menuItem.representedObject)) != nil
        default:
            return true
        }
    }
}

extension DirectoryTreeViewController: NSMenuDelegate {
    /// Rebuilds items based on the right-clicked row's role. Uses the selected row when opened from the keyboard.
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Commit the name being edited before opening the menu. Restore focus because the right-click target is the
        // tree (R51).
        if editingTarget != nil {
            finishEditing(commit: true, restoresFocus: editingFieldHasFocus)
        }
        menu.removeAllItems()
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0,
              let item = outlineView.item(atRow: row),
              let role = role(for: item) else {
            return
        }
        // No items for the heading (do not show a menu).
        for kind in FavoriteCommands.contextMenu(for: role, roots: rootURLs) {
            menu.addItem(makeContextMenuItem(kind, representing: item))
        }
    }
}
