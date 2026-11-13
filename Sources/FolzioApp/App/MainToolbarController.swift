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
    private static let nameFilterIdentifier = NSToolbarItem.Identifier(ToolbarLayout.nameFilterIdentifier)
    /// Width of the name filter field (A-231).
    private static let nameFilterFieldWidth: CGFloat = 180

    let toolbar = NSToolbar(identifier: "MainToolbar")

    private let fileList: FileListViewController
    private let panes: MainSplitViewController
    private let settings: SettingsStore
    private var visibilityObservation: NSKeyValueObservation?
    private var editingObservers: [NSObjectProtocol] = []
    private var configurationObservations: [NSKeyValueObservation] = []
    private var assignmentObserver: ShortcutAssignmentObserver?
    private var terminationObserver: NSObjectProtocol?
    private var displayModeObservation: NSKeyValueObservation?

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

        fileList.onNameFilterChange = { [weak self] text in
            self?.apply(nameFilterText: text)
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
        panes.onSearchAvailabilityChange = { [weak self] in
            self?.applyNameFilterAvailability()
        }
        panes.canFocusNameFilter = { [weak self] in
            self?.canFocusNameFilter ?? false
        }
        panes.focusNameFilter = { [weak self] in
            self?.focusNameFilter()
        }
        // Text only shows no field, so the name filter would act without anything showing it (FR-393, A-226).
        displayModeObservation = toolbar.observe(\.displayMode, options: [.new]) { [weak self] _, change in
            guard change.newValue == .labelOnly else { return }
            MainActor.assumeIsolated { self?.clearNameFilter() }
        }
        observeEditingAvailability()
        observeSheetAvailability()
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
            item.menuFormRepresentation?.title = item.label
            applySlideshowState(to: item)
        }
        for item in items(for: Self.nameFilterIdentifier) {
            applyNameFilterTexts(to: item)
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
            applySlideshowState(to: item)
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
        case Self.nameFilterIdentifier:
            // A field that enters the toolbar shows the current filter (EC-254: empty after being added again).
            if let field = item.view as? NSSearchField, field.stringValue != fileList.currentNameFilterText {
                field.stringValue = fileList.currentNameFilterText
            }
            applyNameFilterAvailability(to: item)
        default:
            break
        }
    }

    private func updateSlideshowAvailability() {
        for item in items(for: Self.slideshowIdentifier) {
            applySlideshowState(to: item)
        }
        applyHistoryAvailability()
        applyNameFilterAvailability()
        toolbar.validateVisibleItems()
    }

    /// Applies on/off, availability, and the tooltip of the Slideshow toggle button (FR-350 to FR-353). The
    /// accessibility label stays the item name in both states, and the toggle value tells whether a slideshow is
    /// running (A-211). Both the item and the button are enabled or disabled, because the text display mode uses
    /// the item.
    private func applySlideshowState(to item: NSToolbarItem) {
        let state = panes.slideshowToggleState
        let help = state.isOn
            ? l10n.text(.toolbarStopSlideshowHelp)
            : ToolbarShortcutText.text(.toolbarStartSlideshowHelp)
        item.isEnabled = state.isEnabled
        item.toolTip = help
        item.menuFormRepresentation?.state = state.isOn ? .on : .off
        guard let button = item.view as? NSButton else { return }
        button.isEnabled = state.isEnabled
        button.state = state.isOn ? .on : .off
        button.toolTip = help
        button.setAccessibilityLabel(l10n.text(.toolbarSlideshowLabel))
        button.setAccessibilityHelp(help)
    }

    /// The Slideshow toggle button, its overflow menu item, and the text display mode (FR-351, EC-240). A push on/off
    /// button flips its own state before sending the action, so the state is reapplied from the slideshow afterward,
    /// including when the press did nothing.
    @objc private func slideshowToggled(_ sender: Any?) {
        panes.toggleSlideshow(sender)
        updateSlideshowAvailability()
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

    /// Updates the Slideshow button when a sheet opens or closes, because the button is unavailable while the main
    /// window has a sheet during a slideshow (FR-352). The update waits one turn, because the sheet may not be attached
    /// yet when `willBeginSheetNotification` is posted. Sheets on other windows also update the button, which is
    /// harmless because the state is read from the main window.
    private func observeSheetAvailability() {
        for name in [NSWindow.willBeginSheetNotification, NSWindow.didEndSheetNotification] {
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
        applyNameFilterAvailability()
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
        // Hiding the toolbar hides the field, so the filter would act without anything showing it (FR-393, A-226).
        // Full screen hides the toolbar through the presentation options and does not change `isVisible` (EC-258).
        if !isVisible {
            clearNameFilter()
        }

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

    // MARK: - Name filter field (TAK-86)

    /// Shows the filter's text in every field in the toolbar, such as after a new location cleared it (FR-384). A field
    /// that already shows the text is left alone, so typing keeps the caret and trailing spaces. A field whose input
    /// method is still composing text is also left alone, because this runs one turn after the change and the
    /// composition may have started in between (FR-389).
    private func apply(nameFilterText text: String) {
        for item in items(for: Self.nameFilterIdentifier) {
            guard let field = item.view as? NSSearchField, field.stringValue != text else { continue }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { continue }
            field.stringValue = text
        }
    }

    /// Enables the field only when the search sheet can open (FR-388). Disabling keeps the text and the filter.
    private func applyNameFilterAvailability() {
        for item in items(for: Self.nameFilterIdentifier) {
            applyNameFilterAvailability(to: item)
        }
    }

    private func applyNameFilterAvailability(to item: NSToolbarItem) {
        let enabled = panes.paneCommands.canSearch
        item.isEnabled = enabled
        (item.view as? NSSearchField)?.isEnabled = enabled
    }

    private func clearNameFilter() {
        guard !fileList.currentNameFilterText.isEmpty else { return }
        fileList.applyNameFilter("")
    }

    /// Whether ⌘F can move the focus into the field: the field is in the toolbar, the toolbar does not show text only,
    /// and the field is not moved into the overflow menu of a narrow window (FR-391). A hidden toolbar is shown first,
    /// so it does not count here. An overflowed field has no window, and focusing it would silently do nothing.
    private var canFocusNameFilter: Bool {
        guard toolbar.displayMode != .labelOnly,
              let field = items(for: Self.nameFilterIdentifier).first?.view else { return false }
        return !toolbar.isVisible || field.window != nil
    }

    /// Shows the toolbar if needed, then puts the keyboard focus in the field and selects its text (FR-391).
    private func focusNameFilter() {
        guard canFocusNameFilter else { return }
        guard !toolbar.isVisible else {
            focusNameFilterField()
            return
        }
        toolbar.isVisible = true
        // The field gets its window once the shown toolbar is laid out.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.focusNameFilterField() }
        }
    }

    private func focusNameFilterField() {
        guard let field = items(for: Self.nameFilterIdentifier).first?.view as? NSSearchField,
              let window = field.window,
              window.makeFirstResponder(field) else { return }
        field.currentEditor()?.selectAll(nil)
    }

    /// The magnifying glass, ⌥⌘F while the field has the focus, and the overflow and text-only item. Opens the search
    /// sheet with the field's text as the keyword (FR-390, FR-392).
    @objc func showSearch(_ sender: Any?) {
        panes.showSearch(carrying: fileList.currentNameFilterText)
    }

    /// The field's action, sent as the user types and when the clear button or Esc empties it (FR-381, FR-383).
    @objc private func nameFilterFieldChanged(_ sender: NSSearchField) {
        updateNameFilter(from: sender)
    }

    /// Filters by the field's text. Text that is still being composed by an input method does not filter until it is
    /// committed (FR-389). Fields in the customization palette are ignored (EC-256).
    private func updateNameFilter(from field: NSSearchField) {
        guard items(for: Self.nameFilterIdentifier).contains(where: { $0.view === field }) else { return }
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        fileList.applyNameFilter(field.stringValue)
    }

    private func makeNameFilterItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let field = ToolbarSearchField(width: Self.nameFilterFieldWidth)
        field.delegate = self
        field.target = self
        field.action = #selector(nameFilterFieldChanged(_:))
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        // The field forwards a click on the magnifying glass and ⌥⌘F to `showSearch(_:)` (FR-390).
        field.findCommandTarget = self

        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = field
        let menuItem = NSMenuItem(title: "", action: #selector(showSearch(_:)), keyEquivalent: "")
        menuItem.target = self
        item.menuFormRepresentation = menuItem
        applyNameFilterTexts(to: item)
        return item
    }

    /// Applies the label, placeholder, tooltips, and accessibility texts in the current language and keys (FR-392,
    /// EC-255). Does not change the typed text.
    private func applyNameFilterTexts(to item: NSToolbarItem) {
        let label = l10n.text(.toolbarNameFilterLabel)
        let placeholder = l10n.text(.toolbarNameFilterPlaceholder)
        let fieldHelp = ToolbarShortcutText.text(.toolbarNameFilterHelp)
        let findHelp = ToolbarShortcutText.text(.toolbarNameFilterFindHelp)
        item.label = label
        item.paletteLabel = label
        item.menuFormRepresentation?.title = label
        guard let field = item.view as? ToolbarSearchField else { return }
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        field.setAccessibilityHelp(fieldHelp)
        field.fieldToolTip = fieldHelp
        field.searchButtonToolTip = findHelp
        field.setFindAccessibilityAction(name: findHelp)
        if let button = (field.cell as? NSSearchFieldCell)?.searchButtonCell {
            button.setAccessibilityLabel(findHelp)
        }
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
    /// The default order comes from `ToolbarLayout`, which also decides whether a configuration equals the default and
    /// need not be saved (FR-233, FR-235).
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ToolbarLayout.defaultOrder.map { NSToolbarItem.Identifier($0) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        (ToolbarLayout.setIdentifiers + [ToolbarLayout.spaceIdentifier, ToolbarLayout.flexibleSpaceIdentifier])
            .map { NSToolbarItem.Identifier($0) }
    }

    /// Applies the current state to an item as it enters the toolbar. At this point the item is not yet in
    /// `toolbar.items`, so the state is applied to the item in the notification.
    func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem else { return }
        applyState(to: item)
    }

    /// Removing the name filter field clears the filter, because nothing would show it (FR-393, A-226). The check
    /// waits one turn, so moving the field within the toolbar, which may remove and add it, keeps the filter.
    func toolbarDidRemoveItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem,
              item.itemIdentifier == Self.nameFilterIdentifier else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.items(for: Self.nameFilterIdentifier).isEmpty else { return }
                self.clearNameFilter()
            }
        }
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
                target: self,
                action: #selector(slideshowToggled(_:))
            )
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .texturedRounded
            button.controlSize = .regular
            button.isBordered = true
            button.imagePosition = .imageOnly
            button.toolTip = ToolbarShortcutText.text(.toolbarStartSlideshowHelp)
            button.setAccessibilityLabel(l10n.text(.toolbarSlideshowLabel))
            button.setAccessibilityHelp(ToolbarShortcutText.text(.toolbarStartSlideshowHelp))

            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = l10n.text(.toolbarSlideshowLabel)
            item.paletteLabel = l10n.text(.toolbarSlideshowLabel)
            item.toolTip = ToolbarShortcutText.text(.toolbarStartSlideshowHelp)
            item.view = button
            item.target = self
            item.action = #selector(slideshowToggled(_:))
            // The overflow menu keeps the item name and shows a checkmark while running (EC-240). `validateMenuItem`
            // applies the state and availability.
            let menuItem = NSMenuItem(
                title: l10n.text(.toolbarSlideshowLabel),
                action: #selector(slideshowToggled(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            item.menuFormRepresentation = menuItem
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
        case Self.nameFilterIdentifier:
            return makeNameFilterItem(identifier: itemIdentifier)
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
            applySlideshowState(to: item)
            return panes.slideshowToggleState.isEnabled
        case Self.previewZoomIdentifier:
            applyZoomAvailability(to: item)
            return panes.zoomAvailability.isAvailable
        case Self.zipVisibilityIdentifier:
            let enabled = !fileList.isEditingText
            (item.view as? NSSegmentedControl)?.isEnabled = enabled
            return enabled
        case Self.nameFilterIdentifier:
            applyNameFilterAvailability(to: item)
            return panes.paneCommands.canSearch
        default:
            return true
        }
    }
}

extension MainToolbarController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? ToolbarSearchField else { return }
        updateNameFilter(from: field)
    }

    /// Return keeps the filter and moves the focus to the file list (FR-389). While an input method composes text,
    /// Return commits the text and does not reach here. Esc is left to the field, which clears the text (FR-383).
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard let field = control as? ToolbarSearchField,
              commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        updateNameFilter(from: field)
        panes.focusFileListForNameFilter()
        return true
    }
}

extension MainToolbarController: NSMenuItemValidation {
    /// The overflow menu item of the Slideshow toggle button (EC-240), and the items that open the search sheet from the
    /// name filter field (FR-388).
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showSearch(_:)) {
            // ⌥⌘F while the name filter field has the focus, and the field's overflow and text-only item (FR-388).
            return panes.paneCommands.canSearch
        }
        guard menuItem.action == #selector(slideshowToggled(_:)) else { return true }
        let state = panes.slideshowToggleState
        menuItem.state = state.isOn ? .on : .off
        return state.isEnabled
    }
}
