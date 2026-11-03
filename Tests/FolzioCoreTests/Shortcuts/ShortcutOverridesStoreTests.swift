import Foundation
import FolzioCore
import Testing

@Suite("Shortcut Overrides Store")
struct ShortcutOverridesStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "ShortcutOverridesStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("Overrides round-trip through the store, and an empty dictionary removes the key")
    func roundTrip() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        #expect(store.shortcutOverrides.isEmpty)
        store.shortcutOverrides = ["newFolder": "opt+cmd+j"]
        #expect(store.shortcutOverrides == ["newFolder": "opt+cmd+j"])
        #expect(defaults.object(forKey: "shortcuts.overrides") != nil)
        store.shortcutOverrides = [:]
        #expect(defaults.object(forKey: "shortcuts.overrides") == nil)
    }

    @Test("A value that is not a dictionary reads as empty")
    func nonDictionary() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not a dictionary", forKey: "shortcuts.overrides")
        #expect(SettingsStore(defaults: defaults).shortcutOverrides.isEmpty)
        defaults.set(["a", "b"], forKey: "shortcuts.overrides")
        #expect(SettingsStore(defaults: defaults).shortcutOverrides.isEmpty)
    }

    @Test("Entries whose value is not a string are dropped")
    func nonStringValues() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["newFolder": "opt+cmd+j", "find": 3, "open": true], forKey: "shortcuts.overrides")
        #expect(SettingsStore(defaults: defaults).shortcutOverrides == ["newFolder": "opt+cmd+j"])
    }

    @Test("A saved assignment table restores the same assignments")
    func restoresAssignments() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let assignments = try ShortcutAssignments()
            .assigning(KeyCombination(key: "j", modifiers: [.option, .command]), to: .newFolder)
            .get()
        store.shortcutOverrides = assignments.storedOverrides
        #expect(ShortcutAssignments(storedOverrides: store.shortcutOverrides) == assignments)
    }
}
