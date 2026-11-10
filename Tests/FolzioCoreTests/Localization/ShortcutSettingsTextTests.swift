import FolzioCore
import FolzioLocalization
import Testing

@Suite("Shortcut Settings Localization")
struct ShortcutSettingsTextTests {
    private let plainKeys: [TextKey] = [
        .settingsTabGeneral, .settingsTabShortcuts, .settingsShortcutsList, .settingsShortcutsRecord,
        .settingsShortcutsRecording, .settingsShortcutsReset, .settingsShortcutsResetAll, .settingsShortcutsChanged,
        .settingsShortcutsErrorModifier, .settingsShortcutsErrorFixed, .settingsShortcutsClear, .settingsShortcutsUnset,
    ]
    private let nameKeys: [TextKey] = [
        .settingsShortcutsRecordFor, .settingsShortcutsResetFor, .settingsShortcutsErrorConflict,
        .settingsShortcutsErrorDefaultConflict, .settingsShortcutsClearFor,
    ]
    private let toolbarKeys: [TextKey] = [
        .toolbarGoBackHelp, .toolbarGoForwardHelp, .toolbarShowFileListOnlyHelp, .toolbarShowPreviewOnlyHelp,
        .toolbarShowImagesOnlyHelp, .toolbarShowVideosOnlyHelp, .toolbarZipFilesHelp, .toolbarStartSlideshowHelp,
        .toolbarZoomInHelp, .toolbarZoomToFitHelp, .toolbarZoomOutHelp, .toolbarThumbnails, .toolbarList,
        .toolbarThumbnailSize,
    ]
    /// Toolbar texts that name a fixed key, so they take no argument (TAK-89).
    private let toolbarPlainKeys: [TextKey] = [.toolbarStopSlideshowHelp]

    @Test("Every shortcut settings text is translated, and plain texts take no argument")
    func plainTextsAreTranslated() throws {
        for language in LocalizationTestSupport.languages {
            let strings = try LocalizationTestSupport.strings(language)
            let localizer = LocalizationTestSupport.localizer(language)
            for key in plainKeys {
                let translation = try #require(strings[key.rawValue], "\(language): \(key.rawValue)")
                #expect(!translation.isEmpty)
                #expect(!translation.contains("%"))
                #expect(key.arguments.isEmpty)
                #expect(localizer.text(key) != key.rawValue)
            }
        }
    }

    @Test("Texts that name a command or a shortcut take exactly one text argument and insert it")
    func argumentTextsInsertTheirValue() throws {
        for language in LocalizationTestSupport.languages {
            let strings = try LocalizationTestSupport.strings(language)
            let localizer = LocalizationTestSupport.localizer(language)
            for key in nameKeys + toolbarKeys {
                let translation = try #require(strings[key.rawValue], "\(language): \(key.rawValue)")
                #expect(translation.contains("%1$@"), "\(language): \(key.rawValue)")
                #expect(key.arguments == [.text], "\(key.rawValue)")
                let text = localizer.text(key, .text("<VALUE>"))
                #expect(text.contains("<VALUE>"), "\(language): \(key.rawValue)")
            }
        }
    }

    @Test("Toolbar texts for a fixed key are translated and take no argument")
    func toolbarPlainTextsAreTranslated() throws {
        for language in LocalizationTestSupport.languages {
            let strings = try LocalizationTestSupport.strings(language)
            let localizer = LocalizationTestSupport.localizer(language)
            for key in toolbarPlainKeys {
                let translation = try #require(strings[key.rawValue], "\(language): \(key.rawValue)")
                #expect(!translation.isEmpty)
                #expect(!translation.contains("%"), "\(language): \(key.rawValue)")
                #expect(translation.contains("Esc"), "\(language): \(key.rawValue)")
                #expect(key.arguments.isEmpty, "\(key.rawValue)")
                #expect(localizer.text(key) != key.rawValue)
            }
        }
    }

    @Test("Toolbar texts no longer hold a shortcut of their own")
    func toolbarTextsHaveNoFixedGlyphs() throws {
        for language in LocalizationTestSupport.languages {
            let strings = try LocalizationTestSupport.strings(language)
            for key in toolbarKeys {
                let translation = try #require(strings[key.rawValue])
                for glyph in ["⌘", "⌃", "⌥", "⇧"] {
                    #expect(!translation.contains(glyph), "\(language): \(key.rawValue)")
                }
            }
        }
    }

    @Test("Every command has a menu item name, and the names are unique")
    func commandNamesAreUnique() throws {
        let keys = ShortcutCommandID.allCases.map(ShortcutText.commandName)
        #expect(Set(keys).count == keys.count)
        for language in LocalizationTestSupport.languages {
            let localizer = LocalizationTestSupport.localizer(language)
            for key in keys {
                #expect(!localizer.text(key).isEmpty)
                #expect(localizer.text(key) != key.rawValue)
            }
        }
    }
}
