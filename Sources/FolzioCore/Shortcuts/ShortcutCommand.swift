/// Identifies a command whose menu shortcut the user can change. The raw value is stored, so it never changes.
public enum ShortcutCommandID: String, CaseIterable, Sendable {
    // Panes and View
    case focusTree
    case focusFileList
    case focusPreview
    case fileListOnly
    case previewOnly
    case toolbar
    case thumbnails
    case list
    case largerThumbnails
    case smallerThumbnails
    case imagesOnly
    case videosOnly
    case zipVisibility
    // Folders and History
    case showContents
    case enclosingFolder
    case back
    case forward
    case goToFavorites
    case addToFavorites
    // Selection and Files
    case open
    case movePaste
    case copyPathname
    case duplicate
    case newFolder
    case trash
    // Search, Images, Video and Slideshow, App
    case find
    case zoomIn
    case zoomOut
    case zoomToFit
    case fullScreen
    case startSlideshow
    case shortcuts
}

/// Describes one customizable command: its default key, its reference section, and its alternates.
public struct ShortcutCommand: Equatable, Sendable {
    public let id: ShortcutCommandID
    public let defaultCombination: KeyCombination
    public let section: ShortcutSection
    /// Extra keys that work only while the command keeps its default key (for example ⌘= for zoom in).
    public let alternates: [KeyCombination]

    public init(
        id: ShortcutCommandID,
        defaultCombination: KeyCombination,
        section: ShortcutSection,
        alternates: [KeyCombination] = []
    ) {
        self.id = id
        self.defaultCombination = defaultCombination
        self.section = section
        self.alternates = alternates
    }
}

public enum ShortcutCommands {
    private static func key(_ key: String, _ modifiers: KeyModifiers) -> KeyCombination {
        KeyCombination(key: key, modifiers: modifiers)
    }

    /// All customizable commands in the order of the settings list. The order also decides which of two conflicting
    /// stored values is dropped when loading.
    public static let all: [ShortcutCommand] = [
        ShortcutCommand(id: .focusTree, defaultCombination: key("1", [.option, .command]), section: .panes),
        ShortcutCommand(id: .focusFileList, defaultCombination: key("2", [.option, .command]), section: .panes),
        ShortcutCommand(id: .focusPreview, defaultCombination: key("3", [.option, .command]), section: .panes),
        ShortcutCommand(id: .fileListOnly, defaultCombination: key("2", [.control, .command]), section: .panes),
        ShortcutCommand(id: .previewOnly, defaultCombination: key("3", [.control, .command]), section: .panes),
        ShortcutCommand(id: .toolbar, defaultCombination: key("t", [.shift, .command]), section: .panes),
        ShortcutCommand(id: .thumbnails, defaultCombination: key("1", [.command]), section: .panes),
        ShortcutCommand(id: .list, defaultCombination: key("2", [.command]), section: .panes),
        ShortcutCommand(id: .largerThumbnails, defaultCombination: key(".", [.control, .command]), section: .panes),
        ShortcutCommand(id: .smallerThumbnails, defaultCombination: key(",", [.control, .command]), section: .panes),
        ShortcutCommand(id: .imagesOnly, defaultCombination: key("i", [.shift, .command]), section: .panes),
        ShortcutCommand(id: .videosOnly, defaultCombination: key("m", [.shift, .command]), section: .panes),
        ShortcutCommand(id: .zipVisibility, defaultCombination: key("z", [.control, .command]), section: .panes),
        ShortcutCommand(id: .showContents, defaultCombination: key("down", [.command]), section: .navigation),
        ShortcutCommand(id: .enclosingFolder, defaultCombination: key("up", [.command]), section: .navigation),
        ShortcutCommand(id: .back, defaultCombination: key("[", [.command]), section: .navigation),
        ShortcutCommand(id: .forward, defaultCombination: key("]", [.command]), section: .navigation),
        ShortcutCommand(id: .goToFavorites, defaultCombination: key("f", [.shift, .command]), section: .navigation),
        ShortcutCommand(id: .addToFavorites, defaultCombination: key("t", [.control, .command]), section: .navigation),
        ShortcutCommand(id: .open, defaultCombination: key("o", [.command]), section: .files),
        ShortcutCommand(id: .movePaste, defaultCombination: key("v", [.option, .command]), section: .files),
        ShortcutCommand(id: .copyPathname, defaultCombination: key("c", [.option, .command]), section: .files),
        ShortcutCommand(id: .duplicate, defaultCombination: key("d", [.command]), section: .files),
        ShortcutCommand(id: .newFolder, defaultCombination: key("n", [.shift, .command]), section: .files),
        ShortcutCommand(id: .trash, defaultCombination: key("delete", [.command]), section: .files),
        ShortcutCommand(id: .find, defaultCombination: key("f", [.command]), section: .search),
        ShortcutCommand(
            id: .zoomIn, defaultCombination: key("+", [.command]), section: .images,
            alternates: [key("=", [.command])]
        ),
        ShortcutCommand(id: .zoomOut, defaultCombination: key("-", [.command]), section: .images),
        ShortcutCommand(id: .zoomToFit, defaultCombination: key("0", [.command]), section: .images),
        ShortcutCommand(id: .fullScreen, defaultCombination: key("f", [.control, .command]), section: .images),
        ShortcutCommand(id: .startSlideshow, defaultCombination: key("s", [.shift, .command]), section: .playback),
        ShortcutCommand(id: .shortcuts, defaultCombination: key("/", [.command]), section: .application),
    ]

    public static func command(_ id: ShortcutCommandID) -> ShortcutCommand {
        // `all` holds every case; the lookup cannot fail.
        all.first { $0.id == id }!
    }
}

/// Keys whose meaning depends on focus or context. They are neither assignable nor usable as a default.
public enum FixedShortcutKeys {
    public static let combinations: Set<KeyCombination> = {
        var set: Set<KeyCombination> = []
        for arrow in ["up", "down", "left", "right"] {
            for modifiers: KeyModifiers in [[], [.shift], [.option]] {
                set.insert(KeyCombination(key: arrow, modifiers: modifiers))
            }
        }
        for key in ["return", "escape", "tab", "space", "delete", "<", ">"] {
            set.insert(KeyCombination(key: key, modifiers: []))
        }
        set.insert(KeyCombination(key: "tab", modifiers: [.shift]))
        set.insert(KeyCombination(key: "a", modifiers: [.command]))
        return set
    }()
}

/// Keys of app and system basics that cannot be reassigned.
public enum ReservedShortcutKeys {
    public static let combinations: Set<KeyCombination> = [
        KeyCombination(key: ".", modifiers: [.command]),
        KeyCombination(key: "q", modifiers: [.command]),
        KeyCombination(key: "w", modifiers: [.command]),
        KeyCombination(key: ",", modifiers: [.command]),
        KeyCombination(key: "z", modifiers: [.command]),
        KeyCombination(key: "z", modifiers: [.shift, .command]),
        KeyCombination(key: "x", modifiers: [.command]),
        KeyCombination(key: "c", modifiers: [.command]),
        KeyCombination(key: "v", modifiers: [.command]),
        KeyCombination(key: "h", modifiers: [.command]),
        KeyCombination(key: "h", modifiers: [.option, .command]),
        KeyCombination(key: "m", modifiers: [.command]),
        KeyCombination(key: "tab", modifiers: [.command]),
        KeyCombination(key: "tab", modifiers: [.shift, .command]),
        KeyCombination(key: "`", modifiers: [.command]),
        KeyCombination(key: "space", modifiers: [.command]),
    ]
}
