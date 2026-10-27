import Foundation

/// Folders listed under Favorites at the top of the tree. Kept in registration order without duplicate locations
/// (FR-061–067).
public struct FavoriteFolders: Sendable, Equatable {
    public private(set) var urls: [URL]

    /// User-assigned display names. Keys are `key(_:)` (`standardizedFileURL.path`). Entries without a display name
    /// are omitted (R48).
    /// Invariants:
    /// - Every key is a key for a location registered in `urls`.
    /// - Every value has been normalized by `FavoriteName.normalized(_:)`: 1–255 characters, no newlines,
    ///   and no leading or trailing whitespace.
    private var customNames: [String: String]

    /// Removes duplicates keeping the first occurrence and preserves the order.
    /// Normalizes `customNames` keys with `key(_:)` and drops keys that are not registered and values that normalize to
    /// empty (R48, R49).
    public init(urls: [URL] = [], customNames: [String: String] = [:]) {
        var seen = Set<String>()
        self.urls = urls.filter { seen.insert(Self.key($0)).inserted }

        var names: [String: String] = [:]
        for (path, name) in customNames {
            let key = Self.key(URL(fileURLWithPath: path))
            guard seen.contains(key), let normalized = FavoriteName.normalized(name) else { continue }
            names[key] = normalized
        }
        self.customNames = names
    }

    public func contains(_ url: URL) -> Bool {
        let key = Self.key(url)
        return urls.contains { Self.key($0) == key }
    }

    /// Appends the URL and returns true when it is not registered; returns false without changes when it is (FR-062).
    @discardableResult
    public mutating func add(_ url: URL) -> Bool {
        guard !contains(url) else { return false }
        urls.append(url)
        return true
    }

    /// Removes only the registration. Does not touch the actual folder (FR-064). Also discards the display name
    /// (EC-44).
    @discardableResult
    public mutating func remove(_ url: URL) -> Bool {
        let key = Self.key(url)
        guard let index = urls.firstIndex(where: { Self.key($0) == key }) else { return false }
        urls.remove(at: index)
        customNames.removeValue(forKey: key)
        return true
    }

    /// The assigned display name, or nil when the URL is not registered or has no display name (FR-101).
    public func customName(for url: URL) -> String? {
        customNames[Self.key(url)]
    }

    /// Returns the display name when present; otherwise returns `defaultName` (FR-101).
    public func displayName(for url: URL, defaultName: String) -> String {
        customName(for: url) ?? defaultName
    }

    /// Applies the input committed from editing (FR-099, R50). Returns false for an unregistered location.
    /// Does nothing and returns false when the normalized result equals the current display name (committing the same
    /// name as `defaultName` for an item without a display name does not add one). A nil result clears the display
    /// name;
    /// any other result sets it and returns true. For an item that already has a display name, keeps a name equal to
    /// `defaultName` as the display name (EC-41).
    @discardableResult
    public mutating func commitDisplayName(_ input: String, for url: URL, defaultName: String) -> Bool {
        let key = Self.key(url)
        guard contains(url) else { return false }
        let normalized = FavoriteName.normalized(input)
        let current = displayName(for: url, defaultName: defaultName)
        if normalized == current { return false }
        if let normalized {
            customNames[key] = normalized
        } else {
            // Committed empty. No change when there is no display name to clear.
            guard customNames.removeValue(forKey: key) != nil else { return false }
        }
        return true
    }

    /// Persistent form: standardized absolute path → display name (R49).
    public var customNamesByPath: [String: String] { customNames }

    /// Identity key. URL equality is not used because it differs depending on a trailing `/`.
    private static func key(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

/// Whether a favorite item still exists as a folder at its registered location. Not persisted (FR-067).
public enum FavoriteAvailability: Sendable, Equatable {
    case unknown, available, missing
}
