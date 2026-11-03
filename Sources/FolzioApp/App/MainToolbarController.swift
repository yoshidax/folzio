import AppKit
import FolzioLocalization
import FolzioCore
import Observation

@MainActor
final class MainToolbarController: NSObject {
    private static let historyIdentifier = NSToolbarItem.Identifier("history")
    private static let paneLayoutIdentifier = NSToolbarItem.Identifier("paneLayout")
    private static let slideshowIdentifier = NSToolbarItem.Identifier("slideshow")
    private static let previewZoomIdentifier = NSToolbarItem.Identifier("previewZoom")
    private static let mediaTypeFilterIdentifier = NSToolbarItem.Identifier("mediaTypeFilter")
    private static let zipVisibilityIdentifier = NSToolbarItem.Identifier("zipVisibility")
    private static let viewModeIdentifier = NSToolbarItem.Identifier("viewMode")
    private static let thumbnailSizeIdentifier = NSToolbarItem.Identifier("thumbnailSize")

    let toolbar = NSToolbar(identifier: "MainToolbar")

    private let fileList: FileListViewController
    private let panes: MainSplitViewController
    private let settings: SettingsStore
    private var visibilityObservation: NSKeyValueObservation?
    private var editingObservers: [NSObjectProtocol] = []
    private var configurationObservations: [NSKeyValueObservation] = []
    private var assignmentObserver: ShortcutAssignmentObserver?
    private var terminationObserver: NSObjectProtocol?

    // The toolbar does not keep references to its controls. The customization palette and the removal and re-adding of
    // items create new items, so a stored reference would point at a control that is no longer displayed (TAK-23, R-2).
    // State is always applied to the items currently in `toolbar.items`, found by identifier.

    init(fileList: FileListViewController, panes: MainSplitViewController, settings: SettingsStore) {
        self.fileList = fileList
        self.panes = panes
        self.settings = settings
        super.init()

        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )
        // The tooltips show the current keys, so an assignment change refreshes them like a language change.
        assignmentObserver = ShortcutAssignmentObserver { [weak self] in self?.displayLanguageDidChange() }

        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.allowsDisplayModeCustomization = true
        // The standard autosave writes the configuration but does not apply it at launch (TAK-23, R-3), so the order
        // and display mode are saved and restored by the app instead.
        toolbar.autosavesConfiguration = false

        fileList.onViewStateChange = { [weak self] mode, size in
            self?.apply(displayMode: mode, thumbnailSize: size)
        }

        fileList.onMediaTypeFilterChange = { [weak self] filter in
            self?.apply(mediaTypeFilter: filter)
        }

        fileList.onShowsZipFilesChange = { [weak self] shows in
            self?.apply(showsZipFiles: shows)
        }

        visibilityObservation = toolbar.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            // Read the new value from the change, because `NSToolbar.isVisible` is main actor-isolated on older SDKs.
            guard let isVisible = change.newValue else { return }
            MainActor.assumeIsolated {
                self?.toolbarVisibilityChanged(isVisible)
            }
        }

        panes.onPaneLayoutChange = { [weak self] layout in
            self?.apply(paneLayout: layout)
        }
        panes.onSlideshowAvailabilityChange = { [weak self] in
            self?.updateSlideshowAvailability()
        }
        panes.onZoomAvailabilityChange = { [weak self] in
            self?.applyZoomAvailability()
        }
        observeEditingAvailability()
        observeHistoryAvailability()
    }

    // MARK: - Saving and restoring the customization

    /// Restores the saved item order and display mode, then starts saving further changes.
    ///
    /// Call this after the toolbar is attached to the window. The standard autosave is not used, because it did not
    /// apply the saved order at launch (TAK-23, R-3). Nothing is applied before the user customizes the toolbar for
    /// the first time, so the default configuration stays in effect.
    func restoreSavedConfiguration() {
        if let rawValue = settings.toolbarDisplayModeRawValue,
           let displayMode = NSToolbar.DisplayMode(rawValue: UInt(rawValue)) {
            toolbar.displayMode = displayMode
        }
        if settings.hasSavedToolbarItemOrder {
            toolbar.itemIdentifiers = settings.toolbarItemOrder.map { NSToolbarItem.Identifier($0) }
        }
        startSavingConfiguration()
    }

    private func startSavingConfiguration() {
        // `NSToolbar.itemIdentifiers` is documented as key value observable. The order is also saved when the app
        // terminates, in case a customization is not reported through the observation.
        configurationObservations = [
            toolbar.observe(\.itemIdentifiers, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.saveConfiguration() }
            },
            toolbar.observe(\.displayMode, options: []) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.saveConfiguration() }
            },
        ]
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveConfiguration() }
        }
    }

    /// Saves the order and display mode only while they differ from the defaults, so that users who never customized
    /// the toolbar keep following the default configuration of later versions.
    private func saveConfiguration() {
        let order = toolbar.itemIdentifiers.map(\.rawValue)
        if order == ToolbarLayout.defaultOrder {
            settings.clearToolbarItemOrder()
        } else {
            settings.toolbarItemOrder = order
        }
        settings.toolbarDisplayModeRawValue = toolbar.displayMode == .iconOnly ? nil : Int(toolbar.displayMode.rawValue)
    }

    // MARK: - Finding the items that are displayed

    /// Returns every item with the identifier that is currently in the toolbar.
    private func items(for identifier: NSToolbarItem.Identifier) -> [NSToolbarItem] {
        toolbar.items.filter { $0.itemIdentifier == identifier }
    }

    @objc private func displayLanguageDidChange() {
        let entries: [(NSToolbarItem.Identifier, TextKey, [TextKey])] = [
            (Self.historyIdentifier, .toolbarHistory, [.toolbarGoBackHelp, .toolbarGoForwardHelp]),
            (Self.paneLayoutIdentifier, .toolbarPanes, [.toolbarShowFileListOnlyHelp, .toolbarShowPreviewOnlyHelp]),
            (Self.previewZoomIdentifier, .toolbarZoomGroup, [.toolbarZoomInHelp, .toolbarZoomToFitHelp, .toolbarZoomOutHelp]),
            (Self.mediaTypeFilterIdentifier, .toolbarMediaType, [.toolbarShowImagesOnlyHelp, .toolbarShowVideosOnlyHelp]),
            (Self.zipVisibilityIdentifier, .toolbarZipFilesLabel, [.toolbarZipFilesHelp]),
            (Self.viewModeIdentifier, .toolbarViewMode, [.toolbarThumbnails, .toolbarList]),
        ]
        for (identifier, key, segmentKeys) in entries {
            let label = l10n.text(key)
            let labels = segmentKeys.map { ToolbarShortcutText.text($0) }
            for item in items(for: identifier) {
                item.label = label
                item.paletteLabel = label
                item.toolTip = label
                guard let control = item.view as? NSSegmentedControl else { continue }
                for (index, text) in labels.enumerated() { control.setToolTip(text, forSegment: index) }
                control.setAccessibilityLabel(l10n.list(labels))
                control.setAccessibilityHelp(l10n.list(labels))
            }
        }
        for item in items(for: Self.slideshowIdentifier) {
            item.label = l10n.text(.toolbarSlideshowLabel)
            item.paletteLabel = item.label
            item.toolTip = ToolbarShortcutText.text(.toolbarStartSlideshowHelp)
            if let button = item.view as? NSButton {
                button.toolTip = ToolbarShortcutText.text(.toolbarStartSlideshowHelp)
                button.setAccessibilityLabel(l10n.text(.menuViewStartSlideshow))
                button.setAccessibilityHelp(ToolbarShortcutText.text(.toolbarStartSlideshowHelp))
            }
        }
        for item in items(for: Self.thumbnailSizeIdentifier) {
            item.label = l10n.text(.toolbarThumbnailSizeLabel)
            item.paletteLabel = item.label
            item.toolTip = ToolbarShortcutText.text(.toolbarThumbnailSize)
            if let slider = item.view as? NSSlider {
                slider.toolTip = ToolbarShortcutText.text(.toolbarThumbnailSize)
                slider.setAccessibilityLabel(ToolbarShortcutText.text(.toolbarThumbnailSize))
                slider.setAccessibilityHelp(ToolbarShortcutText.text(.toolbarThumbnailSize))
            }
        }
    }

    // MARK: - Applying state

    /// Applies the current app state to a single item, such as one that was just created or added to the toolbar.
    private func applyState(to item: NSToolbarItem) {
        switch item.itemIdentifier {
        case Self.historyIdentifier:
            applyHistoryAvailability(to: item)
        case Self.paneLayoutIdentifier:
            applyPaneLayout(panes.paneLayout, to: item)
        case Self.slideshowIdentifier:
            (item.view as? NSButton)?.isEnabled = panes.canStartSlideshow
        case Self.previewZoomIdentifier:
            applyZoomAvailability(to: item)
        case Self.mediaTypeFilterIdentifier:
            applyMediaTypeFilter(fileList.currentMediaTypeFilter, to: item)
        case Self.zipVisibilityIdentifier:
            applyShowsZipFiles(fileList.currentShowsZipFiles, to: item)
        case Self.viewModeIdentifier, Self.thumbnailSizeIdentifier:
            applyDisplayState(
                displayMode: fileList.currentDisplayMode,
                thumbnailSize: fileList.currentThumbnailSize,
                to: item
            )
        default:
            break
        }
    }

    private func updateSlideshowAvailability() {
        for item in items(for: Self.slideshowIdentifier) {
            (item.view as? NSButton)?.isEnabled = panes.canStartSlideshow
        }
        applyHistoryAvailability()
        toolbar.validateVisibleItems()
    }

    /// Enables or disables Zoom In, Zoom Out, and Zoom to Fit from image display, pane visibility, and zoom limits
    /// (FR-134, FR-136).
    private func applyZoomAvailability() {
        for item in items(for: Self.previewZoomIdentifier) {
            applyZoomAvailability(to: item)
        }
    }

    private func applyZoomAvailability(to item: NSToolbarItem) {
        let availability = panes.zoomAvailability
        item.isEnabled = availability.isAvailable
        guard let control = item.view as? NSSegmentedControl else { return }
        control.isEnabled = availability.isAvailable
        control.setEnabled(availability.canZoomIn, forSegment: 0)
        control.setEnabled(availability.canFit, forSegment: 1)
        control.setEnabled(availability.canZoomOut, forSegment: 2)
    }

    private func observeEditingAvailability() {
        for name in [NSControl.textDidBeginEditingNotification, NSControl.textDidEndEditingNotification] {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.updateSlideshowAvailability()
                    }
                }
            }
            editingObservers.append(token)
        }
    }

    /// Enables or disables Back and Forward from history and pane state (FR-112).
    func applyHistoryAvailability() {
        for item in items(for: Self.historyIdentifier) {
            applyHistoryAvailability(to: item)
        }
    }

    private func applyHistoryAvailability(to item: NSToolbarItem) {
        guard let control = item.view as? NSSegmentedControl else { return }
        let canNavigate = panes.paneCommands.canNavigateHistory
        control.setEnabled(canNavigate && panes.historyNavigator.canGoBack, forSegment: 0)
        control.setEnabled(canNavigate && panes.historyNavigator.canGoForward, forSegment: 1)
    }

    private func observeHistoryAvailability() {
        withObservationTracking {
            _ = panes.historyNavigator.canGoBack
            _ = panes.historyNavigator.canGoForward
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyHistoryAvailability()
                self.observeHistoryAvailability()
            }
        }
    }

    func apply(paneLayout: PaneLayout) {
        for item in items(for: Self.paneLayoutIdentifier) {
            applyPaneLayout(paneLayout, to: item)
        }
        applyHistoryAvailability()
    }

    private func applyPaneLayout(_ paneLayout: PaneLayout, to item: NSToolbarItem) {
        guard let control = item.view as? NSSegmentedControl else { return }
        control.setSelected(paneLayout.soloPane == .fileList, forSegment: 0)
        control.setSelected(paneLayout.soloPane == .preview, forSegment: 1)
        control.isEnabled = panes.paneCommands.canChangeLayout
    }

    func apply(displayMode: DisplayMode, thumbnailSize: Double) {
        for identifier in [Self.viewModeIdentifier, Self.thumbnailSizeIdentifier] {
            for item in items(for: identifier) {
                applyDisplayState(displayMode: displayMode, thumbnailSize: thumbnailSize, to: item)
            }
        }
    }

    private func applyDisplayState(displayMode: DisplayMode, thumbnailSize: Double, to item: NSToolbarItem) {
        switch item.itemIdentifier {
        case Self.viewModeIdentifier:
            (item.view as? NSSegmentedControl)?.selectedSegment = displayMode == .thumbnails ? 0 : 1
        case Self.thumbnailSizeIdentifier:
            let sliderEnabled = FileListChrome(
                displayMode: displayMode,
                toolbarShown: toolbar.isVisible
            ).toolbarSliderEnabled
            if let slider = item.view as? NSSlider {
                if abs(slider.doubleValue - thumbnailSize) > 0.01 {
                    slider.doubleValue = thumbnailSize
                }
                slider.isEnabled = sliderEnabled
            }
            item.isEnabled = sliderEnabled
        default:
            break
        }
    }

    func apply(mediaTypeFilter: MediaTypeFilter) {
        for item in items(for: Self.mediaTypeFilterIdentifier) {
            applyMediaTypeFilter(mediaTypeFilter, to: item)
        }
    }

    private func applyMediaTypeFilter(_ filter: MediaTypeFilter, to item: NSToolbarItem) {
        guard let control = item.view as? NSSegmentedControl else { return }
        control.setSelected(filter.imagesOnly, forSegment: 0)
        control.setSelected(filter.videosOnly, forSegment: 1)
    }

    func apply(showsZipFiles: Bool) {
        for item in items(for: Self.zipVisibilityIdentifier) {
            applyShowsZipFiles(showsZipFiles, to: item)
        }
    }

    private func applyShowsZipFiles(_ shows: Bool, to item: NSToolbarItem) {
        guard let control = item.view as? NSSegmentedControl else { return }
        control.setSelected(shows, forSegment: 0)
        control.isEnabled = !fileList.isEditingText
    }

    private func toolbarVisibilityChanged(_ isVisible: Bool) {
        fileList.isToolbarShown = isVisible

        var viewSettings = settings.viewSettings
        guard viewSettings.showsToolbar != isVisible else { return }
        viewSettings.showsToolbar = isVisible
        settings.viewSettings = viewSettings
    }

    @objc private func historySelected(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 {
            panes.goBack(sender)
        } else {
            panes.goForward(sender)
        }
    }

    @objc private func paneLayoutSelected(_ sender: NSSegmentedControl) {
        panes.applyToolbarSelection(
            fileListSelected: sender.isSelected(forSegment: 0),
            previewSelected: sender.isSelected(forSegment: 1)
        )
    }

    @objc private func previewZoomSelected(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            panes.zoomIn()
        case 1:
            panes.zoomToFit()
        case 2:
            panes.zoomOut()
        default:
            break
        }
    }

    @objc private func mediaTypeFilterSelected(_ sender: NSSegmentedControl) {
        fileList.applyMediaTypeFilter(
            MediaTypeFilter(
                imagesOnly: sender.isSelected(forSegment: 0),
                videosOnly: sender.isSelected(forSegment: 1)
            )
        )
    }

    @objc private func zipVisibilitySelected(_ sender: NSSegmentedControl) {
        fileList.applyShowsZipFiles(sender.isSelected(forSegment: 0))
    }

    @objc private func viewModeSelected(_ sender: NSSegmentedControl) {
        fileList.selectDisplayMode(sender.selectedSegment == 0 ? .thumbnails : .list)
    }

    @objc private func thumbnailSizeChanged(_ sender: NSSlider) {
        fileList.applyThumbnailSize(sender.doubleValue)
    }

    /// Creates a thumbnail size slider. Every toolbar item gets its own slider, because a view can have only one
    /// superview and the palette creates its own items.
    private func makeSizeSlider() -> NSSlider {
        let slider = NSSlider()
        slider.minValue = ViewSettings.minimumThumbnailSize
        slider.maxValue = ViewSettings.maximumThumbnailSize
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(thumbnailSizeChanged(_:))
        slider.toolTip = ToolbarShortcutText.text(.toolbarThumbnailSize)
        slider.setAccessibilityLabel(ToolbarShortcutText.text(.toolbarThumbnailSize))
        slider.setAccessibilityHelp(ToolbarShortcutText.text(.toolbarThumbnailSize))
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        return slider
    }

    /// Lays out the three button groups with the same appearance and width (FR-045, 051, 056, 089).
    private func makeSegmentedControl(
        items: [(symbol: String, label: String)],
        trackingMode: NSSegmentedControl.SwitchTracking,
        action: Selector
    ) -> NSSegmentedControl? {
        let images = items.compactMap { item in
            NSImage(
                systemSymbolName: item.symbol,
                accessibilityDescription: item.label
            )
        }
        guard images.count == items.count else { return nil }

        let control = NSSegmentedControl(
            images: images,
            trackingMode: trackingMode,
            target: self,
            action: action
        )
        control.segmentStyle = .texturedRounded
        control.controlSize = .regular
        for index in items.indices {
            control.setWidth(36, forSegment: index)
            control.setToolTip(items[index].label, forSegment: index)
        }
        control.setAccessibilityLabel(l10n.list(items.map(\.label)))
        control.setAccessibilityHelp(l10n.list(items.map(\.label)))
        control.sizeToFit()
        return control
    }

    private func makeGroupItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        control: NSSegmentedControl
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.view = control
        item.target = self
        item.action = control.action
        return item
    }
}

extension MainToolbarController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.historyIdentifier, Self.paneLayoutIdentifier, Self.slideshowIdentifier, Self.previewZoomIdentifier, Self.mediaTypeFilterIdentifier, Self.zipVisibilityIdentifier, Self.viewModeIdentifier, Self.thumbnailSizeIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.historyIdentifier, Self.paneLayoutIdentifier, Self.slideshowIdentifier, Self.previewZoomIdentifier, Self.mediaTypeFilterIdentifier, Self.zipVisibilityIdentifier, Self.viewModeIdentifier, Self.thumbnailSizeIdentifier, .space, .flexibleSpace]
    }

    /// Applies the current state to an item as it enters the toolbar. At this point the item is not yet in
    /// `toolbar.items`, so the state is applied to the item in the notification.
    func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem else { return }
        applyState(to: item)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        // Every call returns a new item with its own controls. `flag` is false for the items shown in the customization
        // palette. Only the items that enter the toolbar get the current state.
        let item = makeItem(for: itemIdentifier)
        if flag, let item {
            applyState(to: item)
        }
        return item
    }

    private func makeItem(for itemIdentifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.historyIdentifier:
            guard let control = makeSegmentedControl(
                items: [
                    ("chevron.left", ToolbarShortcutText.text(.toolbarGoBackHelp)),
                    ("chevron.right", ToolbarShortcutText.text(.toolbarGoForwardHelp)),
                ],
                trackingMode: .momentary,
                action: #selector(historySelected(_:))
            ) else {
                return nil
            }
            return makeGroupItem(
                identifier: itemIdentifier,
                label: l10n.text(.toolbarHistory),
                control: control
            )
        case Self.paneLayoutIdentifier:
            guard let control = makeSegmentedControl(
                items: [
                    ("list.bullet.rectangle", ToolbarShortcutText.text(.toolbarShowFileListOnlyHelp)),
                    ("sidebar.right", ToolbarShortcutText.text(.toolbarShowPreviewOnlyHelp)),
                ],
                trackingMode: .selectAny,
                action: #selector(paneLayoutSelected(_:))
            ) else {
                return nil
            }
            return makeGroupItem(
                identifier: itemIdentifier,
                label: l10n.text(.toolbarPanes),
                control: control
            )
        case Self.slideshowIdentifier:
            let image = IconCatalog.slideshowIcon() ?? NSImage()
            let button = NSButton(
                image: image,
                target: panes,
                action: #selector(MainSplitViewController.startSlideshow(_:))
            )
            button.bezelStyle = .texturedRounded
            button.controlSize = .regular
            button.isBordered = true
            button.imagePosition = .imageOnly
            button.toolTip = ToolbarShortcutText.text(.toolbarStartSlideshowHelp)
            button.setAccessibilityLabel(l10n.text(.menuViewStartSlideshow))
            button.setAccessibilityHelp(ToolbarShortcutText.text(.toolbarStartSlideshowHelp))

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = l10n.text(.toolbarSlideshowLabel)
            item.paletteLabel = l10n.text(.toolbarSlideshowLabel)
            item.toolTip = ToolbarShortcutText.text(.toolbarStartSlideshowHelp)
            item.view = button
            item.target = panes
            item.action = #selector(MainSplitViewController.startSlideshow(_:))
            item.autovalidates = true
            return item
        case Self.previewZoomIdentifier:
            // A momentary action that does not keep a selected state. Do not show a pressed middle button even at
            // 100% (A-61).
            guard let control = makeSegmentedControl(
                items: [
                    ("plus.magnifyingglass", l10n.text(.menuViewZoomIn)),
                    ("arrow.up.left.and.down.right.magnifyingglass", l10n.text(.menuViewZoomToFit)),
                    ("minus.magnifyingglass", l10n.text(.menuViewZoomOut)),
                ],
                trackingMode: .momentary,
                action: #selector(previewZoomSelected(_:))
            ) else {
                return nil
            }
            control.setToolTip(ToolbarShortcutText.text(.toolbarZoomInHelp), forSegment: 0)
            control.setToolTip(ToolbarShortcutText.text(.toolbarZoomToFitHelp), forSegment: 1)
            control.setToolTip(ToolbarShortcutText.text(.toolbarZoomOutHelp), forSegment: 2)
            control.setAccessibilityHelp(l10n.list([
                ToolbarShortcutText.text(.toolbarZoomInHelp), ToolbarShortcutText.text(.toolbarZoomToFitHelp), ToolbarShortcutText.text(.toolbarZoomOutHelp),
            ]))
            return makeGroupItem(
                identifier: itemIdentifier,
                label: l10n.text(.toolbarZoomGroup),
                control: control
            )
        case Self.mediaTypeFilterIdentifier:
            guard let control = makeSegmentedControl(
                items: [
                    ("photo", ToolbarShortcutText.text(.toolbarShowImagesOnlyHelp)),
                    ("film", ToolbarShortcutText.text(.toolbarShowVideosOnlyHelp)),
                ],
                trackingMode: .selectAny,
                action: #selector(mediaTypeFilterSelected(_:))
            ) else {
                return nil
            }
            return makeGroupItem(
                identifier: itemIdentifier,
                label: l10n.text(.toolbarMediaType),
                control: control
            )
        case Self.zipVisibilityIdentifier:
            guard let control = makeSegmentedControl(
                items: [
                    ("doc.zipper", ToolbarShortcutText.text(.toolbarZipFilesHelp)),
                ],
                trackingMode: .selectAny,
                action: #selector(zipVisibilitySelected(_:))
            ) else {
                return nil
            }
            return makeGroupItem(
                identifier: itemIdentifier,
                label: l10n.text(.toolbarZipFilesLabel),
                control: control
            )
        case Self.viewModeIdentifier:
            guard let control = makeSegmentedControl(
                items: [
                    ("square.grid.2x2", ToolbarShortcutText.text(.toolbarThumbnails)),
                    ("list.bullet", ToolbarShortcutText.text(.toolbarList)),
                ],
                trackingMode: .selectOne,
                action: #selector(viewModeSelected(_:))
            ) else {
                return nil
            }
            return makeGroupItem(
                identifier: itemIdentifier,
                label: l10n.text(.toolbarViewMode),
                control: control
            )
        case Self.thumbnailSizeIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = l10n.text(.toolbarThumbnailSizeLabel)
            item.paletteLabel = item.label
            item.toolTip = ToolbarShortcutText.text(.toolbarThumbnailSize)
            item.view = makeSizeSlider()
            item.autovalidates = false
            return item
        default:
            return nil
        }
    }
}

extension MainToolbarController: NSToolbarItemValidation {
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.historyIdentifier:
            applyHistoryAvailability(to: item)
            return panes.paneCommands.canNavigateHistory
                && (panes.historyNavigator.canGoBack || panes.historyNavigator.canGoForward)
        case Self.paneLayoutIdentifier:
            let enabled = panes.paneCommands.canChangeLayout
            (item.view as? NSSegmentedControl)?.isEnabled = enabled
            return enabled
        case Self.slideshowIdentifier:
            let enabled = panes.canStartSlideshow
            (item.view as? NSButton)?.isEnabled = enabled
            return enabled
        case Self.previewZoomIdentifier:
            applyZoomAvailability(to: item)
            return panes.zoomAvailability.isAvailable
        case Self.zipVisibilityIdentifier:
            let enabled = !fileList.isEditingText
            (item.view as? NSSegmentedControl)?.isEnabled = enabled
            return enabled
        default:
            return true
        }
    }
}
