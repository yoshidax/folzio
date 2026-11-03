import AppKit
import FolzioCore
import FolzioLocalization

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class ResetAllButton: NSButton {
    override var canBecomeKeyView: Bool { true }
}

/// The Shortcuts tab of the Settings window: every customizable command with its current key (FR-255, FR-257).
@MainActor
final class ShortcutSettingsView: NSView {
    /// The height of the tab's content. The list scrolls inside it.
    static let contentHeight: CGFloat = 460

    private let store = ShortcutAssignmentStore.shared
    private let scrollView = NSScrollView()
    private let listStack = NSStackView()
    private let resetAllButton: NSButton = ResetAllButton()
    private var rows: [ShortcutRecorderRow] = []
    private var headings: [ShortcutSection: NSTextField] = [:]
    private var recordingCommand: ShortcutCommandID?
    private var languageObserver: LanguageChangeObserver?
    private var assignmentObserver: ShortcutAssignmentObserver?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        buildList()
        buildLayout()
        refreshLocalized()
        languageObserver = LanguageChangeObserver { [weak self] in
            self?.cancelRecording()
            self?.refreshLocalized()
        }
        assignmentObserver = ShortcutAssignmentObserver { [weak self] in self?.refreshRows() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// The controls in Tab order: each row's Record, Clear, and Reset buttons, then Reset All (FR-265).
    var keyViews: [NSView] {
        rows.flatMap { [$0.recordButton, $0.clearButton, $0.resetButton] } + [resetAllButton]
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        if let window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window
            )
        }
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        cancelRecording()
    }

    // MARK: - Building

    private func buildList() {
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.translatesAutoresizingMaskIntoConstraints = false
        for section in ShortcutSection.allCases {
            let commands = ShortcutCommands.all.filter { $0.section == section }
            guard !commands.isEmpty else { continue }
            let heading = NSTextField(labelWithString: "")
            heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            headings[section] = heading
            if !listStack.arrangedSubviews.isEmpty {
                listStack.setCustomSpacing(20, after: listStack.arrangedSubviews.last!)
            }
            listStack.addArrangedSubview(heading)
            for command in commands {
                let row = ShortcutRecorderRow(command: command.id)
                row.onRecordTapped = { [weak self] id in self?.recordTapped(id) }
                row.onClearTapped = { [weak self] id in self?.clearTapped(id) }
                row.onResetTapped = { [weak self] id in self?.resetTapped(id) }
                row.recordButton.onCapture = { [weak self, id = command.id] combination in
                    self?.captured(combination, for: id)
                }
                row.recordButton.onCancel = { [weak self] in self?.cancelRecording() }
                rows.append(row)
                listStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: listStack.widthAnchor).isActive = true
            }
        }
    }

    private func buildLayout() {
        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(listStack)
        let margin: CGFloat = 20
        NSLayoutConstraint.activate([
            listStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            listStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: margin),
            listStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -margin),
            listStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
        ])
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        addSubview(scrollView)

        resetAllButton.bezelStyle = .rounded
        resetAllButton.target = self
        resetAllButton.action = #selector(resetAllTapped(_:))
        resetAllButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(resetAllButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            resetAllButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            resetAllButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
            resetAllButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            heightAnchor.constraint(equalToConstant: Self.contentHeight),
        ])
    }

    // MARK: - Text and state

    private func refreshLocalized() {
        scrollView.setAccessibilityLabel(l10n.text(.settingsShortcutsList))
        for (section, heading) in headings {
            heading.stringValue = l10n.text(ShortcutText.heading(section))
            heading.setAccessibilityLabel(heading.stringValue)
        }
        resetAllButton.title = l10n.text(.settingsShortcutsResetAll)
        refreshRows()
    }

    private func refreshRows() {
        let assignments = store.assignments
        for row in rows {
            row.update(
                name: l10n.text(ShortcutText.commandName(row.command)),
                keyText: assignments.combination(for: row.command)?.displayText ?? l10n.text(.settingsShortcutsUnset),
                isChanged: assignments.isOverridden(row.command),
                canClear: !assignments.isUnset(row.command),
                canReset: assignments.isOverridden(row.command)
            )
        }
        resetAllButton.isEnabled = !assignments.overrides.isEmpty && recordingCommand == nil
    }

    private func message(for error: ShortcutAssignmentError) -> String {
        switch error {
        case .missingModifier:
            return l10n.text(.settingsShortcutsErrorModifier)
        case .reserved, .fixed:
            return l10n.text(.settingsShortcutsErrorFixed)
        case let .conflict(other):
            return l10n.text(.settingsShortcutsErrorConflict, .text(l10n.text(ShortcutText.commandName(other))))
        }
    }

    // MARK: - Recording

    private func row(for command: ShortcutCommandID) -> ShortcutRecorderRow? {
        rows.first { $0.command == command }
    }

    private func recordTapped(_ command: ShortcutCommandID) {
        // Pressing Record again on the row that is recording cancels it.
        if recordingCommand == command {
            cancelRecording()
            return
        }
        cancelRecording()
        guard let target = row(for: command) else { return }
        recordingCommand = command
        for row in rows { row.setRecordEnabled(row.command == command) }
        target.beginRecording()
        resetAllButton.isEnabled = false
        window?.makeFirstResponder(target.recordButton)
    }

    private func captured(_ combination: KeyCombination, for command: ShortcutCommandID) {
        guard recordingCommand == command, let target = row(for: command) else { return }
        if let error = store.assign(combination, to: command) {
            // Stay in recording so that the next key can be tried (FR-258, FR-260).
            target.showError(message(for: error))
            return
        }
        endRecording(target)
    }

    /// Whether a shortcut is being recorded now.
    var isRecording: Bool { recordingCommand != nil }

    /// Stops recording without changing any assignment.
    func cancelRecording() {
        guard let command = recordingCommand, let target = row(for: command) else {
            recordingCommand = nil
            return
        }
        endRecording(target)
    }

    private func endRecording(_ target: ShortcutRecorderRow) {
        recordingCommand = nil
        target.endRecording()
        for row in rows { row.setRecordEnabled(true) }
        refreshRows()
    }

    private func clearTapped(_ command: ShortcutCommandID) {
        cancelRecording()
        row(for: command)?.showError(nil)
        store.unset(command)
    }

    private func resetTapped(_ command: ShortcutCommandID) {
        cancelRecording()
        guard let target = row(for: command) else { return }
        if let error = store.reset(command) {
            if case let .conflict(other) = error {
                target.showError(
                    l10n.text(.settingsShortcutsErrorDefaultConflict, .text(l10n.text(ShortcutText.commandName(other))))
                )
            }
            return
        }
        target.showError(nil)
    }

    @objc private func resetAllTapped(_ sender: Any?) {
        cancelRecording()
        store.resetAll()
        for row in rows { row.showError(nil) }
    }
}
