import FolzioCore
import Testing

@Suite("Key Combination")
struct KeyCombinationTests {
    @Test("An uppercase letter becomes the lowercase letter plus Shift")
    func uppercaseLetter() {
        let combination = KeyCombination.normalized(key: "N", modifiers: [.command])
        #expect(combination == KeyCombination(key: "n", modifiers: [.shift, .command]))
        #expect(combination?.displayText == "⇧⌘N")
    }

    @Test("Shift is kept for letters, so ⇧⌘N and ⌘N differ")
    func shiftedLetterDiffers() {
        let plain = KeyCombination.normalized(key: "n", modifiers: [.command])
        let shifted = KeyCombination.normalized(key: "n", modifiers: [.shift, .command])
        #expect(plain != shifted)
    }

    @Test("A pressed ⇧⌘= equals the default ⌘+, and ⌘= stays different")
    func shiftedSymbolEqualsDefault() {
        let pressed = KeyCombination.normalized(key: "+", modifiers: [.shift, .command])
        #expect(pressed == KeyCombination(key: "+", modifiers: [.command]))
        let equals = KeyCombination.normalized(key: "=", modifiers: [.command])
        #expect(equals == KeyCombination(key: "=", modifiers: [.command]))
        #expect(equals != pressed)
    }

    @Test("Function and control characters map to special key names")
    func specialKeys() {
        #expect(KeyCombination.normalized(key: "\u{F700}", modifiers: [.command])?.key == "up")
        #expect(KeyCombination.normalized(key: "\u{F701}", modifiers: [.command])?.key == "down")
        #expect(KeyCombination.normalized(key: "\u{7F}", modifiers: [.command])?.key == "delete")
        #expect(KeyCombination.normalized(key: "\r", modifiers: [])?.key == "return")
        #expect(KeyCombination.normalized(key: "\u{1B}", modifiers: [])?.key == "escape")
        #expect(KeyCombination.normalized(key: " ", modifiers: [])?.key == "space")
    }

    @Test("Keys without a menu key equivalent are rejected")
    func unsupportedKeys() {
        #expect(KeyCombination.normalized(key: "\u{F704}", modifiers: [.command]) == nil)
        #expect(KeyCombination.normalized(key: "", modifiers: [.command]) == nil)
        #expect(KeyCombination.normalized(key: "ab", modifiers: [.command]) == nil)
    }

    @Test("The display text uses the macOS menu order of modifiers")
    func displayText() {
        #expect(KeyCombination(key: "delete", modifiers: [.command]).displayText == "⌘Delete")
        #expect(KeyCombination(key: "down", modifiers: [.command]).displayText == "⌘↓")
        #expect(KeyCombination(key: "j", modifiers: [.option, .command]).displayText == "⌥⌘J")
        #expect(KeyCombination(key: "1", modifiers: [.control, .option, .shift, .command]).displayText == "⌃⌥⇧⌘1")
    }

    @Test("Stored text round-trips, including the plus key")
    func storedRoundTrip() {
        let samples = [
            KeyCombination(key: "j", modifiers: [.option, .command]),
            KeyCombination(key: "n", modifiers: [.shift, .command]),
            KeyCombination(key: "+", modifiers: [.command]),
            KeyCombination(key: "-", modifiers: [.command]),
            KeyCombination(key: "delete", modifiers: [.command]),
            KeyCombination(key: "1", modifiers: [.control, .option, .shift, .command]),
        ]
        for sample in samples {
            #expect(KeyCombination(storedText: sample.storedText) == sample, "\(sample.storedText)")
        }
        #expect(KeyCombination(key: "+", modifiers: [.command]).storedText == "cmd++")
        #expect(KeyCombination(key: "n", modifiers: [.shift, .command]).storedText == "shift+cmd+n")
    }

    @Test("Unreadable stored text is rejected")
    func invalidStoredText() {
        for text in ["", "cmd+", "cmd+N", "cmd+ab", "shift+", "meta+j", "cmd+cmd+j", "cmd+up2"] {
            #expect(KeyCombination(storedText: text) == nil, "\(text)")
        }
    }

    @Test("A required modifier is Command, Control, or Option; Shift alone does not count")
    func requiredModifier() {
        #expect(!KeyCombination(key: "a", modifiers: []).hasRequiredModifier)
        #expect(!KeyCombination(key: "a", modifiers: [.shift]).hasRequiredModifier)
        #expect(KeyCombination(key: "a", modifiers: [.option]).hasRequiredModifier)
        #expect(KeyCombination(key: "a", modifiers: [.control]).hasRequiredModifier)
        #expect(KeyCombination(key: "a", modifiers: [.command]).hasRequiredModifier)
    }

    @Test("The menu key equivalent uses the characters a menu item expects")
    func menuKeyEquivalent() {
        #expect(KeyCombination(key: "down", modifiers: [.command]).menuKeyEquivalent == "\u{F701}")
        #expect(KeyCombination(key: "delete", modifiers: [.command]).menuKeyEquivalent == "\u{8}")
        #expect(KeyCombination(key: "j", modifiers: [.command]).menuKeyEquivalent == "j")
    }
}
