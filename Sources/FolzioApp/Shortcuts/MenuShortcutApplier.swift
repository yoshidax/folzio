import AppKit
import FolzioCore

/// Applies the current shortcut assignments to menu items.
///
/// Menu items are created in several places (the main menu, menus added later by the view controllers, and context
/// menus), so each creator registers its item here. `NSMenuItem.identifier` is not used because the localization
/// refresh already uses it. Items are held weakly, and context menus register their items again whenever they rebuild.
@MainActor
final class MenuShortcutApplier {
    static let shared = MenuShortcutApplier()

    private struct Registration {
        weak var item: NSMenuItem?
        let command: ShortcutCommandID
        /// Whether the item carries the command's hidden alternate key (such as ⌘= for zoom in).
        let isAlternate: Bool
    }

    private var registrations: [Registration] = []

    /// Registers an item for a command and applies the current key to it.
    func register(_ item: NSMenuItem, for command: ShortcutCommandID, isAlternate: Bool = false) {
        registrations.removeAll { $0.item == nil || $0.item === item }
        let registration = Registration(item: item, command: command, isAlternate: isAlternate)
        registrations.append(registration)
        apply(registration)
    }

    /// Applies the current keys to every live registered item.
    func applyAll() {
        registrations.removeAll { $0.item == nil }
        for registration in registrations { apply(registration) }
    }

    private func apply(_ registration: Registration) {
        guard let item = registration.item else { return }
        let assignments = ShortcutAssignmentStore.shared.assignments
        let combination: KeyCombination?
        if registration.isAlternate {
            combination = assignments.activeAlternates(for: registration.command).first
        } else {
            combination = assignments.combination(for: registration.command)
        }
        guard let combination else {
            // The item has no key: the alternate is off while its command uses a custom key, and an unset command
            // has no key at all (FR-268).
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = combination.menuKeyEquivalent
        item.keyEquivalentModifierMask = Self.flags(for: combination.modifiers)
    }

    static func flags(for modifiers: KeyModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return flags
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var modifiers: KeyModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
