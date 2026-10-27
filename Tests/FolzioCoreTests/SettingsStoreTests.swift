import Foundation
import Testing
@testable import FolzioCore

@Suite("SettingsStore")
struct SettingsStoreTests {
    @Test("The display language defaults to English when unset or invalid")
    func displayLanguageDefaultsToEnglish() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            defaults.set(["ja", "fr"], forKey: "AppleLanguages")
            #expect(store.displayLanguage == .english)
            for value in ["fr", "", "en-GB", 42, true] as [Any] {
                defaults.set(value, forKey: "appearance.language")
                #expect(store.displayLanguage == .english)
            }
        }
    }

    @Test("Saves and restores the display language while preserving other settings")
    func displayLanguageRoundTrips() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.playback = PlaybackOptions(autoplay: false, loop: false)
            for language in [DisplayLanguageSetting.japanese, .english] {
                store.displayLanguage = language
                #expect(SettingsStore(defaults: defaults).displayLanguage == language)
                #expect(defaults.string(forKey: "appearance.language") == language.rawValue)
                #expect(store.playback == PlaybackOptions(autoplay: false, loop: false))
            }
        }
    }

    @Test("Unset settings use default values")
    func usesDefaults() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let view = store.viewSettings
            #expect(view.displayMode == .list)
            #expect(view.thumbnailSize == 128)
            #expect(view.sortOrder == SortOrder(column: .name, ascending: true))
            #expect(view.lastFolder == nil)
            #expect(!view.showsToolbar)
            #expect(store.playback.autoplay)
            #expect(store.playback.loop)
            #expect(store.confirmation.confirmBeforeFileOperations)
            #expect(store.favorites.urls.isEmpty)
        }
    }

    @Test("Saved values round-trip")
    func roundTripsValues() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)

            store.viewSettings = ViewSettings(
                displayMode: .thumbnails,
                thumbnailSize: 256,
                sortOrder: SortOrder(column: .creationDate, ascending: false),
                lastFolder: folder,
                showsToolbar: true
            )
            store.playback = PlaybackOptions(autoplay: false, loop: false)
            store.confirmation = ConfirmationOptions(confirmBeforeFileOperations: false)

            let view = store.viewSettings
            #expect(view.displayMode == .thumbnails)
            #expect(view.thumbnailSize == 256)
            #expect(view.sortOrder == SortOrder(column: .creationDate, ascending: false))
            #expect(view.lastFolder?.path == folder.path)
            #expect(view.showsToolbar)
            #expect(!store.playback.autoplay)
            #expect(!store.playback.loop)
            #expect(!store.confirmation.confirmBeforeFileOperations)

            var hidden = store.viewSettings
            hidden.showsToolbar = false
            store.viewSettings = hidden
            #expect(!store.viewSettings.showsToolbar)
        }
    }

    @Test("Changing only toolbar visibility preserves other view settings")
    func togglingToolbarKeepsOtherViewSettings() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
            store.viewSettings = ViewSettings(
                displayMode: .thumbnails,
                thumbnailSize: 200,
                sortOrder: SortOrder(column: .kind, ascending: false),
                lastFolder: folder
            )

            var updated = store.viewSettings
            updated.showsToolbar = true
            store.viewSettings = updated

            let view = store.viewSettings
            #expect(view.showsToolbar)
            #expect(view.displayMode == .thumbnails)
            #expect(view.thumbnailSize == 200)
            #expect(view.sortOrder == SortOrder(column: .kind, ascending: false))
            #expect(view.lastFolder?.path == folder.path)
        }
    }

    @Test("Clamps thumbnail size to 48 through 512")
    func clampsThumbnailSize() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            defaults.set(10.0, forKey: "view.thumbnailSize")
            #expect(store.viewSettings.thumbnailSize == 48)

            defaults.set(900.0, forKey: "view.thumbnailSize")
            #expect(store.viewSettings.thumbnailSize == 512)
        }
    }

    @Test("Values of the wrong type fall back to defaults")
    func fallsBackForInvalidValues() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            defaults.set("large", forKey: "view.thumbnailSize")
            defaults.set("grid", forKey: "view.displayMode")
            defaults.set("size", forKey: "view.sort.column")
            defaults.set("yes", forKey: "view.sort.ascending")
            defaults.set("no", forKey: "playback.autoplay")
            defaults.set("yes", forKey: "view.showsToolbar")

            let view = store.viewSettings
            #expect(view.thumbnailSize == 128)
            #expect(view.displayMode == .list)
            #expect(view.sortOrder.column == .name)
            #expect(view.sortOrder.ascending)
            #expect(!view.showsToolbar)
            #expect(store.playback.autoplay)
        }
    }

    // MARK: - favorites

    @Test("Unsaved Favorites are empty")
    func favoritesDefaultToEmpty() {
        withDefaults { defaults in
            #expect(SettingsStore(defaults: defaults).favorites == FavoriteFolders())
        }
    }

    @Test("Favorites round-trip as absolute paths in registration order")
    func favoritesRoundTrip() {
        withDefaults { defaults in
            let b = URL(fileURLWithPath: "/tmp/fav/b", isDirectory: true)
            let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
            SettingsStore(defaults: defaults).favorites = FavoriteFolders(urls: [b, a])

            #expect(SettingsStore(defaults: defaults).favorites.urls == [b, a])
            #expect(
                defaults.array(forKey: "favorites.paths") as? [String] == ["/tmp/fav/b", "/tmp/fav/a"]
            )
        }
    }

    @Test("Discards invalid Favorites values")
    func favoritesDropInvalidValues() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            defaults.set("/tmp/fav/a", forKey: "favorites.paths")
            #expect(store.favorites.urls.isEmpty)

            defaults.set(
                ["/tmp/fav/a", 3, "", "relative/path", "/tmp/fav/a"] as [Any],
                forKey: "favorites.paths"
            )
            #expect(store.favorites.urls == [URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)])
        }
    }

    @Test("Favorite display names round-trip and are written to favorites.displayNames (R49)")
    func favoriteDisplayNamesRoundTrip() {
        withDefaults { defaults in
            let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
            let b = URL(fileURLWithPath: "/tmp/fav/b", isDirectory: true)
            let favorites = FavoriteFolders(urls: [a, b], customNames: [b.path: "2025（バックアップ）"])
            SettingsStore(defaults: defaults).favorites = favorites

            #expect(SettingsStore(defaults: defaults).favorites == favorites)
            #expect(
                defaults.dictionary(forKey: "favorites.displayNames") as? [String: String]
                    == [b.path: "2025（バックアップ）"]
            )
        }
    }

    @Test("The legacy favorites.paths-only format retains registration order with no display names (EC-45)")
    func favoritesLegacyFormatHasNoDisplayNames() {
        withDefaults { defaults in
            defaults.set(["/tmp/fav/b", "/tmp/fav/a"], forKey: "favorites.paths")
            let favorites = SettingsStore(defaults: defaults).favorites
            let b = URL(fileURLWithPath: "/tmp/fav/b", isDirectory: true)
            let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
            #expect(favorites.urls == [b, a])
            #expect(favorites.customName(for: a) == nil)
            #expect(favorites.customName(for: b) == nil)
            #expect(favorites.customNamesByPath.isEmpty)
        }
    }

    @Test("A non-dictionary favorites.displayNames leaves names unset without losing registrations")
    func favoriteDisplayNamesIgnoredWhenNotDictionary() {
        withDefaults { defaults in
            let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
            defaults.set(["/tmp/fav/a"], forKey: "favorites.paths")

            defaults.set("one", forKey: "favorites.displayNames")
            #expect(SettingsStore(defaults: defaults).favorites.urls == [a])
            #expect(SettingsStore(defaults: defaults).favorites.customNamesByPath.isEmpty)

            defaults.set(["one"], forKey: "favorites.displayNames")
            #expect(SettingsStore(defaults: defaults).favorites.urls == [a])
            #expect(SettingsStore(defaults: defaults).favorites.customNamesByPath.isEmpty)
        }
    }

    @Test("Discards non-string, unregistered-path, and whitespace-only display names and removes newlines")
    func favoriteDisplayNamesDropInvalidEntries() {
        withDefaults { defaults in
            defaults.set(["/tmp/fav/a", "/tmp/fav/b", "/tmp/fav/c", "/tmp/fav/d"], forKey: "favorites.paths")
            defaults.set(
                [
                    "/tmp/fav/a": 3,
                    "/tmp/fav/b": "  ",
                    "/tmp/fav/c": "o\nne",
                    "/tmp/fav/x": "unregistered",
                    "/tmp/fav/d": "ok",
                ] as [String: Any],
                forKey: "favorites.displayNames"
            )
            #expect(
                SettingsStore(defaults: defaults).favorites.customNamesByPath
                    == ["/tmp/fav/c": "one", "/tmp/fav/d": "ok"]
            )
        }
    }

    @Test("Reads a saved 300-character value truncated to 255 characters")
    func favoriteDisplayNamesAreTruncatedOnRead() {
        withDefaults { defaults in
            defaults.set(["/tmp/fav/a"], forKey: "favorites.paths")
            defaults.set(
                ["/tmp/fav/a": String(repeating: "x", count: 300)],
                forKey: "favorites.displayNames"
            )
            #expect(
                SettingsStore(defaults: defaults).favorites.customNamesByPath
                    == ["/tmp/fav/a": String(repeating: "x", count: 255)]
            )
        }
    }

    @Test("Removes the favorites.displayNames key when no display names remain")
    func favoriteDisplayNamesKeyRemovedWhenEmpty() {
        withDefaults { defaults in
            let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
            let store = SettingsStore(defaults: defaults)
            store.favorites = FavoriteFolders(urls: [a], customNames: [a.path: "one"])
            #expect(defaults.object(forKey: "favorites.displayNames") != nil)

            store.favorites = FavoriteFolders(urls: [a])
            #expect(defaults.object(forKey: "favorites.displayNames") == nil)
        }
    }

    @Test("Does not write display names for removed registrations")
    func removedFavoriteDisplayNameIsNotWritten() {
        withDefaults { defaults in
            let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
            let b = URL(fileURLWithPath: "/tmp/fav/b", isDirectory: true)
            var favorites = FavoriteFolders(urls: [a, b], customNames: [a.path: "one", b.path: "two"])
            favorites.remove(b)
            let store = SettingsStore(defaults: defaults)
            store.favorites = favorites

            #expect(
                defaults.dictionary(forKey: "favorites.displayNames") as? [String: String]
                    == [a.path: "one"]
            )
            #expect(defaults.array(forKey: "favorites.paths") as? [String] == ["/tmp/fav/a"])
        }
    }

    @Test("Saving Favorites preserves other settings")
    func savingFavoritesKeepsOtherSettings() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
            store.viewSettings = ViewSettings(
                displayMode: .thumbnails,
                thumbnailSize: 200,
                sortOrder: SortOrder(column: .kind, ascending: false),
                lastFolder: folder,
                showsToolbar: true
            )
            store.playback = PlaybackOptions(autoplay: false, loop: false)
            store.confirmation = ConfirmationOptions(confirmBeforeFileOperations: false)

            store.favorites = FavoriteFolders(urls: [URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)])

            let view = store.viewSettings
            #expect(view.displayMode == .thumbnails)
            #expect(view.thumbnailSize == 200)
            #expect(view.sortOrder == SortOrder(column: .kind, ascending: false))
            #expect(view.lastFolder?.path == folder.path)
            #expect(view.showsToolbar)
            #expect(store.playback == PlaybackOptions(autoplay: false, loop: false))
            #expect(!store.confirmation.confirmBeforeFileOperations)
        }
    }

    @Test("Location sorting is not saved while other view settings are; a saved location value is read as name sorting")
    func locationSortIsNotPersisted() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            var view = store.viewSettings
            view.sortOrder = SortOrder(column: .kind, ascending: true)
            store.viewSettings = view

            view.sortOrder = SortOrder(column: .location, ascending: false)
            view.displayMode = .thumbnails
            store.viewSettings = view

            #expect(defaults.string(forKey: "view.sort.column") == "kind")
            #expect(defaults.object(forKey: "view.sort.ascending") as? Bool == true)
            #expect(store.viewSettings.displayMode == .thumbnails)
            #expect(store.viewSettings.sortOrder == SortOrder(column: .kind, ascending: true))

            defaults.set("location", forKey: "view.sort.column")
            #expect(store.viewSettings.sortOrder.column == .name)
        }
    }

    // MARK: - Zip File Visibility (view.showsZipFiles)

    @Test("Zip visibility defaults to false when unset and zip files are hidden on first launch")
    func showsZipFilesDefaultsToFalse() {
        withDefaults { defaults in
            #expect(defaults.object(forKey: "view.showsZipFiles") == nil)
            #expect(SettingsStore(defaults: defaults).viewSettings.showsZipFiles == false)
        }
    }

    @Test("Non-Bool zip visibility falls back to false")
    func showsZipFilesFallsBackForInvalidValue() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            defaults.set("yes", forKey: "view.showsZipFiles")
            #expect(store.viewSettings.showsZipFiles == false)
            defaults.set(1.5, forKey: "view.showsZipFiles")
            #expect(store.viewSettings.showsZipFiles == false)
        }
    }

    @Test("Zip visibility can be written and read back")
    func showsZipFilesRoundTrips() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)

            var view = store.viewSettings
            view.showsZipFiles = true
            store.viewSettings = view
            #expect(defaults.object(forKey: "view.showsZipFiles") as? Bool == true)
            #expect(SettingsStore(defaults: defaults).viewSettings.showsZipFiles == true)

            view.showsZipFiles = false
            store.viewSettings = view
            #expect(defaults.object(forKey: "view.showsZipFiles") as? Bool == false)
            #expect(SettingsStore(defaults: defaults).viewSettings.showsZipFiles == false)
        }
    }

    @Test("Changing only zip visibility preserves other view settings")
    func togglingZipVisibilityKeepsOtherViewSettings() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let folder = URL(fileURLWithPath: "/tmp/example", isDirectory: true)
            store.viewSettings = ViewSettings(
                displayMode: .thumbnails,
                thumbnailSize: 200,
                sortOrder: SortOrder(column: .kind, ascending: false),
                lastFolder: folder,
                showsToolbar: true
            )

            var updated = store.viewSettings
            updated.showsZipFiles = true
            store.viewSettings = updated

            let view = store.viewSettings
            #expect(view.showsZipFiles)
            #expect(view.displayMode == .thumbnails)
            #expect(view.thumbnailSize == 200)
            #expect(view.sortOrder == SortOrder(column: .kind, ascending: false))
            #expect(view.lastFolder?.path == folder.path)
            #expect(view.showsToolbar)
        }
    }

    @Test("ViewSettings.showsZipFiles defaults to false and can be specified in the initializer")
    func viewSettingsInitializerHandlesZipVisibility() {
        #expect(ViewSettings().showsZipFiles == false)
        #expect(ViewSettings(showsZipFiles: true).showsZipFiles == true)
    }

    // MARK: - Slideshow (slideshow.*)

    @Test("Unset slideshow settings default to three seconds, repeat enabled, and no transition")
    func slideshowDefaults() {
        withDefaults { defaults in
            let options = SettingsStore(defaults: defaults).slideshow
            #expect(options == SlideshowOptions.defaults)
            #expect(options.intervalSeconds == 3)
            #expect(options.repeats)
            #expect(options.transition == .none)
            #expect(options.interval == .seconds(3))
        }
    }

    @Test("Slideshow settings round-trip and are written to dedicated keys")
    func slideshowRoundTrips() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            let options = SlideshowOptions(intervalSeconds: 10, repeats: false, transition: .crossfade)
            store.slideshow = options

            #expect(SettingsStore(defaults: defaults).slideshow == options)
            #expect(defaults.object(forKey: "slideshow.intervalSeconds") as? Int == 10)
            #expect(defaults.object(forKey: "slideshow.repeats") as? Bool == false)
            #expect(defaults.string(forKey: "slideshow.transition") == "crossfade")

            for effect in SlideshowTransitionEffect.allCases {
                store.slideshow = SlideshowOptions(intervalSeconds: 1, repeats: true, transition: effect)
                #expect(store.slideshow.transition == effect)
            }
            store.slideshow = SlideshowOptions(intervalSeconds: 3600)
            #expect(store.slideshow.intervalSeconds == 3600)
        }
    }

    @Test("Initializing with an out-of-range interval uses three seconds")
    func slideshowOptionsInitializerRejectsOutOfRangeInterval() {
        #expect(SlideshowOptions(intervalSeconds: 0).intervalSeconds == 3)
        #expect(SlideshowOptions(intervalSeconds: 3601).intervalSeconds == 3)
        #expect(SlideshowOptions(intervalSeconds: -5).intervalSeconds == 3)
        #expect(SlideshowOptions.intervalRange == 1...3600)
    }

    @Test("Changing the interval after initialization cannot retain an out-of-range value")
    func slideshowOptionsMutationValidatesInterval() {
        var options = SlideshowOptions(intervalSeconds: 10, repeats: false, transition: .zoom)
        for value in [0, -1, 3601, Int.min, Int.max] {
            options.intervalSeconds = value
            #expect(options.intervalSeconds == 3)
            #expect(options.interval == .seconds(3))
            #expect(!options.repeats)
            #expect(options.transition == .zoom)
        }
        for value in [1, 10, 3600] {
            options.intervalSeconds = value
            #expect(options.intervalSeconds == value)
            #expect(options.interval == .seconds(value))
        }
    }

    @Test("An invalid slideshow interval falls back to three seconds while preserving other saved settings")
    func slideshowInvalidIntervalFallsBackOnly() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            defaults.set(false, forKey: "slideshow.repeats")
            defaults.set("zoom", forKey: "slideshow.transition")

            let invalid: [Any] = [0, 3601, -1, 3.5, "10", true, Double.nan, 1e300]
            for value in invalid {
                defaults.set(value, forKey: "slideshow.intervalSeconds")
                let options = store.slideshow
                #expect(options.intervalSeconds == 3, "value: \(value)")
                #expect(!options.repeats)
                #expect(options.transition == .zoom)
            }

            defaults.set(5.0, forKey: "slideshow.intervalSeconds")
            #expect(store.slideshow.intervalSeconds == 5)
        }
    }

    @Test("An invalid slideshow repeat value falls back to true while preserving other saved settings")
    func slideshowInvalidRepeatsFallsBackOnly() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            defaults.set(20, forKey: "slideshow.intervalSeconds")
            defaults.set("slide", forKey: "slideshow.transition")
            for value in ["no", "yes", 1] as [Any] {
                defaults.set(value, forKey: "slideshow.repeats")
                let options = store.slideshow
                #expect(options.repeats)
                #expect(options.intervalSeconds == 20)
                #expect(options.transition == .slide)
            }
        }
    }

    @Test("An invalid slideshow transition falls back to none while preserving other saved settings")
    func slideshowInvalidTransitionFallsBackOnly() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            defaults.set(20, forKey: "slideshow.intervalSeconds")
            defaults.set(false, forKey: "slideshow.repeats")

            for value in ["fade", "", "Crossfade", 3] as [Any] {
                defaults.set(value, forKey: "slideshow.transition")
                let options = store.slideshow
                #expect(options.transition == .none, "value: \(value)")
                #expect(options.intervalSeconds == 20)
                #expect(!options.repeats)
            }
        }
    }

    @Test("Saving slideshow settings preserves existing keys")
    func savingSlideshowKeepsOtherSettings() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            store.viewSettings = ViewSettings(displayMode: .thumbnails, thumbnailSize: 200, showsToolbar: true)
            store.playback = PlaybackOptions(autoplay: false, loop: false)
            store.confirmation = ConfirmationOptions(confirmBeforeFileOperations: false)
            let a = URL(fileURLWithPath: "/tmp/fav/a", isDirectory: true)
            store.favorites = FavoriteFolders(urls: [a], customNames: [a.path: "one"])

            store.slideshow = SlideshowOptions(intervalSeconds: 7, repeats: false, transition: .slide)

            #expect(store.viewSettings.displayMode == .thumbnails)
            #expect(store.viewSettings.thumbnailSize == 200)
            #expect(store.viewSettings.showsToolbar)
            #expect(store.playback == PlaybackOptions(autoplay: false, loop: false))
            #expect(!store.confirmation.confirmBeforeFileOperations)
            #expect(store.favorites.urls == [a])
            #expect(store.favorites.customName(for: a) == "one")
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("could not create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
