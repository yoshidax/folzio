import Foundation

/// Reason a search root directory input cannot be used (FR-081, research.md R35). The presentation layer chooses
/// the text.
public enum SearchRootError: Error, Sendable, Equatable {
    case empty
    case notAbsolute
    case notFound
    case notAFolder
    case accessDenied
}

/// Interpretation of search root directory input (`parse`; does not read the disk) and validation (`validate`;
/// reads the disk off the UI thread).
public enum SearchRoot {
    /// Trims whitespace, replaces `~` and `~/` with the home directory, and folds `.`, `..`, and a trailing `/`.
    /// Returns `.notAbsolute` for input that starts with neither `/` nor `~`, and for the `~user` form.
    public static func parse(_ input: String, home: URL) -> Result<URL, SearchRootError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let path: String
        if trimmed == "~" {
            path = home.path
        } else if trimmed.hasPrefix("~/") {
            path = home.path + "/" + trimmed.dropFirst(2)
        } else if trimmed.hasPrefix("/") {
            path = trimmed
        } else {
            return .failure(.notAbsolute)
        }
        return .success(URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL)
    }

    /// Checks that the path exists, is a folder (excluding packages and zip files), and can be opened.
    /// On success, returns the URL with symbolic links resolved.
    public static func validate(_ url: URL) async -> Result<URL, SearchRootError> {
        await Task.detached(priority: .userInitiated) {
            let resolved = url.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
                return .failure(.notFound)
            }
            guard isDirectory.boolValue else { return .failure(.notAFolder) }
            if (try? resolved.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
                return .failure(.notAFolder)
            }
            guard let directory = opendir(resolved.path) else { return .failure(.accessDenied) }
            closedir(directory)
            return .success(resolved)
        }.value
    }
}
