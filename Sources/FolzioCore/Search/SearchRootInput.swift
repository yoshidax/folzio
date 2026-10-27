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
    public let input: SearchRootInput
    public let keyword: String
    public let selection: URL?

    init(
        operation: SearchPanelOperation,
        revision: Int,
        requestGeneration: Int,
        input: SearchRootInput,
        keyword: String,
        selection: URL? = nil
    ) {
        self.operation = operation
        self.revision = revision
        self.requestGeneration = requestGeneration
        self.input = input
        self.keyword = keyword
        self.selection = selection
    }
}

/// Small state that tracks the search sheet's input source and arbitrates between initial location resolution,
/// post-confirmation validation, and search validation (data-model.md 4).
///
/// A value type that assumes operations on the MainActor are passed serially and performs no I/O. A completion is
/// accepted only when the captured revision, requestGeneration, and operation kind match the current values and
/// `isActive` is true.
public struct SearchPanelInputState: Sendable, Equatable {
    public private(set) var rootInput: SearchRootInput
    public private(set) var keyword: String
    /// Number of changes to the input source and keyword. Used to accept or reject stale validation results.
    public private(set) var revision: Int
    /// Whether the search sheet is open. Completions after closing are not accepted.
    public private(set) var isActive: Bool
    public private(set) var pendingOperation: SearchPanelOperation
    /// Request generation incremented on start and invalidation. Distinguishes different requests even with the same
    /// input.
    public private(set) var requestGeneration: Int

    public init(rootInput: SearchRootInput, keyword: String = "") {
        self.rootInput = rootInput
        self.keyword = keyword
        revision = 0
        isActive = true
        pendingOperation = .idle
        requestGeneration = 0
    }

    public var displayText: String {
        rootInput.displayText
    }

    /// User edit to the search root field. Produces `typed` even when the text returns to the same string and
    /// invalidates pending work.
    public mutating func updateRootText(_ text: String) {
        guard isActive else { return }
        rootInput = .typed(text)
        revision &+= 1
        invalidatePending()
    }

    /// Keyword edit. Leaves the search root source unchanged and invalidates pending work.
    public mutating func updateKeyword(_ text: String) {
        guard isActive else { return }
        keyword = text
        revision &+= 1
        invalidatePending()
    }

    /// Successful confirmation in the standard panel. Stores the selected URL as `picked` and invalidates older work.
    public mutating func applyPickedRoot(_ url: URL) {
        guard isActive else { return }
        rootInput = .picked(url)
        revision &+= 1
        invalidatePending()
    }

    /// Closes the search sheet. Later completions are not accepted.
    public mutating func close() {
        isActive = false
        revision &+= 1
        invalidatePending()
    }

    /// Starts resolving the panel's initial location. Rejects duplicate starts while the panel is presented and while
    /// search validation is in progress.
    public mutating func beginInitialLocationResolution(
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        guard isActive, !panelPresented, pendingOperation == .idle else { return nil }
        requestGeneration &+= 1
        pendingOperation = .resolvingInitialLocation
        return makeTicket(operation: .resolvingInitialLocation)
    }

    /// Starts revalidation after confirmation. Captures the selected URL, input, and request generation. Rejects
    /// duplicate confirmations and starts while the panel is presented.
    public mutating func beginSelectionValidation(
        _ url: URL,
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        guard isActive, !panelPresented, pendingOperation == .idle else { return nil }
        requestGeneration &+= 1
        pendingOperation = .validatingSelection
        return makeTicket(operation: .validatingSelection, selection: url)
    }

    /// Accepts a search. As before, an empty keyword is a no-op and does not invalidate pending work.
    /// When accepted, invalidates initial location and selection validation first, then moves to search validation.
    public mutating func beginSearchValidation(
        panelPresented: Bool
    ) -> SearchPanelOperationTicket? {
        guard isActive, !panelPresented else { return nil }
        guard SearchPattern(keyword: keyword) != nil else { return nil }
        guard pendingOperation != .validatingSearch else { return nil }
        requestGeneration &+= 1
        pendingOperation = .validatingSearch
        return makeTicket(operation: .validatingSearch)
    }

    /// Accepts completion of the captured operation. Only a successful search validation closes the parent.
    /// A completion that does not match (edit, close, different request, or different kind) leaves the state unchanged
    /// and returns `false`.
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
        selection: URL? = nil
    ) -> SearchPanelOperationTicket {
        SearchPanelOperationTicket(
            operation: operation,
            revision: revision,
            requestGeneration: requestGeneration,
            input: rootInput,
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
