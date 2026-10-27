import Foundation

public struct FileListChrome: Sendable, Equatable {
    public var displayMode: DisplayMode
    public var toolbarShown: Bool

    public init(displayMode: DisplayMode, toolbarShown: Bool) {
        self.displayMode = displayMode
        self.toolbarShown = toolbarShown
    }

    public var showsBottomSizeBar: Bool {
        displayMode == .thumbnails && !toolbarShown
    }

    public var toolbarSliderEnabled: Bool {
        displayMode == .thumbnails
    }
}
