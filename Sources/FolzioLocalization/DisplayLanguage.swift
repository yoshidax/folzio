import Foundation

/// Matches a saved value against the supported languages and falls back to the development language
/// when the value is unset or unknown.
public enum DisplayLanguage {
    public static func resolve(saved: String?, supported: [String], development: String = "en") -> String {
        guard let saved, supported.contains(saved) else { return development }
        return saved
    }
}
