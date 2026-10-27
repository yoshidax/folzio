import AppKit
import FolzioCore
import FolzioLocalization
import Observation

private final class NotificationTokens: @unchecked Sendable {
    var tokens: [NSObjectProtocol] = []
}

private struct HiddenListKeyPress: Sendable {
    enum Key: Sendable {
        case left
        case right
        case up
        case down
        case less
        case greater
    }

    let key: Key?
    let modifierFlags: UInt
    let windowNumber: Int

    init(event: NSEvent) {
        let key: Key?
        switch event.specialKey {
        case .leftArrow:
            key = .left
        case .rightArrow:
            key = .right
        case .upArrow:
            key = .up
        case .downArrow:
            key = .down
        default:
            switch event.charactersIgnoringModifiers {
            case "<":
                key = .less
            case ">":
                key = .greater
            default:
                key = nil
            }
        }
        self.key = key
        self.modifierFlags = event.modifierFlags.rawValue
        self.windowNumber = event.windowNumber
    }
}

@MainActor
final class MainSplitViewController: NSSplitViewController {
    private let settings: SettingsStore
    private let model: BrowserModel
    private let treeViewController: DirectoryTreeViewController
    let fileListViewController: FileListViewController
    private let previewViewController: PreviewViewController
    private let fileOperationCoordinator: FileOperationCoordinator
    let historyNavigator: HistoryNavigator
    /// Source for zip reads. `BrowserModel` and `ThumbnailProvider` share the same instance.
    private let archiveReader: ZipArchiveReader
    private var didObserveInitialListingChange = false
    private var didNotifyInitialListingDisplayed = false
    private var appliedInitialPositions = false
    private var installedFocusMenu = false
    private var treeSplitItem: NSSplitViewItem?
    private var fileListSplitItem: NSSplitViewItem?
    private var previewSplitItem: NSSplitViewItem?
    private(set) var paneLayout: PaneLayout = .all
    private var isFullScreenPresentation = false
    private var appliedPresentation = PanePresentation(layout: .all, isFullScreen: false)
    private var savedPaneWidths: [Double]?
    private var focusBeforeFullScreen: Pane?
    private var isApplyingPresentation = false
    private var collapseObservations: [NSKeyValueObservation] = []
    private var didNormalizeInitialPaneState = false
    private var isAppInitiatedFullScreenTransition = false
    private var hiddenListKeyMonitor: Any?
    /// Keyword from the previous search in the same launch. Not persisted (FR-081, R39).
    private var lastSearchKeyword: String?
    private var pendingKindNames: KindNames?

    var onPaneLayoutChange: ((PaneLayout) -> Void)?
    /// Notifies when whether the slideshow can start changes (listing, editing, or modal changes).
    var onSlideshowAvailabilityChange: (() -> Void)?
    /// Notifies when zoom in, zoom out, or Zoom to Fit availability changes (FR-134, FR-136).
    var onZoomAvailabilityChange: (() -> Void)?

    /// Slideshow driver. Created lazily because it sets this controller as its delegate.
    private(set) lazy var slideshowCoordinator: SlideshowCoordinator = {
        let coordinator = SlideshowCoordinator(settings: settings)
        coordinator.delegate = self
        return coordinator
    }()

    private var slideshowRestoreState: SlideshowRestoreState?
    private var pendingSlideshowRestore: SlideshowRestoreState?
    private var pendingSlideshowGeneration = 0
    private var slideshowPresentationGeneration = 0
    private var slideshowRestoreCompletion: (@MainActor () -> Void)?
    /// Does not auto-select the first item of a hidden list while applying previewOnly inside the slideshow.
    private var isApplyingSlideshowPresentation = false

    var paneCommands: PaneCommands {
        PaneCommands(
            layout: paneLayout,
            isFullScreen: isFullScreenPresentation,
            isEditingText: fileListViewController.isEditingText,
            isSlideshowActive: slideshowCoordinator.isActive,
            isRestoring: slideshowCoordinator.isRestoring
        )
    }

    /// Shared condition for the menu, toolbar, and start action (FR-114, FR-115).
    var canStartSlideshow: Bool {
        guard let window = view.window else { return false }
        return SlideshowStartPolicy(
            hasCandidate: SlideshowSequence.hasMedia(in: model.listing.files),
            isLoading: model.listing.state == .loading,
            isFullScreen: isFullScreenPresentation,
            isSlideshowActive: slideshowCoordinator.isActive,
            isRestoring: slideshowCoordinator.isRestoring,
            isEditingText: fileListViewController.isEditingText,
            hasSheet: window.attachedSheet != nil,
            hasAppModal: NSApp.modalWindow != nil
        ).canStart
    }


    var onInitialListingDisplayed: (() -> Void)? {
        didSet {
            deliverInitialListingIfReady()
        }
    }

    init() {
        let settings = SettingsStore(defaults: .standard)
        self.settings = settings
        let lister = DirectoryLister(kindNames: l10n.kindNames)
        let decoder = ImageDecoder()
        let cache = DecodedImageCache()
        let archiveReader = ZipArchiveReader(kindNames: l10n.kindNames)
        let model = BrowserModel(
            kindNames: l10n.kindNames,
            lister: lister,
            decoder: decoder,
            cache: cache,
            settings: settings,
            archiveReader: archiveReader
        )
        let volumes = VolumeProvider(changes: MainSplitViewController.makeVolumeChanges())
        // Pass the roots that determine `..` and ⌘↑ targets before the tree's initial selection (selectFolder) (R30).
        model.setNavigationRoots(volumes.rootNodes().map(\.url))
        let fileSystemWatcher = FileSystemWatcher()
        let thumbnailProvider = ThumbnailProvider(archiveReader: archiveReader)
        let coordinator = FileOperationCoordinator(
            model: model,
            service: FileOperationService(),
            settings: settings
        )
        let historyNavigator = HistoryNavigator(model: model)
        self.fileOperationCoordinator = coordinator
        self.historyNavigator = historyNavigator
        self.archiveReader = archiveReader
        self.model = model

        self.treeViewController = DirectoryTreeViewController(
            model: model,
            lister: lister,
            volumes: volumes,
            coordinator: coordinator,
            watcher: fileSystemWatcher,
            settings: settings,
            confirmation: ConfirmationPresenter(settings: settings)
        )
        self.fileListViewController = FileListViewController(
            model: model,
            settings: settings,
            thumbnailProvider: thumbnailProvider,
            coordinator: coordinator
        )
        self.previewViewController = PreviewViewController(
            model: model,
            decoder: decoder,
            archiveReader: archiveReader
        )

        super.init(nibName: nil, bundle: nil)

        fileOperationCoordinator.onFoldersChanged = { [weak treeViewController] folders in
            Task { @MainActor in
                await treeViewController?.refreshFolders(folders)
            }
        }
        // Rebase tree nodes synchronously before rebasing the listing (R64).
        fileOperationCoordinator.onFolderRenamed = { [weak treeViewController] oldURL, newURL in
            treeViewController?.didRenameFolder(from: oldURL, to: newURL)
        }
        fileListViewController.onRename = { [weak self] url, newName in
            guard let self else { return }
            await self.fileOperationCoordinator.rename(url, to: newName)
        }
        historyNavigator.presentationHost = self
        coordinator.historyNavigator = historyNavigator
        treeViewController.historyNavigator = historyNavigator
        fileListViewController.onViewChange = { [weak historyNavigator] kind in
            historyNavigator?.recordViewChange(kind)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(textEditingDidEnd), name: NSControl.textDidEndEditingNotification, object: nil
        )

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        let treeItem = makeItem(
            for: treeViewController,
            minimumThickness: 160,
            holdingPriority: 251
        )
        treeSplitItem = treeItem
        addSplitViewItem(treeItem)

        let fileListItem = makeItem(
            for: fileListViewController,
            minimumThickness: 240,
            holdingPriority: 250
        )
        fileListSplitItem = fileListItem
        addSplitViewItem(fileListItem)

        let previewItem = makeItem(
            for: previewViewController,
            minimumThickness: 320,
            holdingPriority: 249
        )
        previewSplitItem = previewItem
        addSplitViewItem(previewItem)

        splitView.autosaveName = "MainSplit"
        observeCollapseChanges()
        fileListViewController.onTogglePlayback = { [weak self] in
            self?.previewViewController.togglePlayback()
        }
        previewViewController.onDoubleClick = { [weak self] in
            self?.togglePreviewFullScreen()
        }
        // Pane visibility changes also arrive here through PreviewViewController.isPaneVisible.
        previewViewController.onZoomAvailabilityChange = { [weak self] in
            self?.onZoomAvailabilityChange?()
        }
        model.onWillReplaceLocation = { [weak self] in
            self?.slideshowCoordinator.handleWillReplaceLocation()
        }
        observeSlideshowData()
        installFocusMenuItems()
        observeInitialListingState()
    }

    @objc private func displayLanguageDidChange() {
        let names = l10n.kindNames
        if fileListViewController.isEditingText {
            pendingKindNames = names
        } else {
            pendingKindNames = nil
            model.setKindNames(names)
        }
    }

    @objc private func textEditingDidEnd() {
        guard pendingKindNames != nil else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.fileListViewController.isEditingText,
                  let names = self.pendingKindNames else { return }
            self.pendingKindNames = nil
            self.model.setKindNames(names)
        }
    }

    private func observeCollapseChanges() {
        let items: [(Pane, NSSplitViewItem?)] = [
            (.tree, treeSplitItem),
            (.fileList, fileListSplitItem),
            (.preview, previewSplitItem)
        ]
        for (pane, item) in items {
            guard let item else { continue }
            let observation = item.observe(\.isCollapsed, options: [.new]) { [weak self] _, change in
                guard let isCollapsed = change.newValue else { return }
                MainActor.assumeIsolated {
                    self?.handleCollapseChange(pane: pane, isCollapsed: isCollapsed)
                }
            }
            collapseObservations.append(observation)
        }
    }

    private func handleCollapseChange(pane: Pane, isCollapsed: Bool) {
        guard !isApplyingPresentation else { return }
        guard !appliedPresentation.isVisible(pane) else { return }
        guard !isCollapsed else { return }
        DispatchQueue.main.async { [weak self] in
            self?.recollapseHiddenPanes()
        }
    }

    private func recollapseHiddenPanes() {
        guard !isApplyingPresentation else { return }
        for pane in Pane.allCases where !appliedPresentation.isVisible(pane) {
            guard let item = splitItem(for: pane) else { continue }
            item.canCollapse = true
            item.isCollapsed = true
        }
    }

    private func observeInitialListingState() {
        withObservationTracking {
            _ = model.listing.state
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.handleInitialListingStateChange()
            }
        }
    }

    /// Connects listing and selection changes to the slideshow auto-end decision and the start button availability.
    /// Stops only when there are zero candidates; losing the selection or re-sorting does not change the deadline.
    private func observeSlideshowData() {
        withObservationTracking {
            _ = model.listing
            _ = model.selection
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.slideshowCoordinator.listingDidChange()
                self.onSlideshowAvailabilityChange?()
                self.observeSlideshowData()
            }
        }
    }

    private func handleInitialListingStateChange() {
        didObserveInitialListingChange = true
        deliverInitialListingIfReady()
        if !didNotifyInitialListingDisplayed {
            observeInitialListingState()
        }
    }

    private func deliverInitialListingIfReady() {
        guard didObserveInitialListingChange, !didNotifyInitialListingDisplayed else { return }

        switch model.listing.state {
        case .loading:
            return
        case .loaded, .empty, .noMatches, .denied, .failed:
            break
        }

        guard let onInitialListingDisplayed else { return }
        didNotifyInitialListingDisplayed = true
        onInitialListingDisplayed()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window, window.delegate == nil {
            window.delegate = self
        }
        normalizeInitialPaneStateIfNeeded()
        configureKeyViewLoop(for: appliedPresentation.visiblePanes)
        applyInitialPositionsIfNeeded()
        onSlideshowAvailabilityChange?()
    }

    private func normalizeInitialPaneStateIfNeeded() {
        guard !didNormalizeInitialPaneState else { return }
        didNormalizeInitialPaneState = true
        for pane in Pane.allCases {
            guard let item = splitItem(for: pane) else { continue }
            if item.isCollapsed {
                item.isCollapsed = false
            }
            if item.canCollapse {
                item.canCollapse = false
            }
        }
    }

    func setPaneLayout(_ layout: PaneLayout) {
        guard paneCommands.canChangeLayout, layout != paneLayout else {
            onPaneLayoutChange?(paneLayout)
            return
        }

        let focused = focusedPane()
        paneLayout = layout
        applyPanePresentation()
        if let target = layout.focusTarget(afterSwitchingFrom: focused) {
            focusPane(focusView(for: target))
        }
        onPaneLayoutChange?(paneLayout)
    }

    func togglePaneLayout(_ pane: SoloPane) {
        setPaneLayout(paneLayout.toggling(pane))
    }

    func applyToolbarSelection(fileListSelected: Bool, previewSelected: Bool) {
        setPaneLayout(
            paneLayout.applyingToolbarSelection(
                fileListSelected: fileListSelected,
                previewSelected: previewSelected
            )
        )
        historyNavigator.recordViewChange(.viewChange)
    }

    /// View > Start Slideshow and the toolbar button (FR-114, FR-115).
    @objc func startSlideshow(_ sender: Any?) {
        guard canStartSlideshow else { return }
        slideshowCoordinator.start()
    }

    /// Saves the normal presentation at start (panes, focus, and three-pane widths) and moves to previewOnly
    /// (FR-114, FR-118). Does not select the first item; the caller's `SlideshowSequence.startTarget` chooses the
    /// start target.
    private func prepareSlideshowPresentation() -> Bool {
        guard canStartSlideshow, view.window != nil else { return false }

        let normalFocus = isFullScreenPresentation ? focusBeforeFullScreen : focusedPane()
        let widths: [Double]?
        if paneLayout == .all {
            widths = validWidths(isFullScreenPresentation ? savedPaneWidths : currentPaneWidths())
        } else {
            widths = nil
        }
        slideshowPresentationGeneration &+= 1
        slideshowRestoreState = SlideshowRestoreState(
            normalPaneLayout: paneLayout,
            normalFocusedPane: normalFocus,
            threePaneWidths: widths
        )
        pendingSlideshowRestore = nil
        slideshowRestoreCompletion = nil

        previewViewController.setSlideshowBackground(true)
        isApplyingSlideshowPresentation = true
        paneLayout = .previewOnly
        applyPanePresentation()
        isApplyingSlideshowPresentation = false
        onPaneLayoutChange?(paneLayout)
        return true
    }

    /// Restores on exit (FR-118, FR-119). In full screen, waits for the exit notification before applying the final
    /// widths and focus.
    private func restoreSlideshowPresentation(completion: @escaping @MainActor () -> Void) {
        guard let state = slideshowRestoreState, let window = view.window else {
            discardSlideshowRestore()
            completion()
            return
        }

        if window.styleMask.contains(.fullScreen) {
            pendingSlideshowRestore = state
            pendingSlideshowGeneration = slideshowPresentationGeneration
            slideshowRestoreCompletion = completion
            window.toggleFullScreen(nil)
            return
        }

        finalizeSlideshowRestore(state)
        completion()
    }

    private func finalizeSlideshowRestore(_ state: SlideshowRestoreState) {
        previewViewController.setSlideshowBackground(false)
        if let widths = state.threePaneWidths {
            savedPaneWidths = widths
        }

        isApplyingSlideshowPresentation = true
        paneLayout = state.normalPaneLayout
        applyPanePresentation()
        isApplyingSlideshowPresentation = false
        onPaneLayoutChange?(paneLayout)

        if let pane = state.normalFocusedPane,
           PanePresentation(layout: paneLayout, isFullScreen: isFullScreenPresentation).isVisible(pane) {
            focusPane(focusView(for: pane))
        }

        slideshowRestoreState = nil
        pendingSlideshowRestore = nil
        pendingSlideshowGeneration = 0
        slideshowRestoreCompletion = nil
        onSlideshowAvailabilityChange?()
    }

    private func discardSlideshowRestore() {
        previewViewController.setSlideshowBackground(false)
        slideshowPresentationGeneration &+= 1
        slideshowRestoreState = nil
        pendingSlideshowRestore = nil
        pendingSlideshowGeneration = 0
        slideshowRestoreCompletion = nil
    }

    private func validWidths(_ widths: [Double]?) -> [Double]? {
        guard let widths,
              widths.count == 3,
              widths.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return nil
        }
        return widths
    }

    private func currentPaneWidths() -> [Double]? {
        let widths = [
            treeViewController.view.frame.width,
            fileListViewController.view.frame.width,
            previewViewController.view.frame.width
        ].map(Double.init)
        guard widths.count == 3, widths.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return nil
        }
        return widths
    }

    private var slideshowInputPolicy: SlideshowInputPolicy {
        SlideshowInputPolicy(
            isActive: slideshowCoordinator.isActive,
            isRestoring: slideshowCoordinator.isRestoring,
            isTargetWindowKey: view.window?.isKeyWindow ?? false,
            hasSheet: view.window?.attachedSheet != nil,
            hasAppModal: NSApp.modalWindow != nil,
            isEditingText: fileListViewController.isEditingText
        )
    }

    /// Whether the slideshow may intercept this Esc or unmodified arrow key (FR-123).
    private func evaluateSlideshowKeyEvent(_ event: NSEvent) -> Bool {
        guard let window = view.window,
              event.windowNumber == window.windowNumber else {
            return false
        }
        let disallowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(disallowed).isEmpty else { return false }

        let policy = slideshowInputPolicy
        switch event.specialKey {
        case .leftArrow, .rightArrow, .upArrow, .downArrow:
            return policy.accepts(.arrow)
        default:
            return event.keyCode == 53 && policy.accepts(.escape)
        }
    }

    /// Whether `/` (play/pause) can be accepted during the slideshow. Uses the same input conditions as Esc and
    /// arrows.
    private func acceptsSlideshowPlaybackKey(_ event: NSEvent) -> Bool {
        guard let window = view.window,
              event.windowNumber == window.windowNumber else {
            return false
        }
        let disallowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(disallowed).isEmpty else { return false }
        return slideshowInputPolicy.acceptsKeys
    }

    /// Peeks at an unhandled accepted key when a deadline and a key are queued in the same run loop (without
    /// dequeueing). Does not target eventTracking during menu tracking and does not intercept the key.
    private func peekSlideshowKeyEvent() -> Bool {
        guard let event = NSApp.nextEvent(
            matching: .keyDown,
            until: Date(),
            inMode: .default,
            dequeue: false
        ) else {
            return false
        }
        return evaluateSlideshowKeyEvent(event)
    }

    /// Fallback for Esc that did not pass through the local monitor, called from `cancelOperation` (FR-123).
    /// Discards slideshow resources without waiting for the restore display when quitting or closing the window
    /// (EC-72).
    func stopSlideshowImmediately() {
        slideshowCoordinator.stopImmediately()
        discardSlideshowRestore()
    }

    func handleSlideshowEscapeFallback() -> Bool {
        // Do not bounce in and out of full screen on repeated input during restore. Consume Esc until restore
        // finishes.
        if slideshowCoordinator.isRestoring { return true }
        guard slideshowCoordinator.isActive else { return false }
        guard slideshowInputPolicy.accepts(.escape) else { return false }
        slideshowCoordinator.stop()
        return true
    }

    private func applyPanePresentation() {
        let presentation = PanePresentation(
            layout: paneLayout,
            isFullScreen: isFullScreenPresentation
        )
        guard presentation != appliedPresentation else { return }

        isApplyingPresentation = true
        defer { isApplyingPresentation = false }

        if appliedPresentation.showsAllPanes && !presentation.showsAllPanes {
            let widths = [
                treeViewController.view.frame.width,
                fileListViewController.view.frame.width,
                previewViewController.view.frame.width
            ].map(Double.init)
            if widths.count == 3 && widths.allSatisfy({ $0.isFinite && $0 > 0 }) {
                savedPaneWidths = widths
            }
            splitView.autosaveName = nil
        }

        if !appliedPresentation.navigatesHiddenFileList && presentation.navigatesHiddenFileList {
            fileListViewController.beginHiddenListNavigation(
                selectingEntry: !isApplyingSlideshowPresentation
                    && !isFullScreenPresentation
                    && paneLayout == .previewOnly
            )
            installHiddenListKeyMonitor()
        }

        for pane in presentation.visiblePanes {
            guard let item = splitItem(for: pane) else { continue }
            item.isCollapsed = false
            item.canCollapse = false
        }
        for pane in Pane.allCases where !presentation.isVisible(pane) {
            guard let item = splitItem(for: pane) else { continue }
            item.canCollapse = true
            item.isCollapsed = true
        }

        previewViewController.paneLayout = paneLayout
        previewViewController.isPaneVisible = presentation.isVisible(.preview)

        let returnsToAllPanes = presentation.showsAllPanes && !appliedPresentation.showsAllPanes

        if appliedPresentation.navigatesHiddenFileList && !presentation.navigatesHiddenFileList {
            removeHiddenListKeyMonitor()
            if !returnsToAllPanes {
                fileListViewController.endHiddenListNavigation()
            }
        }

        if returnsToAllPanes {
            splitView.autosaveName = "MainSplit"
            DispatchQueue.main.async { [weak self] in
                guard let self, self.appliedPresentation == presentation else { return }
                self.splitView.layoutSubtreeIfNeeded()
                let positions = PaneWidths.dividerPositions(
                    savedWidths: self.savedPaneWidths ?? [],
                    totalWidth: Double(self.splitView.bounds.width),
                    dividerThickness: Double(self.splitView.dividerThickness),
                    minimumWidths: [160, 240, 320]
                )
                for (index, position) in positions.enumerated() {
                    self.splitView.setPosition(CGFloat(position), ofDividerAt: index)
                }
                self.treeViewController.scrollSelectedRowToVisible()
                self.fileListViewController.endHiddenListNavigation()
            }
        }

        configureKeyViewLoop(for: presentation.visiblePanes)
        appliedPresentation = presentation
    }

    private func splitItem(for pane: Pane) -> NSSplitViewItem? {
        switch pane {
        case .tree:
            return treeSplitItem
        case .fileList:
            return fileListSplitItem
        case .preview:
            return previewSplitItem
        }
    }

    private func focusedPane() -> Pane? {
        guard let responder = view.window?.firstResponder as? NSView else { return nil }
        if isView(responder, inside: treeViewController.view) {
            return .tree
        }
        if isView(responder, inside: fileListViewController.view) {
            return .fileList
        }
        if isView(responder, inside: previewViewController.view) {
            return .preview
        }
        return nil
    }

    private func focusView(for pane: Pane) -> NSView {
        switch pane {
        case .tree:
            return treeViewController.primaryFocusView
        case .fileList:
            return fileListViewController.primaryFocusView
        case .preview:
            return previewViewController.primaryFocusView
        }
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

    private func enterFullScreenPresentation() {
        guard !isFullScreenPresentation else { return }
        focusBeforeFullScreen = focusedPane()
        isFullScreenPresentation = true
        applyPanePresentation()
    }

    private func leaveFullScreenPresentation() {
        guard isFullScreenPresentation else { return }
        isFullScreenPresentation = false
        applyPanePresentation()

        let presentation = PanePresentation(layout: paneLayout, isFullScreen: false)
        if let pane = focusBeforeFullScreen, presentation.isVisible(pane) {
            focusPane(focusView(for: pane))
        }
        focusBeforeFullScreen = nil
    }

    @objc func togglePreviewFullScreen() {
        guard let window = view.window else { return }

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            return
        }

        enterFullScreenPresentation()
        isAppInitiatedFullScreenTransition = true
        window.toggleFullScreen(nil)
    }

    func exitPreviewFullScreenIfNeeded() {
        guard let window = view.window else { return }

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            leaveFullScreenPresentation()
        }
    }

    private func installHiddenListKeyMonitor() {
        guard hiddenListKeyMonitor == nil else { return }
        hiddenListKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                self?.handleHiddenListKey(event) ?? false
            }
            return handled ? nil : event
        }
    }

    private func removeHiddenListKeyMonitor() {
        guard let hiddenListKeyMonitor else { return }
        NSEvent.removeMonitor(hiddenListKeyMonitor)
        self.hiddenListKeyMonitor = nil
    }

    private func handleHiddenListKey(_ event: NSEvent) -> Bool {
        if slideshowCoordinator.handleKeyEvent(event) {
            return true
        }

        // `/` plays or pauses video during the slideshow too (FR-121). Does not change the deadline.
        if slideshowCoordinator.isActive,
           event.charactersIgnoringModifiers == "/",
           acceptsSlideshowPlaybackKey(event) {
            previewViewController.togglePlayback()
            return true
        }

        let press = HiddenListKeyPress(event: event)
        guard let window = view.window,
              press.windowNumber == window.windowNumber,
              appliedPresentation.navigatesHiddenFileList else {
            return false
        }
        guard !(window.firstResponder is NSTextView) else { return false }

        let flags = NSEvent.ModifierFlags(rawValue: press.modifierFlags)
        switch press.key {
        case .left, .right, .up, .down:
            let disallowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            guard flags.intersection(disallowed).isEmpty else { return false }
            let move: FocusMove
            switch press.key {
            case .left:
                move = .left
            case .right:
                move = .right
            case .up:
                move = .up
            default:
                move = .down
            }
            return fileListViewController.moveFocusInHiddenList(move)
        case .less, .greater:
            let disallowed: NSEvent.ModifierFlags = [.command, .option, .control]
            guard flags.intersection(disallowed).isEmpty else { return false }
            return previewViewController.seekVideo(by: press.key == .less ? -5 : 5)
        case nil:
            return false
        }
    }

    private func makeItem(
        for viewController: NSViewController,
        minimumThickness: CGFloat,
        holdingPriority: Float,
        canCollapse: Bool = false
    ) -> NSSplitViewItem {
        let item = NSSplitViewItem(viewController: viewController)
        item.minimumThickness = minimumThickness
        item.canCollapse = canCollapse
        item.holdingPriority = NSLayoutConstraint.Priority(holdingPriority)
        return item
    }

    private func applyInitialPositionsIfNeeded() {
        guard !appliedInitialPositions else { return }
        appliedInitialPositions = true

        let autosaveKey = "NSSplitView Subview Frames MainSplit"
        guard UserDefaults.standard.object(forKey: autosaveKey) == nil else { return }

        splitView.setPosition(220, ofDividerAt: 0)
        let secondDivider = 220 + splitView.dividerThickness + 360
        splitView.setPosition(secondDivider, ofDividerAt: 1)
    }

    private func configureKeyViewLoop(for visiblePanes: [Pane]) {
        let views = visiblePanes.map(focusView(for:))
        guard let first = views.first else { return }

        for (index, view) in views.enumerated() {
            view.nextKeyView = views[(index + 1) % views.count]
        }

        view.window?.initialFirstResponder = first
    }

    private func installFocusMenuItems() {
        guard !installedFocusMenu else { return }
        guard let viewMenu = NSApp.mainMenu?.items
            .first(where: { $0.submenu?.identifier == NSUserInterfaceItemIdentifier("menu.view") })?
            .submenu else {
            return
        }
        installedFocusMenu = true

        viewMenu.addItem(.separator())
        let fileListOnlyItem = NSMenuItem(
            title: l10n.text(.menuViewShowFileListOnly),
            action: #selector(toggleFileListOnly(_:)),
            keyEquivalent: "2"
        )
        fileListOnlyItem.keyEquivalentModifierMask = [.command, .control]
        fileListOnlyItem.target = self
        MainMenu.bind(fileListOnlyItem, .menuViewShowFileListOnly)
        viewMenu.addItem(fileListOnlyItem)

        let previewOnlyItem = NSMenuItem(
            title: l10n.text(.menuViewShowPreviewOnly),
            action: #selector(togglePreviewOnly(_:)),
            keyEquivalent: "3"
        )
        previewOnlyItem.keyEquivalentModifierMask = [.command, .control]
        previewOnlyItem.target = self
        MainMenu.bind(previewOnlyItem, .menuViewShowPreviewOnly)
        viewMenu.addItem(previewOnlyItem)

        addFocusItem(
            to: viewMenu,
            key: .menuViewFocusTree,
            keyEquivalent: "1",
            action: #selector(focusTreePane(_:))
        )
        addFocusItem(
            to: viewMenu,
            key: .menuViewFocusFileList,
            keyEquivalent: "2",
            action: #selector(focusFileListPane(_:))
        )
        addFocusItem(
            to: viewMenu,
            key: .menuViewFocusPreview,
            keyEquivalent: "3",
            action: #selector(focusPreviewPane(_:))
        )

        // An uppercase F makes this ⇧⌘F.
        let favoritesItem = NSMenuItem(
            title: l10n.text(.menuViewGoToFavorites),
            action: #selector(focusFavorites(_:)),
            keyEquivalent: "F"
        )
        favoritesItem.keyEquivalentModifierMask = [.command]
        favoritesItem.target = self
        MainMenu.bind(favoritesItem, .menuViewGoToFavorites)
        viewMenu.addItem(favoritesItem)
    }

    private func addFocusItem(
        to menu: NSMenu,
        key: TextKey,
        keyEquivalent: String,
        action: Selector
    ) {
        let item = NSMenuItem(title: l10n.text(key), action: action, keyEquivalent: keyEquivalent)
        MainMenu.bind(item, key)
        item.keyEquivalentModifierMask = [.command, .option]
        item.target = self
        menu.addItem(item)
    }

    @objc private func toggleFileListOnly(_ sender: Any?) {
        togglePaneLayout(.fileList)
        historyNavigator.recordViewChange(.viewChange)
    }

    @objc private func togglePreviewOnly(_ sender: Any?) {
        togglePaneLayout(.preview)
        historyNavigator.recordViewChange(.viewChange)
    }

    /// ⌘[. Goes back one history entry (FR-112).
    @objc func goBack(_ sender: Any?) {
        guard paneCommands.canNavigateHistory, historyNavigator.canGoBack else { return }
        historyNavigator.goBack()
    }

    /// ⌘]. Goes forward one history entry (FR-112).
    @objc func goForward(_ sender: Any?) {
        guard paneCommands.canNavigateHistory, historyNavigator.canGoForward else { return }
        historyNavigator.goForward()
    }

    @objc private func focusTreePane(_ sender: Any?) {
        guard paneCommands.canFocus(.tree) else { return }
        focusPane(treeViewController.primaryFocusView)
    }

    @objc private func focusFileListPane(_ sender: Any?) {
        guard paneCommands.canFocus(.fileList) else { return }
        focusPane(fileListViewController.primaryFocusView)
    }

    @objc private func focusPreviewPane(_ sender: Any?) {
        guard paneCommands.canFocus(.preview) else { return }
        focusPane(previewViewController.primaryFocusView)
    }

    @objc private func focusFavorites(_ sender: Any?) {
        guard paneCommands.canGoToFavorites else { return }
        treeViewController.focusFavoritesHeader()
    }

    /// ⌃⌘T. Registers the folder selected in the tree regardless of which pane has focus (FR-062).
    @objc func addSelectedFolderToFavorites(_ sender: Any?) {
        guard paneCommands.allowsAddingFavorite,
              treeViewController.canAddSelectedFolderToFavorites else {
            return
        }
        treeViewController.addSelectedFolderToFavorites()
    }

    /// ⌘F. Opens the search modal. The default root is the displayed folder (the pre-search folder while showing
    /// search results; FR-080, FR-081).
    @objc func showSearch(_ sender: Any?) {
        guard paneCommands.canSearch else { return }
        let panel = SearchPanelController(
            keyword: lastSearchKeyword,
            rootPath: model.listing.folder.path
        ) { [weak self] pattern, root in
            guard let self else { return }
            self.lastSearchKeyword = pattern.keyword
            self.model.startSearch(pattern, root: root)
            // Move focus to the file list so the arrow keys can navigate the results.
            self.focusPane(self.fileListViewController.primaryFocusView)
        }
        presentAsSheet(panel)
    }

    private func focusPane(_ view: NSView) {
        view.window?.makeFirstResponder(view)
    }

    private static func makeVolumeChanges() -> AsyncStream<[FolderNode]> {
        AsyncStream { continuation in
            let tokens = NotificationTokens()
            let center = NSWorkspace.shared.notificationCenter

            for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
                let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
                    continuation.yield(VolumeProvider.computeRootNodes())
                }
                tokens.tokens.append(token)
            }

            continuation.onTermination = { _ in
                for token in tokens.tokens {
                    center.removeObserver(token)
                }
            }
        }
    }
}

extension MainSplitViewController: HistoryPresentationHost {
    var historyPresentation: HistoryPresentation {
        HistoryPresentation(
            displayMode: fileListViewController.currentDisplayMode,
            thumbnailSize: fileListViewController.currentThumbnailSize,
            // Record presentation changes during the slideshow in the normal layout used for restore (FR-121).
            paneLayout: slideshowRestoreState?.normalPaneLayout ?? paneLayout
        )
    }

    func applyHistoryPresentation(_ presentation: HistoryPresentation) {
        fileListViewController.restore(
            displayMode: presentation.displayMode,
            thumbnailSize: presentation.thumbnailSize
        )
        setPaneLayout(presentation.paneLayout)
        // Called only when history navigation succeeds. Resets to 100% even when returning to the same image
        // (FR-137, EC-88).
        previewViewController.resetZoom()
    }
}

// MARK: - Preview Zoom (FR-133–FR-137)

extension MainSplitViewController {
    var zoomAvailability: PreviewZoomAvailability {
        previewViewController.zoomAvailability
    }

    /// Zoom changes are not recorded in history (FR-137).
    @discardableResult
    func zoomIn() -> Bool {
        previewViewController.zoomIn()
    }

    @discardableResult
    func zoomOut() -> Bool {
        previewViewController.zoomOut()
    }

    @discardableResult
    func zoomToFit() -> Bool {
        previewViewController.zoomToFit()
    }

    func resetZoom() {
        previewViewController.resetZoom()
    }
}

extension MainSplitViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleFileListOnly(_:)):
            menuItem.state = paneLayout.soloPane == .fileList ? .on : .off
            return paneCommands.canChangeLayout
        case #selector(togglePreviewOnly(_:)):
            menuItem.state = paneLayout.soloPane == .preview ? .on : .off
            return paneCommands.canChangeLayout
        case #selector(focusTreePane(_:)):
            return paneCommands.canFocus(.tree)
        case #selector(focusFileListPane(_:)):
            return paneCommands.canFocus(.fileList)
        case #selector(focusPreviewPane(_:)):
            return paneCommands.canFocus(.preview)
        case #selector(focusFavorites(_:)):
            return paneCommands.canGoToFavorites
        case #selector(showSearch(_:)):
            return paneCommands.canSearch
        case #selector(goBack(_:)):
            return paneCommands.canNavigateHistory && historyNavigator.canGoBack
        case #selector(goForward(_:)):
            return paneCommands.canNavigateHistory && historyNavigator.canGoForward
        case #selector(addSelectedFolderToFavorites(_:)):
            return paneCommands.allowsAddingFavorite
                && treeViewController.canAddSelectedFolderToFavorites
        case #selector(startSlideshow(_:)):
            return canStartSlideshow
        default:
            return true
        }
    }
}

extension MainSplitViewController: SlideshowCoordinatorDelegate {
    func slideshowBeginTransition(to url: URL, current: URL?, effect: SlideshowTransitionEffect) {
        previewViewController.beginTransition(to: url, current: current, effect: effect)
    }

    func slideshowCancelTransition() {
        previewViewController.cancelTransition()
    }

    var slideshowFiles: [MediaFile] { model.listing.files }
    var slideshowSelectedURLs: Set<URL> { model.selection.selected }
    var slideshowFocusedURL: URL? { model.selection.focused }
    var slideshowListingIsLoading: Bool { model.listing.state == .loading }

    func slideshowPrepareForStart() -> Bool {
        prepareSlideshowPresentation()
    }

    func slideshowSynchronizeSelection(to url: URL) -> Bool {
        model.synchronizeSlideshowSelection(to: url)
    }

    func slideshowMoveFocus(_ move: FocusMove) {
        _ = fileListViewController.moveFocusInHiddenList(move)
    }

    func slideshowFocusPreview() {
        focusPane(previewViewController.primaryFocusView)
    }

    func slideshowRestoreAfterStop(completion: @escaping @MainActor () -> Void) {
        restoreSlideshowPresentation(completion: completion)
    }

    func slideshowDiscardRestore() {
        discardSlideshowRestore()
    }

    func slideshowAcceptsKeyEvent(_ event: NSEvent) -> Bool {
        evaluateSlideshowKeyEvent(event)
    }

    func slideshowHasPendingKeyEvent() -> Bool {
        peekSlideshowKeyEvent()
    }

    func slideshowAvailabilityDidChange() {
        onPaneLayoutChange?(paneLayout)
        onSlideshowAvailabilityChange?()
    }
}

extension MainSplitViewController: NSWindowDelegate {
    func window(
        _ window: NSWindow,
        willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []
    ) -> NSApplication.PresentationOptions {
        proposedOptions.union([.autoHideToolbar, .autoHideMenuBar])
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === view.window else { return }

        if isAppInitiatedFullScreenTransition {
            isAppInitiatedFullScreenTransition = false
        } else {
            enterFullScreenPresentation()
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isAppInitiatedFullScreenTransition = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === view.window else { return }

        isAppInitiatedFullScreenTransition = false
        guard let restore = pendingSlideshowRestore else {
            leaveFullScreenPresentation()
            return
        }

        let completion = slideshowRestoreCompletion
        pendingSlideshowRestore = nil
        slideshowRestoreCompletion = nil
        guard pendingSlideshowGeneration == slideshowPresentationGeneration else {
            pendingSlideshowGeneration = 0
            completion?()
            return
        }
        pendingSlideshowGeneration = 0
        leaveFullScreenPresentation()
        finalizeSlideshowRestore(restore)
        completion?()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === view.window else { return }
        stopSlideshowImmediately()
    }
}
