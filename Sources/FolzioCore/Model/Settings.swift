import Foundation

public struct ViewSettings: Sendable, Equatable {
    public static let defaultThumbnailSize: Double = 128
    public static let minimumThumbnailSize: Double = 48
    public static let maximumThumbnailSize: Double = 512

    public var displayMode: DisplayMode
    public var sortOrder: SortOrder
    public var lastFolder: URL?
    public var showsToolbar: Bool
    /// Whether zip file rows appear in the file list (FR-095). Hidden by default.
    public var showsZipFiles: Bool
    private var storedThumbnailSize: Double

    public var thumbnailSize: Double {
        get { storedThumbnailSize }
        set { storedThumbnailSize = Self.clampThumbnailSize(newValue) }
    }

    public init(
        displayMode: DisplayMode = .list,
        thumbnailSize: Double = defaultThumbnailSize,
        sortOrder: SortOrder = SortOrder(),
        lastFolder: URL? = nil,
        showsToolbar: Bool = false,
        showsZipFiles: Bool = false
    ) {
        self.displayMode = displayMode
        self.storedThumbnailSize = Self.clampThumbnailSize(thumbnailSize)
        self.sortOrder = sortOrder
        self.lastFolder = lastFolder
        self.showsToolbar = showsToolbar
        self.showsZipFiles = showsZipFiles
    }

    public static func clampThumbnailSize(_ value: Double) -> Double {
        guard value.isFinite else { return defaultThumbnailSize }
        return min(max(value, minimumThumbnailSize), maximumThumbnailSize)
    }
}

public enum DisplayMode: String, Sendable, CaseIterable {
    case list
    case thumbnails
}

public enum SortColumn: String, Sendable, CaseIterable {
    case name
    case creationDate
    case kind
    /// Used only while showing search results (FR-084). Not persisted.
    case location
}

public struct SortOrder: Sendable, Equatable {
    public var column: SortColumn
    public var ascending: Bool

    public init(column: SortColumn = .name, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }
}

public struct PlaybackOptions: Sendable, Equatable {
    public var autoplay: Bool
    public var loop: Bool

    public init(autoplay: Bool = true, loop: Bool = true) {
        self.autoplay = autoplay
        self.loop = loop
    }
}

public enum SlideshowTransitionEffect: String, Sendable, CaseIterable {
    case none
    case crossfade
    case slide
    case zoom

    public func effective(reduceMotion: Bool) -> SlideshowTransitionEffect {
        if reduceMotion, self == .slide || self == .zoom { return .crossfade }
        return self
    }
}

public struct SlideshowOptions: Sendable, Equatable {
    public static let intervalRange = 1...3600
    public static let defaultIntervalSeconds = 3
    public static let defaults = SlideshowOptions()

    private var storedIntervalSeconds: Int

    public var intervalSeconds: Int {
        get { storedIntervalSeconds }
        set {
            storedIntervalSeconds = Self.intervalRange.contains(newValue)
                ? newValue : Self.defaultIntervalSeconds
        }
    }
    /// A setting independent of video loop playback (`PlaybackOptions.loop`).
    public var repeats: Bool
    public var transition: SlideshowTransitionEffect

    public var interval: Duration { .seconds(intervalSeconds) }

    /// Uses 3 seconds for an out-of-range `intervalSeconds`.
    public init(
        intervalSeconds: Int = 3,
        repeats: Bool = true,
        transition: SlideshowTransitionEffect = .none
    ) {
        self.storedIntervalSeconds = Self.intervalRange.contains(intervalSeconds)
            ? intervalSeconds : Self.defaultIntervalSeconds
        self.repeats = repeats
        self.transition = transition
    }
}

public struct ConfirmationOptions: Sendable, Equatable {
    public var confirmBeforeFileOperations: Bool

    public init(confirmBeforeFileOperations: Bool = true) {
        self.confirmBeforeFileOperations = confirmBeforeFileOperations
    }
}
