import Foundation

/// URL for the `..` row of a regular folder (`mvparent:///<absolute folder path>`). Creation and detection happen
/// only here. Do not pass it to `FileManager`, `NSWorkspace`, or the pasteboard (research.md R30).
public enum ParentLink {
    public static let scheme = "mvparent"

    /// Characters allowed in path elements. Starts with `.urlPathAllowed` and removes `#`, `?`, `%`, and `;`
    /// (the same as `ArchiveURL`).
    private static let pathElementAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "#?%;/")
        return set
    }()

    /// Returns the same URL for the same folder, including differences in a trailing `/` or `.`.
    public static func url(for folder: URL) -> URL {
        let path = folder.standardizedFileURL.path
        var components = URLComponents()
        components.scheme = scheme
        components.percentEncodedHost = ""
        components.percentEncodedPath = path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: pathElementAllowed) ?? "" }
            .joined(separator: "/")
        return components.url ?? URL(fileURLWithPath: "/")
    }

    public static func isParentLink(_ url: URL) -> Bool {
        url.scheme == scheme
    }
}
