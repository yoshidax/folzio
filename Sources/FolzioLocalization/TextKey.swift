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

    case menuAppSettings = "menu.app.settings"
    case menuAppQuit = "menu.app.quit"
    case menuFile = "menu.file"
    case menuFileOpen = "menu.file.open"
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
    case toolbarStartSlideshowHelp = "toolbar.startSlideshowHelp"
    case toolbarZoomInHelp = "toolbar.zoomInHelp"
    case toolbarZoomToFitHelp = "toolbar.zoomToFitHelp"
    case toolbarZoomOutHelp = "toolbar.zoomOutHelp"
    case toolbarThumbnails = "toolbar.thumbnails"
    case toolbarList = "toolbar.list"

    // MARK: - Settings Window

    case settingsWindow = "settings.window"
    case settingsLanguage = "settings.language"
    case settingsLanguageEnglish = "settings.language.english"
    case settingsLanguageJapanese = "settings.language.japanese"
    case settingsVideo = "settings.video"
    case settingsAutoplay = "settings.autoplay"
    case settingsLoop = "settings.loop"
    case settingsFileOperations = "settings.fileOperations"
    case settingsConfirm = "settings.confirm"
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

    // MARK: - File List and Tree

    case listColumnName = "list.column.name"
    case listColumnCreationDate = "list.column.creationDate"
    case listColumnKind = "list.column.kind"
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
    case dialogOperationSummary = "dialog.operation.summary"
    case dialogOperationFailureLine = "dialog.operation.failureLine"
    case dialogOperationMore = "dialog.operation.more"
    case dialogCancel = "dialog.cancel"
    case dialogOK = "dialog.ok"

    // MARK: - Accessibility

    case a11yThumbnail = "a11y.thumbnail"

    /// Argument sequence (determines the positions and kinds of the positional format specifiers).
    public var arguments: [TextArgument] {
        switch self {
        case .errorZipCannotOpen, .errorOperationTrashExistingFailed, .errorOperationSystemFailure,
             .listSortAscending, .listSortDescending,
             .dialogConfirmBullet, .dialogConfirmDestination, .dialogConfirmLocation,
             .dialogFavoriteRemoveItems, .previewUnavailable:
            return [.text]
        case .contextCopySingle:
            return [.text]
        case .dialogExtensionMessage, .dialogOperationFailureLine:
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
        default:
            return []
        }
    }

    /// Translator-facing description (where the string is used and what each value means).
    public var comment: String {
        switch self {
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
             .errorOperationSameNameExists, .errorOperationSameNameAtDestination:
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
        case .menuAppSettings:
            return "Settings item in the application menu (ends with … because it opens a dialog)"
        case .menuAppQuit:
            return "Quit item in the application menu. Do not translate the app name"
        case .menuFile, .menuEdit, .menuView, .menuGo:
            return "Menu bar menu names"
        case .menuFileOpen, .menuFileShowContents, .menuFileEnclosingFolder,
             .menuFileRevealInFinder, .menuFileAddToFavorites, .menuFileFind,
             .menuFileTrash, .menuFileRemoveFromFavorites:
            return "File menu items (the Trash and Remove from Favorites items swap depending on the state)"
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
             .toolbarViewMode, .toolbarSize:
            return "Toolbar group names"
        case .toolbarThumbnailSize:
            return "Thumbnail size in the toolbar and size bar. Includes the shortcut"
        case .toolbarStartSlideshowHelp:
            return "Slideshow tooltip. Includes the shortcut"
        case .toolbarZoomInHelp, .toolbarZoomToFitHelp, .toolbarZoomOutHelp:
            return "Zoom in and out tooltips. Include the shortcuts"
        case .toolbarThumbnails, .toolbarList:
            return "View mode options in the toolbar"
        case .settingsWindow:
            return "Settings window title"
        case .settingsLanguage:
            return "Display language label in the Settings window"
        case .settingsLanguageEnglish, .settingsLanguageJapanese:
            return "Display language options. Each language name is shown in that language"
        case .settingsVideo, .settingsFileOperations, .settingsSlideshow:
            return "Section headings in the Settings window"
        case .settingsAutoplay, .settingsLoop, .settingsConfirm, .settingsRepeat:
            return "Checkboxes in the Settings window"
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
        case .listColumnName, .listColumnCreationDate, .listColumnKind, .listColumnLocation:
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
        case .dialogOperationSummary:
            return "Counts of successful and failed file operations. The values are formatted counts"
        case .dialogOperationFailureLine:
            return "One failure line for a file operation. The values are the name and the reason"
        case .dialogOperationMore:
            return "Remaining failure count for file operations. The value is the formatted count"
        case .a11yThumbnail:
            return "Accessibility label for a thumbnail image"
        }
    }
}
