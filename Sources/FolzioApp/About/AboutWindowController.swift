import AppKit
import FolzioCore
import FolzioLocalization

/// A borderless button that looks like a link and is reachable with Tab regardless of the system Keyboard
/// Navigation setting (FR-040, FR-242).
@MainActor
final class AboutLinkButton: NSButton {
    override var canBecomeKeyView: Bool { true }

    /// Whether the focus ring is drawn. It is drawn only when keyboard navigation moved the focus here.
    ///
    /// The link is the only key view, so AppKit gives it the initial focus when the window opens. Showing the ring
    /// then would look like a permanent blue frame around the link (FR-242).
    private(set) var showsFocusRing = false

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            setShowsFocusRing(NSApp?.currentEvent?.type == .keyDown)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { setShowsFocusRing(false) }
        return resigned
    }

    private func setShowsFocusRing(_ shows: Bool) {
        showsFocusRing = shows
        focusRingType = shows ? .exterior : .none
        noteFocusRingMaskChanged()
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// Activates on Return and Enter as well as on Space, which `NSButton` handles itself.
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Shows the app icon, name, version, and repository link in one independent, non-modal window (FR-238...FR-245).
@MainActor
final class AboutWindowController: NSWindowController {
    private let openURL: @MainActor (URL) -> Bool
    private let version: String?
    private let stack = NSStackView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "Folzio")
    private let versionLabel: NSTextField?
    private var languageObserver: LanguageChangeObserver?

    /// The link control. Exposed to tests.
    let linkButton = AboutLinkButton()

    /// The text of the version line, or `nil` when the line is omitted. Exposed to tests.
    var versionText: String? { versionLabel?.stringValue }

    /// - Parameters:
    ///   - version: The display version, or `nil` to omit the version line (FR-241).
    ///   - openURL: Opens a URL in the default web browser. Defaults to `NSWorkspace`; tests inject their own.
    init(version: String?, openURL: (@MainActor (URL) -> Bool)? = nil) {
        self.version = version
        if let openURL {
            self.openURL = openURL
        } else {
            self.openURL = { NSWorkspace.shared.open($0) }
        }
        self.versionLabel = version == nil ? nil : NSTextField(labelWithString: "")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true

        configureContent()
        window.contentView = stack
        refreshLanguage()
        window.center()
        languageObserver = LanguageChangeObserver { [weak self] in self?.refreshLanguage() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Brings the window to the front, keeping its position when it is already on screen.
    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        iconView.image = NSApplication.shared.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityElement(true)
        iconView.setAccessibilityRole(.image)

        nameLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        nameLabel.alignment = .center

        versionLabel?.font = .systemFont(ofSize: 13)
        versionLabel?.textColor = .secondaryLabelColor
        versionLabel?.alignment = .center

        linkButton.isBordered = false
        linkButton.setButtonType(.momentaryChange)
        // The ring appears only after keyboard navigation reaches the link (see AboutLinkButton).
        linkButton.focusRingType = .none
        linkButton.attributedTitle = NSAttributedString(
            string: AboutInfo.repositoryURL.absoluteString,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ]
        )
        linkButton.target = self
        linkButton.action = #selector(openRepository(_:))
        linkButton.setAccessibilityRole(.link)
        linkButton.setAccessibilityLabel(AboutInfo.repositoryURL.absoluteString)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 40, bottom: 28, right: 40)
        stack.addArrangedSubview(iconView)
        stack.setCustomSpacing(12, after: iconView)
        stack.addArrangedSubview(nameLabel)
        if let versionLabel { stack.addArrangedSubview(versionLabel) }
        stack.setCustomSpacing(14, after: versionLabel ?? nameLabel)
        stack.addArrangedSubview(linkButton)

        // The stack already contains these views, so the constraints may be activated.
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 96),
            iconView.heightAnchor.constraint(equalToConstant: 96),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
    }

    private func refreshLanguage() {
        window?.title = l10n.text(.aboutWindow)
        iconView.setAccessibilityLabel(l10n.text(.aboutIcon))
        linkButton.setAccessibilityHelp(l10n.text(.aboutLink))
        if let versionLabel, let version {
            versionLabel.stringValue = l10n.text(.aboutVersion, .text(version))
            versionLabel.setAccessibilityLabel(versionLabel.stringValue)
        }
        fitContent(keepingTop: true)
    }

    /// Sizes the window to its content (the window is not resizable by the user, EC-169).
    private func fitContent(keepingTop: Bool) {
        guard let window else { return }
        stack.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let old = window.frame
        guard abs(old.width - frame.width) > 0.5 || abs(old.height - frame.height) > 0.5 else { return }
        if keepingTop {
            frame.origin = NSPoint(x: old.minX, y: old.maxY - frame.height)
        } else {
            frame.origin = old.origin
        }
        window.setFrame(frame, display: false)
    }

    @objc private func openRepository(_ sender: Any?) {
        // A failure to open is ignored on purpose: no error is shown and the window stays open (EC-166).
        _ = openURL(AboutInfo.repositoryURL)
    }
}
