import Foundation

/// Display language saved by the app. Independent of the OS preferred languages.
public enum DisplayLanguageSetting: String, CaseIterable, Sendable {
    case english = "en"
    case japanese = "ja"
}

public struct SettingsStore {
    private enum Keys {
        static let displayLanguage = "appearance.language"
        static let displayMode = "view.displayMode"
        static let thumbnailSize = "view.thumbnailSize"
        static let sortColumn = "view.sort.column"
        static let sortAscending = "view.sort.ascending"
        static let lastFolderPath = "view.lastFolderPath"
        static let showsToolbar = "view.showsToolbar"
        static let showsZipFiles = "view.showsZipFiles"
        static let autoplay = "playback.autoplay"
        static let loop = "playback.loop"
        static let confirmBeforeExecuting = "fileOps.confirmBeforeExecuting"
        static let favoritePaths = "favorites.paths"
        static let favoriteDisplayNames = "favorites.displayNames"
        static let slideshowIntervalSeconds = "slideshow.intervalSeconds"
        static let slideshowRepeats = "slideshow.repeats"
        static let slideshowTransition = "slideshow.transition"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var displayLanguage: DisplayLanguageSetting {
        get {
            (defaults.object(forKey: Keys.displayLanguage) as? String)
                .flatMap(DisplayLanguageSetting.init(rawValue:)) ?? .english
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Keys.displayLanguage)
        }
    }

    public var viewSettings: ViewSettings {
        get {
            let displayMode = (defaults.object(forKey: Keys.displayMode) as? String)
                .flatMap(DisplayMode.init(rawValue:)) ?? .list
            let thumbnailSize = storedDouble(forKey: Keys.thumbnailSize)
                ?? ViewSettings.defaultThumbnailSize
            // Location is used only while showing search results and is not persisted (FR-084). If present, fall back
            // to name.
            let column = (defaults.object(forKey: Keys.sortColumn) as? String)
                .flatMap(SortColumn.init(rawValue:))
                .flatMap { $0 == .location ? nil : $0 } ?? .name
            let ascending = storedBool(forKey: Keys.sortAscending) ?? true
            let lastFolder = (defaults.object(forKey: Keys.lastFolderPath) as? String)
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            let showsToolbar = storedBool(forKey: Keys.showsToolbar) ?? false
            let showsZipFiles = storedBool(forKey: Keys.showsZipFiles) ?? false

            return ViewSettings(
                displayMode: displayMode,
                thumbnailSize: thumbnailSize,
                sortOrder: SortOrder(column: column, ascending: ascending),
                lastFolder: lastFolder,
                showsToolbar: showsToolbar,
                showsZipFiles: showsZipFiles
            )
        }
        nonmutating set {
            defaults.set(newValue.displayMode.rawValue, forKey: Keys.displayMode)
            defaults.set(newValue.thumbnailSize, forKey: Keys.thumbnailSize)
            if newValue.sortOrder.column != .location {
                defaults.set(newValue.sortOrder.column.rawValue, forKey: Keys.sortColumn)
                defaults.set(newValue.sortOrder.ascending, forKey: Keys.sortAscending)
            }
            if let lastFolder = newValue.lastFolder {
                defaults.set(lastFolder.path, forKey: Keys.lastFolderPath)
            } else {
                defaults.removeObject(forKey: Keys.lastFolderPath)
            }
            defaults.set(newValue.showsToolbar, forKey: Keys.showsToolbar)
            defaults.set(newValue.showsZipFiles, forKey: Keys.showsZipFiles)
        }
    }

    public var playback: PlaybackOptions {
        get {
            PlaybackOptions(
                autoplay: storedBool(forKey: Keys.autoplay) ?? true,
                loop: storedBool(forKey: Keys.loop) ?? true
            )
        }
        nonmutating set {
            defaults.set(newValue.autoplay, forKey: Keys.autoplay)
            defaults.set(newValue.loop, forKey: Keys.loop)
        }
    }

    public var confirmation: ConfirmationOptions {
        get {
            ConfirmationOptions(
                confirmBeforeFileOperations: storedBool(forKey: Keys.confirmBeforeExecuting) ?? true
            )
        }
        nonmutating set {
            defaults.set(
                newValue.confirmBeforeFileOperations,
                forKey: Keys.confirmBeforeExecuting
            )
        }
    }

    /// Validates each item independently. Only invalid items fall back to defaults; other items keep their stored
    /// values.
    public var slideshow: SlideshowOptions {
        get {
            let transition = (defaults.object(forKey: Keys.slideshowTransition) as? String)
                .flatMap(SlideshowTransitionEffect.init(rawValue:)) ?? .none
            return SlideshowOptions(
                intervalSeconds: storedInterval(forKey: Keys.slideshowIntervalSeconds)
                    ?? SlideshowOptions.defaultIntervalSeconds,
                repeats: storedBool(forKey: Keys.slideshowRepeats) ?? true,
                transition: transition
            )
        }
        nonmutating set {
            defaults.set(newValue.intervalSeconds, forKey: Keys.slideshowIntervalSeconds)
            defaults.set(newValue.repeats, forKey: Keys.slideshowRepeats)
            defaults.set(newValue.transition.rawValue, forKey: Keys.slideshowTransition)
        }
    }

    /// Persisted as an array of absolute paths. A non-array reads as empty; non-string elements, empty strings, and
    /// relative paths are dropped (FR-066). Display names are stored in `favorites.displayNames` (standardized
    /// absolute path → display name) only for items that have one. The legacy format (only `favorites.paths`) reads
    /// as having no display names. There is no migration (R49).
    public var favorites: FavoriteFolders {
        get {
            guard let stored = defaults.object(forKey: Keys.favoritePaths) as? [Any] else {
                return FavoriteFolders()
            }
            let urls = stored
                .compactMap { $0 as? String }
                .filter { !$0.isEmpty && $0.hasPrefix("/") }
                .map { URL(fileURLWithPath: $0, isDirectory: true) }
            // No display names when not a dictionary. The initializer drops unregistered paths and values that
            // normalize to empty, normalizes values, and truncates to 255 characters.
            let names = (defaults.object(forKey: Keys.favoriteDisplayNames) as? [String: Any])?
                .compactMapValues { $0 as? String } ?? [:]
            return FavoriteFolders(urls: urls, customNames: names)
        }
        nonmutating set {
            defaults.set(newValue.urls.map(\.path), forKey: Keys.favoritePaths)
            if newValue.customNamesByPath.isEmpty {
                defaults.removeObject(forKey: Keys.favoriteDisplayNames)
            } else {
                defaults.set(newValue.customNamesByPath, forKey: Keys.favoriteDisplayNames)
            }
        }
    }

    private func storedBool(forKey key: String) -> Bool? {
        defaults.object(forKey: key) as? Bool
    }

    /// Returns the value only when it is a numeric value (not a Boolean), converts exactly to Int, and is in the
    /// 1–3600 range.
    private func storedInterval(forKey key: String) -> Int? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let value = Int(exactly: number),
              SlideshowOptions.intervalRange.contains(value)
        else { return nil }
        return value
    }

    private func storedDouble(forKey key: String) -> Double? {
        guard let value = defaults.object(forKey: key) as? Double, value.isFinite else {
            return nil
        }
        return value
    }
}
