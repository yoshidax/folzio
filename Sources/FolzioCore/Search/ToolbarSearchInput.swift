import Foundation

/// Decides what the search modal shows when it is opened from the toolbar search field (FR-390).
public enum ToolbarSearchInput {
    /// The keyword to put in the modal's keyword field.
    ///
    /// Text in the toolbar field is used, without its leading and trailing whitespace. An empty or whitespace-only
    /// field opens the modal as ⌥⌘F does, with the keyword of the previous search in this launch, if any.
    public static func modalKeyword(fieldText: String, previousKeyword: String?) -> String? {
        let trimmed = fieldText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? previousKeyword : trimmed
    }
}
