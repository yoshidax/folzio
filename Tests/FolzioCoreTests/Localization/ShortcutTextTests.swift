import FolzioCore
import FolzioLocalization
import Testing

@Suite("Shortcut Reference Localization")
struct ShortcutTextTests {
    @Test("Every reference heading, description, and condition is translated without falling back")
    func allEntriesAreTranslated() throws {
        for language in LocalizationTestSupport.languages {
            let strings = try LocalizationTestSupport.strings(language)
            let localizer = LocalizationTestSupport.localizer(language)
            var keys: [TextKey] = [.menuFileShortcuts, .menuFileClose, .shortcutsWindow]
            keys += ShortcutSection.allCases.map { ShortcutText.heading($0) }
            for entry in ShortcutCatalog.entries {
                keys.append(ShortcutText.description(entry.id))
                if let condition = ShortcutText.condition(entry.id) { keys.append(condition) }
            }
            #expect(Set(keys).count == keys.count)
            for key in keys {
                let translation = try #require(strings[key.rawValue], "\(language): \(key.rawValue)")
                #expect(!translation.isEmpty)
                #expect(!localizer.text(key).isEmpty)
                #expect(localizer.text(key) != key.rawValue)
                #expect(key.arguments.isEmpty)
            }
        }
    }

    @Test("Context-sensitive actions retain their availability notes")
    func availabilityNotes() {
        let withoutConditions: Set<ShortcutID> = [.toolbar, .listStyle, .settings, .quit]
        for id in ShortcutID.allCases {
            #expect((ShortcutText.condition(id) == nil) == withoutConditions.contains(id))
        }
        #expect(ShortcutText.description(.cancelReceiving) == .menuCancelReceiving)
        #expect(ShortcutText.condition(.cancelReceiving) == .shortcutCancelReceivingCondition)
        #expect(ShortcutText.condition(.selection) != ShortcutText.condition(.slideshowNavigate))
        #expect(ShortcutText.description(.videoControls) != ShortcutText.description(.selection))
    }

    @Test("Language selection changes prose and preserves key glyphs and literal percent signs")
    func languageAndGlyphs() {
        let japanese = LocalizationTestSupport.localizer("ja")
        let english = LocalizationTestSupport.localizer("en")
        for section in ShortcutSection.allCases {
            #expect(japanese.text(ShortcutText.heading(section)) != english.text(ShortcutText.heading(section)))
        }
        for entry in ShortcutCatalog.entries {
            let key = ShortcutText.description(entry.id)
            #expect(japanese.text(key) != english.text(key))
        }
        for localizer in [japanese, english] {
            let zoom = localizer.text(.shortcutImageZoomCondition)
            #expect(zoom.contains("25%"))
            #expect(zoom.contains("800%"))
            #expect(!zoom.contains("%%"))
            #expect(localizer.text(.shortcutImageFitCondition).contains("100%"))
        }
        let referenceKeys = ShortcutCatalog.entries.map(\.keys)
        #expect(referenceKeys.contains("⌘/"))
        #expect(referenceKeys.contains("⌘W"))
        #expect(!referenceKeys.contains("/"))
    }
}
