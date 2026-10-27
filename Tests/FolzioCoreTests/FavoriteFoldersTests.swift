import Foundation
import Testing
@testable import FolzioCore

@Suite("FavoriteFolders")
struct FavoriteFoldersTests {
    private let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
    private let b = URL(fileURLWithPath: "/tmp/fav/b", isDirectory: true)
    private let c = URL(fileURLWithPath: "/tmp/fav/c", isDirectory: true)
    private let d = URL(fileURLWithPath: "/tmp/fav/d", isDirectory: true)

    /// Alternative spellings for the same location as registered a (including a trailing `/` and `..`).
    private var aliasesOfA: [URL] {
        [
            a,
            URL(fileURLWithPath: "/tmp/fav/a/"),
            URL(fileURLWithPath: "/tmp/fav/x/../a"),
        ]
    }

    @Test("Defaults to empty")
    func defaultsToEmpty() {
        #expect(FavoriteFolders().urls.isEmpty)
    }

    @Test("add appends in registration order")
    func addAppendsInOrder() {
        var favorites = FavoriteFolders()
        let added = [a, b, c].map { favorites.add($0) }
        #expect(added == [true, true, true])
        #expect(favorites.urls == [a, b, c])
    }

    @Test("Does not add an already registered location with a different path representation")
    func addRejectsDuplicates() {
        var favorites = FavoriteFolders(urls: [a])
        for alias in aliasesOfA {
            let added = favorites.add(alias)
            #expect(!added, "\(alias.path)")
            #expect(favorites.urls == [a])
        }
    }

    @Test("contains treats different path representations as the same location")
    func containsMatchesAliases() {
        let favorites = FavoriteFolders(urls: [a])
        for alias in aliasesOfA {
            #expect(favorites.contains(alias), "\(alias.path)")
        }
        #expect(!favorites.contains(d))
    }

    @Test("remove deletes only registered locations and preserves order")
    func removeKeepsOrder() {
        var favorites = FavoriteFolders(urls: [a, b, c])
        let removedB = favorites.remove(b)
        #expect(removedB)
        #expect(favorites.urls == [a, c])

        let removedD = favorites.remove(d)
        #expect(!removedD)
        #expect(favorites.urls == [a, c])
    }

    @Test("remove also accepts path representations containing ..")
    func removeMatchesAliases() {
        var favorites = FavoriteFolders(urls: [a, b, c])
        let removed = favorites.remove(URL(fileURLWithPath: "/tmp/fav/x/../b"))
        #expect(removed)
        #expect(favorites.urls == [a, c])
    }

    @Test("init(urls:) removes duplicates using the first occurrence and preserves order")
    func initRemovesDuplicates() {
        let favorites = FavoriteFolders(urls: [a, b, a, c, b])
        #expect(favorites.urls == [a, b, c])
    }

    // MARK: - Display Names (FR-099–101; R48, R50)

    @Test("Setting a display name updates customName and displayName")
    func commitSetsDisplayName() {
        var favorites = FavoriteFolders(urls: [a, b])
        let changed = favorites.commitDisplayName("2025（バックアップ）", for: b, defaultName: "2025")
        #expect(changed)
        #expect(favorites.customName(for: b) == "2025（バックアップ）")
        #expect(favorites.displayName(for: b, defaultName: "2025") == "2025（バックアップ）")
        #expect(favorites.customName(for: a) == nil)
        #expect(favorites.displayName(for: a, defaultName: "a") == "a")
    }

    @Test("Changes to a different name")
    func commitChangesDisplayName() {
        var favorites = FavoriteFolders(urls: [a])
        favorites.commitDisplayName("one", for: a, defaultName: "a")
        let changed = favorites.commitDisplayName("two", for: a, defaultName: "a")
        #expect(changed)
        #expect(favorites.customName(for: a) == "two")
    }

    @Test("Committing an empty or whitespace-only name clears the display name")
    func commitBlankClearsDisplayName() {
        for blank in ["", "   "] {
            var favorites = FavoriteFolders(urls: [a])
            favorites.commitDisplayName("one", for: a, defaultName: "a")
            let changed = favorites.commitDisplayName(blank, for: a, defaultName: "a")
            #expect(changed, "\(blank.debugDescription)")
            #expect(favorites.customName(for: a) == nil)
            #expect(favorites.displayName(for: a, defaultName: "a") == "a")
        }
    }

    @Test("Committing the current display name changes nothing")
    func commitSameNameIsNoOp() {
        var favorites = FavoriteFolders(urls: [a])
        favorites.commitDisplayName("one", for: a, defaultName: "a")
        let before = favorites
        for same in ["one", " one ", "one\n"] {
            let changed = favorites.commitDisplayName(same, for: a, defaultName: "a")
            #expect(!changed, "\(same.debugDescription)")
            #expect(favorites == before)
        }
    }

    @Test("Committing defaultName for an item without a display name does not set one (R50)")
    func commitDefaultNameWithoutCustomNameIsNoOp() {
        var favorites = FavoriteFolders(urls: [a])
        let changed = favorites.commitDisplayName("a", for: a, defaultName: "a")
        #expect(!changed)
        #expect(favorites.customName(for: a) == nil)
        #expect(favorites.customNamesByPath.isEmpty)
    }

    @Test("Committing defaultName for an item with a display name retains it as a display name (EC-41)")
    func commitDefaultNameWithCustomNameIsKept() {
        var favorites = FavoriteFolders(urls: [a])
        favorites.commitDisplayName("one", for: a, defaultName: "a")
        let changed = favorites.commitDisplayName("a", for: a, defaultName: "a")
        #expect(changed)
        #expect(favorites.customName(for: a) == "a")
    }

    @Test("Multiple items can share a display name and accept / and : (EC-41)")
    func commitAllowsDuplicatesAndSpecialCharacters() {
        var favorites = FavoriteFolders(urls: [a, b])
        let changedA = favorites.commitDisplayName("same", for: a, defaultName: "a")
        let changedB = favorites.commitDisplayName("same", for: b, defaultName: "b")
        #expect(changedA)
        #expect(changedB)
        #expect(favorites.customName(for: a) == "same")
        #expect(favorites.customName(for: b) == "same")

        let changedSpecial = favorites.commitDisplayName("a/b:c", for: a, defaultName: "a")
        #expect(changedSpecial)
        #expect(favorites.customName(for: a) == "a/b:c")
    }

    @Test("Committing an unregistered location returns false and changes nothing")
    func commitRejectsUnregistered() {
        var favorites = FavoriteFolders(urls: [a])
        let changed = favorites.commitDisplayName("x", for: d, defaultName: "d")
        #expect(!changed)
        #expect(favorites.customNamesByPath.isEmpty)
        #expect(favorites.customName(for: d) == nil)
    }

    @Test("remove clears the display name and adding again starts without one (EC-44)")
    func removeDiscardsDisplayName() {
        var favorites = FavoriteFolders(urls: [a, b])
        favorites.commitDisplayName("one", for: b, defaultName: "b")
        favorites.remove(b)
        #expect(favorites.customNamesByPath.isEmpty)

        favorites.add(b)
        #expect(favorites.customName(for: b) == nil)
    }

    @Test("Different path representations retrieve and set the same registered display name")
    func displayNameMatchesAliases() {
        var favorites = FavoriteFolders(urls: [a])
        for alias in aliasesOfA {
            let changed = favorites.commitDisplayName("one", for: alias, defaultName: "a")
            #expect(changed, "\(alias.path)")
            #expect(favorites.customName(for: alias) == "one", "\(alias.path)")
            #expect(favorites.displayName(for: alias, defaultName: "a") == "one", "\(alias.path)")
            favorites.commitDisplayName("", for: a, defaultName: "a")
        }
    }

    @Test("init(customNames:) discards unregistered keys and empty values and normalizes length and newlines")
    func initSanitizesCustomNames() {
        let long = String(repeating: "x", count: 256)
        let favorites = FavoriteFolders(
            urls: [a, b, c],
            customNames: [
                a.path: "one",
                d.path: "unregistered",
                b.path: "  ",
                c.path: long,
            ]
        )
        #expect(favorites.customNamesByPath == [a.path: "one", c.path: String(repeating: "x", count: 255)])

        let withNewline = FavoriteFolders(urls: [a], customNames: [a.path: "o\nne"])
        #expect(withNewline.customName(for: a) == "one")
    }

    @Test("customNamesByPath uses standardizedFileURL.path as its keys")
    func customNamesByPathUsesStandardizedPath() {
        var favorites = FavoriteFolders(urls: [URL(fileURLWithPath: "/tmp/fav/x/../a")])
        favorites.commitDisplayName("one", for: a, defaultName: "a")
        #expect(favorites.customNamesByPath == ["/tmp/fav/a": "one"])

        let fromAlias = FavoriteFolders(urls: [a], customNames: ["/tmp/fav/a/": "two"])
        #expect(fromAlias.customNamesByPath == ["/tmp/fav/a": "two"])
    }

    @Test("Equality includes display names")
    func equalityIncludesDisplayNames() {
        let plain = FavoriteFolders(urls: [a, b])
        let named = FavoriteFolders(urls: [a, b], customNames: [b.path: "one"])
        #expect(plain != named)
        #expect(named == FavoriteFolders(urls: [a, b], customNames: [b.path: "one"]))
    }
}
