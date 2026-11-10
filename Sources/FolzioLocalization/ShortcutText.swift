import FolzioCore

/// Maps stable shortcut IDs to complete, localized descriptions and availability notes.
public enum ShortcutText {
    public static func heading(_ section: ShortcutSection) -> TextKey {
        switch section {
        case .panes: return .shortcutsSectionPanes
        case .navigation: return .shortcutsSectionNavigation
        case .files: return .shortcutsSectionFiles
        case .search: return .shortcutsSectionSearch
        case .images: return .shortcutsSectionImages
        case .playback: return .shortcutsSectionPlayback
        case .application: return .shortcutsSectionApplication
        }
    }

    public static func description(_ id: ShortcutID) -> TextKey {
        switch id {
        case .paneCycle: return .shortcutPaneCycle
        case .paneFocus: return .shortcutPaneFocus
        case .listOnly: return .shortcutListOnly
        case .previewOnly: return .shortcutPreviewOnly
        case .toolbar: return .shortcutToolbar
        case .listStyle: return .shortcutListStyle
        case .thumbnailSize: return .shortcutThumbnailSize
        case .imageFilter: return .shortcutImageFilter
        case .movieFilter: return .shortcutMovieFilter
        case .zipVisibility: return .shortcutZipVisibility
        case .treeSelect: return .shortcutTreeSelect
        case .treeExpand: return .shortcutTreeExpand
        case .treeExpandAll: return .shortcutTreeExpandAll
        case .openContainer: return .shortcutOpenContainer
        case .enclosingFolder: return .shortcutEnclosingFolder
        case .history: return .shortcutHistory
        case .favorites: return .shortcutFavorites
        case .addFavorite: return .shortcutAddFavorite
        case .selection: return .shortcutSelection
        case .extendSelection: return .shortcutExtendSelection
        case .openDefault: return .shortcutOpenDefault
        case .quickLook: return .shortcutQuickLook
        case .rename: return .shortcutRename
        case .copy: return .shortcutCopy
        case .cancelReceiving: return .menuCancelReceiving
        case .paste: return .shortcutPaste
        case .copyPath: return .shortcutCopyPath
        case .duplicate: return .shortcutDuplicate
        case .newFolder: return .shortcutNewFolder
        case .trash: return .shortcutTrash
        case .find: return .shortcutFind
        case .searchSubmit: return .shortcutSearchSubmit
        case .endSearch: return .shortcutEndSearch
        case .imageZoom: return .shortcutImageZoom
        case .imageFit: return .shortcutImageFit
        case .imageScroll: return .shortcutImageScroll
        case .fullScreen: return .shortcutFullScreen
        case .videoPlay: return .shortcutVideoPlay
        case .videoControls: return .shortcutVideoControls
        case .videoSeek: return .shortcutVideoSeek
        case .slideshowStart: return .shortcutSlideshowStart
        case .slideshowNavigate: return .shortcutSlideshowNavigate
        case .slideshowStop: return .shortcutSlideshowStop
        case .settings: return .shortcutSettings
        case .cheatsheet: return .shortcutCheatsheet
        case .close: return .shortcutClose
        case .quit: return .shortcutQuit
        }
    }

    public static func condition(_ id: ShortcutID) -> TextKey? {
        switch id {
        case .paneCycle: return .shortcutPaneCycleCondition
        case .paneFocus: return .shortcutPaneFocusCondition
        case .listOnly: return .shortcutListOnlyCondition
        case .previewOnly: return .shortcutPreviewOnlyCondition
        case .toolbar: return nil
        case .listStyle: return nil
        case .thumbnailSize: return .shortcutThumbnailSizeCondition
        case .imageFilter: return .shortcutImageFilterCondition
        case .movieFilter: return .shortcutMovieFilterCondition
        case .zipVisibility: return .shortcutZipVisibilityCondition
        case .treeSelect: return .shortcutTreeSelectCondition
        case .treeExpand: return .shortcutTreeExpandCondition
        case .treeExpandAll: return .shortcutTreeExpandAllCondition
        case .openContainer: return .shortcutOpenContainerCondition
        case .enclosingFolder: return .shortcutEnclosingFolderCondition
        case .history: return .shortcutHistoryCondition
        case .favorites: return .shortcutFavoritesCondition
        case .addFavorite: return .shortcutAddFavoriteCondition
        case .selection: return .shortcutSelectionCondition
        case .extendSelection: return .shortcutExtendSelectionCondition
        case .openDefault: return .shortcutOpenDefaultCondition
        case .quickLook: return .shortcutQuickLookCondition
        case .rename: return .shortcutRenameCondition
        case .copy: return .shortcutCopyCondition
        case .cancelReceiving: return .shortcutCancelReceivingCondition
        case .paste: return .shortcutPasteCondition
        case .copyPath: return .shortcutCopyPathCondition
        case .duplicate: return .shortcutDuplicateCondition
        case .newFolder: return .shortcutNewFolderCondition
        case .trash: return .shortcutTrashCondition
        case .find: return .shortcutFindCondition
        case .searchSubmit: return .shortcutSearchSubmitCondition
        case .endSearch: return .shortcutEndSearchCondition
        case .imageZoom: return .shortcutImageZoomCondition
        case .imageFit: return .shortcutImageFitCondition
        case .imageScroll: return .shortcutImageScrollCondition
        case .fullScreen: return .shortcutFullScreenCondition
        case .videoPlay: return .shortcutVideoPlayCondition
        case .videoControls: return .shortcutVideoControlsCondition
        case .videoSeek: return .shortcutVideoSeekCondition
        case .slideshowStart: return .shortcutSlideshowStartCondition
        case .slideshowNavigate: return .shortcutSlideshowNavigateCondition
        case .slideshowStop: return .shortcutSlideshowStopCondition
        case .settings: return nil
        case .cheatsheet: return .shortcutCheatsheetCondition
        case .close: return .shortcutCloseCondition
        case .quit: return nil
        }
    }

    /// The menu item name that identifies a customizable command in the Settings window and in conflict messages.
    public static func commandName(_ id: ShortcutCommandID) -> TextKey {
        switch id {
        case .focusTree: return .menuViewFocusTree
        case .focusFileList: return .menuViewFocusFileList
        case .focusPreview: return .menuViewFocusPreview
        case .fileListOnly: return .menuViewShowFileListOnly
        case .previewOnly: return .menuViewShowPreviewOnly
        case .toolbar: return .menuViewShowToolbar
        case .thumbnails: return .menuViewAsThumbnails
        case .list: return .menuViewAsList
        case .largerThumbnails: return .menuViewLargerThumbnails
        case .smallerThumbnails: return .menuViewSmallerThumbnails
        case .imagesOnly: return .menuViewShowImagesOnly
        case .videosOnly: return .menuViewShowVideosOnly
        case .zipVisibility: return .menuViewShowZipFiles
        case .showContents: return .menuFileShowContents
        case .enclosingFolder: return .menuFileEnclosingFolder
        case .back: return .menuGoBack
        case .forward: return .menuGoForward
        case .goToFavorites: return .menuViewGoToFavorites
        case .addToFavorites: return .menuFileAddToFavorites
        case .open: return .menuFileOpen
        case .movePaste: return .menuEditMovePaste
        case .copyPathname: return .menuEditCopyPathname
        case .duplicate: return .menuEditDuplicate
        case .newFolder: return .menuFileNewFolder
        case .trash: return .menuFileTrash
        case .find: return .menuFileFind
        case .zoomIn: return .menuViewZoomIn
        case .zoomOut: return .menuViewZoomOut
        case .zoomToFit: return .menuViewZoomToFit
        case .fullScreen: return .menuViewFullScreen
        case .startSlideshow: return .menuViewStartSlideshow
        case .shortcuts: return .menuFileShortcuts
        }
    }
}
