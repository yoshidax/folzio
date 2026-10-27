import Foundation

/// URL for an entry inside a zip (`mvzip:///<entry path>?archive=<absolute zip path>`). Creation and parsing
/// happen only here.
public enum ArchiveURL {
    public static let scheme = "mvzip"

    private static let archiveQueryName = "archive"
    private static let parentFragment = "parent"

    /// Characters allowed in path elements. Starts with `.urlPathAllowed` and removes `#`, `?`, `%`, and `;`.
    private static let pathElementAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "#?%;/")
        return set
    }()

    /// Characters allowed in query values. Does not keep characters that could act as separators.
    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~/")
        return set
    }()

    /// URL for an entry. Directories end the path with `/`. The root has an empty path.
    public static func entry(archive: URL, path: String) -> URL {
        makeURL(archive: archive, path: path, fragment: nil)
    }

    /// URL for the `..` row: the current directory URL with `#parent` appended.
    public static func parentLink(of location: ArchiveLocation) -> URL {
        makeURL(archive: location.archive, path: location.directory, fragment: parentFragment)
    }

    /// Returns nil for schemes other than `mvzip` or URLs without a zip specification.
    public static func parse(_ url: URL) -> (archive: URL, path: String, isParentLink: Bool)? {
        guard url.scheme == scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let item = components.percentEncodedQueryItems?.first(where: { $0.name == archiveQueryName }),
              let encodedArchive = item.value,
              let archivePath = encodedArchive.removingPercentEncoding,
              !archivePath.isEmpty,
              let decodedPath = components.percentEncodedPath.removingPercentEncoding
        else { return nil }

        let path = decodedPath.hasPrefix("/") ? String(decodedPath.dropFirst()) : decodedPath
        return (
            archive: URL(fileURLWithPath: archivePath),
            path: path,
            isParentLink: components.fragment == parentFragment
        )
    }

    private static func makeURL(archive: URL, path: String, fragment: String?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.percentEncodedHost = ""
        components.percentEncodedPath = "/" + encodePath(path)
        let archiveValue = archive.path.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? ""
        components.percentEncodedQueryItems = [URLQueryItem(name: archiveQueryName, value: archiveValue)]
        components.fragment = fragment
        return components.url ?? URL(fileURLWithPath: "/")
    }

    private static func encodePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: pathElementAllowed) ?? "" }
            .joined(separator: "/")
    }
}
