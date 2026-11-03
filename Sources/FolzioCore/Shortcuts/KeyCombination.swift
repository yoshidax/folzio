/// The modifier keys of a key combination. Independent of AppKit so that the logic stays testable in Core.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
}

/// A key and its modifiers, in the form a menu item's key equivalent uses.
///
/// `key` is one lowercase character, or the name of a special key (`up`, `down`, `left`, `right`, `delete`, `return`,
/// `escape`, `tab`, `space`). Build values from a pressed key with `normalized(key:modifiers:)`.
public struct KeyCombination: Hashable, Sendable {
    public let key: String
    public let modifiers: KeyModifiers

    public init(key: String, modifiers: KeyModifiers) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The names of the special keys, in the order used by stored values.
    public static let specialKeyNames: [String] = [
        "up", "down", "left", "right", "delete", "return", "escape", "tab", "space",
    ]

    /// The characters that need Shift on a US keyboard. A menu item states them without Shift (for example, ⌘+ is
    /// `"+"` with only Command), so `normalized` drops Shift for them.
    private static let shiftedSymbols: Set<Character> = [
        "+", "?", "<", ">", ":", "\"", "{", "}", "|", "~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "_",
    ]

    /// Builds a combination from the characters a key press produces (`charactersIgnoringModifiers`) and its modifiers.
    ///
    /// An uppercase letter becomes the lowercase letter plus Shift. Shift is dropped for the symbols that need it on
    /// a US keyboard, so that a pressed ⇧⌘= equals the default ⌘+. Function-key and control characters become the
    /// special key names.
    public static func normalized(key characters: String, modifiers: KeyModifiers) -> KeyCombination? {
        var modifiers = modifiers
        guard let name = keyName(forCharacters: characters) else { return nil }
        guard name.count == 1, let character = name.first else {
            return KeyCombination(key: name, modifiers: modifiers)
        }
        if character.isUppercase {
            modifiers.insert(.shift)
            return KeyCombination(key: name.lowercased(), modifiers: modifiers)
        }
        if shiftedSymbols.contains(character) {
            modifiers.remove(.shift)
        }
        return KeyCombination(key: name, modifiers: modifiers)
    }

    /// Maps the characters of a key event to one key name, or nil when there is not exactly one key.
    public static func keyName(forCharacters characters: String) -> String? {
        let scalars = Array(characters.unicodeScalars)
        guard scalars.count == 1, let scalar = scalars.first else {
            // Two or more characters (a dead key, a composition) are not a single key.
            return characters.count == 1 ? characters : nil
        }
        switch scalar.value {
        case 0xF700: return "up"
        case 0xF701: return "down"
        case 0xF702: return "left"
        case 0xF703: return "right"
        case 0x7F, 0x08: return "delete"
        case 0x0D, 0x03: return "return"
        case 0x1B: return "escape"
        case 0x09, 0x19: return "tab"
        case 0x20: return "space"
        case 0xF704...0xF8FF: return nil // other function keys have no key equivalent here
        case 0x00...0x1F: return nil
        default: return String(Character(scalar))
        }
    }

    /// Whether the combination includes Command, Control, or Option. Shift alone does not count.
    public var hasRequiredModifier: Bool {
        !modifiers.isDisjoint(with: [.command, .control, .option])
    }

    /// The text for a menu item's `keyEquivalent`.
    public var menuKeyEquivalent: String {
        switch key {
        case "up": return "\u{F700}"
        case "down": return "\u{F701}"
        case "left": return "\u{F702}"
        case "right": return "\u{F703}"
        case "delete": return "\u{8}"
        case "return": return "\r"
        case "escape": return "\u{1B}"
        case "tab": return "\t"
        case "space": return " "
        default: return key
        }
    }

    /// The display text with the modifiers in the macOS menu order (⌃⌥⇧⌘), such as `⇧⌘N` or `⌘Delete`.
    public var displayText: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case "up": text += "↑"
        case "down": text += "↓"
        case "left": text += "←"
        case "right": text += "→"
        case "delete": text += "Delete"
        case "return": text += "Return"
        case "escape": text += "Esc"
        case "tab": text += "Tab"
        case "space": text += "Space"
        default: text += key.uppercased()
        }
        return text
    }

    private static let storedModifierPrefixes: [(prefix: String, modifier: KeyModifiers)] = [
        ("ctrl+", .control), ("opt+", .option), ("shift+", .shift), ("cmd+", .command),
    ]

    /// The stored form: modifiers in the order `ctrl`, `opt`, `shift`, `cmd`, each followed by `+`, then the key
    /// (for example `shift+cmd+n`, or `cmd++` for ⌘+).
    public var storedText: String {
        var text = ""
        for (prefix, modifier) in Self.storedModifierPrefixes where modifiers.contains(modifier) {
            text += prefix
        }
        return text + key
    }

    /// Reads a stored form. Returns nil for anything that is not a modifier list followed by one valid key.
    public init?(storedText: String) {
        var rest = Substring(storedText)
        var modifiers: KeyModifiers = []
        var progressed = true
        while progressed {
            progressed = false
            for (prefix, modifier) in Self.storedModifierPrefixes where rest.hasPrefix(prefix) && !modifiers.contains(modifier) {
                // A key named by one of these words alone ("shift+") would leave nothing, so require a remainder.
                let remainder = rest.dropFirst(prefix.count)
                guard !remainder.isEmpty else { return nil }
                modifiers.insert(modifier)
                rest = remainder
                progressed = true
                break
            }
        }
        let key = String(rest)
        let isSpecial = Self.specialKeyNames.contains(key)
        let isSingleCharacter = key.count == 1 && key == key.lowercased()
        guard isSpecial || isSingleCharacter else { return nil }
        // Reject forms that normalization would change, so that a stored value always round-trips.
        guard let normalized = Self.normalized(key: isSpecial ? Self.characters(forSpecialKey: key) : key, modifiers: modifiers),
              normalized.key == key, normalized.modifiers == modifiers else { return nil }
        self = normalized
    }

    private static func characters(forSpecialKey name: String) -> String {
        KeyCombination(key: name, modifiers: []).menuKeyEquivalent
    }
}
