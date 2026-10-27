import AppKit
import FolzioCore
import FolzioLocalization

/// Button that accepts Tab focus regardless of the system Keyboard Navigation setting (R39).
private final class KeyViewButton: NSButton {
    override var canBecomeKeyView: Bool { true }
}

/// Search modal (a sheet on the main window). Accepts a keyword and search root directory, validates the root,
/// then calls `onSearch` (FR-080–082). "Choose…" opens a standard `NSOpenPanel` as a child sheet and revalidates
/// asynchronously after confirmation (FR-141–144).
@MainActor
final class SearchPanelController: NSViewController, NSSearchFieldDelegate {
    private let initialKeyword: String?
    private let initialRootPath: String
    private let onSearch: (SearchPattern, URL) -> Void

    private let keywordField = NSSearchField()
    private let rootField = NSTextField()
    private let keywordLabel = NSTextField(labelWithString: "")
    private let rootLabel = NSTextField(labelWithString: "")
    private let reasonLabel = NSTextField(labelWithString: "")
    private let chooseFolderButton = KeyViewButton()
    private let cancelButton = KeyViewButton()
    private let searchButton = KeyViewButton()

    private var inputState: SearchPanelInputState
    private var initialLocationTask: Task<Void, Never>?
    private var selectionTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var folderPanel: NSOpenPanel?
    private var panelPresented = false
    private var initialFocusApplied = false
    private var localizedReason: (@MainActor () -> String)?

    init(keyword: String?, rootPath: String, onSearch: @escaping (SearchPattern, URL) -> Void) {
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

        keywordLabel.stringValue = l10n.text(.searchKeyword)
        rootLabel.stringValue = l10n.text(.searchRoot)

        keywordField.placeholderString = l10n.text(.searchKeyword)
        keywordField.delegate = self
        keywordField.setAccessibilityLabel(l10n.text(.searchKeyword))
        keywordField.stringValue = initialKeyword ?? ""

        configureRootField()

        reasonLabel.textColor = .systemRed
        reasonLabel.lineBreakMode = .byWordWrapping
        reasonLabel.maximumNumberOfLines = 0
        reasonLabel.isHidden = true
        reasonLabel.setAccessibilityLabel(l10n.text(.searchError))

        chooseFolderButton.title = l10n.text(.searchChoose)
        chooseFolderButton.bezelStyle = .push
        chooseFolderButton.target = self
        chooseFolderButton.action = #selector(chooseFolder(_:))
        chooseFolderButton.setAccessibilityLabel(l10n.text(.searchChoose))
        chooseFolderButton.setAccessibilityHelp(l10n.text(.searchChooseHelp))

        cancelButton.title = l10n.text(.dialogCancel)
        cancelButton.bezelStyle = .push
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel(_:))

        searchButton.title = l10n.text(.searchSearch)
        searchButton.bezelStyle = .push
        searchButton.keyEquivalent = "\r"
        searchButton.target = self
        searchButton.action = #selector(search(_:))

        keywordField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rootField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rootField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        chooseFolderButton.setContentHuggingPriority(.required, for: .horizontal)

        let rootRow = NSStackView(views: [rootField, chooseFolderButton])
        rootRow.orientation = .horizontal
        rootRow.alignment = .centerY
        rootRow.spacing = 8

        let buttons = NSStackView(views: [cancelButton, searchButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let stack = NSStackView(views: [
            keywordLabel, keywordField, rootLabel, rootRow, reasonLabel, buttons,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(14, after: keywordField)
        stack.setCustomSpacing(14, after: reasonLabel)
        stack.setCustomSpacing(14, after: rootRow)
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
            rootRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            reasonLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        keywordField.nextKeyView = rootField
        rootField.nextKeyView = chooseFolderButton
        chooseFolderButton.nextKeyView = cancelButton
        cancelButton.nextKeyView = searchButton
        searchButton.nextKeyView = keywordField

        view = container
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )
        refreshControls()
    }

    @objc private func displayLanguageDidChange() {
        keywordLabel.stringValue = l10n.text(.searchKeyword)
        rootLabel.stringValue = l10n.text(.searchRoot)
        keywordField.placeholderString = l10n.text(.searchKeyword)
        keywordField.setAccessibilityLabel(l10n.text(.searchKeyword))
        rootField.setAccessibilityLabel(l10n.text(.searchRoot))
        reasonLabel.setAccessibilityLabel(l10n.text(.searchError))
        if !reasonLabel.isHidden, let localizedReason { reasonLabel.stringValue = localizedReason() }
        chooseFolderButton.title = l10n.text(.searchChoose)
        chooseFolderButton.setAccessibilityLabel(l10n.text(.searchChoose))
        chooseFolderButton.setAccessibilityHelp(l10n.text(.searchChooseHelp))
        cancelButton.title = l10n.text(.dialogCancel)
        searchButton.title = l10n.text(.searchSearch)
        folderPanel?.title = l10n.text(.searchPanelTitle)
        folderPanel?.message = l10n.text(.searchPanelMessage)
        folderPanel?.prompt = l10n.text(.searchPanelPrompt)
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

    private func configureRootField() {
        rootField.usesSingleLineMode = true
        rootField.cell?.isScrollable = true
        rootField.cell?.wraps = false
        rootField.lineBreakMode = .byTruncatingHead
        rootField.delegate = self
        rootField.setAccessibilityLabel(l10n.text(.searchRoot))
        rootField.stringValue = initialRootPath
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === rootField {
            inputState.updateRootText(field.stringValue)
        } else if field === keywordField {
            inputState.updateKeyword(field.stringValue)
        }
        refreshControls()
    }

    /// Determines whether search and selection are available. Search remains available while resolving the initial
    /// location; selection and duplicate searches are disabled while validating a search.
    private func refreshControls() {
        let pending = inputState.pendingOperation
        chooseFolderButton.isEnabled = !panelPresented && pending == .idle
        searchButton.isEnabled = !panelPresented
            && pending != .validatingSearch
            && SearchPattern(keyword: keywordField.stringValue) != nil
        cancelButton.isEnabled = !panelPresented
    }

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
            guard let self else { return }
            let home = FileManager.default.homeDirectoryForCurrentUser
            let url: URL
            switch ticket.input.resolvedInput(home: home) {
            case let .success(value):
                url = value
            case let .failure(error):
                guard self.inputState.complete(ticket, succeeded: false) else { return }
                self.showReason { l10n.text(for: error) }
                self.refreshControls()
                return
            }

            let result = await SearchRoot.validate(url)
            switch result {
            case let .success(root):
                guard self.inputState.complete(ticket, succeeded: true) else { return }
                guard let pattern = SearchPattern(keyword: ticket.keyword) else { return }
                self.dismiss(self)
                self.onSearch(pattern, root)
            case let .failure(error):
                guard self.inputState.complete(ticket, succeeded: false) else { return }
                self.showReason { l10n.text(for: error) }
                self.refreshControls()
            }
        }
    }

    @objc private func chooseFolder(_ sender: Any?) {
        guard !panelPresented else { return }
        guard let ticket = inputState.beginInitialLocationResolution(panelPresented: panelPresented) else {
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
                self.presentFolderPanel(initialDirectory: directory)
            case let .failure(error):
                guard self.inputState.complete(ticket, succeeded: false) else { return }
                self.showReason { l10n.text(for: error) }
                self.refreshControls()
            }
        }
    }

    private func presentFolderPanel(initialDirectory: URL) {
        guard !panelPresented, let window = view.window else {
            showReason { l10n.text(.searchPanelFailed) }
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
                self.focusChooseButton()
                self.refreshControls()
                return
            }
            self.beginSelectionValidation(url)
        }
    }

    private func beginSelectionValidation(_ url: URL) {
        guard let ticket = inputState.beginSelectionValidation(url, panelPresented: panelPresented) else {
            focusChooseButton()
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
                self.inputState.applyPickedRoot(url)
                self.rootField.stringValue = self.inputState.displayText
                self.hideReason()
                self.focusChooseButton()
                self.refreshControls()
            case let .failure(error):
                guard self.inputState.complete(ticket, succeeded: false) else { return }
                self.showReason { l10n.text(for: error) }
                self.focusChooseButton()
                self.refreshControls()
            }
        }
    }

    private func focusChooseButton() {
        view.window?.makeFirstResponder(chooseFolderButton)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.view.window?.makeFirstResponder(self.chooseFolderButton)
        }
    }

    private func hideReason() {
        reasonLabel.isHidden = true
        localizedReason = nil
    }

    /// Shows the reason below the field and announces it (does not close the modal; FR-081).
    private func showReason(_ render: @escaping @MainActor () -> String) {
        localizedReason = render
        let message = render()
        reasonLabel.stringValue = message
        reasonLabel.isHidden = false
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
