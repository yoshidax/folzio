import Foundation

/// Validation of the search sheet's root rows and organization of the validated roots (FR-436, FR-437;
/// research.md R2, data-model.md 3).
public enum SearchRootList {
    /// The topmost invalid row. `row` is the index among all rows (blank rows included) and `rowCount` is the number
    /// of rows shown, so the presentation layer can omit the row number when there is only one row.
    public struct Failure: Error, Sendable, Equatable {
        public let row: Int
        public let rowCount: Int
        public let error: SearchRootError

        public init(row: Int, rowCount: Int, error: SearchRootError) {
            self.row = row
            self.rowCount = rowCount
            self.error = error
        }
    }

    /// Whether a row is blank: a typed row that is empty after trimming whitespace. A picked row is never blank.
    public static func isBlank(_ input: SearchRootInput) -> Bool {
        guard case let .typed(text) = input else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Interprets and validates every non-blank row from the top. Fails at the first invalid row. When every row is
    /// blank, fails with `.empty` for the first row (EC-303, EC-304).
    /// - Parameter validate: Checks one interpreted URL and returns the resolved URL. Defaults to `SearchRoot.validate`,
    ///   which reads the disk off the UI thread.
    public static func validate(
        _ inputs: [SearchRootInput],
        home: URL,
        validate: @Sendable (URL) async -> Result<URL, SearchRootError> = { await SearchRoot.validate($0) }
    ) async -> Result<[URL], Failure> {
        var roots: [URL] = []
        for (index, input) in inputs.enumerated() where !isBlank(input) {
            let url: URL
            switch input.resolvedInput(home: home) {
            case let .success(value):
                url = value
            case let .failure(error):
                return .failure(Failure(row: index, rowCount: inputs.count, error: error))
            }
            switch await validate(url) {
            case let .success(resolved):
                roots.append(resolved)
            case let .failure(error):
                return .failure(Failure(row: index, rowCount: inputs.count, error: error))
            }
        }
        guard !roots.isEmpty else {
            return .failure(Failure(row: 0, rowCount: inputs.count, error: .empty))
        }
        return .success(roots)
    }

    /// Merges roots that are the same folder and removes a root that another root's enumeration already traverses.
    /// Keeps the input order (the first occurrence of a duplicate keeps its position).
    ///
    /// A root `inner` below another root `outer` is removed only when no level from the child of `outer` down to
    /// `inner` itself is skipped by enumeration (hidden or a package; see `isSkippedByEnumeration`). Otherwise the
    /// enumeration of `outer` never enters `inner`, so both stay and results cannot overlap (EC-300 to EC-302).
    /// - Parameters:
    ///   - roots: Validated roots with symbolic links resolved.
    ///   - isSkipped: Whether enumeration skips a folder. Reads the file system; call off the UI thread.
    public static func organize(_ roots: [URL], isSkipped: (URL) -> Bool = SearchRootList.isSkippedByEnumeration) -> [URL] {
        var unique: [URL] = []
        var seen = Set<String>()
        for root in roots where seen.insert(SearchPath.normalized(root)).inserted {
            unique.append(root)
        }

        let paths = unique.map(SearchPath.normalized)
        return unique.enumerated().compactMap { index, root in
            let path = paths[index]
            let covered = paths.enumerated().contains { otherIndex, outer in
                otherIndex != index
                    && outer != path
                    && SearchPath.isSameOrWithin(path, outer)
                    && !hasSkippedLevel(from: outer, to: path, isSkipped: isSkipped)
            }
            return covered ? nil : root
        }
    }

    /// Whether the enumerator skips the folder: a name starting with ".", the hidden attribute, or a package.
    public static func isSkippedByEnumeration(_ url: URL) -> Bool {
        if url.lastPathComponent.hasPrefix(".") { return true }
        let values = try? url.resourceValues(forKeys: [.isHiddenKey, .isPackageKey])
        return values?.isHidden == true || values?.isPackage == true
    }

    /// Whether any level below `outer` down to and including `inner` is skipped by enumeration.
    private static func hasSkippedLevel(from outer: String, to inner: String, isSkipped: (URL) -> Bool) -> Bool {
        let outerComponents = outer == "/" ? [] : outer.split(separator: "/").map(String.init)
        let innerComponents = inner.split(separator: "/").map(String.init)
        var current = outer == "/" ? "" : outer
        for component in innerComponents.dropFirst(outerComponents.count) {
            current += "/" + component
            if isSkipped(URL(fileURLWithPath: current, isDirectory: true)) { return true }
        }
        return false
    }
}
