import FolzioCore
import Testing

@Suite("Shortcut Command Consistency")
struct ShortcutCommandConsistencyTests {
    @Test("There are 32 commands, one definition per ID")
    func commandsCoverEveryID() {
        #expect(ShortcutCommandID.allCases.count == 32)
        #expect(ShortcutCommands.all.count == 32)
        #expect(Set(ShortcutCommands.all.map(\.id)) == Set(ShortcutCommandID.allCases))
    }

    @Test("No two commands share a default key or an alternate")
    func defaultsAreUnique() {
        var seen: [KeyCombination: ShortcutCommandID] = [:]
        for command in ShortcutCommands.all {
            for combination in [command.defaultCombination] + command.alternates {
                #expect(seen[combination] == nil, "\(command.id) duplicates \(String(describing: seen[combination]))")
                seen[combination] = command.id
            }
        }
    }

    @Test("Every default satisfies the modifier rule and avoids fixed and reserved keys")
    func defaultsAreAssignable() {
        for command in ShortcutCommands.all {
            for combination in [command.defaultCombination] + command.alternates {
                #expect(combination.hasRequiredModifier, "\(command.id)")
                #expect(!FixedShortcutKeys.combinations.contains(combination), "\(command.id)")
                #expect(!ReservedShortcutKeys.combinations.contains(combination), "\(command.id)")
            }
        }
    }

    @Test("Default keys match the approved shortcut contract")
    func defaultsMatchContract() {
        let expected: [ShortcutCommandID: String] = [
            .focusTree: "⌥⌘1", .focusFileList: "⌥⌘2", .focusPreview: "⌥⌘3", .fileListOnly: "⌃⌘2",
            .previewOnly: "⌃⌘3", .toolbar: "⇧⌘T", .thumbnails: "⌘1", .list: "⌘2",
            .largerThumbnails: "⌃⌘.", .smallerThumbnails: "⌃⌘,", .imagesOnly: "⇧⌘I", .videosOnly: "⇧⌘M",
            .zipVisibility: "⌃⌘Z", .showContents: "⌘↓", .enclosingFolder: "⌘↑", .back: "⌘[", .forward: "⌘]",
            .goToFavorites: "⇧⌘F", .addToFavorites: "⌃⌘T", .open: "⌘O", .movePaste: "⌥⌘V",
            .copyPathname: "⌥⌘C", .duplicate: "⌘D", .newFolder: "⇧⌘N", .trash: "⌘Delete", .find: "⌘F",
            .zoomIn: "⌘+", .zoomOut: "⌘-", .zoomToFit: "⌘0", .fullScreen: "⌃⌘F", .startSlideshow: "⇧⌘S",
            .shortcuts: "⌘/",
        ]
        #expect(expected.count == 32)
        for command in ShortcutCommands.all {
            #expect(command.defaultCombination.displayText == expected[command.id], "\(command.id)")
        }
    }

    @Test("Reference entries built from the default assignments equal their static keys")
    func catalogMatchesDefaults() {
        let assignments = ShortcutAssignments()
        for entry in ShortcutCatalog.entries {
            #expect(entry.keys(using: assignments) == entry.keys, "\(entry.id)")
        }
    }

    @Test("Changing a command changes the reference entries that show it")
    func catalogFollowsAssignments() throws {
        let changed = try ShortcutAssignments()
            .assigning(KeyCombination(key: "j", modifiers: [.option, .command]), to: .back)
            .get()
        let history = try #require(ShortcutCatalog.entries.first { $0.id == .history })
        #expect(history.keys(using: changed) == "⌥⌘J / ⌘]")
        let endSearch = try #require(ShortcutCatalog.entries.first { $0.id == .endSearch })
        #expect(endSearch.keys(using: changed) == "Esc / ⌥⌘J")
    }

    @Test("The zoom entry shows the alternate only while zoom in keeps its default key")
    func zoomAlternate() throws {
        let zoom = try #require(ShortcutCatalog.entries.first { $0.id == .imageZoom })
        #expect(zoom.keys(using: ShortcutAssignments()) == "⌘+ / ⌘= / ⌘-")
        let changed = try ShortcutAssignments()
            .assigning(KeyCombination(key: "j", modifiers: [.option, .command]), to: .zoomIn)
            .get()
        #expect(zoom.keys(using: changed) == "⌥⌘J / ⌘-")
    }

    @Test("An unset command shows the given text in the reference entries")
    func catalogShowsUnset() throws {
        let assignments = ShortcutAssignments().unsetting(.back)
        let history = try #require(ShortcutCatalog.entries.first { $0.id == .history })
        #expect(history.keys(using: assignments, unsetText: "Not Set") == "Not Set / ⌘]")
        let zoom = try #require(ShortcutCatalog.entries.first { $0.id == .imageZoom })
        #expect(zoom.keys(using: ShortcutAssignments().unsetting(.zoomIn), unsetText: "Not Set") == "Not Set / ⌘-")
    }
}
