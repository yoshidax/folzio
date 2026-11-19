import AppKit
import FolzioCore
import FolzioLocalization

/// Accepts Tab focus regardless of the system Keyboard Navigation setting.
private class KeyViewCheckbox: NSButton {
    override var canBecomeKeyView: Bool { true }
}

/// Wraps its title to the current width and reports the height of the wrapped lines as its intrinsic height.
///
/// A plain `NSButton` measures its intrinsic size on a single line, so a wrapped title would be clipped.
private final class WrappingCheckbox: KeyViewCheckbox {
    private var measuredWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        guard let cell, bounds.width > 0 else { return super.intrinsicContentSize }
        // Never shorter than a single-line checkbox; a shorter frame shrinks the box and lets the title overflow.
        let singleLine = cell.cellSize.height
        let wrapped = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: bounds.width, height: 10_000)).height
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(max(singleLine, wrapped)))
    }

    override func layout() {
        super.layout()
        if bounds.width != measuredWidth {
            measuredWidth = bounds.width
            invalidateIntrinsicContentSize()
        }
    }

    override var title: String {
        didSet { invalidateIntrinsicContentSize() }
    }
}

private final class KeyViewPopUpButton: NSPopUpButton {
    override var canBecomeKeyView: Bool { true }
}

/// The Settings window. Control-Tab and Control-Shift-Tab switch tabs without adding a stop to the Tab order of
/// either tab (FR-255).
private final class SettingsWindow: NSWindow {
    /// Called with whether to go forward. Returns whether the key press was used.
    var onSwitchTab: ((Bool) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, event.keyCode == 48, flags == [.control] || flags == [.control, .shift],
           onSwitchTab?(!flags.contains(.shift)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private enum Tab: Int {
        case general
        case shortcuts
    }

    private let store: SettingsStore
    /// Viewing and file-operation settings in the General tab.
    private var generalView = NSView()
    private let shortcutsView = ShortcutSettingsView(frame: .zero)
    private let tabSelector = NSSegmentedControl()
    private let tabHolder = NSView()
    private var currentTab = Tab.general

    private let autoplayCheckbox: NSButton
    private let loopCheckbox: NSButton
    /// One checkbox per operation, in `ConfirmationTarget.allCases` order (FR-223).
    private let confirmationCheckboxes: [ConfirmationTarget: NSButton]
    private let languagePopup = KeyViewPopUpButton(frame: .zero, pullsDown: false)
    private let languageLabel = NSTextField(labelWithString: "")
    private let previewHeader = NSTextField(labelWithString: "")
    private let previewModeLabel = NSTextField(labelWithString: "")
    private let previewModePopup = KeyViewPopUpButton(frame: .zero, pullsDown: false)
    private let favoritesHeader = NSTextField(labelWithString: "")
    private let restoreFavoritesCheckbox = WrappingCheckbox(checkboxWithTitle: "", target: nil, action: nil)
    private let videoHeader = NSTextField(labelWithString: "")
    private let fileOperationsHeader = NSTextField(labelWithString: "")
    private let slideshowHeader = NSTextField(labelWithString: "")
    private let intervalLabel = NSTextField(labelWithString: "")
    private let secondsLabel = NSTextField(labelWithString: "")
    private let transitionLabel = NSTextField(labelWithString: "")
    private let intervalField = NSTextField(string: "3")
    private let transitionPopup = KeyViewPopUpButton(frame: .zero, pullsDown: false)
    private let repeatsCheckbox = KeyViewCheckbox(
        checkboxWithTitle: l10n.text(.settingsRepeat),
        target: nil,
        action: nil
    )

    private var hasShownOnce = false

    init(store: SettingsStore = SettingsStore(defaults: .standard)) {
        self.store = store

        let autoplayCheckbox = KeyViewCheckbox(
            checkboxWithTitle: l10n.text(.settingsAutoplay),
            target: nil,
            action: nil
        )
        let loopCheckbox = KeyViewCheckbox(
            checkboxWithTitle: l10n.text(.settingsLoop),
            target: nil,
            action: nil
        )
        var confirmationCheckboxes: [ConfirmationTarget: NSButton] = [:]
        for target in ConfirmationTarget.allCases {
            confirmationCheckboxes[target] = WrappingCheckbox(
                checkboxWithTitle: l10n.text(Self.titleKey(for: target)),
                target: nil,
                action: nil
            )
        }
        self.autoplayCheckbox = autoplayCheckbox
        self.loopCheckbox = loopCheckbox
        self.confirmationCheckboxes = confirmationCheckboxes

        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.onSwitchTab = { [weak self] forward in
            guard let self, !self.shortcutsView.isRecording else { return false }
            self.select(forward ? .shortcuts : .general)
            return true
        }

        window.title = l10n.text(.settingsWindow)
        window.isReleasedWhenClosed = false
        window.delegate = self
        generalView = makeContentView()
        window.contentView = makeRootView()
        window.autorecalculatesKeyViewLoop = false
        languagePopup.nextKeyView = previewModePopup
        previewModePopup.nextKeyView = restoreFavoritesCheckbox
        restoreFavoritesCheckbox.nextKeyView = autoplayCheckbox
        autoplayCheckbox.nextKeyView = loopCheckbox
        // Loop → each confirmation in the Settings window order → interval (US40-AS4).
        var previousKeyView: NSView = loopCheckbox
        for checkbox in orderedConfirmationCheckboxes {
            previousKeyView.nextKeyView = checkbox
            previousKeyView = checkbox
        }
        previousKeyView.nextKeyView = intervalField
        intervalField.nextKeyView = repeatsCheckbox
        repeatsCheckbox.nextKeyView = transitionPopup
        transitionPopup.nextKeyView = languagePopup
        let shortcutKeyViews = shortcutsView.keyViews
        for (index, view) in shortcutKeyViews.enumerated() {
            view.nextKeyView = shortcutKeyViews[(index + 1) % shortcutKeyViews.count]
        }
        window.initialFirstResponder = languagePopup

        autoplayCheckbox.target = self
        autoplayCheckbox.action = #selector(toggleAutoplay(_:))
        loopCheckbox.target = self
        loopCheckbox.action = #selector(toggleLoop(_:))
        restoreFavoritesCheckbox.target = self
        restoreFavoritesCheckbox.action = #selector(toggleFavoritesRestoration(_:))
        for checkbox in orderedConfirmationCheckboxes {
            checkbox.target = self
            checkbox.action = #selector(toggleConfirmation(_:))
        }
        repeatsCheckbox.target = self
        repeatsCheckbox.action = #selector(toggleRepeats(_:))
        intervalField.delegate = self
        intervalField.setAccessibilityLabel(l10n.text(.settingsIntervalA11y))
        repeatsCheckbox.setAccessibilityLabel(l10n.text(.settingsRepeat))
        for (effect, title) in [(SlideshowTransitionEffect.none, l10n.text(.settingsTransitionNone)),
                                (.crossfade, l10n.text(.settingsTransitionCrossfade)),
                                (.slide, l10n.text(.settingsTransitionSlide)),
                                (.zoom, l10n.text(.settingsTransitionZoom))] {
            transitionPopup.addItem(withTitle: title)
            transitionPopup.lastItem?.representedObject = effect.rawValue
        }
        transitionPopup.target = self
        transitionPopup.action = #selector(selectTransition(_:))
        transitionPopup.setAccessibilityLabel(l10n.text(.settingsTransition))

        languagePopup.addItem(withTitle: l10n.text(.settingsLanguageEnglish))
        languagePopup.lastItem?.representedObject = DisplayLanguageSetting.english.rawValue
        languagePopup.addItem(withTitle: l10n.text(.settingsLanguageJapanese))
        languagePopup.lastItem?.representedObject = DisplayLanguageSetting.japanese.rawValue
        languagePopup.target = self
        languagePopup.action = #selector(selectLanguage(_:))
        for mode in PreviewInteractionMode.allCases {
            previewModePopup.addItem(withTitle: "")
            previewModePopup.lastItem?.representedObject = mode.rawValue
        }
        previewModePopup.target = self
        previewModePopup.action = #selector(selectPreviewMode(_:))
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateLocalizedLabels), name: .displayLanguageDidChange, object: nil
        )
        // "Don't ask again" in a confirmation modal can change a setting while this window is open (EC-261).
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncConfirmationCheckboxes), name: .confirmationOptionsDidChange, object: nil
        )

        updateLocalizedLabels()
        syncFromStore()
    }

    private static let contentWidth: CGFloat = 620
    private static let margin: CGFloat = 20
    /// The spacing between items in a section, and between a heading and its first item (FR-222).
    private static let itemSpacing: CGFloat = 8
    /// The spacing before each section heading. It matches the window margin (FR-222).
    private static let sectionSpacing: CGFloat = 20

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        // The Settings window always opens on the General tab (FR-255).
        select(.general)
        syncFromStore()
        if !hasShownOnce {
            hasShownOnce = true
            window?.center()
        }
        super.showWindow(sender)
    }

    private func makeContentView() -> NSView {
        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 340)
        )

        previewHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        favoritesHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        videoHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        fileOperationsHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        slideshowHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let languageRow = NSStackView(views: [languageLabel, languagePopup])
        languageRow.orientation = .horizontal
        languageRow.alignment = .firstBaseline
        languageRow.spacing = 8

        let previewRow = NSStackView(views: [previewModeLabel, previewModePopup])
        previewRow.orientation = .horizontal
        previewRow.alignment = .firstBaseline
        previewRow.spacing = 8

        let intervalRow = NSStackView(views: [
            intervalLabel,
            intervalField,
            secondsLabel,
        ])
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .firstBaseline
        intervalRow.spacing = 8

        let transitionRow = NSStackView(views: [transitionLabel, transitionPopup])
        transitionRow.orientation = .horizontal
        transitionRow.alignment = .firstBaseline
        transitionRow.spacing = 8

        for checkbox in orderedConfirmationCheckboxes + [restoreFavoritesCheckbox] {
            checkbox.cell?.wraps = true
            checkbox.cell?.isScrollable = false
            checkbox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let stack = NSStackView(views: [
            languageRow,
            previewHeader,
            previewRow,
            favoritesHeader,
            restoreFavoritesCheckbox,
            videoHeader,
            autoplayCheckbox,
            loopCheckbox,
            fileOperationsHeader,
        ] + orderedConfirmationCheckboxes + [
            slideshowHeader,
            intervalRow,
            repeatsCheckbox,
            transitionRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.itemSpacing
        stack.setCustomSpacing(Self.sectionSpacing, after: languageRow)
        stack.setCustomSpacing(Self.sectionSpacing, after: previewRow)
        stack.setCustomSpacing(Self.sectionSpacing, after: restoreFavoritesCheckbox)
        stack.setCustomSpacing(Self.sectionSpacing, after: loopCheckbox)
        // No operation always confirms, so the checkboxes have no supplementary note (FR-223).
        if let last = orderedConfirmationCheckboxes.last {
            stack.setCustomSpacing(Self.sectionSpacing, after: last)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.margin),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.margin),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.margin),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Self.margin),
            intervalField.widthAnchor.constraint(equalToConstant: 80),
        ] + (orderedConfirmationCheckboxes + [restoreFavoritesCheckbox]).map {
            $0.widthAnchor.constraint(equalTo: stack.widthAnchor)
        })

        return contentView
    }

    private static let tabSelectorTopMargin: CGFloat = 12
    private static let tabSelectorBottomMargin: CGFloat = 8

    /// Builds the window's content: a tab selector above the selected tab's view.
    private func makeRootView() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 340))
        tabSelector.segmentCount = 2
        tabSelector.trackingMode = .selectOne
        tabSelector.segmentStyle = .rounded
        tabSelector.target = self
        tabSelector.action = #selector(tabSelectorChanged(_:))
        tabSelector.translatesAutoresizingMaskIntoConstraints = false
        tabHolder.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabSelector)
        root.addSubview(tabHolder)
        generalView.translatesAutoresizingMaskIntoConstraints = false
        // The window's width is fixed, so the General tab lays out at that width as it did before the tabs.
        generalView.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        NSLayoutConstraint.activate([
            tabSelector.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.tabSelectorTopMargin),
            tabSelector.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            tabHolder.topAnchor.constraint(equalTo: tabSelector.bottomAnchor, constant: Self.tabSelectorBottomMargin),
            tabHolder.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabHolder.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabHolder.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        tabHolder.addSubview(generalView)
        pinToHolder(generalView)
        tabSelector.selectedSegment = Tab.general.rawValue
        return root
    }

    private func pinToHolder(_ view: NSView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: tabHolder.topAnchor),
            view.leadingAnchor.constraint(equalTo: tabHolder.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: tabHolder.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: tabHolder.bottomAnchor),
        ])
    }

    @objc private func tabSelectorChanged(_ sender: NSSegmentedControl) {
        select(Tab(rawValue: sender.selectedSegment) ?? .general)
    }

    /// Shows a tab. Recording stops, and an interval being edited is committed first (FR-258).
    private func select(_ tab: Tab) {
        shortcutsView.cancelRecording()
        if tab != currentTab {
            window?.makeFirstResponder(nil)
            let outgoing: NSView = currentTab == .general ? generalView : shortcutsView
            let incoming: NSView = tab == .general ? generalView : shortcutsView
            outgoing.removeFromSuperview()
            tabHolder.addSubview(incoming)
            pinToHolder(incoming)
            currentTab = tab
        }
        tabSelector.selectedSegment = tab.rawValue
        let first: NSView? = tab == .general ? languagePopup : shortcutsView.keyViews.first
        tabSelector.nextKeyView = first
        window?.initialFirstResponder = first
        resizeToFitContent()
    }

    /// Fits the window height to the selected tab and keeps the top edge in place (FR-222).
    private func resizeToFitContent() {
        guard let window else { return }
        let inner: CGFloat
        switch currentTab {
        case .general:
            // The wrapping checkbox updates its height after it learns its width, so lay out twice.
            generalView.layoutSubtreeIfNeeded()
            generalView.layoutSubtreeIfNeeded()
            inner = generalView.fittingSize.height
        case .shortcuts:
            inner = ShortcutSettingsView.contentHeight
        }
        let selectorHeight = ceil(tabSelector.fittingSize.height)
        let height = Self.tabSelectorTopMargin + selectorHeight + Self.tabSelectorBottomMargin + inner
        let contentSize = NSSize(width: Self.contentWidth, height: height)
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        window.setFrame(frame, display: window.isVisible)
    }

    private func syncFromStore() {
        restoreFavoritesCheckbox.state = store.restoresFavoritesExpansion ? .on : .off
        if let item = previewModePopup.itemArray.first(where: {
            $0.representedObject as? String == store.previewInteractionMode.rawValue
        }) { previewModePopup.select(item) }
        if let item = languagePopup.itemArray.first(where: {
            $0.representedObject as? String == store.displayLanguage.rawValue
        }) {
            languagePopup.select(item)
        }
        let playback = store.playback
        autoplayCheckbox.state = playback.autoplay ? .on : .off
        loopCheckbox.state = playback.loop ? .on : .off
        syncConfirmationCheckboxes()
        let slideshow = store.slideshow
        intervalField.stringValue = String(slideshow.intervalSeconds)
        repeatsCheckbox.state = slideshow.repeats ? .on : .off
        if let item = transitionPopup.itemArray.first(where: {
            $0.representedObject as? String == slideshow.transition.rawValue
        }) {
            transitionPopup.select(item)
        }
    }

    @objc private func selectLanguage(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let language = DisplayLanguageSetting(rawValue: raw) else { return }
        LocalizationState.shared.select(language)
    }

    @objc private func updateLocalizedLabels() {
        window?.title = l10n.text(.settingsWindow)
        tabSelector.setLabel(l10n.text(.settingsTabGeneral), forSegment: Tab.general.rawValue)
        tabSelector.setLabel(l10n.text(.settingsTabShortcuts), forSegment: Tab.shortcuts.rawValue)
        tabSelector.setAccessibilityLabel(l10n.text(.settingsWindow))
        languageLabel.stringValue = l10n.text(.settingsLanguage)
        languagePopup.setAccessibilityLabel(l10n.text(.settingsLanguage))
        previewHeader.stringValue = l10n.text(.settingsPreview)
        previewModeLabel.stringValue = l10n.text(.settingsPreviewInteraction)
        previewModePopup.setAccessibilityLabel(l10n.text(.settingsPreviewInteraction))
        previewModePopup.item(at: 0)?.title = l10n.text(.settingsPreviewWheelPan)
        previewModePopup.item(at: 1)?.title = l10n.text(.settingsPreviewScroll)
        favoritesHeader.stringValue = l10n.text(.settingsFavorites)
        restoreFavoritesCheckbox.title = l10n.text(.settingsRestoreFavoritesExpansion)
        restoreFavoritesCheckbox.setAccessibilityLabel(l10n.text(.settingsRestoreFavoritesExpansion))
        videoHeader.stringValue = l10n.text(.settingsVideo)
        fileOperationsHeader.stringValue = l10n.text(.settingsFileOperations)
        slideshowHeader.stringValue = l10n.text(.settingsSlideshow)
        autoplayCheckbox.title = l10n.text(.settingsAutoplay)
        loopCheckbox.title = l10n.text(.settingsLoop)
        for target in ConfirmationTarget.allCases {
            confirmationCheckboxes[target]?.title = l10n.text(Self.titleKey(for: target))
        }
        intervalLabel.stringValue = l10n.text(.settingsInterval)
        secondsLabel.stringValue = l10n.text(.settingsSeconds)
        intervalField.setAccessibilityLabel(l10n.text(.settingsIntervalA11y))
        repeatsCheckbox.title = l10n.text(.settingsRepeat)
        repeatsCheckbox.setAccessibilityLabel(l10n.text(.settingsRepeat))
        transitionLabel.stringValue = l10n.text(.settingsTransition)
        transitionPopup.setAccessibilityLabel(l10n.text(.settingsTransition))
        for (index, key) in [TextKey.settingsTransitionNone, .settingsTransitionCrossfade,
                             .settingsTransitionSlide, .settingsTransitionZoom].enumerated() {
            transitionPopup.item(at: index)?.title = l10n.text(key)
        }
        resizeToFitContent()
    }

    @objc private func toggleFavoritesRestoration(_ sender: NSButton) {
        store.restoresFavoritesExpansion = sender.state == .on
    }

    @objc private func selectPreviewMode(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let mode = PreviewInteractionMode(rawValue: raw) else { return }
        store.previewInteractionMode = mode
        NotificationCenter.default.post(name: .previewInteractionModeDidChange, object: nil)
    }

    @objc private func selectTransition(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let effect = SlideshowTransitionEffect(rawValue: raw) else { return }
        var options = store.slideshow
        options.transition = effect
        store.slideshow = options
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === intervalField else { return }
        if let seconds = SlideshowIntervalInput.parse(intervalField.stringValue) {
            var options = store.slideshow
            options.intervalSeconds = seconds
            store.slideshow = options
        }
        intervalField.stringValue = String(store.slideshow.intervalSeconds)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === intervalField,
              commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        let saved = String(store.slideshow.intervalSeconds)
        intervalField.stringValue = saved
        textView.string = saved
        return true
    }

    func windowWillClose(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    @objc private func toggleRepeats(_ sender: NSButton) {
        var options = store.slideshow
        options.repeats = sender.state == .on
        store.slideshow = options
    }

    @objc private func toggleAutoplay(_ sender: NSButton) {
        var playback = store.playback
        playback.autoplay = sender.state == .on
        store.playback = playback
    }

    @objc private func toggleLoop(_ sender: NSButton) {
        var playback = store.playback
        playback.loop = sender.state == .on
        store.playback = playback
    }

    @objc private func toggleConfirmation(_ sender: NSButton) {
        guard let target = confirmationCheckboxes.first(where: { $0.value === sender })?.key else { return }
        var confirmation = store.confirmation
        confirmation.setEnabled(sender.state == .on, for: target)
        store.confirmation = confirmation
    }

    @objc private func syncConfirmationCheckboxes() {
        let confirmation = store.confirmation
        for target in ConfirmationTarget.allCases {
            confirmationCheckboxes[target]?.state = confirmation.isEnabled(target) ? .on : .off
        }
    }

    private var orderedConfirmationCheckboxes: [NSButton] {
        ConfirmationTarget.allCases.compactMap { confirmationCheckboxes[$0] }
    }

    private static func titleKey(for target: ConfirmationTarget) -> TextKey {
        switch target {
        case .copy: .settingsConfirmCopy
        case .move: .settingsConfirmMove
        case .rename: .settingsConfirmRename
        case .removeFavorite: .settingsConfirmRemoveFavorite
        case .trash: .settingsConfirmTrash
        }
    }
}
