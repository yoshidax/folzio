import Testing
@testable import FolzioCore

@Suite("ToolbarSearchInput")
struct ToolbarSearchInputTests {
    @Test("Text in the field is carried to the modal without surrounding whitespace, ahead of the previous keyword")
    func fieldTextWins() {
        #expect(ToolbarSearchInput.modalKeyword(fieldText: "kyoto", previousKeyword: nil) == "kyoto")
        #expect(ToolbarSearchInput.modalKeyword(fieldText: " kyoto ", previousKeyword: "cat") == "kyoto")
        #expect(ToolbarSearchInput.modalKeyword(fieldText: "*.png", previousKeyword: "cat") == "*.png")
    }

    @Test("An empty or whitespace-only field opens the modal like ⌘F, with the previous keyword if any")
    func emptyFieldUsesPreviousKeyword() {
        for text in ["", " ", "\t", "\n "] {
            #expect(ToolbarSearchInput.modalKeyword(fieldText: text, previousKeyword: "cat") == "cat")
            #expect(ToolbarSearchInput.modalKeyword(fieldText: text, previousKeyword: nil) == nil)
        }
    }
}
