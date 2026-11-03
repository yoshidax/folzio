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
    /// The General tab: the settings that existed before the Shortcuts tab. Its layout is unchanged (FR-255).
    private var generalView = NSView()
    private let shortcutsView = ShortcutSettingsView(frame: .zero)
    private let tabSelector = NSSegmentedControl()
    private let tabHolder = NSView()
    private var currentTab = Tab.general

    private let autoplayCheckbox: NSButton
    private let loopCheckbox: NSButton
    private let confirmFileOperationsCheckbox: NSButton
    private let confirmFileOperationsNote = NSTextField(wrappingLabelWithString: "")
    private let languagePopup = KeyViewPopUpButton(frame: .zero, pullsDown: false)
    private let languageLabel = NSTextField(labelWithString: "")
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
        let confirmFileOperationsCheckbox = WrappingCheckbox(
            checkboxWithTitle: l10n.text(.settingsConfirm),
            target: nil,
            action: nil
        )
        self.autoplayCheckbox = autoplayCheckbox
        self.loopCheckbox = loopCheckbox
        self.confirmFileOperationsCheckbox = confirmFileOperationsCheckbox

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
        languagePopup.nextKeyView = autoplayCheckbox
        autoplayCheckbox.nextKeyView = loopCheckbox
        loopCheckbox.nextKeyView = confirmFileOperationsCheckbox
        confirmFileOperationsCheckbox.nextKeyView = intervalField
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
        confirmFileOperationsCheckbox.target = self
        confirmFileOperationsCheckbox.action = #selector(toggleConfirmFileOperations(_:))
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateLocalizedLabels), name: .displayLanguageDidChange, object: nil
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
    /// The spacing between the confirmation checkbox and its supplementary note (FR-223).
    private static let noteSpacing: CGFloat = 4
    /// The indent used when the checkbox cell reports an unexpected title position.
    private static let fallbackNoteIndent: CGFloat = 20

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

        videoHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        fileOperationsHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        slideshowHeader.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let languageRow = NSStackView(views: [languageLabel, languagePopup])
        languageRow.orientation = .horizontal
        languageRow.alignment = .firstBaseline
        languageRow.spacing = 8

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

        confirmFileOperationsCheckbox.cell?.wraps = true
        confirmFileOperationsCheckbox.cell?.isScrollable = false
        confirmFileOperationsCheckbox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // The note is a dependent description of the checkbox: smaller, secondary, and not interactive (FR-223).
        confirmFileOperationsNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        confirmFileOperationsNote.textColor = .secondaryLabelColor
        confirmFileOperationsNote.isSelectable = false
        confirmFileOperationsNote.isEditable = false
        confirmFileOperationsNote.refusesFirstResponder = true
        confirmFileOperationsNote.setAccessibilityElement(false)
        confirmFileOperationsNote.translatesAutoresizingMaskIntoConstraints = false
        let noteContainer = NSView()
        noteContainer.translatesAutoresizingMaskIntoConstraints = false
        noteContainer.addSubview(confirmFileOperationsNote)

        let stack = NSStackView(views: [
            languageRow,
            videoHeader,
            autoplayCheckbox,
            loopCheckbox,
            fileOperationsHeader,
            confirmFileOperationsCheckbox,
            noteContainer,
            slideshowHeader,
            intervalRow,
            repeatsCheckbox,
            transitionRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Self.itemSpacing
        stack.setCustomSpacing(Self.sectionSpacing, after: languageRow)
        stack.setCustomSpacing(Self.sectionSpacing, after: loopCheckbox)
        stack.setCustomSpacing(Self.noteSpacing, after: confirmFileOperationsCheckbox)
        stack.setCustomSpacing(Self.sectionSpacing, after: noteContainer)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.margin),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.margin),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.margin),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -Self.margin),
            confirmFileOperationsCheckbox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            noteContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            confirmFileOperationsNote.topAnchor.constraint(equalTo: noteContainer.topAnchor),
            confirmFileOperationsNote.bottomAnchor.constraint(equalTo: noteContainer.bottomAnchor),
            confirmFileOperationsNote.leadingAnchor.constraint(
                equalTo: noteContainer.leadingAnchor, constant: noteIndent()
            ),
            confirmFileOperationsNote.trailingAnchor.constraint(equalTo: noteContainer.trailingAnchor),
            intervalField.widthAnchor.constraint(equalToConstant: 80),
        ])
        confirmFileOperationsNote.preferredMaxLayoutWidth =
            Self.contentWidth - Self.margin * 2 - noteIndent()

        return contentView
    }

    /// Returns the x-coordinate where the confirmation checkbox draws its title, so the note lines up with it.
    private func noteIndent() -> CGFloat {
        guard let cell = confirmFileOperationsCheckbox.cell else { return Self.fallbackNoteIndent }
        let size = cell.cellSize
        let indent = cell.titleRect(forBounds: NSRect(origin: .zero, size: size)).minX
        return (14...28).contains(indent) ? indent : Self.fallbackNoteIndent
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
        if let item = languagePopup.itemArray.first(where: {
            $0.representedObject as? String == store.displayLanguage.rawValue
        }) {
            languagePopup.select(item)
        }
        let playback = store.playback
        autoplayCheckbox.state = playback.autoplay ? .on : .off
        loopCheckbox.state = playback.loop ? .on : .off
        confirmFileOperationsCheckbox.state =
            store.confirmation.confirmBeforeFileOperations ? .on : .off
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
        videoHeader.stringValue = l10n.text(.settingsVideo)
        fileOperationsHeader.stringValue = l10n.text(.settingsFileOperations)
        slideshowHeader.stringValue = l10n.text(.settingsSlideshow)
        autoplayCheckbox.title = l10n.text(.settingsAutoplay)
        loopCheckbox.title = l10n.text(.settingsLoop)
        confirmFileOperationsCheckbox.title = l10n.text(.settingsConfirm)
        confirmFileOperationsNote.stringValue = l10n.text(.settingsConfirmNote)
        confirmFileOperationsCheckbox.setAccessibilityHelp(l10n.text(.settingsConfirmNote))
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

    @objc private func toggleConfirmFileOperations(_ sender: NSButton) {
        var confirmation = store.confirmation
        confirmation.confirmBeforeFileOperations = sender.state == .on
        store.confirmation = confirmation
    }
}
