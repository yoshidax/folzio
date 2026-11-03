import Foundation

/// Fixed facts and value handling for the About dialog (FR-241, FR-242).
public enum AboutInfo {
    /// The public repository of Folzio. The About dialog shows its `absoluteString` as the link text.
    ///
    /// The app never requests this URL itself; it only hands it to the OS to open in the default browser.
    /// `scripts/check-no-network.sh` allows exactly this literal in this file and no other URL literal.
    public static let repositoryURL = URL(string: "https://github.com/yoshidax/folzio")!

    /// Returns the version to display for the raw `CFBundleShortVersionString` value.
    ///
    /// Returns `nil` when the value is missing, is not a string, or is empty after trimming whitespace, so that
    /// the About dialog omits the version line instead of showing a wrong or empty version (EC-168).
    public static func displayVersion(from value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
