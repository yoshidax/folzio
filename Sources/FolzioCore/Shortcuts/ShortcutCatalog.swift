/// Groups the shortcut reference by user intent, in display order.
public enum ShortcutSection: String, CaseIterable, Sendable {
    case panes
    case navigation
    case files
    case search
    case images
    case playback
    case application

    public var entries: [ShortcutEntry] {
        ShortcutCatalog.entries.filter { $0.section == self }
    }
}

/// Identifies a reference entry independently of its language and key glyphs.
public enum ShortcutID: String, CaseIterable, Sendable {
    case paneCycle
    case paneFocus
    case listOnly
    case previewOnly
    case toolbar
    case listStyle
    case thumbnailSize
    case imageFilter
    case movieFilter
    case zipVisibility
    case treeSelect
    case treeExpand
    case treeExpandAll
    case openContainer
    case enclosingFolder
    case history
    case favorites
    case addFavorite
    case selection
    case extendSelection
    case openDefault
    case quickLook
    case rename
    case copy
    case paste
    case cancelReceiving
    case copyPath
    case duplicate
    case newFolder
    case trash
    case find
    case searchSubmit
    case endSearch
    case imageZoom
    case imageFit
    case imageScroll
    case fullScreen
    case videoPlay
    case videoControls
    case videoSeek
    case slideshowStart
    case slideshowNavigate
    case slideshowStop
    case settings
    case cheatsheet
    case close
    case quit
}

/// Describes a shortcut without UI, translation, or command execution dependencies.
public struct ShortcutEntry: Equatable, Sendable {
    public let id: ShortcutID
    /// The default keys as shown in the reference.
    public let keys: String
    public let section: ShortcutSection
    /// How `keys` is built from the current assignments, or nil when the keys never change.
    public let parts: [ShortcutKeyPart]?

    public init(id: ShortcutID, keys: String, section: ShortcutSection, parts: [ShortcutKeyPart]? = nil) {
        self.id = id
        self.keys = keys
        self.section = section
        self.parts = parts
    }

    /// The keys to show for the given assignments. `unsetText` stands in for the key of an unset command.
    public func keys(using assignments: ShortcutAssignments, unsetText: String = "-") -> String {
        guard let parts else { return keys }
        return parts.map { $0.displayText(using: assignments, unsetText: unsetText) }.joined()
    }
}

/// One piece of an entry's keys: fixed text, or the current key of a command.
public enum ShortcutKeyPart: Equatable, Sendable {
    case text(String)
    case command(ShortcutCommandID)
    /// The command's key followed by its active alternates, separated by " / ".
    case commandWithAlternates(ShortcutCommandID)

    public func displayText(using assignments: ShortcutAssignments, unsetText: String = "-") -> String {
        switch self {
        case .text(let text):
            return text
        case .command(let id):
            return assignments.combination(for: id)?.displayText ?? unsetText
        case .commandWithAlternates(let id):
            guard let combination = assignments.combination(for: id) else { return unsetText }
            let keys = [combination] + assignments.activeAlternates(for: id)
            return keys.map(\.displayText).joined(separator: " / ")
        }
    }
}

/// Provides the fixed shortcut reference. Context-specific uses of a key have separate entry IDs.
public enum ShortcutCatalog {
    public static let entries: [ShortcutEntry] = [
        ShortcutEntry(id: .paneCycle, keys: "Tab / ⇧Tab", section: .panes),
        ShortcutEntry(id: .paneFocus, keys: "⌥⌘1 / ⌥⌘2 / ⌥⌘3", section: .panes, parts: [
            .command(.focusTree), .text(" / "), .command(.focusFileList), .text(" / "), .command(.focusPreview),
        ]),
        ShortcutEntry(id: .listOnly, keys: "⌃⌘2", section: .panes, parts: [.command(.fileListOnly)]),
        ShortcutEntry(id: .previewOnly, keys: "⌃⌘3", section: .panes, parts: [.command(.previewOnly)]),
        ShortcutEntry(id: .toolbar, keys: "⇧⌘T", section: .panes, parts: [.command(.toolbar)]),
        ShortcutEntry(id: .listStyle, keys: "⌘1 / ⌘2", section: .panes, parts: [.command(.thumbnails), .text(" / "), .command(.list)]),
        ShortcutEntry(id: .thumbnailSize, keys: "⌃⌘. / ⌃⌘,", section: .panes, parts: [
            .command(.largerThumbnails), .text(" / "), .command(.smallerThumbnails),
        ]),
        ShortcutEntry(id: .imageFilter, keys: "⇧⌘I", section: .panes, parts: [.command(.imagesOnly)]),
        ShortcutEntry(id: .movieFilter, keys: "⇧⌘M", section: .panes, parts: [.command(.videosOnly)]),
        ShortcutEntry(id: .zipVisibility, keys: "⌃⌘Z", section: .panes, parts: [.command(.zipVisibility)]),
        ShortcutEntry(id: .treeSelect, keys: "↑ / ↓", section: .navigation),
        ShortcutEntry(id: .treeExpand, keys: "→ / ←", section: .navigation),
        ShortcutEntry(id: .treeExpandAll, keys: "⌥→ / ⌥←", section: .navigation),
        ShortcutEntry(id: .openContainer, keys: "⌘↓", section: .navigation, parts: [.command(.showContents)]),
        ShortcutEntry(id: .enclosingFolder, keys: "⌘↑", section: .navigation, parts: [.command(.enclosingFolder)]),
        ShortcutEntry(id: .history, keys: "⌘[ / ⌘]", section: .navigation, parts: [.command(.back), .text(" / "), .command(.forward)]),
        ShortcutEntry(id: .favorites, keys: "⇧⌘F", section: .navigation, parts: [.command(.goToFavorites)]),
        ShortcutEntry(id: .addFavorite, keys: "⌃⌘T", section: .navigation, parts: [.command(.addToFavorites)]),
        ShortcutEntry(id: .selection, keys: "↑ / ↓ / ← / →", section: .files),
        ShortcutEntry(id: .extendSelection, keys: "⇧↑ / ⇧↓ / ⇧← / ⇧→ / ⌘A", section: .files),
        ShortcutEntry(id: .openDefault, keys: "⌘O", section: .files, parts: [.command(.open)]),
        ShortcutEntry(id: .quickLook, keys: "Space", section: .files),
        ShortcutEntry(id: .rename, keys: "Return", section: .files),
        ShortcutEntry(id: .copy, keys: "⌘C", section: .files),
        ShortcutEntry(id: .cancelReceiving, keys: "⌘.", section: .files),
        ShortcutEntry(id: .paste, keys: "⌘V / ⌥⌘V", section: .files, parts: [.text("⌘V / "), .command(.movePaste)]),
        ShortcutEntry(id: .copyPath, keys: "⌥⌘C", section: .files, parts: [.command(.copyPathname)]),
        ShortcutEntry(id: .duplicate, keys: "⌘D", section: .files, parts: [.command(.duplicate)]),
        ShortcutEntry(id: .newFolder, keys: "⇧⌘N", section: .files, parts: [.command(.newFolder)]),
        ShortcutEntry(id: .trash, keys: "⌘Delete", section: .files, parts: [.command(.trash)]),
        ShortcutEntry(id: .find, keys: "⌘F", section: .search, parts: [.command(.find)]),
        ShortcutEntry(id: .searchSubmit, keys: "Return / Esc", section: .search),
        ShortcutEntry(id: .endSearch, keys: "Esc / ⌘[", section: .search, parts: [.text("Esc / "), .command(.back)]),
        ShortcutEntry(id: .imageZoom, keys: "⌘+ / ⌘= / ⌘-", section: .images, parts: [
            .commandWithAlternates(.zoomIn), .text(" / "), .command(.zoomOut),
        ]),
        ShortcutEntry(id: .imageFit, keys: "⌘0", section: .images, parts: [.command(.zoomToFit)]),
        ShortcutEntry(id: .imageScroll, keys: "⌥↑ / ⌥↓ / ⌥← / ⌥→", section: .images),
        ShortcutEntry(id: .fullScreen, keys: "⌃⌘F", section: .images, parts: [.command(.fullScreen)]),
        ShortcutEntry(id: .videoPlay, keys: "Space", section: .playback),
        ShortcutEntry(id: .videoControls, keys: "← / → / ↑ / ↓", section: .playback),
        ShortcutEntry(id: .videoSeek, keys: "< / >", section: .playback),
        ShortcutEntry(id: .slideshowStart, keys: "⇧⌘S", section: .playback, parts: [.command(.startSlideshow)]),
        ShortcutEntry(id: .slideshowNavigate, keys: "↑ / ↓ / ← / →", section: .playback),
        ShortcutEntry(id: .slideshowStop, keys: "Esc", section: .playback),
        ShortcutEntry(id: .settings, keys: "⌘,", section: .application),
        ShortcutEntry(id: .cheatsheet, keys: "⌘/", section: .application, parts: [.command(.shortcuts)]),
        ShortcutEntry(id: .close, keys: "⌘W", section: .application),
        ShortcutEntry(id: .quit, keys: "⌘Q", section: .application),
    ]
}
