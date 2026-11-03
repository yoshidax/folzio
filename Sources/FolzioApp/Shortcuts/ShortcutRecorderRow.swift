import AppKit
import FolzioCore
import FolzioLocalization

/// A button that captures the next key press while it is recording (FR-258).
///
/// The window offers a key press to its view hierarchy before the main menu, so returning true from
/// `performKeyEquivalent` keeps the menu from running the command that already uses the key (EC-178).
final class ShortcutRecordButton: NSButton {
    var isRecording = false
    var onCapture: ((KeyCombination) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        return handle(event)
    }

    override func keyDown(with event: NSEvent) {
        if isRecording {
            _ = handle(event)
        } else {
            super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { onCancel?() }
        return super.resignFirstResponder()
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = MenuShortcutApplier.modifiers(from: event.modifierFlags)
        // Esc without modifiers cancels. It is never a candidate.
        if event.keyCode == 53, modifiers.isEmpty {
            onCancel?()
            return true
        }
        if event.isARepeat { return true }
        // Keys without a menu key equivalent (function keys, dead keys) are ignored while recording continues.
        guard let characters = event.charactersIgnoringModifiers,
              let combination = KeyCombination.normalized(key: characters, modifiers: modifiers) else {
            return true
        }
        onCapture?(combination)
        return true
    }
}

/// A row button that accepts Tab focus regardless of the system Keyboard Navigation setting.
private final class ShortcutRowButton: NSButton {
    override var canBecomeKeyView: Bool { true }
}

/// One command's row in the Shortcuts tab: its name, current key, state, and the Record and Reset buttons.
@MainActor
final class ShortcutRecorderRow: NSView {
    let command: ShortcutCommandID
    let recordButton = ShortcutRecordButton()
    let clearButton: NSButton = ShortcutRowButton()
    let resetButton: NSButton = ShortcutRowButton()

    private let nameLabel = NSTextField(wrappingLabelWithString: "")
    private let keyLabel = NSTextField(labelWithString: "")
    private let changedLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private var keyText = ""
    private var isChanged = false
    private(set) var isRecording = false

    private static let nameColumnWidth: CGFloat = 160
    private static let keyColumnWidth: CGFloat = 110

    var onRecordTapped: ((ShortcutCommandID) -> Void)?
    var onClearTapped: ((ShortcutCommandID) -> Void)?
    var onResetTapped: ((ShortcutCommandID) -> Void)?

    init(command: ShortcutCommandID) {
        self.command = command
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // Every column has a fixed width, so the columns line up in every row whatever the text length or language.
        // A long command name wraps to a second line instead of pushing the other columns (FR-257).
        nameLabel.lineBreakMode = .byWordWrapping
        nameLabel.maximumNumberOfLines = 2
        nameLabel.preferredMaxLayoutWidth = Self.nameColumnWidth
        nameLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        keyLabel.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        keyLabel.alignment = .left
        keyLabel.lineBreakMode = .byTruncatingTail
        keyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        changedLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        changedLabel.textColor = .secondaryLabelColor
        changedLabel.setAccessibilityElement(false)

        for button in [recordButton, clearButton, resetButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
        }
        recordButton.action = #selector(recordTapped(_:))
        clearButton.action = #selector(clearTapped(_:))
        resetButton.action = #selector(resetTapped(_:))

        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.setAccessibilityElement(false)

        // The state ("Changed") sits under the key, so that the row stays within the list's width in every language.
        let keyColumn = NSStackView(views: [keyLabel, changedLabel])
        keyColumn.orientation = .vertical
        keyColumn.alignment = .leading
        keyColumn.spacing = 0
        let line = NSStackView(views: [nameLabel, keyColumn, recordButton, clearButton, resetButton])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        let column = NSStackView(views: [line, errorLabel])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.widthAnchor.constraint(equalTo: column.widthAnchor),
            errorLabel.widthAnchor.constraint(equalTo: column.widthAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: Self.nameColumnWidth),
            keyColumn.widthAnchor.constraint(equalToConstant: Self.keyColumnWidth),
            keyLabel.widthAnchor.constraint(equalTo: keyColumn.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the command name, its current key, and whether it differs from the default.
    func update(name: String, keyText: String, isChanged: Bool, canClear: Bool, canReset: Bool) {
        self.keyText = keyText
        self.isChanged = isChanged
        nameLabel.stringValue = name
        changedLabel.stringValue = isChanged ? l10n.text(.settingsShortcutsChanged) : ""
        changedLabel.isHidden = !isChanged
        recordButton.title = l10n.text(.settingsShortcutsRecord)
        clearButton.title = l10n.text(.settingsShortcutsClear)
        resetButton.title = l10n.text(.settingsShortcutsReset)
        clearButton.isEnabled = canClear && !isRecording
        resetButton.isEnabled = canReset && !isRecording
        recordButton.setAccessibilityLabel(l10n.text(.settingsShortcutsRecordFor, .text(name)))
        clearButton.setAccessibilityLabel(l10n.text(.settingsShortcutsClearFor, .text(name)))
        resetButton.setAccessibilityLabel(l10n.text(.settingsShortcutsResetFor, .text(name)))
        renderKey(name: name)
    }

    private func renderKey(name: String) {
        keyLabel.stringValue = isRecording ? l10n.text(.settingsShortcutsRecording) : keyText
        // Read the name, the key, and the state as one unit; the state is not conveyed by color alone (FR-265).
        let state = isChanged ? l10n.text(.settingsShortcutsChanged) : ""
        keyLabel.setAccessibilityLabel([name, state].filter { !$0.isEmpty }.joined(separator: ", "))
        keyLabel.setAccessibilityValue(keyLabel.stringValue)
    }

    func beginRecording() {
        isRecording = true
        recordButton.isRecording = true
        clearButton.isEnabled = false
        resetButton.isEnabled = false
        showError(nil)
        renderKey(name: nameLabel.stringValue)
    }

    func endRecording() {
        isRecording = false
        recordButton.isRecording = false
        showError(nil)
        renderKey(name: nameLabel.stringValue)
    }

    /// Enables or disables the Record button, so that only one row records at a time.
    func setRecordEnabled(_ enabled: Bool) {
        recordButton.isEnabled = enabled
    }

    /// Shows the reason a key was refused, and announces it, or hides it when `message` is nil.
    func showError(_ message: String?) {
        guard let message else {
            errorLabel.isHidden = true
            errorLabel.stringValue = ""
            return
        }
        errorLabel.stringValue = "⚠︎ " + message
        errorLabel.isHidden = false
        let element: Any
        if let window { element = window } else { element = self }
        NSAccessibility.post(
            element: element,
            notification: .announcementRequested,
            userInfo: [
                .announcement: nameLabel.stringValue + ". " + message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    @objc private func recordTapped(_ sender: Any?) {
        onRecordTapped?(command)
    }

    @objc private func clearTapped(_ sender: Any?) {
        onClearTapped?(command)
    }

    @objc private func resetTapped(_ sender: Any?) {
        onResetTapped?(command)
    }
}
