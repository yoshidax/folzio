import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
final class FileListViewController: NSViewController {
    private let model: BrowserModel
    private let settings: SettingsStore
    private let thumbnailProvider: any ThumbnailProviding
    private let coordinator: FileOperationCoordinator
    private let listModeView: ListModeView
    private let thumbnailModeView: ThumbnailModeView
    private lazy var fileContextMenu = FileContextMenu(host: self)
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let bottomBar = NSView()
    /// One-line message band shown while the list stays visible (R26). At the bottom of the list, above the size
    /// bar.
    private let messageBand = NSView()
    private let messageBandLabel = NSTextField(labelWithString: "")
    private let sizeSlider = NSSlider()
    private let sizeLabel = NSTextField(labelWithString: "")
    /// Band shown at the top of the list while search results are displayed (R37).
    private let searchBar = NSView()
    private let searchBarLabel = NSTextField(labelWithString: "")
    private let searchBarSpinner = NSProgressIndicator()

    private var searchBarHeightConstraint: NSLayoutConstraint?
    private var bottomBarHeightConstraint: NSLayoutConstraint?
    private var messageBandHeightConstraint: NSLayoutConstraint?
    private var displayMode: DisplayMode
    private let initialThumbnailSize: Double
    private struct HiddenListNavigation {
        let width: Double
    }

    private var hiddenListNavigation: HiddenListNavigation?
    private var installedViewMenuItems = false
    private weak var thumbnailMenuItem: NSMenuItem?
    private weak var listMenuItem: NSMenuItem?
    private weak var imagesOnlyMenuItem: NSMenuItem?
    private weak var videosOnlyMenuItem: NSMenuItem?
    private weak var zipVisibilityMenuItem: NSMenuItem?
    /// Scroll position preserved across list rebuilds (SC-017).
    private var pendingScrollOrigin: CGPoint?

    var onViewStateChange: ((DisplayMode, Double) -> Void)?
    var onMediaTypeFilterChange: ((MediaTypeFilter) -> Void)?
    var onShowsZipFilesChange: ((Bool) -> Void)?
    /// Notifies history when the user changes the presentation (FR-107 item 3). Not called from the restore
    /// setter (R70).
    var onViewChange: ((HistoryRecordKind) -> Void)?

    var isToolbarShown = false {
        didSet {
            guard isToolbarShown != oldValue, isViewLoaded else { return }
            updateModeVisibility()
        }
    }

    var currentDisplayMode: DisplayMode {
        displayMode
    }

    var currentThumbnailSize: Double {
        thumbnailModeView.thumbnailSize
    }

    var currentMediaTypeFilter: MediaTypeFilter {
        model.mediaTypeFilter
    }

    var currentShowsZipFiles: Bool {
        model.showsZipFiles
    }

    init(
        model: BrowserModel,
        settings: SettingsStore,
        thumbnailProvider: any ThumbnailProviding,
        coordinator: FileOperationCoordinator
    ) {
        let viewSettings = settings.viewSettings
        self.model = model
        self.settings = settings
        self.thumbnailProvider = thumbnailProvider
        self.coordinator = coordinator
        self.listModeView = ListModeView(
            model: model,
            provider: thumbnailProvider
        )
        self.thumbnailModeView = ThumbnailModeView(
            model: model,
            provider: thumbnailProvider
        )
        self.displayMode = viewSettings.displayMode
        self.initialThumbnailSize = ViewSettings.clampThumbnailSize(
            viewSettings.thumbnailSize
        )
        super.init(nibName: nil, bundle: nil)
        thumbnailModeView.thumbnailSize = initialThumbnailSize
        fileContextMenu.install(
            listModeView: listModeView,
            thumbnailModeView: thumbnailModeView
        )
        let handleDrop: ([URL], URL, Bool) -> Void = { [weak self] urls, destination, copy in
            guard let self else { return }
            Task { @MainActor in
                await self.coordinator.internalDrop(urls, to: destination, copy: copy)
            }
        }
        listModeView.onInternalDrop = handleDrop
        thumbnailModeView.onInternalDrop = handleDrop
        listModeView.onOpenItem = { [weak self] url in
            self?.openItem(url)
        }
        thumbnailModeView.onOpenItem = { [weak self] url in
            self?.openItem(url)
        }
        listModeView.onEscape = { [weak self] in
            self?.leaveSearchResults() ?? false
        }
        thumbnailModeView.onEscape = { [weak self] in
            self?.leaveSearchResults() ?? false
        }
    }

    /// Esc. While showing search results (excluding full screen and renaming), returns to the pre-search folder
    /// listing. If searching, stops the search. Does nothing otherwise (FR-086).
    private func leaveSearchResults() -> Bool {
        guard model.isShowingSearchResults,
              hiddenListNavigation == nil,
              !isEditingText else { return false }
        let folder = model.listing.folder
        Task { @MainActor [model] in
            await model.selectFolder(folder)
        }
        return true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Where AppKit moved focus when the list was hidden (the next key view, such as the preview).
    /// When the list reappears, returns focus to the file list if focus is still there.
    private weak var displacedFocus: NSResponder?

    var primaryFocusView: NSView {
        displayMode == .thumbnails
            ? thumbnailModeView.focusView
            : listModeView.focusView
    }

    var onTogglePlayback: (() -> Void)? {
        get { listModeView.onTogglePlayback }
        set { listModeView.onTogglePlayback = newValue }
    }

    var onRename: ((URL, String) async -> Void)? {
        get { listModeView.onRename }
        set {
            listModeView.onRename = newValue
            thumbnailModeView.onRename = newValue
        }
    }

    func beginHiddenListNavigation(selectingEntry: Bool) {
        guard hiddenListNavigation == nil else { return }
        hiddenListNavigation = HiddenListNavigation(
            width: thumbnailModeView.navigationWidth
        )

        guard selectingEntry, PaneLayout.shouldAutoSelectEntry(in: model.listing) else { return }
        let files = model.listing.files
        let currentIndex = model.selection.focused.flatMap { focused in
            files.firstIndex { $0.url == focused }
        }
        guard let target = FocusNavigator.entryIndex(
            currentIndex: currentIndex,
            fileCount: files.count,
            isNavigable: { files[$0].kind.isMedia }
        ), target != currentIndex else {
            return
        }
        let url = files[target].url
        model.select([url], focused: url)
    }

    @discardableResult
    func moveFocusInHiddenList(_ move: FocusMove) -> Bool {
        guard let navigation = hiddenListNavigation else { return false }
        let files = model.listing.files
        guard !files.isEmpty else { return true }

        let layout: FocusLayout = displayMode == .thumbnails
            ? .grid(columns: thumbnailModeView.columnCount(forWidth: navigation.width))
            : .list
        let currentIndex = model.selection.focused.flatMap { focused in
            files.firstIndex { $0.url == focused }
        }
        guard let target = FocusNavigator.targetIndex(
            currentIndex: currentIndex,
            fileCount: files.count,
            move: move,
            layout: layout,
            isNavigable: { files[$0].kind.isMedia }
        ) else {
            return true
        }

        let url = files[target].url
        model.select([url], focused: url)
        return true
    }

    func endHiddenListNavigation() {
        guard hiddenListNavigation != nil else { return }
        hiddenListNavigation = nil

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch self.displayMode {
            case .list:
                self.listModeView.scrollToFocused()
            case .thumbnails:
                self.thumbnailModeView.scrollToFocused()
            }
        }
    }

    /// Target of file operations in listing order, excluding the `..` row (R30).
    var selectedFileURLs: [URL] {
        model.operableSelection
    }

    /// Availability of each command based on the focused row and current location.
    var focusedItemCommands: ListItemCommands {
        model.focusedItemCommands
    }

    /// Availability of file operations for the selection (judged from other selected rows even when the focus is on
    /// `..`).
    var selectionItemCommands: ListItemCommands {
        model.selectionItemCommands
    }

    var isEditingText: Bool {
        view.window?.firstResponder is NSTextView
    }

    override func loadView() {
        let container = NSView()

        setupBottomBar()

        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bottomBar)
        let bottomBarHeight = bottomBar.heightAnchor.constraint(equalToConstant: 0)
        bottomBarHeightConstraint = bottomBarHeight
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bottomBarHeight,
        ])

        setupMessageBand()
        messageBand.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(messageBand)
        let messageBandHeight = messageBand.heightAnchor.constraint(equalToConstant: 0)
        messageBandHeightConstraint = messageBandHeight
        NSLayoutConstraint.activate([
            messageBand.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            messageBand.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            messageBand.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            messageBandHeight,
        ])

        setupSearchBar()
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(searchBar)
        let searchBarHeight = searchBar.heightAnchor.constraint(equalToConstant: 0)
        searchBarHeightConstraint = searchBarHeight
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: container.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            searchBarHeight,
        ])

        for modeView in [listModeView as NSView, thumbnailModeView as NSView] {
            modeView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(modeView)
            NSLayoutConstraint.activate([
                modeView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
                modeView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                modeView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                modeView.bottomAnchor.constraint(equalTo: messageBand.topAnchor),
            ])
        }

        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.cell?.wraps = true
        messageLabel.isHidden = true

        container.addSubview(progressIndicator)
        container.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
        ])

        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )
        installViewMenuItems()
        refresh()
        observeModel()
        observeMediaTypeFilter()
        observeShowsZipFiles()
    }

    @objc private func displayLanguageDidChange() {
        sizeLabel.stringValue = l10n.text(.toolbarSize)
        sizeLabel.toolTip = l10n.text(.toolbarThumbnailSize)
        sizeSlider.toolTip = l10n.text(.toolbarThumbnailSize)
        sizeSlider.setAccessibilityLabel(l10n.text(.toolbarThumbnailSize))
        sizeSlider.setAccessibilityHelp(l10n.text(.toolbarThumbnailSize))
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installViewMenuItems()
    }

    private func setupMessageBand() {
        messageBand.isHidden = true
        messageBand.clipsToBounds = true

        messageBandLabel.translatesAutoresizingMaskIntoConstraints = false
        messageBandLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        messageBandLabel.textColor = .secondaryLabelColor
        messageBandLabel.alignment = .center
        messageBandLabel.lineBreakMode = .byTruncatingTail
        // The label defaults (hugging 251, compression resistance 750) exceed NSSplitViewItem's holdingPriority (250)
        // and pull the pane width back to the label width. Make the band follow the pane width and truncate long text.
        messageBandLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        messageBandLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        messageBand.addSubview(messageBandLabel)
        NSLayoutConstraint.activate([
            messageBandLabel.leadingAnchor.constraint(equalTo: messageBand.leadingAnchor, constant: 12),
            messageBandLabel.trailingAnchor.constraint(equalTo: messageBand.trailingAnchor, constant: -12),
            messageBandLabel.centerYAnchor.constraint(equalTo: messageBand.centerYAnchor),
        ])
    }

    private func setupSearchBar() {
        searchBar.isHidden = true
        searchBar.clipsToBounds = true

        searchBarLabel.translatesAutoresizingMaskIntoConstraints = false
        searchBarLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        searchBarLabel.textColor = .secondaryLabelColor
        searchBarLabel.lineBreakMode = .byTruncatingMiddle
        // As with the bottom band, do not let the label width pull the pane width back (stay below holdingPriority
        // 250).
        searchBarLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        searchBarLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        searchBarSpinner.translatesAutoresizingMaskIntoConstraints = false
        searchBarSpinner.style = .spinning
        searchBarSpinner.controlSize = .small
        searchBarSpinner.isDisplayedWhenStopped = false

        searchBar.addSubview(searchBarLabel)
        searchBar.addSubview(searchBarSpinner)
        NSLayoutConstraint.activate([
            searchBarSpinner.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor, constant: 8),
            searchBarSpinner.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchBarSpinner.widthAnchor.constraint(equalToConstant: 16),
            searchBarSpinner.heightAnchor.constraint(equalToConstant: 16),
            searchBarLabel.leadingAnchor.constraint(equalTo: searchBarSpinner.trailingAnchor, constant: 6),
            searchBarLabel.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -12),
            searchBarLabel.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
        ])
    }

    /// "Search results for "<keyword>" — <root folder name> — <count> items". While searching, appends "Searching…"
    /// and a spinner; when the media type filter hides items, uses "Showing <visible> of <count> items" (R37).
    private func updateSearchBar() {
        guard let search = model.listing.search else {
            searchBar.isHidden = true
            searchBarHeightConstraint?.constant = 0
            searchBarSpinner.stopAnimation(nil)
            searchBarLabel.stringValue = ""
            searchBarLabel.toolTip = nil
            return
        }

        let rootName = search.root.path == "/" ? "/" : search.root.lastPathComponent
        let shownCount = model.listing.files.count
        let count = shownCount != search.totalCount
            ? l10n.text(
                .searchBarCountLimited,
                .count(search.totalCount),
                .text(l10n.count(shownCount))
            )
            : l10n.text(.searchBarCount, .count(search.totalCount))
        let text: String
        if search.phase == .searching {
            text = l10n.text(
                .searchBarSearching,
                .text(search.keyword),
                .text(rootName),
                .text(count)
            )
            searchBarSpinner.startAnimation(nil)
        } else {
            text = l10n.text(
                .searchBarResults,
                .text(search.keyword),
                .text(rootName),
                .text(count)
            )
            searchBarSpinner.stopAnimation(nil)
        }
        searchBarLabel.stringValue = text
        searchBarLabel.toolTip = text
        searchBarLabel.setAccessibilityValue(text)
        searchBar.isHidden = false
        searchBarHeightConstraint?.constant = 24
    }

    private func setupBottomBar() {
        let label = sizeLabel
        label.stringValue = l10n.text(.toolbarSize)
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.toolTip = l10n.text(.toolbarThumbnailSize)

        sizeSlider.toolTip = l10n.text(.toolbarThumbnailSize)
        sizeSlider.setAccessibilityLabel(l10n.text(.toolbarThumbnailSize))
        sizeSlider.setAccessibilityHelp(l10n.text(.toolbarThumbnailSize))
        sizeSlider.minValue = ViewSettings.minimumThumbnailSize
        sizeSlider.maxValue = ViewSettings.maximumThumbnailSize
        sizeSlider.doubleValue = initialThumbnailSize
        sizeSlider.isContinuous = true
        sizeSlider.controlSize = .small
        sizeSlider.target = self
        sizeSlider.action = #selector(thumbnailSizeSliderChanged(_:))
        sizeSlider.translatesAutoresizingMaskIntoConstraints = false
        sizeSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let stack = NSStackView(views: [label, sizeSlider])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: bottomBar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.listing.state
            _ = model.listing.files
            _ = model.listing.search
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refresh()
                self?.observeModel()
            }
        }
    }

    private func observeMediaTypeFilter() {
        withObservationTracking {
            _ = model.mediaTypeFilter
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateViewMenuState()
                self.onMediaTypeFilterChange?(self.model.mediaTypeFilter)
                self.refresh()
                self.observeMediaTypeFilter()
            }
        }
    }

    private func observeShowsZipFiles() {
        withObservationTracking {
            _ = model.showsZipFiles
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateViewMenuState()
                self.onShowsZipFilesChange?(self.model.showsZipFiles)
                self.observeShowsZipFiles()
            }
        }
    }

    /// Keeps showing the list even in a message state when rows remain (`..` or directories).
    /// For an unreadable folder, shows the list when `..` remains and puts the message in the bottom band (FR-077).
    private var showsFileList: Bool {
        switch model.listing.state {
        case .loaded:
            return true
        case .empty, .noMatches, .denied, .failed:
            return !model.listing.files.isEmpty
        case .loading:
            return false
        }
    }

    private func refresh() {
        let originBeforeRefresh = currentVisibleOrigin
        messageLabel.isHidden = true
        messageLabel.stringValue = ""
        messageBandLabel.stringValue = ""
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true

        let isSearch = model.isShowingSearchResults
        var message: String?
        switch model.listing.state {
        case .loaded:
            break
        case .loading:
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
            message = isSearch ? l10n.text(.emptySearching) : l10n.text(.emptyLoading)
        case .empty:
            // Distinguish this from "No supported media files" in FR-060.
            message = isSearch ? l10n.text(.emptyNoMatches) : l10n.text(.emptyNoMedia)
        case .noMatches:
            switch model.mediaTypeFilter.emptyState {
            case .imagesOnly: message = l10n.text(.emptyFilterImages)
            case .videosOnly: message = l10n.text(.emptyFilterVideos)
            case nil: message = ""
            }
        case .denied:
            message = l10n.text(.emptyAccessDenied)
        case let .failed(reason):
            message = l10n.text(for: reason)
        }

        if let message {
            if showsFileList {
                messageBandLabel.stringValue = message
            } else {
                messageLabel.stringValue = message
                messageLabel.isHidden = false
            }
        }

        updateSearchBar()
        updateModeVisibility()
        restoreScrollOriginIfNeeded(originBeforeRefresh)
    }

    /// Scroll position of the visible list. Not captured while the list is hidden.
    private var currentVisibleOrigin: CGPoint? {
        switch displayMode {
        case .list:
            return listModeView.isHidden ? nil : listModeView.visibleOrigin
        case .thumbnails:
            return thumbnailModeView.isHidden ? nil : thumbnailModeView.visibleOrigin
        }
    }

    /// Captures the scroll position before rebuilding the list (SC-017).
    private func captureScrollOrigin() {
        pendingScrollOrigin = currentVisibleOrigin
    }

    /// Restores the captured position. Applies it only when the origin changed during the list rebuild.
    private func restoreScrollOriginIfNeeded(_ fallback: CGPoint? = nil) {
        let target = pendingScrollOrigin ?? fallback
        pendingScrollOrigin = nil
        guard let target, let current = currentVisibleOrigin, current != target else { return }
        switch displayMode {
        case .list:
            listModeView.restoreVisibleOrigin(target)
        case .thumbnails:
            thumbnailModeView.restoreVisibleOrigin(target)
        }
    }

    private func updateModeVisibility() {
        let showsFiles = showsFileList
        let firstResponder = view.window?.firstResponder as? NSView
        let focusWasInFileList = firstResponder.map {
            isView($0, inside: listModeView) || isView($0, inside: thumbnailModeView)
        } ?? false

        listModeView.isHidden = !(showsFiles && displayMode == .list)
        let thumbnailWasHidden = thumbnailModeView.isHidden
        thumbnailModeView.isHidden = !(showsFiles && displayMode == .thumbnails)
        if thumbnailWasHidden, !thumbnailModeView.isHidden {
            thumbnailModeView.needsLayout = true
        }

        // Loading hides the list, so AppKit moves focus to the next key view (such as the preview).
        // Return focus when the list reappears so keyboard focus stays in the file list while entering or leaving
        // folders (FR-078).
        if focusWasInFileList, !showsFiles, let window = view.window {
            displacedFocus = window.firstResponder
        }
        if showsFiles, let displaced = displacedFocus {
            displacedFocus = nil
            // Do not steal focus when the user moved to another pane during loading.
            if let window = view.window, window.firstResponder === displaced {
                window.makeFirstResponder(primaryFocusView)
            }
        }

        let showsBand = showsFiles && !messageBandLabel.stringValue.isEmpty
        messageBand.isHidden = !showsBand
        messageBandHeightConstraint?.constant = showsBand ? 24 : 0

        let showsThumbnailBar = FileListChrome(
            displayMode: displayMode,
            toolbarShown: isToolbarShown
        ).showsBottomSizeBar
        bottomBar.isHidden = !showsThumbnailBar
        bottomBarHeightConstraint?.constant = showsThumbnailBar ? 32 : 0
        updateViewMenuState()
        onViewStateChange?(displayMode, thumbnailModeView.thumbnailSize)
    }

    private func installViewMenuItems() {
        guard !installedViewMenuItems else { return }
        guard let viewMenu = NSApp.mainMenu?.items
            .first(where: { $0.submenu?.identifier == NSUserInterfaceItemIdentifier("menu.view") })?
            .submenu else {
            return
        }
        installedViewMenuItems = true

        let thumbnailsItem = NSMenuItem(
            title: l10n.text(.menuViewAsThumbnails),
            action: #selector(showThumbnails(_:)),
            keyEquivalent: "1"
        )
        thumbnailsItem.target = self
        MainMenu.bind(thumbnailsItem, .menuViewAsThumbnails)
        viewMenu.addItem(thumbnailsItem)
        thumbnailMenuItem = thumbnailsItem

        let listItem = NSMenuItem(
            title: l10n.text(.menuViewAsList),
            action: #selector(showList(_:)),
            keyEquivalent: "2"
        )
        listItem.target = self
        MainMenu.bind(listItem, .menuViewAsList)
        viewMenu.addItem(listItem)
        listMenuItem = listItem

        let zoomInItem = NSMenuItem(
            title: l10n.text(.menuViewLargerThumbnails),
            action: #selector(increaseThumbnailSize(_:)),
            keyEquivalent: "."
        )
        // ⌘+ and ⌘- are used for preview zoom, so use ⌃⌘. and ⌃⌘, which work without Shift (FR-135, A-74).
        zoomInItem.keyEquivalentModifierMask = [.command, .control]
        zoomInItem.target = self
        MainMenu.bind(zoomInItem, .menuViewLargerThumbnails)
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(
            title: l10n.text(.menuViewSmallerThumbnails),
            action: #selector(decreaseThumbnailSize(_:)),
            keyEquivalent: ","
        )
        zoomOutItem.keyEquivalentModifierMask = [.command, .control]
        zoomOutItem.target = self
        MainMenu.bind(zoomOutItem, .menuViewSmallerThumbnails)
        viewMenu.addItem(zoomOutItem)

        viewMenu.addItem(.separator())

        let imagesOnlyItem = NSMenuItem(
            title: l10n.text(.menuViewShowImagesOnly),
            action: #selector(toggleImagesOnly(_:)),
            keyEquivalent: "I"
        )
        imagesOnlyItem.target = self
        MainMenu.bind(imagesOnlyItem, .menuViewShowImagesOnly)
        viewMenu.addItem(imagesOnlyItem)
        imagesOnlyMenuItem = imagesOnlyItem

        let videosOnlyItem = NSMenuItem(
            title: l10n.text(.menuViewShowVideosOnly),
            action: #selector(toggleVideosOnly(_:)),
            keyEquivalent: "M"
        )
        videosOnlyItem.target = self
        MainMenu.bind(videosOnlyItem, .menuViewShowVideosOnly)
        viewMenu.addItem(videosOnlyItem)
        videosOnlyMenuItem = videosOnlyItem

        let zipVisibilityItem = NSMenuItem(
            title: l10n.text(.menuViewShowZipFiles),
            action: #selector(toggleShowsZipFiles(_:)),
            keyEquivalent: "z"
        )
        zipVisibilityItem.keyEquivalentModifierMask = [.command, .control]
        zipVisibilityItem.target = self
        MainMenu.bind(zipVisibilityItem, .menuViewShowZipFiles)
        viewMenu.addItem(zipVisibilityItem)
        zipVisibilityMenuItem = zipVisibilityItem

        updateViewMenuState()
    }

    private func updateViewMenuState() {
        thumbnailMenuItem?.state = displayMode == .thumbnails ? .on : .off
        listMenuItem?.state = displayMode == .list ? .on : .off
        imagesOnlyMenuItem?.state = model.mediaTypeFilter.imagesOnly ? .on : .off
        videosOnlyMenuItem?.state = model.mediaTypeFilter.videosOnly ? .on : .off
        zipVisibilityMenuItem?.state = model.showsZipFiles ? .on : .off
    }

    func applyMediaTypeFilter(_ filter: MediaTypeFilter) {
        guard !isEditingText else {
            onMediaTypeFilterChange?(model.mediaTypeFilter)
            return
        }
        captureScrollOrigin()
        model.setMediaTypeFilter(filter)
        onViewChange?(.viewChange)
        Task { @MainActor in self.restoreScrollOriginIfNeeded() }
    }

    func applyShowsZipFiles(_ shows: Bool) {
        guard !isEditingText else {
            onShowsZipFilesChange?(model.showsZipFiles)
            return
        }
        captureScrollOrigin()
        model.setShowsZipFiles(shows)
        onViewChange?(.viewChange)
        Task { @MainActor in self.restoreScrollOriginIfNeeded() }
    }

    func selectDisplayMode(_ mode: DisplayMode) {
        setDisplayMode(mode)
        onViewChange?(.viewChange)
    }

    func applyThumbnailSize(_ value: Double) {
        setThumbnailSize(value, persist: true)
        onViewChange?(.thumbnailSize)
    }

    /// Restores the presentation state from history. Does not go through the recording entry point (R70).
    func restore(displayMode: DisplayMode, thumbnailSize: Double) {
        setDisplayMode(displayMode)
        setThumbnailSize(thumbnailSize, persist: true)
    }

    private func setDisplayMode(_ mode: DisplayMode) {
        guard mode != displayMode else {
            if mode == .thumbnails {
                thumbnailModeView.scrollToFocused()
            }
            return
        }

        let firstResponder = view.window?.firstResponder as? NSView
        let focusWasInFileList = firstResponder.map {
            isView($0, inside: listModeView) || isView($0, inside: thumbnailModeView)
        } ?? false

        displayMode = mode
        persistDisplayMode(mode)
        updateModeVisibility()

        if mode == .thumbnails {
            thumbnailModeView.scrollToFocused()
        }

        if focusWasInFileList {
            view.window?.makeFirstResponder(primaryFocusView)
        }
    }

    private func persistDisplayMode(_ mode: DisplayMode) {
        var viewSettings = settings.viewSettings
        guard viewSettings.displayMode != mode else { return }
        viewSettings.displayMode = mode
        settings.viewSettings = viewSettings
    }

    private func setThumbnailSize(_ value: Double, persist: Bool) {
        let clamped = ViewSettings.clampThumbnailSize(value)
        let previous = thumbnailModeView.thumbnailSize
        thumbnailModeView.thumbnailSize = clamped
        if abs(sizeSlider.doubleValue - clamped) > 0.01 {
            sizeSlider.doubleValue = clamped
        }
        onViewStateChange?(displayMode, clamped)
        guard persist, previous != clamped else { return }

        var viewSettings = settings.viewSettings
        viewSettings.thumbnailSize = clamped
        settings.viewSettings = viewSettings
    }

    private func isView(_ view: NSView, inside ancestor: NSView) -> Bool {
        var current: NSView? = view
        while let candidate = current {
            if candidate === ancestor {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    @objc func copy(_ sender: Any?) {
        guard selectionItemCommands.allowsFileOperations else { return }
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    /// Copy as Pathname: puts the absolute path of the single selected item on the pasteboard as a string
    /// (FR-181). Does not touch the selection, focus, or preview (FR-185).
    @objc func copyPathname(_ sender: Any?) {
        let urls = selectedFileURLs
        guard !isEditingText,
              selectionItemCommands.allowsCopyPathname(selectionCount: urls.count),
              let url = urls.first else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        guard focusedItemCommands.allowsPaste else { return }
        guard !isEditingText else { return }
        let folder = model.listing.folder
        Task { @MainActor in
            await coordinator.paste(into: folder, move: false)
        }
    }

    @objc func movePaste(_ sender: Any?) {
        guard focusedItemCommands.allowsPaste else { return }
        guard !isEditingText else { return }
        let folder = model.listing.folder
        Task { @MainActor in
            await coordinator.paste(into: folder, move: true)
        }
    }

    @objc func duplicate(_ sender: Any?) {
        guard selectionItemCommands.allowsFileOperations else { return }
        guard !isEditingText else { return }
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            await coordinator.duplicate(urls)
        }
    }

    @objc func rename(_ sender: Any?) {
        guard focusedItemCommands.allowsFileOperations else { return }
        guard !isEditingText else { return }
        let selected = model.selection.selected
        guard selected.count == 1,
              let focused = model.selection.focused,
              selected.contains(focused) else {
            return
        }

        switch displayMode {
        case .list:
            _ = listModeView.beginRenaming()
        case .thumbnails:
            guard let window = view.window else { return }
            window.makeFirstResponder(thumbnailModeView.focusView)
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "\r",
                charactersIgnoringModifiers: "\r",
                isARepeat: false,
                keyCode: 36
            ) else {
                return
            }
            thumbnailModeView.focusView.keyDown(with: event)
        }
    }

    @objc func moveToTrash(_ sender: Any?) {
        guard selectionItemCommands.allowsFileOperations else { return }
        guard !isEditingText else { return }
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return }
        Task { @MainActor in
            await coordinator.trash(urls)
        }
    }

    @objc func open(_ sender: Any?) {
        guard selectionItemCommands.allowsFileOperations else { return }
        guard !isEditingText else { return }
        for url in selectedFileURLs {
            _ = NSWorkspace.shared.open(url)
        }
    }

    @objc func revealInFinder(_ sender: Any?) {
        guard selectionItemCommands.allowsFileOperations else { return }
        let urls = selectedFileURLs
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// Opens the focused zip file or directory. If it is `..`, goes up one level (⌘↓, FR-069).
    @objc func openFocusedItem(_ sender: Any?) {
        guard !isEditingText,
              focusedItemCommands.canOpenContainer,
              let focused = model.selection.focused else {
            return
        }
        openItem(focused)
    }

    /// Called from double-click and ⌘↓. Does nothing for media rows (Core decides).
    func openItem(_ url: URL) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.model.openItem(url)
            await self.scrollFocusedItemIntoViewAfterModelUpdate()
        }
    }

    /// Inside a zip, goes up one level. At the zip root, returns to the listing of the folder containing the zip
    /// (⌘↑, FR-070).
    @objc func goToEnclosingLevel(_ sender: Any?) {
        guard !isEditingText, focusedItemCommands.canGoUp else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.model.goToEnclosingLevel()
            await self.scrollFocusedItemIntoViewAfterModelUpdate()
        }
    }

    /// Scrolls the focused row into view after the list update (the task triggered by the Observation notification)
    /// finishes.
    private func scrollFocusedItemIntoViewAfterModelUpdate() async {
        await Task.yield()
        switch displayMode {
        case .list:
            listModeView.scrollToFocused()
        case .thumbnails:
            thumbnailModeView.scrollToFocused()
        }
    }

    @objc private func showThumbnails(_ sender: Any?) {
        setDisplayMode(.thumbnails)
        onViewChange?(.viewChange)
    }

    @objc private func showList(_ sender: Any?) {
        setDisplayMode(.list)
        onViewChange?(.viewChange)
    }

    @objc private func increaseThumbnailSize(_ sender: Any?) {
        setThumbnailSize(thumbnailModeView.thumbnailSize + 16, persist: true)
        onViewChange?(.thumbnailSize)
    }

    @objc private func decreaseThumbnailSize(_ sender: Any?) {
        setThumbnailSize(thumbnailModeView.thumbnailSize - 16, persist: true)
        onViewChange?(.thumbnailSize)
    }

    @objc private func toggleImagesOnly(_ sender: Any?) {
        var filter = model.mediaTypeFilter
        filter.imagesOnly.toggle()
        applyMediaTypeFilter(filter)
    }

    @objc private func toggleVideosOnly(_ sender: Any?) {
        var filter = model.mediaTypeFilter
        filter.videosOnly.toggle()
        applyMediaTypeFilter(filter)
    }

    @objc private func toggleShowsZipFiles(_ sender: Any?) {
        applyShowsZipFiles(!model.showsZipFiles)
    }

    @objc private func thumbnailSizeSliderChanged(_ sender: NSSlider) {
        setThumbnailSize(sender.doubleValue, persist: true)
        onViewChange?(.thumbnailSize)
    }
}

extension FileListViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleImagesOnly(_:))
            || menuItem.action == #selector(toggleVideosOnly(_:))
            || menuItem.action == #selector(toggleShowsZipFiles(_:)) {
            return !isEditingText
        }

        if menuItem.action == #selector(openFocusedItem(_:)) {
            return !isEditingText && focusedItemCommands.canOpenContainer
        }
        if menuItem.action == #selector(goToEnclosingLevel(_:)) {
            return !isEditingText && focusedItemCommands.canGoUp
        }

        // A zip is read-only (FR-073). `..` is not an operation target (R30). ListItemCommands makes the decision.
        let commands = selectionItemCommands
        switch menuItem.action {
        case #selector(copy(_:)),
             #selector(open(_:)),
             #selector(revealInFinder(_:)),
             #selector(moveToTrash(_:)),
             #selector(duplicate(_:)):
            if !commands.allowsFileOperations { return false }
        case #selector(rename(_:)):
            if !focusedItemCommands.allowsFileOperations { return false }
        case #selector(copyPathname(_:)):
            return !isEditingText
                && commands.allowsCopyPathname(selectionCount: selectedFileURLs.count)
        case #selector(paste(_:)), #selector(movePaste(_:)):
            if !commands.allowsPaste { return false }
        default:
            break
        }

        if isEditingText {
            switch menuItem.action {
            case #selector(open(_:)),
                 #selector(moveToTrash(_:)),
                 #selector(rename(_:)),
                 #selector(duplicate(_:)),
                 #selector(revealInFinder(_:)):
                return false
            default:
                break
            }
        }

        switch menuItem.action {
        case #selector(copy(_:)),
             #selector(open(_:)),
             #selector(revealInFinder(_:)),
             #selector(moveToTrash(_:)),
             #selector(duplicate(_:)):
            return !selectedFileURLs.isEmpty
        case #selector(rename(_:)):
            return model.selection.selected.count == 1
                && model.selection.focused != nil
        case #selector(paste(_:)), #selector(movePaste(_:)):
            return FileContextMenu.pasteboardHasFileURLs()
        default:
            return true
        }
    }
}
