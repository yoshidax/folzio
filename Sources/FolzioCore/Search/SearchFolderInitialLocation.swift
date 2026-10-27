import Foundation

/// Reason the initial location of the standard panel cannot be determined. The presentation layer chooses the
/// text (data-model.md 2).
public enum SearchFolderInitialLocationError: Error, Sendable, Equatable {
    case noUsableFolder
}

/// Resolves the initial location of the standard panel in this order: current input, startup default, home
/// (FR-143, data-model.md 2).
///
/// Validates each candidate with the same conditions as `SearchRoot.validate`. Allows hidden folders and skips
/// files, zips, packages, and unreadable folders. Tests can inject the validator.
public enum SearchFolderInitialLocation {
    public typealias Validator = @Sendable (URL) async -> Result<URL, SearchRootError>

    public static func resolve(
        input: SearchRootInput,
        defaultPath: String?,
        home: URL,
        validate: Validator = { await SearchRoot.validate($0) }
    ) async -> Result<URL, SearchFolderInitialLocationError> {
        var candidates: [URL] = []
        if case let .success(url) = input.resolvedInput(home: home) {
            candidates.append(url)
        }
        if let defaultPath, defaultPath.hasPrefix("/"), !defaultPath.isEmpty {
            candidates.append(URL(fileURLWithPath: defaultPath, isDirectory: true))
        }
        candidates.append(home)

        var seen: Set<String> = []
        for candidate in candidates {
            guard seen.insert(SearchPath.normalized(candidate)).inserted else { continue }
            if case let .success(url) = await validate(candidate) {
                return .success(url)
            }
        }
        return .failure(.noUsableFolder)
    }
}
