import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
private final class ThumbnailCollectionView: NSCollectionView {
    var onArrowKey: ((NSEvent.SpecialKey, NSEvent.ModifierFlags) -> Bool)?
    var onReturnKey: (() -> Bool)?
    var onEscape: (() -> Bool)?
    var onDoubleClickItem: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let indexPath = indexPathForItem(at: point) else { return }
        onDoubleClickItem?(indexPath.item)
    }

    override func keyDown(with event: NSEvent) {
        if event.isPlainEscape, onEscape?() == true {
            return
        }

        if event.specialKey == .carriageReturn
            || event.specialKey == .enter
            || event.charactersIgnoringModifiers == "\r" {
            let disallowed: NSEvent.ModifierFlags = [.command, .option, .control]
            if event.modifierFlags.intersection(disallowed).isEmpty,
               onReturnKey?() == true {
                return
            }
        }

        // Do not pass to the default action when the menu item is disabled (R26).
        if event.isCommandOnlyVerticalArrow {
            return
        }

        if let key = event.specialKey {
            switch key {
            case .leftArrow, .rightArrow, .upArrow, .downArrow:
                if onArrowKey?(key, event.modifierFlags) == true {
                    return
                }
            default:
                break
            }
        }
        super.keyDown(with: event)
    }
}

@MainActor
private final class RenameTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        guard accepted else { return false }
        selectBaseName()
        return true
    }

    func selectBaseName() {
        guard let editor = currentEditor() as? NSTextView else { return }
        let baseName = (stringValue as NSString).deletingPathExtension
        editor.selectedRange = NSRange(location: 0, length: (baseName as NSString).length)
    }
}

@MainActor
private final class ThumbnailItemView: NSCollectionViewItem {
    private let thumbnailImageView = NSImageView()
    private let nameLabel = RenameTextField(wrappingLabelWithString: "")

    private(set) var representedURL: URL?
    var onCommitRename: ((URL, String) -> Void)?

    private var originalName: String?
    private var isRenaming = false

    override func loadView() {
        let cellView = NSView()
        cellView.wantsLayer = true
        cellView.layer?.cornerRadius = 6
        cellView.layer?.masksToBounds = true

        thumbnailImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.imageAlignment = .alignCenter
        thumbnailImageView.setAccessibilityLabel(l10n.text(.a11yThumbnail))
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.alignment = .center
        nameLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        nameLabel.textColor = .labelColor
        nameLabel.maximumNumberOfLines = 2
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.cell?.wraps = true
        nameLabel.cell?.isScrollable = false
        nameLabel.cell?.truncatesLastVisibleLine = true
        nameLabel.delegate = self

        cellView.addSubview(thumbnailImageView)
        cellView.addSubview(nameLabel)

        NSLayoutConstraint.activate([
            thumbnailImageView.topAnchor.constraint(equalTo: cellView.topAnchor, constant: 4),
            thumbnailImageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
            thumbnailImageView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
            thumbnailImageView.heightAnchor.constraint(equalTo: thumbnailImageView.widthAnchor),

            nameLabel.topAnchor.constraint(equalTo: thumbnailImageView.bottomAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -2),
            nameLabel.heightAnchor.constraint(equalToConstant: 30),
            nameLabel.bottomAnchor.constraint(lessThanOrEqualTo: cellView.bottomAnchor, constant: -2),
        ])

        self.view = cellView
        imageView = thumbnailImageView
        textField = nameLabel
    }

    @objc private func displayLanguageDidChange() {
        thumbnailImageView.setAccessibilityLabel(l10n.text(.a11yThumbnail))
        if let representedURL, ParentLink.isParentLink(representedURL) {
            let label = l10n.text(.listParentRow)
            view.setAccessibilityLabel(label)
            if !isRenaming { nameLabel.setAccessibilityLabel(label) }
        }
    }

    override var isSelected: Bool {
        didSet { updateSelectionAppearance() }
    }

    override var highlightState: NSCollectionViewItem.HighlightState {
        didSet { updateSelectionAppearance() }
    }

    func configure(with file: MediaFile, iconPointSize: Double) {
        if isRenaming, representedURL != file.url {
            endRenaming(commit: false, restoreFocus: false)
        }
        let urlChanged = representedURL != file.url
        representedURL = file.url
        if !isRenaming {
            nameLabel.stringValue = file.name
            nameLabel.setAccessibilityLabel(file.name)
        }
        let accessibilityName = file.kind == .parent ? l10n.text(.listParentRow) : file.name
        view.setAccessibilityLabel(accessibilityName)
        if !file.kind.isMedia {
            if !isRenaming {
                nameLabel.setAccessibilityLabel(accessibilityName)
            }
            showListItemIcon(for: file.kind, pointSize: iconPointSize)
        } else if urlChanged || thumbnailImageView.image == nil {
            thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
            thumbnailImageView.contentTintColor = nil
            thumbnailImageView.image = NSWorkspace.shared.icon(forFile: file.url.path)
        }
        updateSelectionAppearance()
    }

    /// Kind icon for zip file, directory, and `..` rows. Does not request a thumbnail.
    func showListItemIcon(for kind: ListItemKind, pointSize: Double) {
        thumbnailImageView.imageScaling = .scaleNone
        thumbnailImageView.contentTintColor = .secondaryLabelColor
        thumbnailImageView.image = IconCatalog.listItemIcon(for: kind, pointSize: CGFloat(pointSize))
    }

    @discardableResult
    func beginRenaming() -> Bool {
        guard !isRenaming,
              representedURL != nil,
              let window = view.window else {
            return false
        }
        originalName = nameLabel.stringValue
        isRenaming = true
        setRenamingAppearance(true)
        guard window.makeFirstResponder(nameLabel) else {
            endRenaming(commit: false, restoreFocus: false)
            return false
        }
        nameLabel.selectBaseName()
        return true
    }

    func setThumbnailImage(_ image: CGImage?) {
        guard let image else { return }
        thumbnailImageView.image = NSImage(
            cgImage: image,
            size: NSSize(width: CGFloat(image.width), height: CGFloat(image.height))
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if isRenaming {
            endRenaming(commit: false, restoreFocus: false)
        }
        onCommitRename = nil
        representedURL = nil
        thumbnailImageView.image = nil
        thumbnailImageView.imageScaling = .scaleProportionallyUpOrDown
        thumbnailImageView.contentTintColor = nil
        nameLabel.stringValue = ""
        view.setAccessibilityLabel(nil)
        updateSelectionAppearance()
    }

    private func setRenamingAppearance(_ renaming: Bool) {
        nameLabel.isEditable = renaming
        nameLabel.isSelectable = renaming
        nameLabel.isBezeled = false
        nameLabel.isBordered = false
        nameLabel.drawsBackground = renaming
        nameLabel.backgroundColor = renaming ? .textBackgroundColor : .clear
        nameLabel.focusRingType = renaming ? .default : .none
        nameLabel.maximumNumberOfLines = renaming ? 1 : 2
        nameLabel.lineBreakMode = renaming ? .byClipping : .byTruncatingTail
        nameLabel.alignment = renaming ? .left : .center
        nameLabel.cell?.wraps = !renaming
        nameLabel.cell?.isScrollable = renaming
        nameLabel.cell?.truncatesLastVisibleLine = !renaming
    }

    private func endRenaming(commit: Bool, restoreFocus: Bool) {
        guard isRenaming else { return }
        isRenaming = false
        let oldName = originalName ?? nameLabel.stringValue
        let newName = nameLabel.stringValue
        originalName = nil

        setRenamingAppearance(false)
        nameLabel.stringValue = oldName
        nameLabel.setAccessibilityLabel(oldName)
        view.setAccessibilityLabel(oldName)

        if commit {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, newName != oldName, let url = representedURL {
                nameLabel.stringValue = newName
                nameLabel.setAccessibilityLabel(newName)
                view.setAccessibilityLabel(newName)
                onCommitRename?(url, newName)
            }
        }

        if restoreFocus, let collectionView {
            collectionView.window?.makeFirstResponder(collectionView)
        }
    }

    private func updateSelectionAppearance() {
        let isHighlighted = isSelected || highlightState == .forSelection
        view.layer?.backgroundColor = isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
        view.layer?.borderWidth = isSelected ? 1 : 0
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
    }
}

extension ThumbnailItemView: NSTextFieldDelegate {
    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            nameLabel.stringValue = textView.string
            endRenaming(commit: true, restoreFocus: true)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            endRenaming(commit: false, restoreFocus: true)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard isRenaming else { return }
        endRenaming(commit: true, restoreFocus: false)
    }
}

@MainActor
final class ThumbnailModeView: NSView {
    private struct ThumbnailRequest {
        let token: UUID
        let pointSize: Double
        let scale: Double
        let task: Task<Void, Never>
    }

    private static let itemIdentifier = NSUserInterfaceItemIdentifier("ThumbnailItem")
    private static let spacing: CGFloat = 12
    private static let sectionInset = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

    private let model: BrowserModel
    private let provider: any ThumbnailProviding
    private let scrollView = NSScrollView()
    private let collectionView = ThumbnailCollectionView()
    private let flowLayout = NSCollectionViewFlowLayout()

    private var storedThumbnailSize: Double
    private var lastURLs: [URL] = []
    private var isApplyingSelection = false
    private var lastSelectedURL: URL?
    private var selectionAnchor: Int?
    private var keepSelectionAnchorOnModelChange = false
    private var requests: [URL: ThumbnailRequest] = [:]

    init(model: BrowserModel, provider: any ThumbnailProviding) {
        self.model = model
        self.provider = provider
        self.storedThumbnailSize = ViewSettings.defaultThumbnailSize
        super.init(frame: .zero)
        setup()
        applyModel()
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var focusView: NSView { collectionView }

    var onRename: ((URL, String) async -> Void)?
    var onOpenItem: ((URL) -> Void)?
    var onInternalDrop: (([URL], URL, Bool) -> Void)?
    /// Esc. Returns true when handled (ends search results; FR-086).
    var onEscape: (() -> Bool)? {
        get { collectionView.onEscape }
        set { collectionView.onEscape = newValue }
    }

    var contextMenu: NSMenu? {
        get { collectionView.menu }
        set { collectionView.menu = newValue }
    }

    var thumbnailSize: Double {
        get { storedThumbnailSize }
        set {
            let clamped = ViewSettings.clampThumbnailSize(newValue)
            guard clamped != storedThumbnailSize else { return }
            storedThumbnailSize = clamped
            flowLayout.invalidateLayout()
            needsLayout = true
            refreshVisibleThumbnails()
        }
    }

    var currentColumnCount: Int {
        columnCount()
    }

    /// Width excluding section insets, used for navigating a hidden file list (R43).
    var navigationWidth: Double {
        Double(max(
            0,
            collectionView.bounds.width - Self.sectionInset.left - Self.sectionInset.right
        ))
    }

    /// Number of columns for the given width (R43).
    func columnCount(forWidth width: Double) -> Int {
        max(1, ThumbnailGridLayout.columns(
            availableWidth: width,
            thumbnailSize: storedThumbnailSize,
            spacing: Double(Self.spacing)
        ).count)
    }

    func scrollToFocused() {
        guard let focused = model.selection.focused,
              let index = model.listing.files.firstIndex(where: { $0.url == focused }) else {
            return
        }
        scrollItemIntoView(at: index)
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

    private func scrollItemIntoView(at index: Int) {
        let files = model.listing.files
        guard files.indices.contains(index) else { return }

        layoutSubtreeIfNeeded()
        collectionView.layoutSubtreeIfNeeded()

        let indexPath = IndexPath(item: index, section: 0)
        let estimatedFrame = estimatedItemFrame(at: index)
        let itemFrame = collectionView.layoutAttributesForItem(at: indexPath)?.frame
            ?? estimatedFrame
        guard let itemFrame else {
            collectionView.scrollToItems(
                at: [indexPath],
                scrollPosition: .nearestVerticalEdge
            )
            return
        }

        let visibleRect = scrollView.contentView.bounds
        let contentHeight = max(
            max(flowLayout.collectionViewContentSize.height, collectionView.bounds.height),
            itemFrame.maxY
        )
        let target = ThumbnailScroll.offsetY(
            itemMinY: Double(itemFrame.minY),
            itemMaxY: Double(itemFrame.maxY),
            visibleMinY: Double(visibleRect.minY),
            visibleHeight: Double(visibleRect.height),
            contentHeight: Double(contentHeight)
        )
        guard target.isFinite else { return }

        let maximum = max(0, Double(contentHeight - visibleRect.height))
        let clampedTarget = min(max(0, target), maximum)
        guard abs(clampedTarget - Double(visibleRect.minY)) > 0.5 else { return }

        scrollView.contentView.scroll(
            to: NSPoint(x: visibleRect.minX, y: CGFloat(clampedTarget))
        )
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func estimatedItemFrame(at index: Int) -> NSRect? {
        let available = Double(max(
            0,
            collectionView.bounds.width - Self.sectionInset.left - Self.sectionInset.right
        ))
        let layout = ThumbnailGridLayout.columns(
            availableWidth: available,
            thumbnailSize: storedThumbnailSize,
            spacing: Double(Self.spacing)
        )
        guard layout.count > 0, layout.cellWidth > 0 else { return nil }

        let cellHeight = storedThumbnailSize + 36
        let column = index % layout.count
        let row = index / layout.count
        let x = Double(Self.sectionInset.left)
            + Double(column) * (layout.cellWidth + Double(Self.spacing))
        let y = Double(Self.sectionInset.top)
            + Double(row) * (cellHeight + Double(Self.spacing))
        return NSRect(x: x, y: y, width: layout.cellWidth, height: cellHeight)
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        flowLayout.scrollDirection = .vertical
        flowLayout.minimumInteritemSpacing = Self.spacing
        flowLayout.minimumLineSpacing = Self.spacing
        flowLayout.sectionInset = Self.sectionInset

        collectionView.collectionViewLayout = flowLayout
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(
            ThumbnailItemView.self,
            forItemWithIdentifier: Self.itemIdentifier
        )
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        InternalDrag.register(collectionView)
        collectionView.onArrowKey = { [weak self] key, modifiers in
            self?.handleArrowKey(key, modifiers: modifiers) ?? false
        }
        collectionView.onReturnKey = { [weak self] in
            self?.beginRenameFromKeyboard() ?? false
        }
        collectionView.onDoubleClickItem = { [weak self] index in
            self?.openItem(at: index)
        }
        collectionView.frame = NSRect(x: 0, y: 0, width: 400, height: 400)

        scrollView.documentView = collectionView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layout() {
        super.layout()
        updateCollectionViewFrame()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.size.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged {
            needsLayout = true
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsLayout = true
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        refreshVisibleThumbnails()
    }

    private func updateCollectionViewFrame() {
        let contentSize = scrollView.contentSize
        let width = max(0, contentSize.width)
        if abs(collectionView.frame.size.width - width) > 0.5 {
            collectionView.frame.size.width = width
            flowLayout.invalidateLayout()
        }

        collectionView.layoutSubtreeIfNeeded()
        let contentHeight = flowLayout.collectionViewContentSize.height
        let height = max(contentHeight, contentSize.height)
        if abs(collectionView.frame.size.height - height) > 0.5 {
            collectionView.frame.size.height = height
        }
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.listing.files
            _ = model.selection.selected
            _ = model.selection.focused
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
        // For a hidden mode, defer reloading and selection updates until it is shown (viewDidUnhide) (SC-015).
        guard !isHidden else { return }
        let files = model.listing.files
        let urls = files.map(\.url)

        if urls != lastURLs {
            lastURLs = urls
            pruneRequests(keeping: Set(urls))
            collectionView.reloadData()
            flowLayout.invalidateLayout()
            needsLayout = true
        }

        let selectedPaths = Set(
            SelectionIndex.indexes(of: model.selection.selected, in: urls).map {
                IndexPath(item: $0, section: 0)
            }
        )

        isApplyingSelection = true
        if collectionView.selectionIndexPaths != selectedPaths {
            collectionView.selectionIndexPaths = selectedPaths
        }
        isApplyingSelection = false

        lastSelectedURL = model.selection.focused
        if keepSelectionAnchorOnModelChange {
            keepSelectionAnchorOnModelChange = false
        } else if let focused = model.selection.focused,
                  let index = urls.firstIndex(of: focused) {
            selectionAnchor = index
        } else {
            selectionAnchor = nil
        }
    }

    private func pruneRequests(keeping urls: Set<URL>) {
        let staleURLs = requests.keys.filter { !urls.contains($0) }
        for url in staleURLs {
            cancelRequest(for: url)
        }
    }

    private func requestThumbnail(for file: MediaFile) {
        guard window?.inLiveResize != true else { return }
        guard file.kind.isMedia else {
            // Do not request thumbnails for non-media rows; show the kind icon instead.
            cancelRequest(for: file.url)
            for case let item as ThumbnailItemView in collectionView.visibleItems()
            where item.representedURL == file.url {
                item.showListItemIcon(for: file.kind, pointSize: listItemIconPointSize)
            }
            return
        }
        let pointSize = storedThumbnailSize
        let scale = Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        if let existing = requests[file.url],
           existing.pointSize == pointSize,
           existing.scale == scale {
            return
        }
        if let existing = requests[file.url] {
            existing.task.cancel()
            requests[file.url] = nil
            provider.cancel(
                for: file.url,
                pointSize: existing.pointSize,
                scale: existing.scale
            )
        }

        let pointSizeValue = pointSize
        let token = UUID()
        let provider = self.provider
        let url = file.url
        let task = Task { [weak self] in
            let image = await provider.thumbnail(
                for: url,
                pointSize: pointSizeValue,
                scale: scale
            )
            guard !Task.isCancelled, let self else { return }
            guard self.requests[url]?.token == token else { return }
            self.requests[url] = nil
            self.apply(image, for: url)
        }
        requests[url] = ThumbnailRequest(
            token: token,
            pointSize: pointSize,
            scale: scale,
            task: task
        )
    }

    private func apply(_ image: CGImage?, for url: URL) {
        guard let image else { return }
        for case let item as ThumbnailItemView in collectionView.visibleItems()
        where item.representedURL == url {
            item.setThumbnailImage(image)
        }
    }

    private func cancelRequest(for url: URL) {
        guard let request = requests[url] else { return }
        request.task.cancel()
        requests[url] = nil
        provider.cancel(
            for: url,
            pointSize: request.pointSize,
            scale: request.scale
        )
    }

    private func refreshVisibleThumbnails() {
        let files = model.listing.files
        for path in collectionView.indexPathsForVisibleItems()
        where files.indices.contains(path.item) {
            requestThumbnail(for: files[path.item])
        }
    }

    private func isVisible(url: URL) -> Bool {
        let files = model.listing.files
        return collectionView.indexPathsForVisibleItems().contains { path in
            files.indices.contains(path.item) && files[path.item].url == url
        }
    }

    private func columnCount() -> Int {
        columnCount(forWidth: navigationWidth)
    }

    /// Icon size for non-media rows (about half the thumbnail size).
    private var listItemIconPointSize: Double {
        max(16, storedThumbnailSize / 2)
    }

    /// Selects a double-clicked item as the only selection, then opens it (FR-069, FR-070).
    private func openItem(at index: Int) {
        let files = model.listing.files
        guard files.indices.contains(index) else { return }
        let url = files[index].url
        if model.selection.selected != [url] || model.selection.focused != url {
            applySelection([IndexPath(item: index, section: 0)], focusedURL: url)
            selectionAnchor = index
        }
        onOpenItem?(url)
    }

    private func beginRenameFromKeyboard() -> Bool {
        // Do not start renaming inside a zip (FR-073). Consume the key.
        guard model.focusedItemCommands.allowsFileOperations else { return true }
        guard onRename != nil else { return false }
        let selected = model.selection.selected
        guard selected.count == 1,
              let url = selected.first,
              let index = model.listing.files.firstIndex(where: { $0.url == url }) else {
            return false
        }

        let indexPath = IndexPath(item: index, section: 0)
        scrollItemIntoView(at: index)
        collectionView.layoutSubtreeIfNeeded()
        guard let item = collectionView.item(at: indexPath) as? ThumbnailItemView,
              item.representedURL == url else {
            return false
        }
        return item.beginRenaming()
    }

    private func commitRename(url: URL, newName: String) {
        guard let onRename else { return }
        Task { @MainActor in
            await onRename(url, newName)
        }
    }

    private func handleArrowKey(
        _ key: NSEvent.SpecialKey,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        let files = model.listing.files
        guard !files.isEmpty else { return false }
        guard let move = focusMove(for: key) else { return false }

        let currentIndex: Int?
        if let focused = model.selection.focused {
            currentIndex = files.firstIndex(where: { $0.url == focused })
        } else {
            currentIndex = model.selection.selected
                .compactMap { url in files.firstIndex(where: { $0.url == url }) }
                .min()
        }

        guard let target = FocusNavigator.targetIndex(
            currentIndex: currentIndex,
            fileCount: files.count,
            move: move,
            layout: .grid(columns: currentColumnCount)
        ) else {
            return true
        }

        if modifiers.contains(.shift), let currentIndex {
            let anchor = selectionAnchor ?? currentIndex
            selectionAnchor = anchor
            let lower = min(anchor, target)
            let upper = max(anchor, target)
            let paths = Set((lower...upper).map { IndexPath(item: $0, section: 0) })
            applySelection(paths, focusedURL: files[target].url)
        } else {
            selectionAnchor = target
            applySelection(
                [IndexPath(item: target, section: 0)],
                focusedURL: files[target].url
            )
        }

        scrollItemIntoView(at: target)
        return true
    }

    private func focusMove(for key: NSEvent.SpecialKey) -> FocusMove? {
        switch key {
        case .leftArrow:
            return .left
        case .rightArrow:
            return .right
        case .upArrow:
            return .up
        case .downArrow:
            return .down
        default:
            return nil
        }
    }

    private func applySelection(_ paths: Set<IndexPath>, focusedURL: URL?) {
        isApplyingSelection = true
        collectionView.selectionIndexPaths = paths
        isApplyingSelection = false

        lastSelectedURL = focusedURL
        let files = model.listing.files
        let urls = Set(paths.compactMap { path -> URL? in
            guard files.indices.contains(path.item) else { return nil }
            return files[path.item].url
        })
        keepSelectionAnchorOnModelChange = true
        model.select(urls, focused: focusedURL)
    }

    private func selectionDidChange(newlySelected: Set<IndexPath>?) {
        guard !isApplyingSelection else { return }

        let files = model.listing.files
        let paths = collectionView.selectionIndexPaths
        let urls = Set(paths.compactMap { path -> URL? in
            guard files.indices.contains(path.item) else { return nil }
            return files[path.item].url
        })

        if urls == model.selection.selected {
            let currentFocused = model.selection.focused
            if currentFocused.map(urls.contains) ?? true {
                lastSelectedURL = currentFocused
                return
            }
        }

        let focused: URL?
        if let newlySelected, !newlySelected.isEmpty {
            let path: IndexPath?
            if let anchor = selectionAnchor,
               !newlySelected.contains(IndexPath(item: anchor, section: 0)) {
                path = newlySelected.max {
                    abs($0.item - anchor) < abs($1.item - anchor)
                }
            } else {
                path = newlySelected.max { $0.item < $1.item }
            }
            focused = path.flatMap { path in
                files.indices.contains(path.item) ? files[path.item].url : nil
            }
        } else if paths.count == 1,
                  let path = paths.first,
                  files.indices.contains(path.item) {
            focused = files[path.item].url
        } else if let lastSelectedURL, urls.contains(lastSelectedURL) {
            focused = lastSelectedURL
        } else if let path = paths.max(by: { $0.item < $1.item }),
                  files.indices.contains(path.item) {
            focused = files[path.item].url
        } else {
            focused = nil
        }

        lastSelectedURL = focused
        if let newlySelected, newlySelected.count == 1,
           let path = newlySelected.first,
           files.indices.contains(path.item) {
            selectionAnchor = path.item
        } else if paths.isEmpty {
            selectionAnchor = nil
        }

        if model.selection.selected != urls || model.selection.focused != focused {
            keepSelectionAnchorOnModelChange = true
            model.select(urls, focused: focused)
        }
    }
}

extension ThumbnailModeView: NSCollectionViewDataSource {
    func collectionView(_ collectionView: NSCollectionView, validateDrop info: any NSDraggingInfo, proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let index = proposedIndexPath.pointee.item
        guard dropOperation.pointee == .on, !model.isBrowsingArchive,
              model.listing.files.indices.contains(index), model.listing.files[index].kind == .folder else { return [] }
        let operation = InternalDrag.operation(info, destination: model.listing.files[index].url)
        if !operation.isEmpty { dropOperation.pointee = .on }
        return operation
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: any NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let index = indexPath.item
        guard dropOperation == .on, !model.isBrowsingArchive,
              model.listing.files.indices.contains(index), model.listing.files[index].kind == .folder,
              let urls = InternalDrag.urls(info) else { return false }
        let destination = model.listing.files[index].url
        guard !InternalDrag.operation(info, destination: destination).isEmpty else { return false }
        onInternalDrop?(urls, destination, NSEvent.modifierFlags.contains(.option))
        return true
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        model.listing.files.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: Self.itemIdentifier,
            for: indexPath
        )
        guard let thumbnailItem = item as? ThumbnailItemView else {
            return item
        }

        let files = model.listing.files
        guard files.indices.contains(indexPath.item) else {
            return thumbnailItem
        }
        let file = files[indexPath.item]
        if let oldURL = thumbnailItem.representedURL, oldURL != file.url {
            cancelRequest(for: oldURL)
        }
        thumbnailItem.onCommitRename = { [weak self] url, newName in
            self?.commitRename(url: url, newName: newName)
        }
        thumbnailItem.configure(with: file, iconPointSize: listItemIconPointSize)
        // In search results, show the location tooltip for same-named files that cannot be distinguished by name alone
        // (FR-084, R37).
        thumbnailItem.view.toolTip = model.listing.search?.location(of: file.url)
        requestThumbnail(for: file)
        return thumbnailItem
    }
}

extension ThumbnailModeView: NSCollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        let available = Double(max(
            0,
            collectionView.bounds.width - Self.sectionInset.left - Self.sectionInset.right
        ))
        let result = ThumbnailGridLayout.columns(
            availableWidth: available,
            thumbnailSize: storedThumbnailSize,
            spacing: Double(Self.spacing)
        )
        return NSSize(
            width: CGFloat(max(1, result.cellWidth)),
            height: CGFloat(storedThumbnailSize + 36)
        )
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        let files = model.listing.files
        guard files.indices.contains(indexPath.item) else { return nil }
        // Do not start a drag for rows inside a zip or `..` (FR-073).
        guard model.itemCommands(forRowAt: indexPath.item).allowsFileOperations else { return nil }
        return files[indexPath.item].url as NSURL
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        selectionDidChange(newlySelected: indexPaths)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didDeselectItemsAt indexPaths: Set<IndexPath>
    ) {
        selectionDidChange(newlySelected: nil)
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didEndDisplaying item: NSCollectionViewItem,
        forRepresentedObjectAt indexPath: IndexPath
    ) {
        guard let thumbnailItem = item as? ThumbnailItemView,
              let url = thumbnailItem.representedURL else {
            return
        }
        if !isVisible(url: url) {
            cancelRequest(for: url)
        }
    }
}

extension ThumbnailModeView: NSCollectionViewPrefetching {
    func collectionView(
        _ collectionView: NSCollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        guard window?.inLiveResize != true else { return }
        let files = model.listing.files
        for path in indexPaths where files.indices.contains(path.item) {
            requestThumbnail(for: files[path.item])
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        cancelPrefetchingForItemsAt indexPaths: [IndexPath]
    ) {
        let files = model.listing.files
        for path in indexPaths where files.indices.contains(path.item) {
            let url = files[path.item].url
            if !isVisible(url: url) {
                cancelRequest(for: url)
            }
        }
    }
}
