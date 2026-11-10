import AppKit
import FolzioCore
import FolzioLocalization
import Quartz

@MainActor
private final class FileListTableView: NSTableView {
    var onSpace: ((NSEvent) -> Bool)?
    /// Takes control of the Quick Look panel while this table has the focus (FR-247, research.md R2).
    var quickLook: QuickLookCoordinator?

    // The panel control methods are not main-actor isolated in the SDK, but AppKit calls them on the main thread.
    nonisolated override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { quickLook != nil }
    }

    nonisolated override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.attach(to: panel) }
    }

    nonisolated override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { quickLook?.detach(from: panel) }
    }
    var onReturn: (() -> Bool)?
    var onEscape: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        if event.isPlainEscape, onEscape?() == true {
            return
        }

        if event.specialKey == .carriageReturn
            || event.specialKey == .enter
            || event.charactersIgnoringModifiers == "\r" {
            let disallowed: NSEvent.ModifierFlags = [.command, .option, .control]
            if event.modifierFlags.intersection(disallowed).isEmpty,
               onReturn?() == true {
                return
            }
        }

        // Do not pass to the default action (such as moving to the end) when the menu item is disabled (R26).
        if event.isCommandOnlyVerticalArrow {
            return
        }

        if event.charactersIgnoringModifiers == " ", onSpace?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class FileListIconCell: NSTableCellView {
    let iconView = NSImageView()
    let nameField = NSTextField(labelWithString: "")
    var iconTask: Task<Void, Never>?
    var representedURL: URL?
    /// Content version of the file whose thumbnail is shown or requested (FR-228).
    var representedVersion: FileContentVersion?
    var iconPointSize: Double = 0
    var iconScale: Double = 0

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setAccessibilityElement(false)
        addSubview(iconView)
        imageView = iconView

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.lineBreakMode = .byTruncatingMiddle
        addSubview(nameField)
        textField = nameField

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            nameField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func cancelIconRequest(using provider: any ThumbnailProviding) {
        iconTask?.cancel()
        iconTask = nil
        if let url = representedURL, iconPointSize > 0, iconScale > 0 {
            provider.cancel(
                for: url,
                pointSize: iconPointSize,
                scale: iconScale,
                version: representedVersion
            )
        }
        representedURL = nil
        representedVersion = nil
    }
}

@MainActor
final class ListModeView: NSView {
    private let model: BrowserModel
    private let provider: any ThumbnailProviding
    private let scrollView = NSScrollView()
    private let tableView = FileListTableView()

    /// Coordinator of the Quick Look panel, set by the file list controller (FR-247).
    var quickLook: QuickLookCoordinator? {
        didSet { tableView.quickLook = quickLook }
    }
    var onRename: ((URL, String) async -> Void)?
    /// Commits the name of a folder created with New Folder, without the rename confirmation (FR-211).
    var onRenameNewFolder: ((URL, String) async -> Void)?
    var onOpenItem: ((URL) -> Void)?
    /// A drop on a folder item, from this app's views or from another app: the URLs, the destination folder, and
    /// whether to copy (FR-020, FR-345, FR-346).
    var onDrop: (([URL], URL, Bool) -> Void)?
    var onImageDrop: ((any NSDraggingInfo, URL) -> Bool)?
    /// Esc. Returns true when handled (ends search results; FR-086).
    var onEscape: (() -> Bool)? {
        get { tableView.onEscape }
        set { tableView.onEscape = newValue }
    }

    var contextMenu: NSMenu? {
        get { tableView.menu }
        set { tableView.menu = newValue }
    }

    private static var sortEntries: [(column: SortColumn, title: String)] {
        [
            (.name, l10n.text(.listColumnName)),
            (.creationDate, l10n.text(.listColumnCreationDate)),
            (.kind, l10n.text(.listColumnKind)),
            (.size, l10n.text(.listColumnSize)),
            (.modificationDate, l10n.text(.listColumnModificationDate)),
            (.location, l10n.text(.listColumnLocation)),
        ]
    }

    /// Title of the column header menu item (and of the column) for a toggleable column.
    private static func title(of column: ListColumn) -> String {
        switch column {
        case .creationDate: return l10n.text(.listColumnCreationDate)
        case .kind: return l10n.text(.listColumnKind)
        case .size: return l10n.text(.listColumnSize)
        case .modificationDate: return l10n.text(.listColumnModificationDate)
        }
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // Show "0 bytes" instead of "Zero KB" for empty files.
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    /// Text of the Size column: `--` for folders and `..`, which have no size (TAK-47, FR-276).
    private static func sizeText(of file: MediaFile) -> String {
        file.hasFileSize ? sizeFormatter.string(fromByteCount: file.fileSize) : "--"
    }

    private var lastURLs: [URL] = []
    /// `BrowserModel.contentChangeGeneration` already applied to the rows (FR-228).
    private var lastContentChangeGeneration = 0
    private var isApplyingSelection = false
    private var isSyncingSortDescriptors = false
    private var sortMenuInstalled = false
    private var sortMenuItems: [NSMenuItem] = []
    /// Menu of the column header that shows or hides columns (TAK-47). Items are rebuilt each time it opens.
    private let columnsMenu = NSMenu()
    private var renamingURL: URL?
    private var renamingOriginalName: String?
    /// Whether the current rename names a folder just created with New Folder (FR-211, research.md R8).
    private var renamingIsNewFolder = false
    private var isFinishingRename = false

    init(model: BrowserModel, provider: any ThumbnailProviding) {
        self.model = model
        self.provider = provider
        super.init(frame: .zero)
        setup()
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )
        applyModel()
        observeModel()
    }

    @objc private func displayLanguageDidChange() {
        for (identifier, key) in [("name", TextKey.listColumnName), ("creationDate", .listColumnCreationDate),
                                  ("kind", .listColumnKind), ("size", .listColumnSize),
                                  ("modificationDate", .listColumnModificationDate),
                                  ("location", .listColumnLocation)] {
            tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(identifier))?.title = l10n.text(key)
        }
        updateSortMenuItems()
        refreshVisibleLocalizedCells()
    }

    private func refreshVisibleLocalizedCells() {
        let range = tableView.rows(in: tableView.visibleRect)
        guard range.location != NSNotFound else { return }
        let files = model.listing.files
        for row in range.location..<min(range.location + range.length, files.count) {
            if files[row].kind == .parent {
                let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
                if column >= 0,
                   let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? FileListIconCell {
                    cell.nameField.setAccessibilityLabel(l10n.text(.listParentRow))
                }
            }
            for (identifier, text) in [("creationDate", l10n.dateTime(files[row].creationDate)),
                                       ("modificationDate", l10n.dateTime(files[row].modificationDate)),
                                       ("kind", files[row].localizedKindName(using: l10n.kindNames).typeDescription)] {
                let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(identifier))
                guard column >= 0,
                      let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView else { continue }
                cell.textField?.stringValue = text
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var focusView: NSView { tableView }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        installSortMenuIfNeeded()
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 20
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes(ExternalImageDrag.registeredTypes)
        InternalDrag.register(tableView)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask(ExternalDrag.sourceOperationMaskOutsideApp, forLocal: false)
        // Space toggles the Quick Look panel instead of video playback (FR-247, FR-248).
        tableView.onSpace = { [weak self] event in
            self?.quickLook?.handleSpace(event) ?? false
        }
        tableView.onReturn = { [weak self] in
            guard let self else { return false }
            // Do not start renaming inside a zip (FR-073). Consume the key.
            guard self.model.focusedItemCommands.allowsFileOperations else { return true }
            return self.beginRenaming()
        }
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick(_:))

        addColumn(identifier: "name", title: l10n.text(.listColumnName), width: 220)
        addColumn(identifier: "creationDate", title: l10n.text(.listColumnCreationDate), width: 150)
        addColumn(identifier: "kind", title: l10n.text(.listColumnKind), width: 150)
        addColumn(identifier: "size", title: l10n.text(.listColumnSize), width: 90)
        addColumn(identifier: "modificationDate", title: l10n.text(.listColumnModificationDate), width: 150)
        // Shown only while search results are displayed (FR-084, R37).
        addColumn(identifier: "location", title: l10n.text(.listColumnLocation), width: 180)
        tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("location"))?.isHidden = true
        updateColumnVisibility()

        // Right-clicking the column header opens the menu that shows or hides columns, as in Finder (TAK-47).
        // The row context menu (`tableView.menu`) is not used for the header.
        columnsMenu.delegate = self
        columnsMenu.autoenablesItems = false
        tableView.headerView?.menu = columnsMenu

        scrollView.documentView = tableView
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @objc private func handleDoubleClick(_ sender: Any?) {
        let row = tableView.clickedRow
        let files = model.listing.files
        guard row >= 0, row < files.count else { return }

        let url = files[row].url
        if tableView.selectedRowIndexes != IndexSet(integer: row) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        onOpenItem?(url)
    }

    /// On-screen frame of the icon of the row for `url`, where Quick Look zooms from and back to. `.zero` when the
    /// row is not visible (FR-247, EC-173).
    func quickLookSourceFrame(for url: URL) -> NSRect {
        guard let window = tableView.window,
              let row = model.listing.files.firstIndex(where: { $0.url == url }) else {
            return .zero
        }
        let rowRect = tableView.rect(ofRow: row)
        guard tableView.visibleRect.intersects(rowRect) else { return .zero }
        let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        let cellRect = column >= 0 ? tableView.frameOfCell(atColumn: column, row: row) : rowRect
        let iconRect = NSRect(x: cellRect.minX + 2, y: cellRect.midY - 8, width: 16, height: 16)
        return window.convertToScreen(tableView.convert(iconRect, to: nil))
    }

    /// Scrolls the focused row into view (following after going back; FR-070).
    func scrollToFocused() {
        guard let focused = model.selection.focused,
              let row = model.listing.files.firstIndex(where: { $0.url == focused }) else {
            return
        }
        tableView.scrollRowToVisible(row)
    }

    /// Origin of the visible list range (used to preserve the scroll position; SC-017).
    var visibleOrigin: CGPoint {
        scrollView.contentView.bounds.origin
    }

    /// Restores the captured scroll position. Clamps to the document range when rows were removed.
    func restoreVisibleOrigin(_ origin: CGPoint) {
        let clipView = scrollView.contentView
        let proposed = NSRect(origin: origin, size: clipView.bounds.size)
        let constrained = clipView.constrainBoundsRect(proposed).origin
        clipView.scroll(to: constrained)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func addColumn(identifier: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = 80
        column.sortDescriptorPrototype = NSSortDescriptor(key: identifier, ascending: true)
        tableView.addTableColumn(column)
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.listing.files
            _ = model.selection.selected
            _ = model.selection.focused
            _ = model.sortOrder
            _ = model.visibleColumns
            _ = model.listing.search
            _ = model.contentChangeGeneration
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyModel()
                self?.observeModel()
            }
        }
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        applyModel()
    }

    private func applyModel() {
        updateLocationColumn()
        updateColumnVisibility()
        // For a hidden mode, defer row reloading and selection updates until it is shown (viewDidUnhide).
        // This avoids blocking the main thread for an invisible list when opening a zip with 10,000 rows (SC-015).
        guard !isHidden else {
            syncSortDescriptors()
            updateSortMenuItems()
            return
        }
        let urls = model.listing.files.map(\.url)
        let selected = SelectionIndex.indexes(of: model.selection.selected, in: urls)

        isApplyingSelection = true
        if urls != lastURLs {
            if renamingURL != nil {
                finishRenaming(commit: false)
            }
            lastURLs = urls
            lastContentChangeGeneration = model.contentChangeGeneration
            tableView.reloadData()
        } else if lastContentChangeGeneration != model.contentChangeGeneration {
            // Several changes may have happened while hidden; then only the latest set is known, so reload all rows.
            let missedChanges = model.contentChangeGeneration &- lastContentChangeGeneration != 1
            lastContentChangeGeneration = model.contentChangeGeneration
            if missedChanges {
                if renamingURL != nil {
                    finishRenaming(commit: false)
                }
                tableView.reloadData()
            } else {
                reloadReplacedRows(urls: urls)
            }
        }
        if tableView.selectedRowIndexes != selected {
            tableView.selectRowIndexes(selected, byExtendingSelection: false)
        }
        isApplyingSelection = false

        if let focused = model.selection.focused, let row = urls.firstIndex(of: focused) {
            tableView.scrollRowToVisible(row)
        }

        syncSortDescriptors()
        updateSortMenuItems()
        refreshVisibleLocalizedCells()
    }

    /// Reloads only the rows whose content was replaced at the same URL, keeping the selection and scroll position
    /// (FR-228, FR-229). Skips the row being renamed so the edit is not discarded.
    private func reloadReplacedRows(urls: [URL]) {
        let changed = model.changedContentURLs
        guard !changed.isEmpty else { return }
        var rows = IndexSet()
        for (row, url) in urls.enumerated() where changed.contains(url) && url != renamingURL {
            rows.insert(row)
        }
        guard !rows.isEmpty else { return }
        tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
    }

    /// Shows the Location column only while search results are displayed.
    private func updateLocationColumn() {
        let hidden = !model.isShowingSearchResults
        guard let column = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("location")),
              column.isHidden != hidden else { return }
        column.isHidden = hidden
    }

    /// Shows the columns the user chose besides the name column, which is always shown (TAK-47, FR-274).
    private func updateColumnVisibility() {
        for column in ListColumn.allCases {
            guard let tableColumn = tableView.tableColumn(
                withIdentifier: NSUserInterfaceItemIdentifier(column.rawValue)
            ) else { continue }
            let hidden = !model.visibleColumns.contains(column)
            if tableColumn.isHidden != hidden {
                tableColumn.isHidden = hidden
            }
        }
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let column = ListColumn(rawValue: rawValue) else { return }
        model.setColumn(column, visible: !model.visibleColumns.contains(column))
    }

    private func syncSortDescriptors() {
        let order = model.sortOrder
        let current = tableView.sortDescriptors.first
        guard current?.key != order.column.rawValue
            || current?.ascending != order.ascending else {
            return
        }

        isSyncingSortDescriptors = true
        tableView.sortDescriptors = [
            NSSortDescriptor(key: order.column.rawValue, ascending: order.ascending)
        ]
        isSyncingSortDescriptors = false
    }

    private func installSortMenuIfNeeded() {
        guard !sortMenuInstalled else { return }
        guard let viewMenu = NSApp.mainMenu?.items
            .first(where: { $0.submenu?.identifier == NSUserInterfaceItemIdentifier("menu.view") })?
            .submenu else {
            return
        }
        sortMenuInstalled = true

        let submenu: NSMenu
        if let existing = viewMenu.items
            .first(where: { $0.submenu?.identifier == NSUserInterfaceItemIdentifier("menu.view.sort") })?
            .submenu {
            submenu = existing
        } else {
            submenu = NSMenu(title: l10n.text(.menuViewSortBy))
            submenu.identifier = NSUserInterfaceItemIdentifier("menu.view.sort")
            let parentItem = NSMenuItem(title: l10n.text(.menuViewSortBy), action: nil, keyEquivalent: "")
            MainMenu.bind(parentItem, .menuViewSortBy)
            parentItem.submenu = submenu
            viewMenu.addItem(parentItem)
        }

        sortMenuItems = Self.sortEntries.enumerated().map { index, entry in
            let item = NSMenuItem(
                title: entry.title,
                action: #selector(chooseSortColumn(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            submenu.addItem(item)
            return item
        }
        updateSortMenuItems()
    }

    private func updateSortMenuItems() {
        guard !sortMenuItems.isEmpty else { return }
        let order = model.sortOrder
        for (index, item) in sortMenuItems.enumerated() {
            guard index < Self.sortEntries.count else { break }
            let entry = Self.sortEntries[index]
            let isActive = entry.column == order.column
            item.state = isActive ? .on : .off
            item.title = isActive
                ? l10n.text(
                    order.ascending ? .listSortAscending : .listSortDescending,
                    .text(entry.title)
                )
                : entry.title
        }
    }

    @objc private func chooseSortColumn(_ sender: NSMenuItem) {
        guard sender.tag >= 0, sender.tag < Self.sortEntries.count else { return }
        let column = Self.sortEntries[sender.tag].column
        // Location can be selected only while search results are displayed (FR-084).
        guard column != .location || model.isShowingSearchResults else { return }
        let current = model.sortOrder
        let ascending = current.column == column ? !current.ascending : true
        model.sortOrder = SortOrder(column: column, ascending: ascending)
        updateSortMenuItems()
    }

    /// Whether the rows on screen already include `url`. A listing change reloads the table and cancels any rename, so
    /// naming a new folder waits until its row has been applied (FR-210).
    func hasAppliedRow(for url: URL) -> Bool {
        !isHidden && lastURLs.contains(url)
    }

    /// Whether the last context click hit no row, so the file list shows the background menu (FR-213, R7).
    var isContextClickOnBackground: Bool {
        tableView.clickedRow < 0
    }

    /// Starts renaming the single selected row. Pass `isNewFolder: true` only right after New Folder, so the commit
    /// skips the rename confirmation (FR-211).
    @discardableResult
    func beginRenaming(isNewFolder: Bool = false) -> Bool {
        guard renamingURL == nil else { return false }

        let selected = model.selection.selected
        guard selected.count == 1,
              let focused = model.selection.focused,
              selected.contains(focused),
              let row = model.listing.files.firstIndex(where: { $0.url == focused }),
              let window = tableView.window else {
            return false
        }

        tableView.scrollRowToVisible(row)
        tableView.layoutSubtreeIfNeeded()
        guard let cell = tableView.view(
            atColumn: 0,
            row: row,
            makeIfNecessary: true
        ) as? NSTableCellView,
            let field = cell.textField else {
            return false
        }

        renamingURL = focused
        renamingOriginalName = field.stringValue
        renamingIsNewFolder = isNewFolder
        field.stringValue = focused.lastPathComponent
        setEditingAppearance(field, editing: true)

        guard window.makeFirstResponder(field) else {
            finishRenaming(commit: false)
            return false
        }

        if let editor = field.currentEditor() as? NSTextView {
            let baseName = (field.stringValue as NSString).deletingPathExtension
            editor.selectedRange = NSRange(location: 0, length: (baseName as NSString).length)
        }
        return true
    }

    private func finishRenaming(commit: Bool, newNameOverride: String? = nil) {
        guard !isFinishingRename,
              let url = renamingURL,
              let oldName = renamingOriginalName else {
            return
        }
        isFinishingRename = true
        defer { isFinishingRename = false }

        renamingURL = nil
        renamingOriginalName = nil
        let isNewFolder = renamingIsNewFolder
        renamingIsNewFolder = false

        var newName = oldName
        if let row = model.listing.files.firstIndex(where: { $0.url == url }),
           let cell = tableView.view(
               atColumn: 0,
               row: row,
               makeIfNecessary: false
           ) as? NSTableCellView,
           let field = cell.textField {
            let rawName = newNameOverride ?? field.stringValue
            newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            setEditingAppearance(field, editing: false)
            field.stringValue = oldName
        }

        if let window = tableView.window,
           window.firstResponder !== tableView {
            window.makeFirstResponder(tableView)
        }

        guard commit, !newName.isEmpty, newName != oldName else { return }
        let handler = isNewFolder ? onRenameNewFolder : onRename
        Task { @MainActor in
            await handler?(url, newName)
        }
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
}

extension ListModeView: NSMenuDelegate {
    /// Builds the column header menu: one checkable item per toggleable column. The name column has no item because it
    /// is always shown (TAK-47, FR-273).
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === columnsMenu else { return }
        menu.removeAllItems()
        for column in ListColumn.allCases {
            let item = NSMenuItem(title: Self.title(of: column), action: #selector(toggleColumn(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = column.rawValue
            item.state = model.visibleColumns.contains(column) ? .on : .off
            menu.addItem(item)
        }
    }
}

extension ListModeView: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.action == #selector(chooseSortColumn(_:)),
              Self.sortEntries.indices.contains(menuItem.tag) else { return true }
        // Location in View > Sort is enabled only while search results are displayed (FR-084).
        return Self.sortEntries[menuItem.tag].column != .location || model.isShowingSearchResults
    }
}

extension ListModeView: NSTableViewDataSource {
    /// The destination of a drop on `row`: a folder row, or the displayed folder for the gaps between rows, empty
    /// space, and rows that are not folders (FR-163, FR-349). Row -1 is the whole table, as set for a background drop.
    private func dropTarget(row: Int, dropOperation: NSTableView.DropOperation) -> (destination: URL, row: Int?)? {
        let files = model.listing.files
        let onItem = dropOperation == .on && files.indices.contains(row)
        guard let target = FileListDropTarget.resolve(
            kind: onItem ? files[row].kind : nil,
            index: onItem ? row : nil,
            isBrowsingArchive: model.isBrowsingArchive,
            isShowingSearchResults: model.isShowingSearchResults,
            state: model.listing.state
        ) else { return nil }
        switch target {
        case .folder(let index): return (files[index].url, index)
        case .displayedFolder: return (model.listing.folder, nil)
        }
    }

    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard let target = dropTarget(row: row, dropOperation: dropOperation) else { return [] }
        let operation = InternalDrag.urls(info) != nil
            ? InternalDrag.operation(info, destination: target.destination)
            : ExternalDrag.operation(info, destination: target.destination)
        guard !operation.isEmpty else { return [] }
        // A background drop highlights the whole table (row -1 with `.on`).
        tableView.setDropRow(target.row ?? -1, dropOperation: .on)
        return operation
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let target = dropTarget(row: row, dropOperation: dropOperation) else { return false }
        let destination = target.destination
        if let urls = InternalDrag.urls(info) {
            guard !InternalDrag.operation(info, destination: destination).isEmpty else { return false }
            InternalDrag.markAccepted(info.draggingSequenceNumber)
            onDrop?(urls, destination, NSEvent.modifierFlags.contains(.option))
            return true
        }
        // A drop from another app, such as Finder (FR-345, FR-346).
        guard let drop = ExternalDrag.dropOperation(info, destination: destination) else { return onImageDrop?(info, destination) ?? false }
        onDrop?(drop.urls, destination, drop.kind == .copy)
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.listing.files.count
    }
}

extension ListModeView: NSTableViewDelegate {
    func tableView(
        _ tableView: NSTableView,
        sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
        guard !isSyncingSortDescriptors else { return }
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let column = SortColumn(rawValue: key) else {
            return
        }

        model.sortOrder = SortOrder(column: column, ascending: descriptor.ascending)
        updateSortMenuItems()
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn, row < model.listing.files.count else { return nil }
        let file = model.listing.files[row]

        if tableColumn.identifier.rawValue == "name" {
            return nameCell(for: file, identifier: tableColumn.identifier, in: tableView)
        }

        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: tableColumn.identifier, owner: self)
            as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = tableColumn.identifier

            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            text.lineBreakMode = .byTruncatingMiddle
            text.delegate = self
            setEditingAppearance(text, editing: false)
            cell.addSubview(text)
            cell.textField = text

            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        if let textField = cell.textField, renamingURL != file.url {
            setEditingAppearance(textField, editing: false)
        }

        switch tableColumn.identifier.rawValue {
        case "creationDate":
            cell.textField?.stringValue = l10n.dateTime(file.creationDate)
        case "modificationDate":
            cell.textField?.stringValue = l10n.dateTime(file.modificationDate)
        case "size":
            cell.textField?.stringValue = Self.sizeText(of: file)
        case "kind":
            cell.textField?.stringValue = file.localizedKindName(using: l10n.kindNames).typeDescription
        case "location":
            cell.textField?.stringValue = model.listing.search?.location(of: file.url) ?? ""
        default:
            cell.textField?.stringValue = ""
        }

        return cell
    }

    private func nameCell(
        for file: MediaFile,
        identifier: NSUserInterfaceItemIdentifier,
        in tableView: NSTableView
    ) -> FileListIconCell {
        let cell: FileListIconCell
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self)
            as? FileListIconCell {
            cell = reused
        } else {
            cell = FileListIconCell(identifier: identifier)
            cell.nameField.delegate = self
        }

        if !file.kind.isMedia {
            // Do not request thumbnails for zip files, directories, or `..`; show the kind icon instead.
            cell.cancelIconRequest(using: provider)
            cell.iconPointSize = 0
            cell.iconScale = 0
            cell.representedURL = file.url
            cell.representedVersion = nil
            cell.iconView.image = IconCatalog.listItemIcon(for: file.kind, pointSize: 16)
            cell.iconView.contentTintColor = IconCatalog.tintColor(for: file.kind)
            if renamingURL != file.url {
                setEditingAppearance(cell.nameField, editing: false)
            }
            if file.kind == .parent {
                cell.nameField.stringValue = ".."
                cell.nameField.setAccessibilityLabel(l10n.text(.listParentRow))
            } else {
                cell.nameField.stringValue = file.name
                cell.nameField.setAccessibilityLabel(nil)
            }
            return cell
        }
        cell.iconView.contentTintColor = nil
        cell.nameField.setAccessibilityLabel(nil)

        if cell.representedURL != file.url || cell.representedVersion != file.contentVersion {
            cell.cancelIconRequest(using: provider)
            cell.representedURL = file.url
            cell.representedVersion = file.contentVersion
            cell.iconView.image = file.kind.mediaKind.flatMap { IconCatalog.fallbackIcon(for: $0) }

            let scale = Double(
                window?.backingScaleFactor
                    ?? NSScreen.main?.backingScaleFactor
                    ?? 2
            )
            let pointSize = 16.0
            cell.iconPointSize = pointSize
            cell.iconScale = scale

            let provider = self.provider
            let url = file.url
            let version = file.contentVersion
            cell.iconTask = Task { [weak cell] in
                let image = await provider.thumbnail(
                    for: url,
                    pointSize: pointSize,
                    scale: scale,
                    version: version
                )
                guard !Task.isCancelled,
                      let cell,
                      cell.representedURL == url,
                      cell.representedVersion == version,
                      let image else {
                    return
                }
                cell.iconView.image = NSImage(
                    cgImage: image,
                    size: NSSize(width: 16, height: 16)
                )
            }
        }

        if renamingURL != file.url {
            setEditingAppearance(cell.nameField, editing: false)
        }
        cell.nameField.stringValue = file.name
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection else { return }

        let files = model.listing.files
        let urls = tableView.selectedRowIndexes.compactMap { row in
            row < files.count ? files[row].url : nil
        }

        let focusedRow: Int
        if tableView.selectedRow >= 0 {
            focusedRow = tableView.selectedRow
        } else {
            focusedRow = tableView.selectedRowIndexes.first ?? -1
        }
        let focused = focusedRow >= 0 && focusedRow < files.count
            ? files[focusedRow].url
            : nil

        model.select(Set(urls), focused: focused)
    }
}

extension ListModeView: NSTextFieldDelegate {
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard renamingURL != nil else { return false }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishRenaming(commit: true, newNameOverride: textView.string)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            finishRenaming(commit: false)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard renamingURL != nil, !isFinishingRename else { return }
        finishRenaming(commit: true)
    }
}

extension ListModeView {
    func tableView(
        _ tableView: NSTableView,
        pasteboardWriterForRow row: Int
    ) -> NSPasteboardWriting? {
        guard row >= 0, row < model.listing.files.count else { return nil }
        // Do not start a drag for rows inside a zip or `..` (FR-073).
        guard model.itemCommands(forRowAt: row).allowsFileOperations else { return nil }
        return model.listing.files[row].url as NSURL
    }
}
