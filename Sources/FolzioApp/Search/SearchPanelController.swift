import AppKit
import FolzioCore
import FolzioLocalization

/// Search modal (a sheet on the main window). Accepts a keyword and one to ten search root rows, validates and
/// organizes the roots, then calls `onSearch` (FR-080–082, FR-435–437). Each row's "Choose…" opens a standard
/// `NSOpenPanel` as a child sheet and revalidates asynchronously after confirmation (FR-141–144).
@MainActor
final class SearchPanelController: NSViewController, NSSearchFieldDelegate {
    /// Reason shown below the rows. A row reason is rendered with the current row count, so it can drop or change
    /// its row number when rows are added or removed (FR-435, FR-436).
    private enum Reason {
        case general(@MainActor () -> String)
        case row(Int, SearchRootError)
    }

    private let initialKeyword: String?
    private let initialRootPath: String
    private let onSearch: (SearchPattern, [URL]) -> Void

    private let headingLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    let keywordField = NSSearchField()
    let wildcardLabel = NSTextField(wrappingLabelWithString: "")
    private let keywordLabel = NSTextField(labelWithString: "")
    private let rootLabel = NSTextField(labelWithString: "")
    private let rowsStack = NSStackView()
    private(set) var rows: [SearchRootRowView] = []
    let addRootButton = SearchKeyViewButton()
    private let reasonLabel = NSTextField(labelWithString: "")
    let cancelButton = SearchKeyViewButton()
    private let searchButton = SearchKeyViewButton()

    private var inputState: SearchPanelInputState
    private var initialLocationTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var folderPanel: NSOpenPanel?
    private var panelPresented = false
    private var initialFocusApplied = false
    private var reason: Reason?

    init(keyword: String?, rootPath: String, onSearch: @escaping (SearchPattern, [URL]) -> Void) {
        initialKeyword = keyword
        initialRootPath = rootPath
        self.onSearch = onSearch
        inputState = SearchPanelInputState(rootInput: .typed(rootPath), keyword: keyword ?? "")
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let container = NSView()

        // The heading and its description tell this search from the toolbar name filter: it looks through the
        // subfolders of the search roots (FR-394). They match the Settings window's section headings and notes
        // (FR-223): a bold heading, and a smaller, secondary note that is not interactive.
        headingLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        configureNote(descriptionLabel)
        // The wildcard note uses the same style below the keyword field (FR-441).
        configureNote(wildcardLabel)

        keywordField.delegate = self
        keywordField.stringValue = initialKeyword ?? ""

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        reasonLabel.textColor = .systemRed
        reasonLabel.lineBreakMode = .byWordWrapping
        reasonLabel.maximumNumberOfLines = 0
        reasonLabel.isHidden = true

        addRootButton.bezelStyle = .push
        addRootButton.target = self
        addRootButton.action = #selector(addRoot(_:))

        cancelButton.bezelStyle = .push
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))

        searchButton.bezelStyle = .push
        searchButton.keyEquivalent = "\r"
        searchButton.target = self
        searchButton.action = #selector(search(_:))

        keywordField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttons = NSStackView(views: [cancelButton, searchButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [
            headingLabel, descriptionLabel, keywordLabel, keywordField, wildcardLabel, rootLabel, rowsStack,
            addRootButton, reasonLabel, buttons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(4, after: headingLabel)
        stack.setCustomSpacing(14, after: descriptionLabel)
        stack.setCustomSpacing(4, after: keywordField)
        stack.setCustomSpacing(14, after: wildcardLabel)
        stack.setCustomSpacing(8, after: rowsStack)
        stack.setCustomSpacing(14, after: addRootButton)
        stack.setCustomSpacing(14, after: reasonLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            keywordField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reasonLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            descriptionLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            wildcardLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        appendRowView(text: initialRootPath)

        view = container
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )
        applyText()
        refreshControls()
    }

    private func configureNote(_ label: NSTextField) {
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.isSelectable = false
        label.isEditable = false
        label.refusesFirstResponder = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The keyword field reads the notes as its help, so they are not read again as separate items.
        label.setAccessibilityElement(false)
    }

    /// Sets every title, label, and accessibility text in the current language.
    private func applyText() {
        headingLabel.stringValue = l10n.text(.searchHeading)
        descriptionLabel.stringValue = l10n.text(.searchDescription)
        wildcardLabel.stringValue = l10n.text(.searchWildcardHint)
        keywordLabel.stringValue = l10n.text(.searchKeyword)
        rootLabel.stringValue = l10n.text(.searchRoot)
        keywordField.placeholderString = l10n.text(.searchKeyword)
        keywordField.setAccessibilityLabel(l10n.text(.searchKeyword))
        // The description, then the wildcard note (FR-394, FR-441).
        keywordField.setAccessibilityHelp(l10n.text(.searchDescription) + " " + l10n.text(.searchWildcardHint))
        reasonLabel.setAccessibilityLabel(l10n.text(.searchError))
        addRootButton.title = l10n.text(.searchAddRoot)
        addRootButton.setAccessibilityLabel(l10n.text(.searchAddRoot))
        cancelButton.title = l10n.text(.dialogCancel)
        searchButton.title = l10n.text(.searchSearch)
        updateRowText()
        if !reasonLabel.isHidden, reason != nil { renderReason(announce: false) }
        folderPanel?.title = l10n.text(.searchPanelTitle)
        folderPanel?.message = l10n.text(.searchPanelMessage)
        folderPanel?.prompt = l10n.text(.searchPanelPrompt)
    }

    @objc private func displayLanguageDidChange() {
        applyText()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard !initialFocusApplied else { return }
        initialFocusApplied = true
        view.window?.initialFirstResponder = keywordField
        view.window?.makeFirstResponder(keywordField)
        if initialKeyword != nil {
            keywordField.currentEditor()?.selectAll(nil)
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        inputState.close()
        initialLocationTask?.cancel()
        selectionTask?.cancel()
        searchTask?.cancel()
    }

    // MARK: - Rows

    /// Adds a row view at the end. Activates its width constraint after adding it to the stack.
    private func appendRowView(text: String) {
        let row = SearchRootRowView(text: text)
        row.field.delegate = self
        row.chooseButton.target = self
        row.chooseButton.action = #selector(chooseFolder(_:))
        row.removeButton.target = self
        row.removeButton.action = #selector(removeRoot(_:))
        rowsStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        rows.append(row)
        updateRowText()
        updateKeyViewLoop()
    }

    private func updateRowText() {
        let numbered = rows.count > 1
        for (index, row) in rows.enumerated() {
            row.updateText(number: numbered ? index + 1 : nil)
        }
    }

    /// Tab order: keyword, each row (field, "Choose…", "Remove"), "Add Folder", Cancel, Search (FR-081). Disabled
    /// buttons are skipped because they cannot become the key view.
    private func updateKeyViewLoop() {
        var chain: [NSView] = [keywordField]
        for row in rows {
            chain.append(contentsOf: [row.field, row.chooseButton, row.removeButton])
        }
        chain.append(contentsOf: [addRootButton, cancelButton, searchButton])
        for (index, view) in chain.enumerated() {
            view.nextKeyView = chain[(index + 1) % chain.count]
        }
    }

    private func rowIndex(of view: Any?) -> Int? {
        guard let view = view as? NSView else { return nil }
        return rows.firstIndex { $0.field === view || $0.chooseButton === view || $0.removeButton === view }
    }

    @objc private func addRoot(_ sender: Any?) {
        guard let index = inputState.addRow(panelPresented: panelPresented) else { return }
        appendRowView(text: inputState.rootInputs[index].displayText)
        renderReasonIfShown()
        refreshControls()
        view.window?.makeFirstResponder(rows[index].field)
    }

    @objc private func removeRoot(_ sender: Any?) {
        guard let index = rowIndex(of: sender),
              let focus = inputState.removeRow(at: index, panelPresented: panelPresented) else { return }
        let row = rows.remove(at: index)
        rowsStack.removeArrangedSubview(row)
        row.removeFromSuperview()
        // A reason for the removed row disappears; a reason for a later row moves up with it (FR-435).
        if case let .row(reasonRow, error) = reason {
            if reasonRow == index {
                hideReason()
            } else if reasonRow > index {
                reason = .row(reasonRow - 1, error)
            }
        }
        updateRowText()
        updateKeyViewLoop()
        renderReasonIfShown()
        refreshControls()
        view.window?.makeFirstResponder(rows[focus].field)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === keywordField {
            inputState.updateKeyword(field.stringValue)
        } else if let index = rowIndex(of: field) {
            inputState.updateRootText(field.stringValue, at: index)
        }
        refreshControls()
    }

    /// Determines whether search, selection, and row changes are available. Search remains available while resolving
    /// the initial location; selection, row changes, and duplicate searches are disabled while work is pending.
    private func refreshControls() {
        let pending = inputState.pendingOperation
        let canRemove = inputState.canRemoveRow(panelPresented: panelPresented)
        for row in rows {
            row.chooseButton.isEnabled = !panelPresented && pending == .idle
            row.removeButton.isEnabled = canRemove
        }
        addRootButton.isEnabled = inputState.canAddRow(panelPresented: panelPresented)
        searchButton.isEnabled = !panelPresented
            && pending != .validatingSearch
            && SearchPattern(keyword: keywordField.stringValue) != nil
        cancelButton.isEnabled = !panelPresented
    }

    // MARK: - Search

    @objc private func cancel(_ sender: Any?) {
        guard !panelPresented else { return }
        dismiss(self)
    }

    @objc private func search(_ sender: Any?) {
        guard !panelPresented else { return }
        guard let ticket = inputState.beginSearchValidation(panelPresented: panelPresented) else { return }
        refreshControls()
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let result = await SearchRootList.validate(ticket.inputs, home: home)
            guard let self else { return }
            switch result {
            case let .success(roots):
                // Organizing reads folder attributes, so it runs off the UI thread (FR-437).
                let organized = await Task.detached(priority: .userInitiated) {
                    SearchRootList.organize(roots)
                }.value
                guard self.inputState.complete(ticket, succeeded: true) else { return }
                guard let pattern = SearchPattern(keyword: ticket.keyword) else { return }
                self.dismiss(self)
                self.onSearch(pattern, organized)
            case let .failure(failure):
                guard self.inputState.complete(ticket, succeeded: false) else { return }
                self.showReason(.row(failure.row, failure.error))
                if self.rows.indices.contains(failure.row) {
                    self.view.window?.makeFirstResponder(self.rows[failure.row].field)
                }
                self.refreshControls()
            }
        }
    }

    // MARK: - Folder Selection

    @objc private func chooseFolder(_ sender: Any?) {
        guard !panelPresented, let row = rowIndex(of: sender) else { return }
        guard let ticket = inputState.beginInitialLocationResolution(row: row, panelPresented: panelPresented) else {
            return
        }
        refreshControls()
        initialLocationTask?.cancel()
        initialLocationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let result = await SearchFolderInitialLocation.resolve(
                input: ticket.input,
                defaultPath: self.initialRootPath,
                home: home
            )
            switch result {
            case let .success(directory):
                guard self.inputState.complete(ticket, succeeded: true) else { return }
                self.presentFolderPanel(initialDirectory: directory, row: row)
            case let .failure(error):
                guard self.inputState.complete(ticket, succeeded: false) else { return }
                self.showReason(.general({ l10n.text(for: error) }))
                self.refreshControls()
            }
        }
    }

    private func presentFolderPanel(initialDirectory: URL, row: Int) {
        guard !panelPresented, let window = view.window else {
            showReason(.general({ l10n.text(.searchPanelFailed) }))
            refreshControls()
            return
        }

        let panel = NSOpenPanel()
        panel.title = l10n.text(.searchPanelTitle)
        panel.message = l10n.text(.searchPanelMessage)
        panel.prompt = l10n.text(.searchPanelPrompt)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.treatsFilePackagesAsDirectories = false
        panel.showsHiddenFiles = false
        panel.directoryURL = initialDirectory

        folderPanel = panel
        panelPresented = true
        refreshControls()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.panelPresented = false
            self.folderPanel = nil
            guard response == .OK, let url = panel.url else {
                self.focusChooseButton(row: row)
                self.refreshControls()
                return
            }
            self.beginSelectionValidation(url, row: row)
        }
    }

    private func beginSelectionValidation(_ url: URL, row: Int) {
        guard let ticket = inputState.beginSelectionValidation(url, row: row, panelPresented: panelPresented) else {
            focusChooseButton(row: row)
            refreshControls()
            return
        }
        refreshControls()
        selectionTask?.cancel()
        selectionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await SearchRoot.validate(url)
            switch result {
            case .success:
                guard self.inputState.complete(ticket, succeeded: true) else { return }
                self.inputState.applyPickedRoot(url, at: row)
                self.rows[row].field.stringValue = self.inputState.rootInputs[row].displayText
                self.hideReason()
                self.focusChooseButton(row: row)
                self.refreshControls()
            case let .failure(error):
                guard self.inputState.complete(ticket, succeeded: false) else { return }
                self.showReason(.general({ l10n.text(for: error) }))
                self.focusChooseButton(row: row)
                self.refreshControls()
            }
        }
    }

    private func focusChooseButton(row: Int) {
        guard rows.indices.contains(row) else { return }
        let button = rows[row].chooseButton
        view.window?.makeFirstResponder(button)
        Task { @MainActor [weak self] in
            self?.view.window?.makeFirstResponder(button)
        }
    }

    // MARK: - Reason

    private func hideReason() {
        reasonLabel.isHidden = true
        reason = nil
    }

    /// Shows the reason below the rows and announces it (does not close the modal; FR-081, FR-436).
    private func showReason(_ newReason: Reason) {
        reason = newReason
        renderReason(announce: true)
    }

    private func renderReasonIfShown() {
        guard !reasonLabel.isHidden, reason != nil else { return }
        renderReason(announce: false)
    }

    private func renderReason(announce: Bool) {
        guard let reason else { return }
        let message: String
        switch reason {
        case let .general(render):
            message = render()
        case let .row(row, error):
            // A single row keeps the unnumbered wording (FR-436).
            message = rows.count > 1
                ? l10n.text(.searchErrorNumbered, .number(row + 1), .text(l10n.text(for: error)))
                : l10n.text(for: error)
        }
        reasonLabel.stringValue = message
        reasonLabel.isHidden = false
        guard announce else { return }
        NSAccessibility.post(
            element: NSApp.mainWindow ?? reasonLabel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }
}
