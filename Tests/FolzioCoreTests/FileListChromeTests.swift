import Testing
@testable import FolzioCore

@Suite("FileListChrome")
struct FileListChromeTests {
    @Test("Thumbnails mode with the toolbar hidden shows the bottom bar and enables the slider")
    func thumbnailsWithoutToolbar() {
        let chrome = FileListChrome(displayMode: .thumbnails, toolbarShown: false)
        #expect(chrome.showsBottomSizeBar)
        #expect(chrome.toolbarSliderEnabled)
    }

    @Test("Thumbnails mode with the toolbar visible hides the bottom bar and enables the slider")
    func thumbnailsWithToolbar() {
        let chrome = FileListChrome(displayMode: .thumbnails, toolbarShown: true)
        #expect(!chrome.showsBottomSizeBar)
        #expect(chrome.toolbarSliderEnabled)
    }

    @Test("List mode with the toolbar hidden hides the bottom bar and disables the slider")
    func listWithoutToolbar() {
        let chrome = FileListChrome(displayMode: .list, toolbarShown: false)
        #expect(!chrome.showsBottomSizeBar)
        #expect(!chrome.toolbarSliderEnabled)
    }

    @Test("List mode with the toolbar visible hides the bottom bar and disables the slider")
    func listWithToolbar() {
        let chrome = FileListChrome(displayMode: .list, toolbarShown: true)
        #expect(!chrome.showsBottomSizeBar)
        #expect(!chrome.toolbarSliderEnabled)
    }
}
