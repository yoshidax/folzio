import FolzioCore
import Testing

@Suite("Shortcut Assignments")
struct ShortcutAssignmentsTests {
    private let optionCommandJ = KeyCombination(key: "j", modifiers: [.option, .command])

    @Test("Assigning a free combination overrides the default")
    func assignsFreeCombination() throws {
        let assignments = try ShortcutAssignments().assigning(optionCommandJ, to: .newFolder).get()
        #expect(assignments.combination(for: .newFolder) == optionCommandJ)
        #expect(assignments.isOverridden(.newFolder))
        #expect(assignments.storedOverrides == ["newFolder": "opt+cmd+j"])
    }

    @Test("A candidate without Command, Control, or Option is rejected")
    func rejectsMissingModifier() {
        for candidate in [
            KeyCombination(key: "a", modifiers: []),
            KeyCombination(key: "a", modifiers: [.shift]),
            KeyCombination(key: "return", modifiers: []),
        ] {
            #expect(ShortcutAssignments().assigning(candidate, to: .newFolder) == .failure(.missingModifier))
        }
    }

    @Test("Reserved keys are rejected as reserved")
    func rejectsReserved() {
        for candidate in [
            KeyCombination(key: "q", modifiers: [.command]),
            KeyCombination(key: "w", modifiers: [.command]),
            KeyCombination(key: ",", modifiers: [.command]),
            KeyCombination(key: "c", modifiers: [.command]),
            KeyCombination(key: ".", modifiers: [.command]),
        ] {
            #expect(ShortcutAssignments().assigning(candidate, to: .newFolder) == .failure(.reserved), "\(candidate)")
        }
    }

    @Test("Fixed keys are rejected as fixed, and Shift-only fixed keys fail the modifier rule first")
    func rejectsFixed() {
        for candidate in [
            KeyCombination(key: "right", modifiers: [.option]),
            KeyCombination(key: "up", modifiers: [.option]),
            KeyCombination(key: "a", modifiers: [.command]),
        ] {
            #expect(ShortcutAssignments().assigning(candidate, to: .newFolder) == .failure(.fixed), "\(candidate)")
        }
        #expect(
            ShortcutAssignments().assigning(KeyCombination(key: "tab", modifiers: [.shift]), to: .newFolder)
                == .failure(.missingModifier)
        )
    }

    @Test("The key of another command, even at its default, is a conflict")
    func rejectsConflict() {
        let result = ShortcutAssignments().assigning(KeyCombination(key: "f", modifiers: [.command]), to: .newFolder)
        #expect(result == .failure(.conflict(.find)))
    }

    @Test("The same combination as the current one succeeds without a change")
    func sameCombinationIsNotAConflict() throws {
        let current = ShortcutAssignments()
        let again = try current.assigning(KeyCombination(key: "n", modifiers: [.shift, .command]), to: .newFolder).get()
        #expect(again == current)
    }

    @Test("Validation order is modifier, then reserved or fixed, then conflict")
    func validationOrder() {
        let assignments = ShortcutAssignments()
        #expect(assignments.error(for: KeyCombination(key: "q", modifiers: []), assigningTo: .find) == .missingModifier)
        #expect(
            assignments.error(for: KeyCombination(key: "q", modifiers: [.command]), assigningTo: .find) == .reserved
        )
        #expect(
            assignments.error(for: KeyCombination(key: "n", modifiers: [.shift, .command]), assigningTo: .find)
                == .conflict(.newFolder)
        )
    }

    @Test("After a change, the old default key becomes free for another command")
    func freedKeyIsAssignable() throws {
        let moved = try ShortcutAssignments().assigning(optionCommandJ, to: .newFolder).get()
        let taken = try moved.assigning(KeyCombination(key: "n", modifiers: [.shift, .command]), to: .find).get()
        #expect(taken.combination(for: .find) == KeyCombination(key: "n", modifiers: [.shift, .command]))
    }

    @Test("Assigning a command its own default removes the override")
    func assigningDefaultClearsOverride() throws {
        let moved = try ShortcutAssignments().assigning(optionCommandJ, to: .newFolder).get()
        let back = try moved.assigning(KeyCombination(key: "n", modifiers: [.shift, .command]), to: .newFolder).get()
        #expect(back.overrides.isEmpty)
    }

    @Test("Resetting returns a command to its default unless another command uses that key")
    func resetting() throws {
        let moved = try ShortcutAssignments().assigning(optionCommandJ, to: .newFolder).get()
        #expect(try moved.resetting(.newFolder).get().overrides.isEmpty)
        let taken = try moved.assigning(KeyCombination(key: "n", modifiers: [.shift, .command]), to: .find).get()
        #expect(taken.resetting(.newFolder) == .failure(.conflict(.find)))
        #expect(try ShortcutAssignments().resetting(.newFolder).get() == ShortcutAssignments())
    }

    @Test("Resetting all removes every override")
    func resettingAll() throws {
        let changed = try ShortcutAssignments().assigning(optionCommandJ, to: .newFolder).get()
        #expect(changed.resettingAll().overrides.isEmpty)
    }

    @Test("Zoom in's alternate works only while it keeps its default key")
    func zoomAlternate() throws {
        let defaults = ShortcutAssignments()
        let equals = KeyCombination(key: "=", modifiers: [.command])
        #expect(defaults.activeAlternates(for: .zoomIn) == [equals])
        #expect(defaults.assigning(equals, to: .find) == .failure(.conflict(.zoomIn)))
        let moved = try defaults.assigning(optionCommandJ, to: .zoomIn).get()
        #expect(moved.activeAlternates(for: .zoomIn).isEmpty)
        #expect(try moved.assigning(equals, to: .find).get().combination(for: .find) == equals)
    }

    @Test("Stored overrides restore, and broken entries are dropped on their own")
    func loadsStoredOverrides() {
        let stored = [
            "newFolder": "opt+cmd+j",
            "find": "cmd+q",          // reserved
            "open": "x",              // unreadable
            "unknownCommand": "cmd+k", // not a command
            "duplicate": "j",         // no required modifier
        ]
        let assignments = ShortcutAssignments(storedOverrides: stored)
        #expect(assignments.overrides.count == 1)
        #expect(assignments.combination(for: .newFolder) == optionCommandJ)
        #expect(assignments.combination(for: .find) == KeyCombination(key: "f", modifiers: [.command]))
    }

    @Test("Of two stored values with the same key, the later command returns to its default")
    func loadsDuplicateStoredValues() {
        // newFolder comes before find in the command order, so find loses.
        let stored = ["find": "opt+cmd+j", "newFolder": "opt+cmd+j"]
        let assignments = ShortcutAssignments(storedOverrides: stored)
        #expect(assignments.combination(for: .newFolder) == optionCommandJ)
        #expect(assignments.combination(for: .find) == KeyCombination(key: "f", modifiers: [.command]))
    }

    @Test("A stored swap of two default keys is accepted when the result has no duplicate")
    func loadsSwap() {
        let stored = ["find": "shift+cmd+n", "newFolder": "cmd+f"]
        let assignments = ShortcutAssignments(storedOverrides: stored)
        #expect(assignments.combination(for: .find) == KeyCombination(key: "n", modifiers: [.shift, .command]))
        #expect(assignments.combination(for: .newFolder) == KeyCombination(key: "f", modifiers: [.command]))
    }

    @Test("A stored value that equals the default or an active alternate of another command is dropped")
    func loadsStoredValueEqualToDefault() {
        let assignments = ShortcutAssignments(storedOverrides: ["find": "cmd+f", "open": "cmd+="])
        #expect(assignments.overrides.isEmpty)
    }

    // MARK: - Unset commands (FR-268)

    @Test("Unsetting removes the command's key and is stored as none")
    func unsetsACommand() {
        let assignments = ShortcutAssignments().unsetting(.find)
        #expect(assignments.combination(for: .find) == nil)
        #expect(assignments.isUnset(.find))
        #expect(assignments.isOverridden(.find))
        #expect(assignments.storedOverrides == ["find": "none"])
    }

    @Test("The key of an unset command is free for another command")
    func unsetFreesTheKey() throws {
        let findKey = KeyCombination(key: "f", modifiers: [.command])
        let assignments = ShortcutAssignments().unsetting(.find)
        #expect(assignments.command(using: findKey) == nil)
        let taken = try assignments.assigning(findKey, to: .newFolder).get()
        #expect(taken.combination(for: .newFolder) == findKey)
    }

    @Test("Two commands swap keys in three steps without a spare key")
    func swapsTwoCommands() throws {
        let findKey = KeyCombination(key: "f", modifiers: [.command])
        let newFolderKey = KeyCombination(key: "n", modifiers: [.shift, .command])
        var assignments = ShortcutAssignments()
        // Without the unset step, taking the other command's key is a conflict.
        #expect(assignments.assigning(findKey, to: .newFolder) == .failure(.conflict(.find)))
        assignments = assignments.unsetting(.find)
        assignments = try assignments.assigning(findKey, to: .newFolder).get()
        assignments = try assignments.assigning(newFolderKey, to: .find).get()
        #expect(assignments.combination(for: .find) == newFolderKey)
        #expect(assignments.combination(for: .newFolder) == findKey)
    }

    @Test("An unset command can record a key, but a key in use is still a conflict")
    func unsetCommandRecords() throws {
        let unset = ShortcutAssignments().unsetting(.find)
        #expect(
            unset.assigning(KeyCombination(key: "n", modifiers: [.shift, .command]), to: .find)
                == .failure(.conflict(.newFolder))
        )
        let recorded = try unset.assigning(optionCommandJ, to: .find).get()
        #expect(recorded.combination(for: .find) == optionCommandJ)
        #expect(!recorded.isUnset(.find))
    }

    @Test("Resetting an unset command restores its default unless another command uses it")
    func resettingAnUnsetCommand() throws {
        let findKey = KeyCombination(key: "f", modifiers: [.command])
        let unset = ShortcutAssignments().unsetting(.find)
        #expect(try unset.resetting(.find).get().overrides.isEmpty)
        let taken = try unset.assigning(findKey, to: .newFolder).get()
        #expect(taken.resetting(.find) == .failure(.conflict(.newFolder)))
    }

    @Test("Resetting all clears the unset commands")
    func resettingAllClearsUnset() {
        let assignments = ShortcutAssignments().unsetting(.find).unsetting(.newFolder)
        #expect(assignments.resettingAll() == ShortcutAssignments())
    }

    @Test("Zoom in's alternate is off while zoom in is unset")
    func unsetZoomInDropsItsAlternate() throws {
        let equals = KeyCombination(key: "=", modifiers: [.command])
        let unset = ShortcutAssignments().unsetting(.zoomIn)
        #expect(unset.activeAlternates(for: .zoomIn).isEmpty)
        #expect(try unset.assigning(equals, to: .find).get().combination(for: .find) == equals)
    }

    @Test("Stored none loads as unset, and an unknown command's none is dropped")
    func loadsStoredNone() {
        let assignments = ShortcutAssignments(storedOverrides: ["find": "none", "unknownCommand": "none"])
        #expect(assignments.isUnset(.find))
        #expect(assignments.overrides.count == 1)
    }

    @Test("Unset commands never take part in a stored conflict")
    func unsetDoesNotConflictOnLoad() {
        let stored = ["find": "none", "newFolder": "cmd+f"]
        let assignments = ShortcutAssignments(storedOverrides: stored)
        #expect(assignments.isUnset(.find))
        #expect(assignments.combination(for: .newFolder) == KeyCombination(key: "f", modifiers: [.command]))
    }

    @Test("A mix of keys and unset commands round-trips through the stored form")
    func unsetRoundTrips() throws {
        let assignments = try ShortcutAssignments()
            .assigning(optionCommandJ, to: .newFolder)
            .get()
            .unsetting(.find)
        #expect(ShortcutAssignments(storedOverrides: assignments.storedOverrides) == assignments)
    }
}
