import Foundation
import FolzioCore

/// Kinds of arguments accepted by a translation unit (data-model.md). Arguments are inserted using positional
/// format specifiers.
public enum TextArgument: Sendable, Equatable {
    /// File names, paths, keywords, OS reasons, and similar values. Inserted verbatim (EC-109).
    case text
    /// A count. Passes two values: the integer used for plural selection and the count formatted for the region (R6).
    case count
    /// A count used as the value of a label whose wording does not change (passes only the formatted string).
    case number
}

/// One user-visible string (translation unit). Defined in `Resources/{en,ja}.lproj/Localizable.strings(dict)`.
public enum TextKey: String, CaseIterable, Sendable {
    // MARK: - Import

    case importImagePrefix = "import.name.image"
    case errorImportNotImageOrVideo = "error.import.notImageOrVideo"
    case errorImportUnsupportedImage = "error.import.unsupportedImage"
    case errorImportUnsupportedVideo = "error.import.unsupportedVideo"
    case errorImportNotRegularFile = "error.import.notRegularFile"
    case errorImportTooLargeImage = "error.import.tooLargeImage"
    case errorImportTooLargeVideo = "error.import.tooLargeVideo"
    case errorImportTooManyPixels = "error.import.tooManyPixels"
    case errorImportTimedOut = "error.import.timedOut"
    case errorImportSourceFailed = "error.import.sourceFailed"
    case receivingProgress = "import.receiving.progress"
    case receivingCancel = "import.receiving.cancel"
    case receivingStage = "import.receiving.stage"
    case checkingStage = "import.checking.stage"
    case shortcutCancelReceivingCondition = "shortcuts.condition.cancelReceiving"
    case menuCancelReceiving = "menu.edit.cancelReceiving"

    // MARK: - Core Values

    case errorSearchRootEmpty = "error.searchRoot.empty"
    case errorSearchRootNotAbsolute = "error.searchRoot.notAbsolute"
    case errorSearchRootNotFound = "error.searchRoot.notFound"
    case errorSearchRootNotAFolder = "error.searchRoot.notAFolder"
    case errorSearchRootAccessDenied = "error.searchRoot.accessDenied"
    case errorSearchRootNoUsableFolder = "error.searchRoot.noUsableFolder"

    case errorZipCannotOpen = "error.zip.cannotOpen"
    case errorZipNotFound = "error.zip.notFound"
    case errorZipAccessDenied = "error.zip.accessDenied"
    case errorZipNotAZip = "error.zip.notAZip"
    case errorZipMultiDisk = "error.zip.multiDisk"
    case errorZipEntryEncrypted = "error.zip.entryEncrypted"
    case errorZipUnsupportedMethod = "error.zip.unsupportedMethod"
    case errorZipTooLarge = "error.zip.tooLarge"

    case errorZipCorruptedCannotStartInflate = "error.zip.corrupted.cannotStartInflate"
    case errorZipCorruptedCompressedDataDamaged = "error.zip.corrupted.compressedDataDamaged"
    case errorZipCorruptedDataTruncated = "error.zip.corrupted.dataTruncated"
    case errorZipCorruptedCompressedDataTruncated = "error.zip.corrupted.compressedDataTruncated"
    case errorZipCorruptedHeaderDamaged = "error.zip.corrupted.headerDamaged"
    case errorZipCorruptedInvalidOffset = "error.zip.corrupted.invalidOffset"
    case errorZipCorruptedCentralDirectoryTooLarge = "error.zip.corrupted.centralDirectoryTooLarge"
    case errorZipCorruptedInvalidLocation = "error.zip.corrupted.invalidLocation"
    case errorZipCorruptedEntryNotFound = "error.zip.corrupted.entryNotFound"
    case errorZipCorruptedSizeMismatch = "error.zip.corrupted.sizeMismatch"
    case errorZipCorruptedDataOutsideFile = "error.zip.corrupted.dataOutsideFile"
    case errorZipCorruptedReadCancelled = "error.zip.corrupted.readCancelled"
    case errorZipCorruptedReadFailed = "error.zip.corrupted.readFailed"
    case errorZipCorruptedUnreadable = "error.zip.corrupted.unreadable"

    case errorNameEmpty = "error.name.empty"
    case errorNameForbiddenCharacter = "error.name.forbiddenCharacter"
    case errorNameLeadingDot = "error.name.leadingDot"
    case errorNameDuplicate = "error.name.duplicate"
    case errorNameBecomesPackage = "error.name.becomesPackage"

    case errorOperationNoDestination = "error.operation.noDestination"
    case errorOperationDestinationNotFound = "error.operation.destinationNotFound"
    case errorOperationSourceNotFound = "error.operation.sourceNotFound"
    case errorOperationIntoItself = "error.operation.intoItself"
    case errorOperationSameNameExists = "error.operation.sameNameExists"
    case errorOperationSameNameAtDestination = "error.operation.sameNameAtDestination"
    case errorOperationReplacementContainsSource = "error.operation.replacementContainsSource"
    case errorOperationTrashExistingFailed = "error.operation.trashExistingFailed"
    case errorOperationSystemFailure = "error.operation.systemFailure"

    case emptyFilterImages = "empty.filter.images"
    case emptyFilterVideos = "empty.filter.videos"
    case emptyFolderNotFound = "empty.folderNotFound"
    case emptyLoading = "empty.loading"
    case emptySearching = "empty.searching"
    case emptyNoMedia = "empty.noMedia"
    case emptyNoMatches = "empty.noMatches"
    case emptyAccessDenied = "empty.accessDenied"

    case previewScrollHorizontal = "preview.scroll.horizontal"
    case previewScrollVertical = "preview.scroll.vertical"
    case previewNoMedia = "preview.noMedia"
    case previewUnavailable = "preview.unavailable"
    case previewAnimationUnavailable = "preview.animationUnavailable"
    case previewFailureUnreadable = "preview.failure.unreadable"
    case previewFailureUnsupportedFormat = "preview.failure.unsupportedFormat"
    case previewFailureCorrupted = "preview.failure.corrupted"

    case kindFolder = "kind.folder"
    case kindZipArchive = "kind.zipArchive"

    // MARK: - Menu Bar

    case menuAppAbout = "menu.app.about"
    case menuAppSettings = "menu.app.settings"
    case menuAppQuit = "menu.app.quit"
    case menuFile = "menu.file"
    case menuFileNewFolder = "menu.file.newFolder"
    case menuFileOpen = "menu.file.open"
    case menuFileOpenWith = "menu.file.openWith"
    case menuFileOpenWithDefaultSuffix = "menu.file.openWith.defaultSuffix"
    case menuFileShowContents = "menu.file.showContents"
    case menuFileEnclosingFolder = "menu.file.enclosingFolder"
    case menuFileRevealInFinder = "menu.file.revealInFinder"
    case menuFileAddToFavorites = "menu.file.addToFavorites"
    case menuFileFind = "menu.file.find"
    case menuFileTrash = "menu.file.trash"
    case menuFileRemoveFromFavorites = "menu.file.removeFromFavorites"
    case menuEdit = "menu.edit"
    case menuEditUndo = "menu.edit.undo"
    case menuEditRedo = "menu.edit.redo"
    case menuEditCut = "menu.edit.cut"
    case menuEditCopy = "menu.edit.copy"
    case menuEditPaste = "menu.edit.paste"
    case menuEditMovePaste = "menu.edit.movePaste"
    case menuEditCopyPathname = "menu.edit.copyPathname"
    case menuEditDuplicate = "menu.edit.duplicate"
    case menuEditRename = "menu.edit.rename"
    case menuEditSelectAll = "menu.edit.selectAll"
    case menuView = "menu.view"
    case menuViewShowToolbar = "menu.view.showToolbar"
    case menuViewHideToolbar = "menu.view.hideToolbar"
    case menuViewFullScreen = "menu.view.fullScreen"
    case menuViewZoomIn = "menu.view.zoomIn"
    case menuViewZoomOut = "menu.view.zoomOut"
    case menuViewZoomToFit = "menu.view.zoomToFit"
    case menuViewStartSlideshow = "menu.view.startSlideshow"
    case menuViewShowFileListOnly = "menu.view.showFileListOnly"
    case menuViewShowPreviewOnly = "menu.view.showPreviewOnly"
    case menuViewFocusTree = "menu.view.focusTree"
    case menuViewFocusFileList = "menu.view.focusFileList"
    case menuViewFocusPreview = "menu.view.focusPreview"
    case menuViewGoToFavorites = "menu.view.goToFavorites"
    case menuViewAsThumbnails = "menu.view.asThumbnails"
    case menuViewAsList = "menu.view.asList"
    case menuViewLargerThumbnails = "menu.view.largerThumbnails"
    case menuViewSmallerThumbnails = "menu.view.smallerThumbnails"
    case menuViewShowImagesOnly = "menu.view.showImagesOnly"
    case menuViewShowVideosOnly = "menu.view.showVideosOnly"
    case menuViewShowZipFiles = "menu.view.showZipFiles"
    case menuViewSortBy = "menu.view.sortBy"
    case menuGo = "menu.go"
    case menuGoBack = "menu.go.back"
    case menuGoForward = "menu.go.forward"

    // MARK: - Context Menu

    case contextCopySingle = "context.copy.single"
    case contextCopyMultiple = "context.copy.multiple"
    case contextPasteHere = "context.pasteHere"
    case contextMovePasteHere = "context.movePasteHere"

    // MARK: - Toolbar

    case toolbarHistory = "toolbar.history"
    case toolbarPanes = "toolbar.panes"
    case toolbarZoomGroup = "toolbar.zoomGroup"
    case toolbarMediaType = "toolbar.mediaType"
    case toolbarViewMode = "toolbar.viewMode"
    case toolbarSize = "toolbar.size"
    case toolbarThumbnailSize = "toolbar.thumbnailSize"
    case toolbarSlideshowLabel = "toolbar.slideshowLabel"
    case toolbarZipFilesLabel = "toolbar.zipFilesLabel"
    case toolbarThumbnailSizeLabel = "toolbar.thumbnailSizeLabel"
    case toolbarGoBackHelp = "toolbar.goBackHelp"
    case toolbarGoForwardHelp = "toolbar.goForwardHelp"
    case toolbarShowFileListOnlyHelp = "toolbar.showFileListOnlyHelp"
    case toolbarShowPreviewOnlyHelp = "toolbar.showPreviewOnlyHelp"
    case toolbarShowImagesOnlyHelp = "toolbar.showImagesOnlyHelp"
    case toolbarShowVideosOnlyHelp = "toolbar.showVideosOnlyHelp"
    case toolbarZipFilesHelp = "toolbar.zipFilesHelp"
    case toolbarStartSlideshowHelp = "toolbar.startSlideshowHelp"
    case toolbarStopSlideshowHelp = "toolbar.stopSlideshowHelp"
    case toolbarZoomInHelp = "toolbar.zoomInHelp"
    case toolbarZoomToFitHelp = "toolbar.zoomToFitHelp"
    case toolbarZoomOutHelp = "toolbar.zoomOutHelp"
    case toolbarThumbnails = "toolbar.thumbnails"
    case toolbarList = "toolbar.list"

    // MARK: - Settings Window

    case settingsWindow = "settings.window"
    case settingsPreview = "settings.preview"
    case settingsPreviewMode = "settings.preview.mode"
    case settingsPreviewModeWheel = "settings.preview.mode.wheel"
    case settingsPreviewModeTraditional = "settings.preview.mode.traditional"
    case settingsLanguage = "settings.language"
    case settingsLanguageEnglish = "settings.language.english"
    case settingsLanguageJapanese = "settings.language.japanese"
    case settingsVideo = "settings.video"
    case settingsAutoplay = "settings.autoplay"
    case settingsLoop = "settings.loop"
    case settingsFileOperations = "settings.fileOperations"
    case settingsConfirm = "settings.confirm"
    case settingsConfirmNote = "settings.confirm.note"
    case settingsSlideshow = "settings.slideshow"
    case settingsInterval = "settings.interval"
    case settingsSeconds = "settings.seconds"
    case settingsIntervalA11y = "settings.intervalA11y"
    case settingsRepeat = "settings.repeat"
    case settingsTransition = "settings.transition"
    case settingsTransitionNone = "settings.transition.none"
    case settingsTransitionCrossfade = "settings.transition.crossfade"
    case settingsTransitionSlide = "settings.transition.slide"
    case settingsTransitionZoom = "settings.transition.zoom"
    case settingsTabGeneral = "settings.tab.general"
    case settingsTabShortcuts = "settings.tab.shortcuts"
    case settingsShortcutsList = "settings.shortcuts.list"
    case settingsShortcutsRecord = "settings.shortcuts.record"
    case settingsShortcutsRecording = "settings.shortcuts.recording"
    case settingsShortcutsReset = "settings.shortcuts.reset"
    case settingsShortcutsResetAll = "settings.shortcuts.resetAll"
    case settingsShortcutsChanged = "settings.shortcuts.changed"
    case settingsShortcutsRecordFor = "settings.shortcuts.recordFor"
    case settingsShortcutsResetFor = "settings.shortcuts.resetFor"
    case settingsShortcutsErrorModifier = "settings.shortcuts.error.modifier"
    case settingsShortcutsErrorFixed = "settings.shortcuts.error.fixed"
    case settingsShortcutsErrorConflict = "settings.shortcuts.error.conflict"
    case settingsShortcutsErrorDefaultConflict = "settings.shortcuts.error.defaultConflict"
    case settingsShortcutsClear = "settings.shortcuts.clear"
    case settingsShortcutsClearFor = "settings.shortcuts.clearFor"
    case settingsShortcutsUnset = "settings.shortcuts.unset"

    // MARK: - File List and Tree

    case listColumnName = "list.column.name"
    case listColumnCreationDate = "list.column.creationDate"
    case listColumnKind = "list.column.kind"
    case listColumnSize = "list.column.size"
    case listColumnModificationDate = "list.column.modificationDate"
    case listColumnLocation = "list.column.location"
    case listSortAscending = "list.sort.ascending"
    case listSortDescending = "list.sort.descending"
    case listParentRow = "list.parentRow"

    case treeColumn = "tree.column"
    case treeFavorites = "tree.favorites"
    case treeTooltipNotAccessible = "tree.tooltip.notAccessible"
    case treeTooltipNotFound = "tree.tooltip.notFound"
    case treeA11yFavoriteName = "tree.a11y.favoriteName"
    case treeA11yFolderName = "tree.a11y.folderName"
    case folderDefaultName = "folder.defaultName"

    // MARK: - Search

    case searchKeyword = "search.keyword"
    case searchRoot = "search.root"
    case searchChoose = "search.choose"
    case searchChooseHelp = "search.choose.help"
    case searchSearch = "search.search"
    case searchError = "search.error"
    case searchPanelTitle = "search.panel.title"
    case searchPanelMessage = "search.panel.message"
    case searchPanelPrompt = "search.panel.prompt"
    case searchPanelFailed = "search.panel.failed"
    case searchBarResults = "search.bar.results"
    case searchBarSearching = "search.bar.searching"
    case searchBarCount = "search.bar.count"
    case searchBarCountLimited = "search.bar.countLimited"

    // MARK: - Confirmation Modals and Dialogs

    case dialogConfirmCopy = "dialog.confirm.copy"
    case dialogConfirmMove = "dialog.confirm.move"
    case dialogConfirmRename = "dialog.confirm.rename"
    case dialogConfirmTrash = "dialog.confirm.trash"
    case dialogConfirmItems = "dialog.confirm.items"
    case dialogConfirmBullet = "dialog.confirm.bullet"
    case dialogConfirmMore = "dialog.confirm.more"
    case dialogConfirmFolderTrash = "dialog.confirm.folderTrash"
    case dialogConfirmFolderProcess = "dialog.confirm.folderProcess"
    case dialogConfirmDestination = "dialog.confirm.destination"
    case dialogConfirmLocation = "dialog.confirm.location"
    case dialogConfirmContinue = "dialog.confirm.continue"
    case dialogConfirmDontAsk = "dialog.confirm.dontAsk"
    case dialogFavoriteRemoveTitle = "dialog.favoriteRemove.title"
    case dialogFavoriteRemoveItems = "dialog.favoriteRemove.items"
    case dialogFavoriteRemoveNote = "dialog.favoriteRemove.note"
    case dialogFavoriteRemoveConfirm = "dialog.favoriteRemove.confirm"
    case dialogConflictTitle = "dialog.conflict.title"
    case dialogConflictItems = "dialog.conflict.items"
    case dialogConflictReplace = "dialog.conflict.replace"
    case dialogConflictKeepBoth = "dialog.conflict.keepBoth"
    case dialogConflictStop = "dialog.conflict.stop"
    case dialogConflictApplyAll = "dialog.conflict.applyAll"
    case dialogExtensionTitle = "dialog.extension.title"
    case dialogExtensionMessage = "dialog.extension.message"
    case dialogExtensionConfirm = "dialog.extension.confirm"
    case dialogRenameFailed = "dialog.rename.failed"
    case dialogOperationFailed = "dialog.operation.failed"
    case dialogOpenWithFailed = "dialog.openWith.failed"
    case dialogOpenWithDetail = "dialog.openWith.detail"
    case dialogOperationSummary = "dialog.operation.summary"
    case dialogOperationFailureLine = "dialog.operation.failureLine"
    case dialogOperationMore = "dialog.operation.more"
    case dialogTreeTrashOverlapTitle = "dialog.treeTrashOverlap.title"
    case dialogTreeTrashOverlapMessage = "dialog.treeTrashOverlap.message"
    case dialogCancel = "dialog.cancel"
    case dialogOK = "dialog.ok"

    // MARK: - About Dialog

    case aboutWindow = "about.window"
    case aboutVersion = "about.version"
    case aboutIcon = "about.icon"
    case aboutLink = "about.link"

    // MARK: - Shortcut Reference

    case menuFileShortcuts = "menu.file.shortcuts"
    case menuFileClose = "menu.file.close"
    case shortcutsWindow = "shortcuts.window"
    case shortcutsSectionPanes = "shortcuts.section.panes"
    case shortcutsSectionNavigation = "shortcuts.section.navigation"
    case shortcutsSectionFiles = "shortcuts.section.files"
    case shortcutsSectionSearch = "shortcuts.section.search"
    case shortcutsSectionImages = "shortcuts.section.images"
    case shortcutsSectionPlayback = "shortcuts.section.playback"
    case shortcutsSectionApplication = "shortcuts.section.application"
    case shortcutPaneCycle = "shortcuts.entry.paneCycle"
    case shortcutPaneCycleCondition = "shortcuts.condition.paneCycle"
    case shortcutPaneFocus = "shortcuts.entry.paneFocus"
    case shortcutPaneFocusCondition = "shortcuts.condition.paneFocus"
    case shortcutListOnly = "shortcuts.entry.listOnly"
    case shortcutListOnlyCondition = "shortcuts.condition.listOnly"
    case shortcutPreviewOnly = "shortcuts.entry.previewOnly"
    case shortcutPreviewOnlyCondition = "shortcuts.condition.previewOnly"
    case shortcutToolbar = "shortcuts.entry.toolbar"
    case shortcutListStyle = "shortcuts.entry.listStyle"
    case shortcutThumbnailSize = "shortcuts.entry.thumbnailSize"
    case shortcutThumbnailSizeCondition = "shortcuts.condition.thumbnailSize"
    case shortcutImageFilter = "shortcuts.entry.imageFilter"
    case shortcutImageFilterCondition = "shortcuts.condition.imageFilter"
    case shortcutMovieFilter = "shortcuts.entry.movieFilter"
    case shortcutMovieFilterCondition = "shortcuts.condition.movieFilter"
    case shortcutZipVisibility = "shortcuts.entry.zipVisibility"
    case shortcutZipVisibilityCondition = "shortcuts.condition.zipVisibility"
    case shortcutTreeSelect = "shortcuts.entry.treeSelect"
    case shortcutTreeSelectCondition = "shortcuts.condition.treeSelect"
    case shortcutTreeExpand = "shortcuts.entry.treeExpand"
    case shortcutTreeExpandCondition = "shortcuts.condition.treeExpand"
    case shortcutTreeExpandAll = "shortcuts.entry.treeExpandAll"
    case shortcutTreeExpandAllCondition = "shortcuts.condition.treeExpandAll"
    case shortcutOpenContainer = "shortcuts.entry.openContainer"
    case shortcutOpenContainerCondition = "shortcuts.condition.openContainer"
    case shortcutEnclosingFolder = "shortcuts.entry.enclosingFolder"
    case shortcutEnclosingFolderCondition = "shortcuts.condition.enclosingFolder"
    case shortcutHistory = "shortcuts.entry.history"
    case shortcutHistoryCondition = "shortcuts.condition.history"
    case shortcutFavorites = "shortcuts.entry.favorites"
    case shortcutFavoritesCondition = "shortcuts.condition.favorites"
    case shortcutAddFavorite = "shortcuts.entry.addFavorite"
    case shortcutAddFavoriteCondition = "shortcuts.condition.addFavorite"
    case shortcutSelection = "shortcuts.entry.selection"
    case shortcutSelectionCondition = "shortcuts.condition.selection"
    case shortcutExtendSelection = "shortcuts.entry.extendSelection"
    case shortcutExtendSelectionCondition = "shortcuts.condition.extendSelection"
    case shortcutOpenDefault = "shortcuts.entry.openDefault"
    case shortcutOpenDefaultCondition = "shortcuts.condition.openDefault"
    case shortcutQuickLook = "shortcuts.entry.quickLook"
    case shortcutQuickLookCondition = "shortcuts.condition.quickLook"
    case shortcutRename = "shortcuts.entry.rename"
    case shortcutRenameCondition = "shortcuts.condition.rename"
    case shortcutCopy = "shortcuts.entry.copy"
    case shortcutCopyCondition = "shortcuts.condition.copy"
    case shortcutPaste = "shortcuts.entry.paste"
    case shortcutPasteCondition = "shortcuts.condition.paste"
    case shortcutCopyPath = "shortcuts.entry.copyPath"
    case shortcutCopyPathCondition = "shortcuts.condition.copyPath"
    case shortcutDuplicate = "shortcuts.entry.duplicate"
    case shortcutDuplicateCondition = "shortcuts.condition.duplicate"
    case shortcutNewFolder = "shortcuts.entry.newFolder"
    case shortcutNewFolderCondition = "shortcuts.condition.newFolder"
    case shortcutTrash = "shortcuts.entry.trash"
    case shortcutTrashCondition = "shortcuts.condition.trash"
    case shortcutFind = "shortcuts.entry.find"
    case shortcutFindCondition = "shortcuts.condition.find"
    case shortcutSearchSubmit = "shortcuts.entry.searchSubmit"
    case shortcutSearchSubmitCondition = "shortcuts.condition.searchSubmit"
    case shortcutEndSearch = "shortcuts.entry.endSearch"
    case shortcutEndSearchCondition = "shortcuts.condition.endSearch"
    case shortcutImageZoom = "shortcuts.entry.imageZoom"
    case shortcutImageZoomCondition = "shortcuts.condition.imageZoom"
    case shortcutImageFit = "shortcuts.entry.imageFit"
    case shortcutImageFitCondition = "shortcuts.condition.imageFit"
    case shortcutImageScroll = "shortcuts.entry.imageScroll"
    case shortcutImageScrollCondition = "shortcuts.condition.imageScroll"
    case shortcutFullScreen = "shortcuts.entry.fullScreen"
    case shortcutFullScreenCondition = "shortcuts.condition.fullScreen"
    case shortcutVideoPlay = "shortcuts.entry.videoPlay"
    case shortcutVideoPlayCondition = "shortcuts.condition.videoPlay"
    case shortcutVideoControls = "shortcuts.entry.videoControls"
    case shortcutVideoControlsCondition = "shortcuts.condition.videoControls"
    case shortcutVideoSeek = "shortcuts.entry.videoSeek"
    case shortcutVideoSeekCondition = "shortcuts.condition.videoSeek"
    case shortcutSlideshowStart = "shortcuts.entry.slideshowStart"
    case shortcutSlideshowStartCondition = "shortcuts.condition.slideshowStart"
    case shortcutSlideshowNavigate = "shortcuts.entry.slideshowNavigate"
    case shortcutSlideshowNavigateCondition = "shortcuts.condition.slideshowNavigate"
    case shortcutSlideshowStop = "shortcuts.entry.slideshowStop"
    case shortcutSlideshowStopCondition = "shortcuts.condition.slideshowStop"
    case shortcutSettings = "shortcuts.entry.settings"
    case shortcutCheatsheet = "shortcuts.entry.cheatsheet"
    case shortcutCheatsheetCondition = "shortcuts.condition.cheatsheet"
    case shortcutClose = "shortcuts.entry.close"
    case shortcutCloseCondition = "shortcuts.condition.close"
    case shortcutQuit = "shortcuts.entry.quit"

    // MARK: - Accessibility

    case a11yThumbnail = "a11y.thumbnail"

    /// Argument sequence (determines the positions and kinds of the positional format specifiers).
    public var arguments: [TextArgument] {
        switch self {
        case .errorZipCannotOpen, .errorOperationTrashExistingFailed, .errorOperationSystemFailure,
             .listSortAscending, .listSortDescending,
             .dialogConfirmBullet, .dialogConfirmDestination, .dialogConfirmLocation,
             .dialogFavoriteRemoveItems, .previewUnavailable, .aboutVersion,
             .toolbarGoBackHelp, .toolbarGoForwardHelp, .toolbarShowFileListOnlyHelp, .toolbarShowPreviewOnlyHelp, .toolbarShowImagesOnlyHelp,
             .toolbarShowVideosOnlyHelp, .toolbarZipFilesHelp, .toolbarStartSlideshowHelp, .toolbarZoomInHelp, .toolbarZoomToFitHelp,
             .toolbarZoomOutHelp, .toolbarThumbnails, .toolbarList, .toolbarThumbnailSize,
             .settingsShortcutsRecordFor, .settingsShortcutsResetFor, .settingsShortcutsErrorConflict, .settingsShortcutsErrorDefaultConflict,
             .settingsShortcutsClearFor:
            return [.text]
        case .contextCopySingle:
            return [.text]
        case .dialogExtensionMessage, .dialogOperationFailureLine, .dialogOpenWithDetail:
            return [.text, .text]
        case .searchBarResults, .searchBarSearching:
            return [.text, .text, .text]
        case .contextCopyMultiple, .dialogConfirmCopy, .dialogConfirmMove, .searchBarCount:
            return [.count]
        case .searchBarCountLimited:
            return [.count, .text]
        case .dialogConfirmItems, .dialogConfirmMore, .dialogConflictItems, .dialogOperationMore:
            return [.number]
        case .dialogOperationSummary:
            return [.number, .number]
        case .errorImportTimedOut:
            return [.number]
        case .receivingProgress:
            return [.number, .number, .text]
        default:
            return []
        }
    }

    /// Translator-facing description (where the string is used and what each value means).
    public var comment: String {
        switch self {
        case .shortcutCancelReceivingCondition, .importImagePrefix, .errorImportNotImageOrVideo, .errorImportUnsupportedImage, .errorImportUnsupportedVideo, .errorImportNotRegularFile, .errorImportTooLargeImage, .errorImportTooLargeVideo, .errorImportTooManyPixels, .errorImportTimedOut, .errorImportSourceFailed, .receivingProgress, .receivingCancel, .receivingStage, .checkingStage, .menuCancelReceiving:
            return "Text for receiving an external image or video. Timeout takes seconds; progress takes total, completed, and formatted size."
        case .menuFileShortcuts:
            return "File menu item that opens the shortcut reference"
        case .menuFileClose:
            return "File menu item that closes the key window"
        case .shortcutsWindow:
            return "Shortcut reference window title"
        case .shortcutsSectionPanes:
            return "Purpose heading in the shortcut reference"
        case .shortcutsSectionNavigation:
            return "Purpose heading in the shortcut reference"
        case .shortcutsSectionFiles:
            return "Purpose heading in the shortcut reference"
        case .shortcutsSectionSearch:
            return "Purpose heading in the shortcut reference"
        case .shortcutsSectionImages:
            return "Purpose heading in the shortcut reference"
        case .shortcutsSectionPlayback:
            return "Purpose heading in the shortcut reference"
        case .shortcutsSectionApplication:
            return "Purpose heading in the shortcut reference"
        case .shortcutPaneCycle:
            return "Action description in the shortcut reference"
        case .shortcutPaneCycleCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutPaneFocus:
            return "Action description in the shortcut reference"
        case .shortcutPaneFocusCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutListOnly:
            return "Action description in the shortcut reference"
        case .shortcutListOnlyCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutPreviewOnly:
            return "Action description in the shortcut reference"
        case .shortcutPreviewOnlyCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutToolbar:
            return "Action description in the shortcut reference"
        case .shortcutListStyle:
            return "Action description in the shortcut reference"
        case .shortcutThumbnailSize:
            return "Action description in the shortcut reference"
        case .shortcutThumbnailSizeCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutImageFilter:
            return "Action description in the shortcut reference"
        case .shortcutImageFilterCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutMovieFilter:
            return "Action description in the shortcut reference"
        case .shortcutMovieFilterCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutZipVisibility:
            return "Action description in the shortcut reference"
        case .shortcutZipVisibilityCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutTreeSelect:
            return "Action description in the shortcut reference"
        case .shortcutTreeSelectCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutTreeExpand:
            return "Action description in the shortcut reference"
        case .shortcutTreeExpandCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutTreeExpandAll:
            return "Action description in the shortcut reference"
        case .shortcutTreeExpandAllCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutOpenContainer:
            return "Action description in the shortcut reference"
        case .shortcutOpenContainerCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutEnclosingFolder:
            return "Action description in the shortcut reference"
        case .shortcutEnclosingFolderCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutHistory:
            return "Action description in the shortcut reference"
        case .shortcutHistoryCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutFavorites:
            return "Action description in the shortcut reference"
        case .shortcutFavoritesCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutAddFavorite:
            return "Action description in the shortcut reference"
        case .shortcutAddFavoriteCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutSelection:
            return "Action description in the shortcut reference"
        case .shortcutSelectionCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutExtendSelection:
            return "Action description in the shortcut reference"
        case .shortcutExtendSelectionCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutOpenDefault:
            return "Action description in the shortcut reference"
        case .shortcutOpenDefaultCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutQuickLook:
            return "Action description in the shortcut reference"
        case .shortcutQuickLookCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutRename:
            return "Action description in the shortcut reference"
        case .shortcutRenameCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutCopy:
            return "Action description in the shortcut reference"
        case .shortcutCopyCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutPaste:
            return "Action description in the shortcut reference"
        case .shortcutPasteCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutCopyPath:
            return "Action description in the shortcut reference"
        case .shortcutCopyPathCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutDuplicate:
            return "Action description in the shortcut reference"
        case .shortcutDuplicateCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutNewFolder:
            return "Action description in the shortcut reference"
        case .shortcutNewFolderCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutTrash:
            return "Action description in the shortcut reference"
        case .shortcutTrashCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutFind:
            return "Action description in the shortcut reference"
        case .shortcutFindCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutSearchSubmit:
            return "Action description in the shortcut reference"
        case .shortcutSearchSubmitCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutEndSearch:
            return "Action description in the shortcut reference"
        case .shortcutEndSearchCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutImageZoom:
            return "Action description in the shortcut reference"
        case .shortcutImageZoomCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutImageFit:
            return "Action description in the shortcut reference"
        case .shortcutImageFitCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutImageScroll:
            return "Action description in the shortcut reference"
        case .shortcutImageScrollCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutFullScreen:
            return "Action description in the shortcut reference"
        case .shortcutFullScreenCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutVideoPlay:
            return "Action description in the shortcut reference"
        case .shortcutVideoPlayCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutVideoControls:
            return "Action description in the shortcut reference"
        case .shortcutVideoControlsCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutVideoSeek:
            return "Action description in the shortcut reference"
        case .shortcutVideoSeekCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutSlideshowStart:
            return "Action description in the shortcut reference"
        case .shortcutSlideshowStartCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutSlideshowNavigate:
            return "Action description in the shortcut reference"
        case .shortcutSlideshowNavigateCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutSlideshowStop:
            return "Action description in the shortcut reference"
        case .shortcutSlideshowStopCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutSettings:
            return "Action description in the shortcut reference"
        case .shortcutCheatsheet:
            return "Action description in the shortcut reference"
        case .shortcutCheatsheetCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutClose:
            return "Action description in the shortcut reference"
        case .shortcutCloseCondition:
            return "Availability note below a shortcut reference action"
        case .shortcutQuit:
            return "Action description in the shortcut reference"
        case .errorSearchRootEmpty, .errorSearchRootNotAbsolute, .errorSearchRootNotFound,
             .errorSearchRootNotAFolder, .errorSearchRootAccessDenied, .errorSearchRootNoUsableFolder:
            return "Reason shown below the input field when the search sheet validates its search root"
        case .errorZipCannotOpen:
            return "Lead-in for the reason a zip cannot be opened. The value is the reason sentence"
        case .errorZipNotFound, .errorZipAccessDenied, .errorZipNotAZip, .errorZipMultiDisk:
            return "Reason a zip cannot be opened (the value of errorZipCannotOpen)"
        case .errorZipEntryEncrypted, .errorZipUnsupportedMethod, .errorZipTooLarge:
            return "Reason an entry in a zip cannot be displayed"
        case .errorZipCorruptedCannotStartInflate, .errorZipCorruptedCompressedDataDamaged,
             .errorZipCorruptedDataTruncated, .errorZipCorruptedCompressedDataTruncated,
             .errorZipCorruptedHeaderDamaged, .errorZipCorruptedInvalidOffset,
             .errorZipCorruptedCentralDirectoryTooLarge, .errorZipCorruptedInvalidLocation,
             .errorZipCorruptedEntryNotFound, .errorZipCorruptedSizeMismatch,
             .errorZipCorruptedDataOutsideFile, .errorZipCorruptedReadCancelled,
             .errorZipCorruptedReadFailed, .errorZipCorruptedUnreadable:
            return "Reason the contents of a zip are damaged (the value of errorZipCannotOpen)"
        case .errorNameEmpty, .errorNameForbiddenCharacter, .errorNameLeadingDot,
             .errorNameDuplicate, .errorNameBecomesPackage:
            return "Reason a name cannot be used for renaming"
        case .errorOperationNoDestination, .errorOperationDestinationNotFound,
             .errorOperationSourceNotFound, .errorOperationIntoItself,
             .errorOperationSameNameExists, .errorOperationSameNameAtDestination,
             .errorOperationReplacementContainsSource:
            return "Reason a file operation failed"
        case .errorOperationTrashExistingFailed:
            return "Reason an existing item could not be moved to the Trash. The value is the reason returned by the OS"
        case .errorOperationSystemFailure:
            return "Reason the OS rejected a file operation. The value is the reason returned by the OS (do not re-translate)"
        case .emptyFilterImages, .emptyFilterVideos:
            return "Empty state when the media type filter leaves no items"
        case .emptyFolderNotFound:
            return "Empty state when the folder to open cannot be found"
        case .emptyLoading:
            return "Loading state for the file list and preview"
        case .emptySearching:
            return "Empty state while searching"
        case .emptyNoMedia:
            return "Empty state for a folder with no supported media files"
        case .emptyNoMatches:
            return "Empty state when the search returns no results"
        case .emptyAccessDenied:
            return "Empty state when the folder cannot be read"
        case .previewScrollHorizontal, .previewScrollVertical:
            return "Accessibility label for the preview image's scroll bars"
        case .previewNoMedia:
            return "Preview when there is no media file to display"
        case .previewUnavailable:
            return "Title shown when the preview cannot be displayed. The value is the reason"
        case .previewAnimationUnavailable:
            return "Reason an animated image cannot be displayed"
        case .previewFailureUnreadable, .previewFailureUnsupportedFormat, .previewFailureCorrupted:
            return "Reason the preview cannot be displayed"
        case .kindFolder, .kindZipArchive:
            return "Fallback kind name (when the OS does not return a kind name)"
        case .menuAppAbout:
            return "About item in the application menu (the first item). Do not translate the app name"
        case .aboutWindow:
            return "Name of the About window. Not drawn on screen; used as the window title for accessibility"
        case .aboutVersion:
            return "Version line in the About window. %1$@ is the version number, for example 1.0.0"
        case .aboutIcon:
            return "Accessibility description of the app icon in the About window"
        case .aboutLink:
            return "Accessibility help of the repository link in the About window"
        case .menuAppSettings:
            return "Settings item in the application menu (ends with … because it opens a dialog)"
        case .menuAppQuit:
            return "Quit item in the application menu. Do not translate the app name"
        case .menuFile, .menuEdit, .menuView, .menuGo:
            return "Menu bar menu names"
        case .menuFileNewFolder, .menuFileOpen, .menuFileOpenWith, .menuFileShowContents, .menuFileEnclosingFolder,
             .menuFileRevealInFinder, .menuFileAddToFavorites, .menuFileFind,
             .menuFileTrash, .menuFileRemoveFromFavorites:
            return "File menu items (the Trash and Remove from Favorites items swap depending on the state)"
        case .menuFileOpenWithDefaultSuffix:
            return "Suffix that identifies the default application in the Open With submenu"
        case .menuEditUndo, .menuEditRedo, .menuEditCut, .menuEditCopy, .menuEditPaste,
             .menuEditMovePaste, .menuEditCopyPathname, .menuEditDuplicate, .menuEditRename, .menuEditSelectAll:
            return "Edit menu items"
        case .menuViewShowToolbar, .menuViewHideToolbar:
            return "Toolbar visibility toggle in the View menu (the item swaps depending on the state)"
        case .menuViewFullScreen, .menuViewZoomIn, .menuViewZoomOut, .menuViewZoomToFit,
             .menuViewStartSlideshow, .menuViewShowFileListOnly, .menuViewShowPreviewOnly,
             .menuViewFocusTree, .menuViewFocusFileList, .menuViewFocusPreview,
             .menuViewGoToFavorites, .menuViewAsThumbnails, .menuViewAsList,
             .menuViewLargerThumbnails, .menuViewSmallerThumbnails,
             .menuViewShowImagesOnly, .menuViewShowVideosOnly, .menuViewShowZipFiles,
             .menuViewSortBy:
            return "View menu items"
        case .menuGoBack, .menuGoForward:
            return "History items in the Go menu"
        case .contextCopySingle:
            return "Copy in the context menu (single item). The value is the file name"
        case .contextCopyMultiple:
            return "Copy in the context menu (multiple items). The wording changes with the count"
        case .contextPasteHere, .contextMovePasteHere:
            return "Paste in the directory tree's context menu"
        case .toolbarHistory, .toolbarPanes, .toolbarZoomGroup, .toolbarMediaType,
             .toolbarViewMode, .toolbarSize, .toolbarZipFilesLabel,
             .toolbarThumbnailSizeLabel:
            return "Toolbar group names. They are also shown in the customization palette and in the text display mode"
        case .toolbarSlideshowLabel:
            return "Name of the Slideshow toolbar item. Also shown in the customization palette and in the text display mode. "
                + "It is also the accessibility label of the toggle button, which VoiceOver reads in both the on and off states"
        case .toolbarThumbnailSize:
            return "Thumbnail size in the toolbar and size bar. The value is the shortcut text"
        case .toolbarStartSlideshowHelp:
            return "Slideshow tooltip. The value is the shortcut text"
        case .toolbarStopSlideshowHelp:
            return "Tooltip and accessibility help of the Slideshow toggle button while a slideshow is running. Esc is a fixed key"
        case .toolbarZoomInHelp, .toolbarZoomToFitHelp, .toolbarZoomOutHelp:
            return "Zoom in, zoom to fit, and zoom out tooltips. The value is the shortcut text"
        case .toolbarGoBackHelp, .toolbarGoForwardHelp, .toolbarShowFileListOnlyHelp, .toolbarShowPreviewOnlyHelp,
             .toolbarShowImagesOnlyHelp, .toolbarShowVideosOnlyHelp, .toolbarZipFilesHelp:
            return "Toolbar button tooltips and accessibility text. They are separate from the menu item names. The value is the shortcut text"
        case .toolbarThumbnails, .toolbarList:
            return "View mode options in the toolbar. Tooltips. The value is the shortcut text"
        case .settingsTabGeneral:
            return "Settings window tab name for the general settings"
        case .settingsTabShortcuts:
            return "Settings window tab name for the shortcut assignments"
        case .settingsShortcutsList:
            return "Accessibility label of the shortcut assignment list in the Settings window"
        case .settingsShortcutsRecord:
            return "Button that starts recording a new shortcut for a command"
        case .settingsShortcutsRecording:
            return "Prompt shown in place of the key while a shortcut is being recorded"
        case .settingsShortcutsReset:
            return "Button that returns one command to its default shortcut"
        case .settingsShortcutsResetAll:
            return "Button that returns every command to its default shortcut"
        case .settingsShortcutsChanged:
            return "Marker for a command whose shortcut differs from the default"
        case .settingsShortcutsRecordFor:
            return "Accessibility label of the Record button. The value is the command name"
        case .settingsShortcutsResetFor:
            return "Accessibility label of the Reset button. The value is the command name"
        case .settingsShortcutsErrorModifier:
            return "Error when the typed shortcut has none of Command, Control, or Option"
        case .settingsShortcutsErrorFixed:
            return "Error when the typed shortcut is reserved or fixed"
        case .settingsShortcutsErrorConflict:
            return "Error when another command uses the typed shortcut. The value is that command name"
        case .settingsShortcutsErrorDefaultConflict:
            return "Error when the default shortcut of a command is used by another command. The value is that command name"
        case .settingsShortcutsClear:
            return "Button that removes the shortcut of a command, so that the command has no key"
        case .settingsShortcutsClearFor:
            return "Accessibility label of the Clear button. The value is the command name"
        case .settingsShortcutsUnset:
            return "Shown in place of the key of a command that has no shortcut, in the Settings window, the shortcut reference, and tooltips"
        case .settingsWindow:
            return "Settings window title"
        case .settingsPreviewMode, .settingsPreviewModeWheel, .settingsPreviewModeTraditional:
            return "Preview interaction mode setting and options"
        case .settingsLanguage:
            return "Display language label in the Settings window"
        case .settingsLanguageEnglish, .settingsLanguageJapanese:
            return "Display language options. Each language name is shown in that language"
        case .settingsPreview, .settingsVideo, .settingsFileOperations, .settingsSlideshow:
            return "Section headings in the Settings window"
        case .settingsAutoplay, .settingsLoop, .settingsConfirm, .settingsRepeat:
            return "Checkboxes in the Settings window"
        case .settingsConfirmNote:
            return "Supplementary note under the confirmation checkbox in the Settings window. Also its accessibility help"
        case .settingsInterval:
            return "Interval label in the Settings window"
        case .settingsSeconds:
            return "Interval unit (after the number)"
        case .settingsIntervalA11y:
            return "Accessibility label for the interval field"
        case .settingsTransition:
            return "Transition label and accessibility label in the Settings window"
        case .settingsTransitionNone, .settingsTransitionCrossfade,
             .settingsTransitionSlide, .settingsTransitionZoom:
            return "Transition options"
        case .listColumnName, .listColumnCreationDate, .listColumnKind, .listColumnSize,
             .listColumnModificationDate, .listColumnLocation:
            return "List view column headings. Also used in the sort menu"
        case .listSortAscending:
            return "Selected column in the sort menu (ascending). The value is the column name"
        case .listSortDescending:
            return "Selected column in the sort menu (descending). The value is the column name"
        case .listParentRow:
            return "Accessibility label for the `..` row in the list"
        case .treeColumn:
            return "Directory tree column heading"
        case .treeFavorites:
            return "Fixed row in the directory tree (Favorites)"
        case .treeTooltipNotAccessible, .treeTooltipNotFound:
            return "Tooltip for a directory tree row"
        case .treeA11yFavoriteName, .treeA11yFolderName:
            return "Accessibility label for a name edit field in the directory tree"
        case .folderDefaultName:
            return "Default name of a folder created with New Folder, before the user renames it. Use Finder's wording"
        case .searchKeyword, .searchRoot, .searchChoose, .searchChooseHelp,
             .searchSearch, .searchError:
            return "Labels, buttons, and accessibility text in the search sheet"
        case .searchPanelTitle, .searchPanelMessage, .searchPanelPrompt:
            return "Text for the folder selection panel used to choose the search root"
        case .searchPanelFailed:
            return "Reason the folder selection panel could not be opened"
        case .searchBarResults:
            return "Completed-state sentence in the search bar. Values are the keyword, search root folder name, and count phrase"
        case .searchBarSearching:
            return "Searching-state sentence in the search bar. Values are the keyword, search root folder name, and count phrase"
        case .searchBarCount:
            return "Count phrase in the search bar. The wording changes with the count"
        case .searchBarCountLimited:
            return "Count phrase in the search bar (truncated at the limit). The wording changes with the count, and the displayed count is inserted as a value"
        case .dialogConfirmCopy, .dialogConfirmMove:
            return "Title for the copy or move confirmation. The wording changes with the count, but the count is not shown"
        case .dialogConfirmRename, .dialogConfirmTrash:
            return "Title for the rename or Trash confirmation"
        case .dialogConfirmItems:
            return "Number of items in the confirmation modal. The value is the formatted count"
        case .dialogConfirmBullet:
            return "One line per item in the confirmation modal. The value is the file name"
        case .dialogConfirmMore:
            return "Remaining item count in the confirmation modal. The value is the formatted count"
        case .dialogConfirmFolderTrash, .dialogConfirmFolderProcess:
            return "Note that folders are processed with their contents"
        case .dialogConfirmDestination, .dialogConfirmLocation:
            return "Folder path in the confirmation modal. The value is the path"
        case .dialogConfirmContinue, .dialogCancel, .dialogOK:
            return "Dialog buttons"
        case .dialogConfirmDontAsk:
            return "The \"Don't ask again\" option in the confirmation modal"
        case .dialogFavoriteRemoveTitle, .dialogFavoriteRemoveItems,
             .dialogFavoriteRemoveNote, .dialogFavoriteRemoveConfirm:
            return "Confirmation for removing from Favorites"
        case .dialogConflictTitle:
            return "Conflict dialog title"
        case .dialogConflictItems:
            return "Conflicting item count in the conflict dialog. The value is the formatted count"
        case .dialogConflictReplace, .dialogConflictKeepBoth, .dialogConflictStop:
            return "Conflict dialog buttons"
        case .dialogConflictApplyAll:
            return "The \"Apply to All\" option in the conflict dialog"
        case .dialogExtensionTitle, .dialogExtensionMessage, .dialogExtensionConfirm:
            return "Confirmation for changing the file extension. Values are the file name and the new extension"
        case .dialogRenameFailed:
            return "Title shown when renaming fails"
        case .dialogOperationFailed:
            return "Title shown when a file operation fails"
        case .dialogOpenWithFailed:
            return "Title shown when the selected application cannot open a file"
        case .dialogOpenWithDetail:
            return "Open With failure details. The values are the application name and the OS error message"
        case .dialogOperationSummary:
            return "Counts of successful and failed file operations. The values are formatted counts"
        case .dialogOperationFailureLine:
            return "One failure line for a file operation. The values are the name and the reason"
        case .dialogOperationMore:
            return "Remaining failure count for file operations. The value is the formatted count"
        case .dialogTreeTrashOverlapTitle, .dialogTreeTrashOverlapMessage:
            return "Error shown when folders selected in the directory tree include a folder inside another selected folder, so nothing is moved to the Trash"
        case .a11yThumbnail:
            return "Accessibility label for a thumbnail image"
        }
    }
}
