import AppKit
import FolzioCore
import FolzioLocalization

/// Accepts Tab focus regardless of the system Keyboard Navigation setting.
private final class KeyViewCheckbox: NSButton {
    override var canBecomeKeyView: Bool { true }
}

private final class KeyViewPopUpButton: NSPopUpButton {
    override var canBecomeKeyView: Bool { true }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate {
    private let store: SettingsStore

    private let autoplayCheckbox: NSButton
    private let loopCheckbox: NSButton
    private let confirmFileOperationsCheckbox: NSButton
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
        let confirmFileOperationsCheckbox = KeyViewCheckbox(
            checkboxWithTitle: l10n.text(.settingsConfirm),
            target: nil,
            action: nil
        )
        self.autoplayCheckbox = autoplayCheckbox
        self.loopCheckbox = loopCheckbox
        self.confirmFileOperationsCheckbox = confirmFileOperationsCheckbox

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = l10n.text(.settingsWindow)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let contentView = makeContentView()
        window.contentView = contentView
        contentView.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 620, height: max(320, contentView.fittingSize.height)))
        window.autorecalculatesKeyViewLoop = false
        languagePopup.nextKeyView = autoplayCheckbox
        autoplayCheckbox.nextKeyView = loopCheckbox
        loopCheckbox.nextKeyView = confirmFileOperationsCheckbox
        confirmFileOperationsCheckbox.nextKeyView = intervalField
        intervalField.nextKeyView = repeatsCheckbox
        repeatsCheckbox.nextKeyView = transitionPopup
        transitionPopup.nextKeyView = languagePopup
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

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func showWindow(_ sender: Any?) {
        syncFromStore()
        if !hasShownOnce {
            hasShownOnce = true
            window?.center()
        }
        super.showWindow(sender)
    }

    private func makeContentView() -> NSView {
        let contentView = NSView(
            frame: NSRect(x: 0, y: 0, width: 620, height: 340)
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

        let stack = NSStackView(views: [
            languageRow,
            videoHeader,
            autoplayCheckbox,
            loopCheckbox,
            fileOperationsHeader,
            confirmFileOperationsCheckbox,
            slideshowHeader,
            intervalRow,
            repeatsCheckbox,
            transitionRow,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            confirmFileOperationsCheckbox.widthAnchor.constraint(equalTo: stack.widthAnchor),
            confirmFileOperationsCheckbox.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            intervalField.widthAnchor.constraint(equalToConstant: 80),
        ])

        return contentView
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
        languageLabel.stringValue = l10n.text(.settingsLanguage)
        languagePopup.setAccessibilityLabel(l10n.text(.settingsLanguage))
        videoHeader.stringValue = l10n.text(.settingsVideo)
        fileOperationsHeader.stringValue = l10n.text(.settingsFileOperations)
        slideshowHeader.stringValue = l10n.text(.settingsSlideshow)
        autoplayCheckbox.title = l10n.text(.settingsAutoplay)
        loopCheckbox.title = l10n.text(.settingsLoop)
        confirmFileOperationsCheckbox.title = l10n.text(.settingsConfirm)
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
        window?.contentView?.layoutSubtreeIfNeeded()
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
