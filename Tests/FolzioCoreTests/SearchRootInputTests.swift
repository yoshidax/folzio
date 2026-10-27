import Foundation
import Testing
@testable import FolzioCore

@Suite("SearchRootInput and the parent input generation")
struct SearchRootInputTests {
    private let home = URL(fileURLWithPath: "/Users/me", isDirectory: true)

    private func requireValue<T>(_ value: T?) throws -> T {
        try #require(value)
    }

    private func standardized(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    @Test("typed uses existing parsing rules while picked preserves trailing whitespace")
    func resolvesTypedAndPicked() {
        #expect(SearchRootInput.typed(" ~/a/b ").resolvedInput(home: home) == .success(standardized("/Users/me/a/b")))
        #expect(SearchRootInput.typed("/a/b/").resolvedInput(home: home) == .success(standardized("/a/b")))
        #expect(SearchRootInput.typed("  ").resolvedInput(home: home) == .failure(.empty))
        #expect(SearchRootInput.typed("a/b").resolvedInput(home: home) == .failure(.notAbsolute))

        #expect(SearchRootInput.typed(" ~/a/b ").displayText == " ~/a/b ")

        let picked = URL(fileURLWithPath: "/Users/me/Photos ", isDirectory: true)
        #expect(SearchRootInput.picked(picked).displayText == "/Users/me/Photos ")
        #expect(SearchRootInput.picked(picked).resolvedInput(home: home) == .success(picked))
        #expect(SearchRootInput.picked(picked).resolvedInput(home: home) != .success(standardized("/Users/me/Photos")))
    }

    @Test("Only editing the root field resets the source to typed; editing the keyword and closing do not")
    func inputSourceTransitions() {
        let picked = URL(fileURLWithPath: "/Users/me/Photos ", isDirectory: true)
        var state = SearchPanelInputState(rootInput: .picked(picked), keyword: "hit")
        #expect(state.isActive)
        #expect(state.revision == 0)
        #expect(state.pendingOperation == .idle)

        state.updateKeyword("cats")
        #expect(state.rootInput == .picked(picked))
        #expect(state.keyword == "cats")
        #expect(state.revision == 1)

        state.updateRootText("/Users/me/Photos ")
        #expect(state.rootInput == .typed("/Users/me/Photos "))
        #expect(state.displayText == "/Users/me/Photos ")
        #expect(state.revision == 2)

        var pickedState = SearchPanelInputState(rootInput: .picked(picked))
        pickedState.applyPickedRoot(URL(fileURLWithPath: "/Users/me/other", isDirectory: true))
        #expect(pickedState.rootInput == .picked(URL(fileURLWithPath: "/Users/me/other", isDirectory: true)))
        #expect(pickedState.revision == 1)

        pickedState.close()
        #expect(!pickedState.isActive)
        #expect(pickedState.pendingOperation == .idle)
    }

    @Test("Initial-location resolution returns the captured input and is invalidated by editing, closing, or accepting a search")
    func initialLocationTickets() throws {
        var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "hit")
        let ticket = try requireValue(state.beginInitialLocationResolution(panelPresented: false))
        #expect(ticket.operation == .resolvingInitialLocation)
        #expect(ticket.input == .typed("/start"))
        #expect(ticket.keyword == "hit")
        #expect(ticket.selection == nil)
        #expect(state.pendingOperation == .resolvingInitialLocation)
        let duplicate = state.beginInitialLocationResolution(panelPresented: false)
        #expect(duplicate == nil)
        let selectionWhileResolving = state.beginSelectionValidation(
            URL(fileURLWithPath: "/picked", isDirectory: true),
            panelPresented: false
        )
        #expect(selectionWhileResolving == nil)
        let completed = state.complete(ticket, succeeded: true)
        #expect(completed)
        #expect(state.pendingOperation == .idle)

        let edited = try requireValue(state.beginInitialLocationResolution(panelPresented: false))
        state.updateRootText("/other")
        let editedAdopted = state.complete(edited, succeeded: true)
        #expect(!editedAdopted)

        let closedTicket = try requireValue(state.beginInitialLocationResolution(panelPresented: false))
        state.close()
        let closedAdopted = state.complete(closedTicket, succeeded: true)
        #expect(!closedAdopted)
    }

    @Test("Accepting a search invalidates initial-location and selection validation; only search success closes the parent")
    func searchInvalidatesPendingWork() throws {
        var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "hit")
        let initial = try requireValue(state.beginInitialLocationResolution(panelPresented: false))
        let search = try requireValue(state.beginSearchValidation(panelPresented: false))
        #expect(search.operation == .validatingSearch)
        #expect(state.pendingOperation == .validatingSearch)
        let initialAdopted = state.complete(initial, succeeded: true)
        #expect(!initialAdopted)
        let searchAdopted = state.complete(search, succeeded: false)
        #expect(searchAdopted)
        #expect(state.isActive)
        #expect(state.pendingOperation == .idle)

        let retry = try requireValue(state.beginSearchValidation(panelPresented: false))
        let oldInitial = SearchPanelOperationTicket(
            operation: .resolvingInitialLocation,
            revision: retry.revision,
            requestGeneration: retry.requestGeneration,
            input: retry.input,
            keyword: retry.keyword
        )
        let staleAdopted = state.complete(oldInitial, succeeded: true)
        #expect(!staleAdopted)
        let retryAdopted = state.complete(retry, succeeded: true)
        #expect(retryAdopted)
        #expect(!state.isActive)
        #expect(state.pendingOperation == .idle)
    }

    @Test("A search during initial-location resolution rejects the old resolution regardless of completion order")
    func completionOrderDoesNotReviveInitialLocation() throws {
        for initialFirst in [true, false] {
            for searchSucceeds in [true, false] {
                var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "hit")
                let initial = try requireValue(state.beginInitialLocationResolution(panelPresented: false))
                let search = try requireValue(state.beginSearchValidation(panelPresented: false))

                let initialAdopted: Bool
                let searchAdopted: Bool
                if initialFirst {
                    initialAdopted = state.complete(initial, succeeded: true)
                    searchAdopted = state.complete(search, succeeded: searchSucceeds)
                } else {
                    searchAdopted = state.complete(search, succeeded: searchSucceeds)
                    initialAdopted = state.complete(initial, succeeded: false)
                }

                #expect(!initialAdopted, "Does not accept a stale initial location (initialFirst: \(initialFirst))")
                #expect(searchAdopted, "Accepts the accepted search (initialFirst: \(initialFirst))")
                #expect(state.isActive == !searchSucceeds)
                #expect(state.pendingOperation == .idle)
            }
        }
    }

    @Test("Post-confirmation validation captures the selected URL and allows applying picked only after success")
    func selectionValidationTickets() throws {
        var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "hit")
        let url = URL(fileURLWithPath: "/Users/me/Photos ", isDirectory: true)
        let ticket = try requireValue(state.beginSelectionValidation(url, panelPresented: false))
        #expect(ticket.operation == .validatingSelection)
        #expect(ticket.selection == url)
        #expect(state.pendingOperation == .validatingSelection)
        let duplicate = state.beginSelectionValidation(url, panelPresented: false)
        #expect(duplicate == nil)
        let adopted = state.complete(ticket, succeeded: true)
        #expect(adopted)
        #expect(state.isActive)
        #expect(state.pendingOperation == .idle)
        #expect(state.rootInput == .typed("/start"), "Completion alone does not change the field")

        state.applyPickedRoot(url)
        #expect(state.rootInput == .picked(url))
        #expect(state.displayText == "/Users/me/Photos ")

        let failed = try requireValue(state.beginSelectionValidation(url, panelPresented: false))
        let failedAdopted = state.complete(failed, succeeded: false)
        #expect(failedAdopted)
        #expect(state.rootInput == .picked(url), "Failure does not apply the selection")
        #expect(state.pendingOperation == .idle)

        let edited = try requireValue(state.beginSelectionValidation(url, panelPresented: false))
        state.updateRootText("/edited")
        let editedAdopted = state.complete(edited, succeeded: true)
        #expect(!editedAdopted)
        #expect(state.rootInput == .typed("/edited"))

        var closed = SearchPanelInputState(rootInput: .typed("/start"))
        let closedTicket = try requireValue(closed.beginSelectionValidation(url, panelPresented: false))
        closed.close()
        let closedAdopted = closed.complete(closedTicket, succeeded: true)
        #expect(!closedAdopted)
    }

    @Test("Searching invalidates pending initial-location and selection validation; duplicate searches during search validation are rejected")
    func selectionThenSearch() throws {
        var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "hit")
        let selection = try requireValue(
            state.beginSelectionValidation(URL(fileURLWithPath: "/picked", isDirectory: true), panelPresented: false)
        )
        let search = try requireValue(state.beginSearchValidation(panelPresented: false))
        let selectionAdopted = state.complete(selection, succeeded: true)
        #expect(!selectionAdopted)
        let searchAdopted = state.complete(search, succeeded: false)
        #expect(searchAdopted)
        #expect(state.isActive)

        let activeSearch = try requireValue(state.beginSearchValidation(panelPresented: false))
        let duplicate = state.beginSearchValidation(panelPresented: false)
        #expect(duplicate == nil)
        let initialDuringSearch = state.beginInitialLocationResolution(panelPresented: false)
        #expect(initialDuringSearch == nil)
        let activeAdopted = state.complete(activeSearch, succeeded: false)
        #expect(activeAdopted)
    }

    @Test("An empty keyword does nothing and does not invalidate a pending initial location")
    func emptyKeywordIsNoOp() throws {
        var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "   ")
        let generation = state.requestGeneration
        let ticket = state.beginSearchValidation(panelPresented: false)
        #expect(ticket == nil)
        #expect(state.requestGeneration == generation)
        #expect(state.pendingOperation == .idle)

        var withInitial = SearchPanelInputState(rootInput: .typed("/start"), keyword: "   ")
        let initial = try requireValue(withInitial.beginInitialLocationResolution(panelPresented: false))
        let emptySearch = withInitial.beginSearchValidation(panelPresented: false)
        #expect(emptySearch == nil)
        #expect(withInitial.pendingOperation == .resolvingInitialLocation)
        let adopted = withInitial.complete(initial, succeeded: true)
        #expect(adopted)
    }

    @Test("The parent rejects search, selection, and initial-location requests while the panel is open")
    func panelPresentationBlocksActions() throws {
        var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "hit")
        let initial = state.beginInitialLocationResolution(panelPresented: true)
        let selection = state.beginSelectionValidation(
            URL(fileURLWithPath: "/picked", isDirectory: true),
            panelPresented: true
        )
        let search = state.beginSearchValidation(panelPresented: true)
        #expect(initial == nil)
        #expect(selection == nil)
        #expect(search == nil)
        #expect(state.pendingOperation == .idle)
    }

    @Test("Rejects completions with a mismatched operation kind or input generation")
    func wrongTicketIsRejected() throws {
        var state = SearchPanelInputState(rootInput: .typed("/start"), keyword: "hit")
        let initial = try requireValue(state.beginInitialLocationResolution(panelPresented: false))
        let wrongKind = SearchPanelOperationTicket(
            operation: .validatingSearch,
            revision: initial.revision,
            requestGeneration: initial.requestGeneration,
            input: initial.input,
            keyword: initial.keyword
        )
        let wrongKindAdopted = state.complete(wrongKind, succeeded: true)
        #expect(!wrongKindAdopted)
        #expect(state.pendingOperation == .resolvingInitialLocation)

        let wrongRevision = SearchPanelOperationTicket(
            operation: .resolvingInitialLocation,
            revision: initial.revision + 1,
            requestGeneration: initial.requestGeneration,
            input: initial.input,
            keyword: initial.keyword
        )
        let wrongRevisionAdopted = state.complete(wrongRevision, succeeded: true)
        #expect(!wrongRevisionAdopted)
        #expect(state.pendingOperation == .resolvingInitialLocation)
        let adopted = state.complete(initial, succeeded: true)
        #expect(adopted)
    }
}
