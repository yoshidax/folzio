import Foundation

/// Source of the search root field input (FR-081, FR-142; data-model.md 1).
///
/// - `typed` is a string typed or edited directly by the user, parsed with the existing `SearchRoot.parse` rules.
/// - `picked` is an absolute file URL confirmed in the standard folder selection panel; the selected URL is used
///   as-is (not trimmed).
///
/// The initial state is `typed`. `picked` is created only after a successful validation following confirmation.
/// User edits to the search root field produce `typed` even when the text returns to the same string, while keyword
/// edits, panel cancellation, failures, and reopening do not change the source.
public enum SearchRootInput: Sendable, Equatable {
    case typed(String)
    case picked(URL)

    /// String shown in the search root field. `picked` returns an absolute path without quotes or escaping.
    public var displayText: String {
        switch self {
        case let .typed(text):
            return text
        case let .picked(url):
            return url.path
        }
    }

    /// Interpretation used by both search and initial location. `picked` returns the selected URL as-is; link
    /// resolution is left to `SearchRoot.validate`.
    public func resolvedInput(home: URL) -> Result<URL, SearchRootError> {
        switch self {
        case let .typed(text):
            return SearchRoot.parse(text, home: home)
        case let .picked(url):
            return .success(url)
        }
    }
}

/// Kind of asynchronous operation owned by the parent search sheet (FR-143, data-model.md 4).
public enum SearchPanelOperation: Sendable, Equatable {
    case idle
    case resolvingInitialLocation
    case validatingSelection
    case validatingSearch
}

/// Input, selected URL, and generation captured when an asynchronous operation starts. Acceptance of completion
/// depends only on this value and the current state.
public struct SearchPanelOperationTicket: Sendable, Equatable {
    public let operation: SearchPanelOperation
    public let revision: Int
    public let requestGeneration: Int
    /// Input of the row the operation is for (`row`), or of the first row for a search validation.
    public let input: SearchRootInput
    /// Inputs of every root row when the operation started (FR-436).
    public let inputs: [SearchRootInput]
    /// Row index the operation is for. Nil for a search validation, which covers every row.
    public let row: Int?
    public let keyword: String
    public let selection: URL?

    init(
        operation: SearchPanelOperation,
        revision: Int,
        requestGeneration: Int,
        input: SearchRootInput,
        inputs: [SearchRootInput]? = nil,
        row: Int? = nil,
        keyword: String,
        selection: URL? = nil
    ) {
        self.operation = operation
        self.revision = revision
        self.requestGeneration = requestGeneration
        self.input = input
        self.inputs = inputs ?? [input]
        self.row = row
        self.keyword = keyword
        self.selection = selection
    }
}

/// Small state that tracks the search sheet's root rows and their input sources, and arbitrates between initial
/// location resolution, post-confirmation validation, and search validation (data-model.md 2).
///
/// A value type that assumes operations on the MainActor are passed serially and performs no I/O. A completion is
/// accepted only when the captured revision, requestGeneration, and operation kind match the current values and
/// `isActive` is true. Methods without a row index act on the first row.
public struct SearchPanelInputState: Sendable, Equatable {
    /// Maximum number of root rows (FR-435).
    public static let maximumRows = 10

    /// Root rows from top to bottom. Always contains between 1 and `maximumRows` inputs.
    public private(set) var rootInputs: [SearchRootInput]
    public private(set) var keyword: String
    /// Number of changes to the rows, their input sources, and the keyword. Used to accept or reject stale results.
    public private(set) var revision: Int
    /// Whether the search sheet is open. Completions after closing are not accepted.
    public private(set) var isActive: Bool
    public private(set) var pendingOperation: SearchPanelOperation
    /// Request generation incremented on start and invalidation. Distinguishes different requests even with the same
    /// input.
    public private(set) var requestGeneration: Int

    public init(rootInput: SearchRootInput, keyword: String = "") {
        rootInputs = [rootInput]
        self.keyword = keyword
        revision = 0
        isActive = true
        pendingOperation = .idle
        requestGeneration = 0
    }

    /// Input of the first row.
    public var rootInput: SearchRootInput {
        rootInputs[0]
    }

    /// String shown in the first row's field.
    public var displayText: String {
        rootInputs[0].displayText
    }

    public var rowCount: Int {
        rootInputs.count
    }

    /// Whether "Add Folder" is available (FR-435).
    public func canAddRow(panelPresented: Bool) -> Bool {
        isActive && !panelPresented && pendingOperation == .idle && rootInputs.count < Self.maximumRows
    }

    /// Whether the rows' "Remove" buttons are available (FR-435).
    public func canRemoveRow(panelPresented: Bool) -> Bool {
        isActive && !panelPresented && pendingOperation == .idle && rootInputs.count > 1
    }

    /// Appends an empty typed row and returns its index, or nil when adding is not available.
    public mutating func addRow(panelPresented: Bool) -> Int? {
        guard canAddRow(panelPresented: panelPresented) else { return nil }
        rootInputs.append(.typed(""))
        revision &+= 1
        return rootInputs.count - 1
    }

    /// Removes a row and returns the index of the row that should receive focus (the row that moved up into the same
    /// position, or the new last row). Returns nil when removing is not available or the index is out of range.
    public mutating func removeRow(at index: Int, panelPresented: Bool) -> Int? {
        guard canRemoveRow(panelPresented: panelPresented), rootInputs.indices.contains(index) else { return nil }
        rootInputs.remove(at: index)
        revision &+= 1
        return min(index, rootInputs.count - 1)
    }

    /// User edit to the first row's field.
    public mutating func updateRootText(_ text: String) {
        updateRootText(text, at: 0)
    }

    /// User edit to a row's field. Produces `typed` even when the text returns to the same string and invalidates
    /// pending work. Other rows keep their source.
    public mutating func updateRootText(_ text: String, at index: Int) {
        guard isActive, rootInputs.indices.contains(index) else { return }
        rootInputs[index] = .typed(text)
        revision &+= 1
        invalidatePending()
    }

    /// Keyword edit. Leaves the rows unchanged and invalidates pending work.
    public mutating func updateKeyword(_ text: String) {
        guard isActive else { return }
        keyword = text
        revision &+= 1
        invalidatePending()
    }

    /// Successful confirmation in the standard panel for the first row.
    public mutating func applyPickedRoot(_ url: URL) {
        applyPickedRoot(url, at: 0)
    }

    /// Successful confirmation in the standard panel. Stores the selected URL as `picked` in that row only and
    /// invalidates older work.
    public mutating func applyPickedRoot(_ url: URL, at index: Int) {
        guard isActive, rootInputs.indices.contains(index) else { return }
        rootInputs[index] = .picked(url)
        revision &+= 1
        invalidatePending()
    }

    /// Closes the search sheet. Later completions are not accepted.
    public mutating func close() {
        isActive = false
        revision &+= 1
        invalidatePending()
    }

    /// Starts resolving the panel's initial location for the first row.
    public mutating func beginInitialLocationResolution(
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        beginInitialLocationResolution(row: 0, panelPresented: panelPresented)
    }

    /// Starts resolving the panel's initial location for a row. Rejects duplicate starts while the panel is presented
    /// and while search validation is in progress.
    public mutating func beginInitialLocationResolution(
        row: Int,
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        guard isActive, !panelPresented, pendingOperation == .idle, rootInputs.indices.contains(row) else { return nil }
        requestGeneration &+= 1
        pendingOperation = .resolvingInitialLocation
        return makeTicket(operation: .resolvingInitialLocation, row: row)
    }

    /// Starts revalidation after confirmation for the first row.
    public mutating func beginSelectionValidation(
        _ url: URL,
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        beginSelectionValidation(url, row: 0, panelPresented: panelPresented)
    }

    /// Starts revalidation after confirmation. Captures the selected URL, the row, its input, and the request
    /// generation. Rejects duplicate confirmations and starts while the panel is presented.
    public mutating func beginSelectionValidation(
        _ url: URL,
        row: Int,
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        guard isActive, !panelPresented, pendingOperation == .idle, rootInputs.indices.contains(row) else { return nil }
        requestGeneration &+= 1
        pendingOperation = .validatingSelection
        return makeTicket(operation: .validatingSelection, row: row, selection: url)
    }

    /// Accepts a search. As before, an empty keyword is a no-op and does not invalidate pending work.
    /// When accepted, invalidates initial location and selection validation first, then moves to search validation.
    /// The ticket captures every row (FR-436).
    public mutating func beginSearchValidation(
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        guard isActive, !panelPresented else { return nil }
        guard SearchPattern(keyword: keyword) != nil else { return nil }
        guard pendingOperation != .validatingSearch else { return nil }
        requestGeneration &+= 1
        pendingOperation = .validatingSearch
        return makeTicket(operation: .validatingSearch, row: nil)
    }

    /// Accepts completion of the captured operation. Only a successful search validation closes the parent.
    /// A completion that does not match (edit, row change, close, different request, or different kind) leaves the
    /// state unchanged and returns `false`.
    @discardableResult
    public mutating func complete(_ ticket: SearchPanelOperationTicket, succeeded: Bool) -> Bool {
        guard isActive,
              pendingOperation == ticket.operation,
              revision == ticket.revision,
              requestGeneration == ticket.requestGeneration
        else { return false }

        pendingOperation = .idle
        if ticket.operation == .validatingSearch, succeeded {
            isActive = false
        }
        return true
    }

    private func makeTicket(
        operation: SearchPanelOperation,
        row: Int?,
        selection: URL? = nil
    ) -> SearchPanelOperationTicket {
        SearchPanelOperationTicket(
            operation: operation,
            revision: revision,
            requestGeneration: requestGeneration,
            input: rootInputs[row ?? 0],
            inputs: rootInputs,
            row: row,
            keyword: keyword,
            selection: selection
        )
    }

    private mutating func invalidatePending() {
        guard pendingOperation != .idle else { return }
        pendingOperation = .idle
        requestGeneration &+= 1
    }
}
