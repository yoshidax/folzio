import Foundation

/// Determines the bundle that provides the localized strings (research.md R3).
/// In an `.app`, uses the lproj in the main bundle's `Contents/Resources`; under `swift run` and in tests,
/// uses the package resource bundle.
public enum LocalizationBundle {
    /// Uses the main bundle when it is an `.app` with an en.lproj table; otherwise uses the package bundle.
    public static func resolve(main: Bundle = .main) -> Bundle {
        if containsTable(language: "en", in: main) {
            return main
        }
        return packageBundle
    }

    /// Package resource bundle used by tests and `swift run`.
    public static var packageBundle: Bundle { Bundle.module }

    /// The lproj for the given language inside `bundle`, or nil when it has no table.
    public static func table(language: String, in bundle: Bundle) -> Bundle? {
        guard let url = bundle.url(forResource: language, withExtension: "lproj"),
              containsTable(language: language, in: bundle) else {
            return nil
        }
        return Bundle(url: url)
    }

    private static func containsTable(language: String, in bundle: Bundle) -> Bool {
        guard let url = bundle.url(forResource: language, withExtension: "lproj") else { return false }
        return FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Localizable.strings").path
        ) || FileManager.default.fileExists(
            atPath: url.appendingPathComponent("Localizable.stringsdict").path
        )
    }
}
