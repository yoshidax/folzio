import Foundation

/// Input rules for favorite display names (FR-100, R50). A namespace of pure functions that do not depend on AppKit.
/// Does not reject names containing `/` or `:`, or names equal to another item (EC-41).
public enum FavoriteName {
    /// Maximum display name length, counted with `String.count` (grapheme clusters). Emoji and combining characters
    /// count as one visible character (FR-100, R50).
    public static let maximumLength = 255

    /// Input during editing. Removes newlines and truncates to `maximumLength` characters from the start.
    /// Keeps leading and trailing whitespace because editing is in progress (FR-100, R50).
    public static func sanitizedForEditing(_ text: String) -> String {
        // `\r\n` is a single grapheme, so it cannot be detected per Character. Remove newlines per Unicode scalar.
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars where !CharacterSet.newlines.contains(scalar) {
            scalars.append(scalar)
        }
        return String(String(scalars).prefix(maximumLength))
    }

    /// Input at commit time. Applies `sanitizedForEditing`, then trims whitespace and newlines. Returns nil when empty
    /// (which clears the display name; FR-100, R50).
    public static func normalized(_ text: String) -> String? {
        let trimmed = sanitizedForEditing(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
