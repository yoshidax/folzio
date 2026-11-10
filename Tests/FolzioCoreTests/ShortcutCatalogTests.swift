import FolzioCore
import Testing

@Suite("Shortcut Catalog")
struct ShortcutCatalogTests {
    @Test("Every approved shortcut has the expected glyphs, group, and display order")
    func matchesApprovedContract() {
        let expected = """
        paneCycle|Tab / ⇧Tab|panes
        paneFocus|⌥⌘1 / ⌥⌘2 / ⌥⌘3|panes
        listOnly|⌃⌘2|panes
        previewOnly|⌃⌘3|panes
        toolbar|⇧⌘T|panes
        listStyle|⌘1 / ⌘2|panes
        thumbnailSize|⌃⌘. / ⌃⌘,|panes
        imageFilter|⇧⌘I|panes
        movieFilter|⇧⌘M|panes
        zipVisibility|⌃⌘Z|panes
        treeSelect|↑ / ↓|navigation
        treeExpand|→ / ←|navigation
        treeExpandAll|⌥→ / ⌥←|navigation
        openContainer|⌘↓|navigation
        enclosingFolder|⌘↑|navigation
        history|⌘[ / ⌘]|navigation
        favorites|⇧⌘F|navigation
        addFavorite|⌃⌘T|navigation
        selection|↑ / ↓ / ← / →|files
        extendSelection|⇧↑ / ⇧↓ / ⇧← / ⇧→ / ⌘A|files
        openDefault|⌘O|files
        quickLook|Space|files
        rename|Return|files
        copy|⌘C|files
        cancelReceiving|⌘.|files
        paste|⌘V / ⌥⌘V|files
        copyPath|⌥⌘C|files
        duplicate|⌘D|files
        newFolder|⇧⌘N|files
        trash|⌘Delete|files
        find|⌘F|search
        searchSubmit|Return / Esc|search
        endSearch|Esc / ⌘[|search
        imageZoom|⌘+ / ⌘= / ⌘-|images
        imageFit|⌘0|images
        imageScroll|⌥↑ / ⌥↓ / ⌥← / ⌥→|images
        fullScreen|⌃⌘F|images
        videoPlay|Space|playback
        videoControls|← / → / ↑ / ↓|playback
        videoSeek|< / >|playback
        slideshowStart|⇧⌘S|playback
        slideshowNavigate|↑ / ↓ / ← / →|playback
        slideshowStop|Esc|playback
        settings|⌘,|application
        cheatsheet|⌘/|application
        close|⌘W|application
        quit|⌘Q|application
        """
        let actual = ShortcutCatalog.entries.map {
            "\($0.id.rawValue)|\($0.keys)|\($0.section.rawValue)"
        }.joined(separator: "\n")
        #expect(actual == expected)
    }

    @Test("All IDs occur once and every group contains reference entries")
    func coversAllIdentifiers() {
        let ids = ShortcutCatalog.entries.map(\.id)
        #expect(ids.count == 47)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(ShortcutID.allCases))
        #expect(ShortcutSection.allCases.map(\.rawValue) == [
            "panes", "navigation", "files", "search", "images", "playback", "application",
        ])
        for section in ShortcutSection.allCases {
            #expect(!section.entries.isEmpty)
            #expect(section.entries.allSatisfy { $0.section == section && !$0.keys.isEmpty })
        }
    }
}
