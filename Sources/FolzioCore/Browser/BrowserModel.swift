import Foundation
import Observation

/// Synchronous notification when `BrowserModel` changes location (R70).
public enum LocationEvent: Sendable, Equatable {
    case navigated(leavingFocus: URL?)
    /// A search result folder row was opened and search results are no longer shown (FR-113, 140; EC-99, EC-100).
    /// `HistoryNavigator` applies the presentation state to the current history entry, then decides whether to record.
    case openedSearchResultFolder(leavingFocus: URL?)
    case relocated(vanished: [URL])
    case notFound(HistoryLocation)
}

/// Location validated without changing the display (R73). The index and failure reason are used by the display.
public struct ResolvedHistoryLocation: Sendable {
    public let location: HistoryLocation
    private let navigationGeneration: Int
    private let archiveIndex: ArchiveIndex?
    private let archiveError: ArchiveError?
    private let usesArchiveIndex: Bool

    init(
        location: HistoryLocation,
        navigationGeneration: Int,
        archiveIndex: ArchiveIndex?,
        archiveError: ArchiveError?
    ) {
        self.location = location
        self.navigationGeneration = navigationGeneration
        self.archiveIndex = archiveIndex
        self.archiveError = archiveError
        self.usesArchiveIndex = location.archive != nil
    }

    func index(for generation: Int) -> ArchiveIndex? {
        guard self.navigationGeneration == generation, usesArchiveIndex else { return nil }
        return archiveIndex
    }

    func error(for generation: Int) -> ArchiveError? {
        guard self.navigationGeneration == generation, usesArchiveIndex else { return nil }
        return archiveError
    }

    func isCurrent(for generation: Int) -> Bool {
        self.navigationGeneration == generation
    }
}

public enum HistoryLocationResolution: Sendable {
    case available(ResolvedHistoryLocation)
    case missing
    case superseded
}

@MainActor
@Observable
public final class BrowserModel {
    public private(set) var listing: FolderListing
    public private(set) var selection: SelectionState
    public private(set) var preview: PreviewContent
    public private(set) var stopPlaybackSignal = 0
    public private(set) var mediaTypeFilter = MediaTypeFilter()
    /// Whether zip file rows appear in the list (FR-095). The source of truth for persistence is
    /// `SettingsStore`'s `view.showsZipFiles`.
    public private(set) var showsZipFiles: Bool
    public var screenMaxPixel: Int
    public var playbackRequest: PlaybackOptions { settings.playback }
    /// Synchronous notification when the location changes (R70). Set by `HistoryNavigator`. Not observed by
    /// Observation.
    @ObservationIgnored public var onLocationEvent: ((LocationEvent) -> Void)?
    /// Called synchronously immediately before replacing the location (FR-126). The slideshow stops advancing here
    /// and fixes the restore target. Called before changing `listing` and `selection`. Not observed by Observation.
    @ObservationIgnored public var onWillReplaceLocation: (() -> Void)?
    /// Whether a zip is being browsed (FR-069).
    public var isBrowsingArchive: Bool { listing.archive != nil }
    /// Whether ⌘↑ has an enclosing level to return to: inside a zip, or a regular folder that is not a tree root
    /// (FR-077). False while showing search results (FR-087).
    public var hasEnclosingLevel: Bool {
        guard !isShowingSearchResults else { return false }
        return listing.archive != nil || enclosingFolder != nil
    }
    /// Whether search results are shown (FR-084–086). `listing.folder` remains the pre-search folder.
    public var isShowingSearchResults: Bool { listing.search != nil }
    /// Current display location (FR-108). Nil while showing search results or the not-found display (R70).
    public var historyLocation: HistoryLocation? {
        guard !isShowingSearchResults, !showsNotFound else { return nil }
        return HistoryLocation(folder: listing.folder, archive: listing.archive)
    }
    /// Selection in listing order without the `..` row. Target of file operations, copy, and drag (R30).
    public var operableSelection: [URL] {
        let selected = selection.selected
        guard !selected.isEmpty else { return [] }
        var urls = listing.files.filter { selected.contains($0.url) && $0.kind != .parent }.map(\.url)
        let listed = Set(listing.files.map(\.url))
        for url in selected where !listed.contains(url) && !ParentLink.isParentLink(url) {
            urls.append(url)
        }
        return urls
    }
    /// Request to synchronize the tree selection when moving to a folder within the file list (FR-078, R31).
    /// Not changed by selection from the tree (`selectFolder`), navigation inside a zip, or external changes.
    public private(set) var treeSyncRequest: TreeSyncRequest?
    /// Location (`.location`) is accepted only while showing search results and is not persisted (FR-084).
    /// Assigning it for a regular folder restores the original value.
    public var sortOrder: SortOrder {
        didSet {
            guard sortOrder != oldValue, !isRevertingSortOrder else { return }
            if sortOrder.column == .location, !isShowingSearchResults {
                // The restoring assignment also calls didSet, so skip settings writes and re-sorting during it.
                isRevertingSortOrder = true
                sortOrder = oldValue
                isRevertingSortOrder = false
                return
            }
            if sortOrder.column != .location {
                var settingsValue = settings.viewSettings
                settingsValue.sortOrder = sortOrder
                settings.viewSettings = settingsValue
            }

            if listing.state == .loaded || listing.state == .empty || listing.state == .noMatches {
                allFiles = sorted(allFiles, by: sortOrder)
                rebuildListing()
            }
        }
    }

    private let lister: any DirectoryListing
    private let decoder: any ImageDecoding
    private let cache: DecodedImageCache
    private let settings: SettingsStore
    private let archiveReader: any ArchiveReading
    private let searcher: any FileNameSearching

    /// Tree roots (home and volumes). Determine the `..` and ⌘↑ enclosing folder for regular folders (R30).
    private var navigationRoots: [URL] = []
    private var treeSyncCounter = 0
    /// ID of the tree synchronization request for a folder opened from search results. When synchronization
    /// completes, stores the location that could be selected as the last selected folder (EC-102, R10). Cleared on
    /// the next navigation.
    private var pendingSearchTreeSyncID: Int?

    /// Index of the displayed zip. Nil outside a zip, while opening, or when opening failed.
    private var archiveIndex: ArchiveIndex?
    /// Incremented on every folder or zip navigation and used to discard results from older asynchronous work.
    private var navigationGeneration = 0
    /// Sorted rows before applying the media type filter. Excludes `..`, which `rebuildListing()` adds once.
    private var allFiles: [MediaFile] = [] {
        didSet { kindFilesRevision &+= 1 }
    }
    @ObservationIgnored private var kindFilesRevision = 0
    @ObservationIgnored private var kindUpdateGeneration = 0
    @ObservationIgnored private var kindNames: KindNames
    private var listingTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var previewGeneration = 0
    private var prefetchTasks: [URL: Task<Void, Never>] = [:]
    private var isRevertingSortOrder = false

    /// Running search enumerations (the original and any added for renames). Cancelled by a new search or folder
    /// navigation (`resetForNavigation`).
    private var searchTasks: [Task<Void, Never>] = []
    /// Criteria of the current search. Used to enumerate the new location after a rename (R63).
    private var searchPattern: SearchPattern?
    /// Folder renames during the current search. Rebases URLs of results that arrive later (R63).
    private var searchLedger = SearchRenameLedger()
    private var movedSearchPaths: Set<String> = []
    /// Number of enumerations that have not finished in the current search. The search ends when it reaches 0 (R63).
    private var activeSearchStreams = 0
    /// Folder renames after opening the current zip (including while opening). Index rows are built with the zip
    /// location at open time, so they are rebased on every level change (R62, EC-50).
    private var archiveRenames: [RenamedFolder] = []
    /// Search results indexed by the folder containing the file (`standardizedFileURL.path`). Used to limit
    /// existence checks after external changes to the reported folders instead of all results (R38).
    private var searchResultsByFolder: [String: Set<URL>] = [:]
    /// Whether a regular folder load ended in the not-found display (EC-62, EC-65). Makes the history location nil.
    private var showsNotFound = false

    /// Reason for the location change (R70). The notification's `leavingFocus` is read immediately before the call.
    private enum LocationChangeReason {
        case navigated
        case openedSearchResultFolder
        case relocated(vanished: [URL])
    }

    private enum ArchiveImageResult {
        case image(DecodedImage)
        case animated(Data)
        case failure(PreviewFailure)
    }

    public init(
        kindNames: KindNames,
        lister: any DirectoryListing,
        decoder: any ImageDecoding,
        cache: DecodedImageCache,
        settings: SettingsStore,
        archiveReader: (any ArchiveReading)? = nil,
        searcher: (any FileNameSearching)? = nil
    ) {
        self.lister = lister
        self.kindNames = kindNames
        self.decoder = decoder
        self.cache = cache
        self.settings = settings
        self.archiveReader = archiveReader ?? ZipArchiveReader(kindNames: kindNames)
        self.searcher = searcher ?? FileNameSearcher(kindNames: kindNames)
        self.sortOrder = settings.viewSettings.sortOrder
        self.showsZipFiles = settings.viewSettings.showsZipFiles
        self.screenMaxPixel = 4096

        let folder = settings.viewSettings.lastFolder
            ?? FileManager.default.homeDirectoryForCurrentUser
        self.listing = FolderListing(folder: folder, files: [], state: .empty)
        self.selection = SelectionState()
        self.preview = .empty
    }

    /// Updates kind names and ordering after a language change without re-enumerating the disk.
    public func setKindNames(_ names: KindNames) {
        guard names != kindNames else { return }
        kindNames = names
        kindUpdateGeneration &+= 1
        let generation = kindUpdateGeneration
        Task { [weak self] in
            guard let self else { return }
            while generation == self.kindUpdateGeneration {
                let files = self.allFiles
                let revision = self.kindFilesRevision
                let order = self.sortOrder
                let updated = await Task.detached(priority: .userInitiated) {
                    sorted(files.map { $0.localizedKindName(using: names) }, by: order)
                }.value
                guard generation == self.kindUpdateGeneration else { return }
                guard revision == self.kindFilesRevision, order == self.sortOrder else { continue }
                self.allFiles = updated
                switch self.listing.state {
                case .loaded, .empty, .noMatches:
                    self.rebuildListing()
                case .loading where self.isShowingSearchResults:
                    self.rebuildListing()
                default:
                    break
                }
                return
            }
        }
    }

    /// Shows a folder listing. If search results are shown, stops the search and ends the search display (FR-086).
    public func selectFolder(_ url: URL) async {
        await selectFolder(url, reason: .navigated)
    }

    private func selectFolder(_ url: URL, reason: LocationChangeReason) async {
        let leavingFocus = selection.focused
        let openedFromSearchResults: Bool
        if case .openedSearchResultFolder = reason {
            openedFromSearchResults = true
        } else {
            openedFromSearchResults = false
        }
        resetForNavigation()
        leaveSearchIfNeeded()
        if openedFromSearchResults {
            // Only for requests opened from search results, accept updating the saved location when synchronization
            // completes (EC-102).
            pendingSearchTreeSyncID = treeSyncRequest?.id
        }
        archiveIndex = nil
        showsNotFound = false
        listing = FolderListing(folder: url, files: [], state: .loading)

        var viewSettings = settings.viewSettings
        if viewSettings.lastFolder?.standardizedFileURL != url.standardizedFileURL {
            viewSettings.lastFolder = url
            settings.viewSettings = viewSettings
        }

        notifyLocationChange(reason, leavingFocus: leavingFocus)

        let generation = navigationGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadFolder(url, generation: generation)
        }
        listingTask = task
        await task.value
    }

    private func notifyLocationChange(_ reason: LocationChangeReason, leavingFocus: URL?) {
        switch reason {
        case .navigated:
            onLocationEvent?(.navigated(leavingFocus: leavingFocus))
        case .openedSearchResultFolder:
            onLocationEvent?(.openedSearchResultFolder(leavingFocus: leavingFocus))
        case let .relocated(vanished):
            onLocationEvent?(.relocated(vanished: vanished))
        }
    }

    /// Starts a search and adds results to the list in the current sort order as they are found (FR-084, 085).
    /// Returns without waiting for enumeration to finish. Does not change `listing.folder`, `lastFolder`, or
    /// `treeSyncRequest`; when started inside a zip, discards the zip state.
    public func startSearch(_ pattern: SearchPattern, root: URL) {
        resetForNavigation()
        archiveIndex = nil
        listing = FolderListing(
            folder: listing.folder,
            files: [],
            state: .loading,
            search: SearchListing(keyword: pattern.keyword, root: root, phase: .searching, totalCount: 0)
        )

        searchPattern = pattern
        startSearchStream(in: root, matching: pattern)
    }

    /// Starts one enumeration. Ends the search when all enumerations finish (R63). Creates a match log per
    /// enumeration and registers it in the ledger; discards the whole ledger when the search stops (R2, R3).
    private func startSearchStream(in root: URL, matching pattern: SearchPattern, matchesRoot: Bool = false) {
        let generation = navigationGeneration
        let visits = SearchVisitLog()
        let streamIndex = searchLedger.addStream(visits: visits)
        let stream = searcher.search(
            SearchRequest(root: root, pattern: pattern, matchesRoot: matchesRoot, visits: visits)
        )
        activeSearchStreams += 1
        let task = Task { [weak self] in
            for await batch in stream {
                guard let self, generation == self.navigationGeneration else { return }
                self.appendSearchResults(batch, fromStream: streamIndex)
            }
            guard let self, !Task.isCancelled, generation == self.navigationGeneration else { return }
            self.activeSearchStreams -= 1
            guard self.activeSearchStreams == 0 else { return }
            self.listing.search?.phase = .finished
            self.rebuildListing()
        }
        searchTasks.append(task)
    }

    /// After renaming in search results, replaces the row's URL and name and re-sorts. Keeps rows that no longer
    /// match the keyword, and removes rows that no longer have a supported media extension. Does nothing when search
    /// results are not shown (FR-087, R38).
    public func didRenameItem(at oldURL: URL, to newURL: URL) {
        guard isShowingSearchResults,
              let index = allFiles.firstIndex(where: { $0.url == oldURL }) else { return }
        guard let kind = MediaKind(fileExtension: newURL.pathExtension) else {
            removeSearchResults([oldURL])
            return
        }

        let old = allFiles[index]
        var renamed = old
        renamed.url = newURL
        renamed.name = newURL.lastPathComponent
        renamed.kind = .media(kind)
        renamed.typeDescription = (try? newURL.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?
            .localizedTypeDescription ?? old.typeDescription
        allFiles[index] = renamed
        removeFromSearchIndex(oldURL)
        addToSearchIndex(newURL)
        allFiles = sorted(allFiles, by: sortOrder)
        rebuildListing()

        var selected = selection.selected
        if selected.remove(oldURL) != nil {
            selected.insert(newURL)
        }
        if selection.focused == oldURL {
            // Reload the preview with the new URL.
            select(selected, focused: newURL)
        } else {
            selection = SelectionState(selected: selected, focused: selection.focused)
        }
    }

    /// After renaming a folder, rebases the displayed listing, selection, search results, position inside a zip, and
    /// last selected folder. Does not read the disk and does not change the preview or playing video (does not call
    /// `select`). During a search, also rebases results that arrive later and, for a rename below the search root,
    /// enumerates the new location. Does nothing when there is no relationship (FR-104, 105; R62, R63).
    public func didRenameFolder(from oldURL: URL, to newURL: URL) {
        let renamed = RenamedFolder(from: oldURL, to: newURL)
        let oldName = oldURL.standardizedFileURL.path

        var updated = listing
        var changed = false
        if let folder = renamed.rebase(updated.folder) {
            updated.folder = folder
            changed = true
        }
        if let location = updated.archive, let archive = renamed.rebase(location.archive) {
            updated.archive = ArchiveLocation(archive: archive, directory: location.directory)
            changed = true
        }
        let previousRoot = updated.search?.root
        if let root = previousRoot, let rebasedRoot = renamed.rebase(root) {
            updated.search?.root = rebasedRoot
            changed = true
        }

        var filesChanged = false
        var namesChanged = false
        // Keep the original and new URLs so rebasing the search result index does not rebase the same URL twice (R67).
        let collectsMoves = isShowingSearchResults
        var moves: [(URL, URL)] = []
        let files = allFiles.map { file -> MediaFile in
            guard let url = renamed.rebase(file.url) else { return file }
            filesChanged = true
            if collectsMoves {
                moves.append((file.url, url))
            }
            var moved = file
            moved.url = url
            if file.kind == .folder, file.url.standardizedFileURL.path == oldName {
                moved.name = newURL.lastPathComponent
                namesChanged = true
            }
            return moved
        }

        var selected = selection.selected
        var selectionChanged = false
        for url in selection.selected {
            guard let rebased = renamed.rebase(url) else { continue }
            selected.remove(url)
            selected.insert(rebased)
            selectionChanged = true
        }
        let focused = selection.focused.map { url -> URL in
            guard let rebased = renamed.rebase(url) else { return url }
            selectionChanged = true
            return rebased
        }

        var viewSettings = settings.viewSettings
        if let lastFolder = viewSettings.lastFolder, let rebased = renamed.rebase(lastFolder) {
            viewSettings.lastFolder = rebased
            settings.viewSettings = viewSettings
        }

        // During a search, a rename below the root matters for results that arrive later even when it does not affect
        // displayed rows. Whether the folder was already matched determines whether the new location is matched as the
        // root itself (EC-94, R2, R3).
        var additionalSearchRoot: URL?
        var additionalMatchesRoot = false
        if listing.search?.phase == .searching, let previousRoot {
            if let rebasedRoot = renamed.rebase(previousRoot) {
                // Renamed the root itself or an ancestor. Enumerate the new root again because the root is not a row.
                searchLedger.recordRename(renamed, visited: true)
                additionalSearchRoot = rebasedRoot
            } else if RenamedFolder(from: previousRoot, to: previousRoot).rebase(oldURL) != nil {
                // A folder below the root. Enumerate only the folder's new location.
                let visited = searchLedger.hasVisited(oldURL)
                searchLedger.recordRename(renamed, visited: visited)
                additionalSearchRoot = newURL
                additionalMatchesRoot = !visited
            }
        }

        guard changed || filesChanged || selectionChanged || additionalSearchRoot != nil else { return }

        let folderChanged = updated.folder != listing.folder
        // Use for rebasing index rows when a zip is displayed, including while opening.
        if listing.archive != nil {
            archiveRenames.append(renamed)
        }
        listing = updated
        if selectionChanged {
            selection = SelectionState(selected: selected, focused: focused)
        }
        if filesChanged {
            // Files below the folder do not change names, so the order changes only when a row name changes or when
            // sorting by Location.
            allFiles = namesChanged || sortOrder.column == .location ? sorted(files, by: sortOrder) : files
        }
        if isShowingSearchResults, filesChanged {
            rebaseSearchIndex(renamed, moved: Dictionary(moves, uniquingKeysWith: { first, _ in first }))
        }

        switch listing.state {
        case .loaded, .empty, .noMatches:
            rebuildListing()
        case .denied, .failed:
            listing.files = unreadableFolderRows()
        case .loading:
            if isShowingSearchResults {
                rebuildListing()
            } else if folderChanged, listing.archive == nil {
                // A loading listing discards results from the old location, so reload with the new location (keep the
                // generation).
                listingTask?.cancel()
                let generation = navigationGeneration
                let folder = listing.folder
                listingTask = Task { [weak self] in
                    await self?.loadFolder(folder, generation: generation)
                }
            }
        }

        if let additionalSearchRoot, let pattern = searchPattern {
            startSearchStream(in: additionalSearchRoot, matching: pattern, matchesRoot: additionalMatchesRoot)
        }
    }

    /// Rebases search result index keys (the folder containing the file). Rebases per key instead of rebuilding keys
    /// from 10,000 URLs (R67). Because keys are compared in the same standardized form as `searchFolderKey`,
    /// standardizes the new location (which exists) and builds the old location from its parent plus the old name.
    private func rebaseSearchIndex(_ renamed: RenamedFolder, moved: [URL: URL]) {
        let newKeyFolder = renamed.to.standardizedFileURL
        let keyRenamed = RenamedFolder(
            from: newKeyFolder.deletingLastPathComponent().appendingPathComponent(renamed.from.lastPathComponent),
            to: newKeyFolder
        )
        var index: [String: Set<URL>] = [:]
        index.reserveCapacity(searchResultsByFolder.count)
        for (key, urls) in searchResultsByFolder {
            if let newKey = keyRenamed.rebase(URL(fileURLWithPath: key, isDirectory: true))?.path {
                index[newKey, default: []].formUnion(urls.map { moved[$0] ?? renamed.rebaseOrSelf($0) })
            } else {
                // Even when the key does not change, the row for the renamed folder itself has a new URL (R4).
                index[key, default: []].formUnion(urls.map { moved[$0] ?? $0 })
            }
        }
        searchResultsByFolder = index
    }

    /// Receives the tree roots. When they change, rebuilds `..` for loaded regular folder listings (does not read the
    /// disk).
    public func setNavigationRoots(_ urls: [URL]) {
        guard urls != navigationRoots else { return }
        navigationRoots = urls
        guard listing.archive == nil else { return }
        switch listing.state {
        case .loaded, .empty, .noMatches:
            rebuildListing()
        case .denied, .failed:
            listing.files = unreadableFolderRows()
        case .loading:
            return
        }

        let restricted = selection.restricted(toVisible: listing.files.map(\.url))
        if restricted.focused == selection.focused {
            selection = restricted
        } else {
            select(restricted.selected, focused: restricted.focused)
        }
    }

    /// Opens a listing row. Zip files, folders, and directories open their contents; `..` goes up. Does nothing for
    /// media files or URLs not in the listing (FR-069, 076).
    public func openItem(_ url: URL) async {
        guard let file = listing.files.first(where: { $0.url == url }) else { return }

        switch file.kind {
        case .archive:
            guard listing.archive == nil else { return }
            await openArchive(file.url)
        case .directory:
            guard let location = listing.archive,
                  let index = archiveIndex,
                  let parsed = ArchiveURL.parse(file.url) else { return }
            let leavingFocus = selection.focused
            resetForNavigation()
            showArchiveLevel(ArchiveLocation(archive: location.archive, directory: parsed.path), index: index)
            onLocationEvent?(.navigated(leavingFocus: leavingFocus))
        case .parent:
            await goToEnclosingLevel()
        case .folder:
            // When opened from search results, apply the presentation state to the current history entry before
            // recording (FR-113, EC-99).
            await navigateToFolder(
                file.url,
                selecting: nil,
                reason: isShowingSearchResults ? .openedSearchResultFolder : .navigated
            )
        case .media:
            break
        }
    }

    /// Moves to the parent when the displayed folder (the folder containing the zip when inside a zip) or an ancestor
    /// is moved to the Trash. Emits `treeSyncRequest` (FR-079). Returns true when it moved; otherwise does nothing and
    /// returns false.
    ///
    /// For Trash from the search result list (`origin: .fileList`), a selected row can be an ancestor of the pre-search
    /// folder. In that case, keeps showing search results and reports that the pre-search folder disappeared when the
    /// display ends (EC-101). From the tree (`origin: .tree`), moves to the parent as before.
    @discardableResult
    public func leaveTrashedFolders(_ trashed: [URL], origin: OperationOrigin = .tree) async -> Bool {
        if origin == .fileList, isShowingSearchResults { return false }
        guard let parent = FolderNavigation.folderToShow(
            afterTrashing: trashed,
            showing: listing.folder,
            roots: navigationRoots
        ) else { return false }
        await navigateToFolder(parent, selecting: nil, reason: .relocated(vanished: trashed))
        return true
    }

    /// Receives completion of tree synchronization for a folder opened from search results (FR-140, EC-102,
    /// research.md R10). Only when the request still comes from search results, the listing shows that folder, and
    /// the selected location is the folder itself or an ancestor (compared with standardized pathComponents), stores
    /// the selected location as the last selected folder. Does not change the listing, history, or focus, and does not
    /// read the disk. Rejects stale requests, duplicates, and synchronization from regular listings or history.
    public func completeSearchResultTreeSync(_ request: TreeSyncRequest, selectedFolder: URL) {
        guard let pending = pendingSearchTreeSyncID,
              pending == request.id,
              treeSyncRequest == request,
              listing.folder.standardizedFileURL == request.folder.standardizedFileURL,
              !isShowingSearchResults,
              listing.archive == nil,
              !showsNotFound else { return }
        let selectedComponents = selectedFolder.standardizedFileURL.pathComponents
        let targetComponents = request.folder.standardizedFileURL.pathComponents
        guard selectedComponents.count <= targetComponents.count,
              Array(targetComponents.prefix(selectedComponents.count)) == selectedComponents else { return }

        pendingSearchTreeSyncID = nil
        var viewSettings = settings.viewSettings
        if viewSettings.lastFolder?.standardizedFileURL != selectedFolder.standardizedFileURL {
            viewSettings.lastFolder = selectedFolder
            settings.viewSettings = viewSettings
        }
    }

    /// Goes to the enclosing level. From the zip root, returns to the folder listing (FR-070). Outside a zip, returns
    /// to the parent folder and does nothing at a tree root (FR-077).
    public func goToEnclosingLevel() async {
        // No enclosing level while showing search results (FR-087).
        guard !isShowingSearchResults else { return }
        guard let location = listing.archive else {
            if let parent = enclosingFolder {
                await navigateToFolder(parent, selecting: listing.folder, reason: .navigated)
            }
            return
        }

        if let parentLocation = location.parent {
            guard let index = archiveIndex else { return }
            let previous = ArchiveURL.entry(archive: location.archive, path: location.directory)
            let leavingFocus = selection.focused
            resetForNavigation()
            showArchiveLevel(parentLocation, index: index)
            onLocationEvent?(.navigated(leavingFocus: leavingFocus))
            if listing.files.contains(where: { $0.url == previous }) {
                select([previous], focused: previous)
            }
        } else {
            await returnToFolder(selecting: location.archive, reason: .navigated)
        }
    }

    public func select(_ urls: Set<URL>, focused: URL?) {
        let previousFocused = selection.focused
        selection = SelectionState(selected: urls, focused: focused)
        if previousFocused != focused {
            stopPlaybackSignal &+= 1
        }
        loadPreview(for: focused)
        schedulePrefetch(around: focused)
    }

    /// Applies the slideshow target to the selection (FR-127). When the same URL is already focused, does not
    /// reload the preview, only narrows the selection to that one item, and keeps the video playback position.
    /// Returns true only when the focus actually changed.
    @discardableResult
    public func synchronizeSlideshowSelection(to url: URL) -> Bool {
        if selection.focused == url {
            if selection.selected != [url] {
                selection = SelectionState(selected: [url], focused: url)
                return true
            }
            return false
        }
        select([url], focused: url)
        return true
    }

    public func setMediaTypeFilter(_ filter: MediaTypeFilter) {
        guard filter != mediaTypeFilter else { return }
        mediaTypeFilter = filter
        switch listing.state {
        case .loaded, .empty, .noMatches:
            rebuildListing()
        case .loading, .denied, .failed:
            break
        }

        let restricted = selection.restricted(toVisible: listing.files.map(\.url))
        if restricted.focused == selection.focused {
            selection = restricted
            schedulePrefetch(around: restricted.focused)
        } else {
            select(restricted.selected, focused: restricted.focused)
        }
    }

    /// Toggles and persists zip file visibility (FR-095–098). Does nothing for the same value.
    /// While a zip is displayed, only persists the setting and does not change the listing, selection, or preview
    /// (FR-098). Otherwise rebuilds the listing (without reading the disk) and restricts the selection to visible
    /// rows (FR-097).
    public func setShowsZipFiles(_ shows: Bool) {
        guard shows != showsZipFiles else { return }
        showsZipFiles = shows
        var viewSettings = settings.viewSettings
        viewSettings.showsZipFiles = shows
        settings.viewSettings = viewSettings

        guard listing.archive == nil else { return }
        switch listing.state {
        case .loaded, .empty, .noMatches:
            rebuildListing()
        case .loading, .denied, .failed:
            break
        }

        // Nothing to restrict without a selection. Avoids building a set of 10,000 URLs (SC-017).
        guard !selection.selected.isEmpty || selection.focused != nil else { return }
        let restricted = selection.restricted(toVisible: listing.files.map(\.url))
        if restricted.focused == selection.focused {
            selection = restricted
            schedulePrefetch(around: restricted.focused)
        } else {
            select(restricted.selected, focused: restricted.focused)
        }
    }

    public func reloadCurrentFolder() async {
        // While showing search results, do not re-enumerate the disk; only remove results that no longer exist
        // (FR-087, R38).
        if isShowingSearchResults {
            await pruneMissingResults(under: nil)
            return
        }
        // Do not overwrite the zip contents with a folder listing while inside a zip.
        guard listing.archive == nil else { return }
        let folder = listing.folder
        let generation = navigationGeneration
        do {
            let files = try await lister.mediaFiles(in: folder)
            guard generation == navigationGeneration,
                  listing.folder == folder,
                  listing.archive == nil else { return }

            showsNotFound = false
            allFiles = sorted(files.map { $0.localizedKindName(using: kindNames) }, by: sortOrder)
            rebuildListing()

            let available = Set(listing.files.map(\.url))
            let selected = selection.selected.intersection(available)
            let focused = selection.focused.flatMap { available.contains($0) ? $0 : nil }
            selection = SelectionState(selected: selected, focused: focused)
            if focused == nil {
                previewTask?.cancel()
                previewTask = nil
                previewGeneration += 1
                preview = .empty
            }
        } catch {
            guard generation == navigationGeneration,
                  listing.folder == folder,
                  listing.archive == nil else { return }
            allFiles = []
            listing.files = unreadableFolderRows()
            switch error {
            case .accessDenied:
                showsNotFound = false
                listing.state = .denied
            case .notFound:
                showsNotFound = true
                listing.state = .failed(.folderNotFound)
                onLocationEvent?(.notFound(HistoryLocation(folder: folder)))
            case let .other(message):
                showsNotFound = false
                listing.state = .failed(.systemFailure(systemReason: message))
            }
            previewTask?.cancel()
            previewTask = nil
            previewGeneration += 1
            selection = SelectionState()
            preview = .empty
        }
    }

    public func handleFileSystemEvent(_ folders: Set<URL>) async {
        // While showing search results, check only results under the reported folders. Do not move to the parent even
        // when `listing.folder` disappears (R38).
        if isShowingSearchResults {
            await pruneMissingResults(under: folders)
            return
        }
        let current = listing.folder.standardizedFileURL
        guard folders.contains(where: { $0.standardizedFileURL == current }) else {
            return
        }

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: listing.folder.path,
            isDirectory: &isDirectory
        )
        guard exists, isDirectory.boolValue else {
            let vanished = listing.folder
            await selectFolder(vanished.deletingLastPathComponent(), reason: .relocated(vanished: [vanished]))
            return
        }

        if let location = listing.archive {
            // While opening, there is no index to compare, so wait without comparing.
            if archiveIndex == nil, listing.state == .loading { return }
            if let identity = archiveReader.identity(of: location.archive),
               identity == archiveIndex?.identity {
                return
            }
            let vanished = archiveReader.identity(of: location.archive) == nil ? [location.archive] : []
            await returnToFolder(selecting: nil, reason: .relocated(vanished: vanished))
            return
        }

        await reloadCurrentFolder()
    }

    public func moveFocus(_ direction: FocusDirection) {
        let files = listing.files
        guard !files.isEmpty else { return }

        let currentIndex = selection.focused.flatMap { focused in
            files.firstIndex { $0.url == focused }
        }

        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = max(0, (currentIndex ?? 0) - 1)
        case .next:
            targetIndex = min(files.count - 1, (currentIndex ?? -1) + 1)
        }

        let url = files[targetIndex].url
        if currentIndex == targetIndex, selection.selected == [url] {
            return
        }
        select([url], focused: url)
    }

    // MARK: - Listing

    /// Builds displayed rows and state from `allFiles` (which does not include `..`). Adds `..` here once: always
    /// inside a zip, and only when an enclosing level exists for regular folders (FR-070, 077). Does not add it for
    /// search results, and uses `.loading` while searching before any results arrive.
    private func rebuildListing() {
        // Apply the zip visibility once after the media type filter. Does not change `allFiles` (FR-095, R46).
        let filtered = ZipFileVisibility(showsZipFiles: showsZipFiles)
            .apply(to: mediaTypeFilter.apply(to: allFiles))
        if let location = listing.archive {
            listing.files = [Self.parentRow(for: location)] + filtered
        } else {
            listing.files = folderParentRows() + filtered
        }

        if listing.search?.phase == .searching, allFiles.isEmpty {
            listing.state = .loading
            return
        }

        // Zip files, folders, directories, and `..` do not count for the "no media" decision (FR-060).
        // Media is unaffected by zip visibility, so use `allFiles`; derive other rows from the displayed rows (FR-097).
        let hasMedia = allFiles.contains { $0.kind.isMedia }
        let hasOtherRows = filtered.contains { !$0.kind.isMedia }
        if !hasMedia && !hasOtherRows {
            listing.state = .empty
        } else if hasMedia && !filtered.contains(where: { $0.kind.isMedia }) {
            listing.state = .noMatches
        } else {
            listing.state = .loaded
        }
    }

    private static func parentRow(for location: ArchiveLocation) -> MediaFile {
        parentRow(url: ArchiveURL.parentLink(of: location))
    }

    private static func parentRow(url: URL) -> MediaFile {
        MediaFile(
            url: url,
            name: "..",
            kind: .parent,
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
    }

    /// Enclosing level of a regular folder. Nil at a tree root and outside the roots.
    private var enclosingFolder: URL? {
        FolderNavigation.enclosingFolder(of: listing.folder, roots: navigationRoots)
    }

    /// `..` row placed at the start of a regular folder. Empty when there is no enclosing level or while showing
    /// search results.
    private func folderParentRows() -> [MediaFile] {
        guard !isShowingSearchResults, enclosingFolder != nil else { return [] }
        return [Self.parentRow(url: ParentLink.url(for: listing.folder))]
    }

    /// Rows for an unreadable regular folder (`.denied` or `.failed`). Keeps only `..` outside roots so the folder is
    /// not a dead end (FR-077).
    private func unreadableFolderRows() -> [MediaFile] {
        listing.archive == nil ? folderParentRows() : []
    }

    /// Moves to a folder within the file list (opening a folder row, `..`, or ⌘↑). Loads like `selectFolder` and
    /// emits a tree synchronization request. If a row for `target` exists after loading, selects only that row
    /// (FR-076–078).
    private func navigateToFolder(
        _ url: URL,
        selecting target: URL?,
        reason: LocationChangeReason
    ) async {
        treeSyncCounter += 1
        let request = TreeSyncRequest(folder: url, id: treeSyncCounter)
        // Emit the request before loading so tree synchronization does not wait for the listing to finish.
        treeSyncRequest = request
        await selectFolder(url, reason: reason)

        guard treeSyncRequest == request,
              listing.folder == url,
              listing.archive == nil,
              let target else { return }
        let standardized = target.standardizedFileURL
        if let row = listing.files.first(where: { $0.kind != .parent && $0.url.standardizedFileURL == standardized }) {
            select([row.url], focused: row.url)
        }
    }

    /// Cancels loading, preview, and prefetching, stops video, and clears the selection and preview.
    /// Shared by `selectFolder` and navigation inside a zip.
    private func resetForNavigation() {
        onWillReplaceLocation?()
        navigationGeneration += 1
        showsNotFound = false
        listingTask?.cancel()
        listingTask = nil
        for task in searchTasks {
            task.cancel()
        }
        searchTasks.removeAll()
        searchPattern = nil
        searchLedger = SearchRenameLedger()
        movedSearchPaths.removeAll()
        pendingSearchTreeSyncID = nil
        activeSearchStreams = 0
        searchResultsByFolder.removeAll()
        previewGeneration += 1
        previewTask?.cancel()
        previewTask = nil
        for task in prefetchTasks.values {
            task.cancel()
        }
        prefetchTasks.removeAll()

        if case .video = preview {
            stopPlaybackSignal &+= 1
        }

        selection = SelectionState()
        preview = .empty
        allFiles = []
    }

    /// Opens a zip and builds the root listing. Uses `.loading` while opening.
    private func openArchive(_ url: URL) async {
        let leavingFocus = selection.focused
        resetForNavigation()
        leaveSearchIfNeeded()
        archiveIndex = nil
        archiveRenames.removeAll()
        listing = FolderListing(
            folder: listing.folder,
            files: [],
            state: .loading,
            archive: ArchiveLocation(archive: url, directory: "")
        )
        onLocationEvent?(.navigated(leavingFocus: leavingFocus))

        let generation = navigationGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadArchive(url, generation: generation)
        }
        listingTask = task
        await task.value
    }

    private func loadArchive(_ url: URL, generation: Int) async {
        let result: Result<ArchiveIndex, ArchiveError>
        do throws(ArchiveError) {
            result = .success(try await archiveReader.open(url))
        } catch {
            result = .failure(error)
        }
        guard !Task.isCancelled, generation == navigationGeneration else { return }

        switch result {
        case let .success(index):
            archiveIndex = index
            // If the folder containing the zip was renamed while opening, display it at the new location (R62).
            showArchiveLevel(ArchiveLocation(archive: rebasedForArchive(url), directory: ""), index: index)
        case let .failure(error):
            archiveIndex = nil
            allFiles = []
            if let location = listing.archive {
                listing.files = [Self.parentRow(for: location)]
            }
            listing.state = .failed(.archive(error))
        }
    }

    /// Builds a listing for one level inside a zip from the open index (does not reopen the zip).
    private func showArchiveLevel(_ location: ArchiveLocation, index: ArchiveIndex) {
        listing = FolderListing(folder: listing.folder, files: [], state: .loading, archive: location)
        var items = index.items(in: location.directory)
        if !archiveRenames.isEmpty {
            items = items.map { item in
                var moved = item
                moved.url = rebasedForArchive(item.url)
                return moved
            }
        }
        allFiles = sorted(items.map { $0.localizedKindName(using: kindNames) }, by: sortOrder)
        rebuildListing()
    }

    /// Applies renames recorded after the zip was opened, in order.
    private func rebasedForArchive(_ url: URL) -> URL {
        archiveRenames.reduce(url) { $1.rebaseOrSelf($0) }
    }

    /// Closes the zip and reloads the folder containing it from disk. Does not rewrite `lastFolder`.
    private func returnToFolder(selecting target: URL?, reason: LocationChangeReason) async {
        let folder = listing.folder
        let leavingFocus = selection.focused
        resetForNavigation()
        leaveSearchIfNeeded()
        archiveIndex = nil
        listing = FolderListing(folder: folder, files: [], state: .loading)
        notifyLocationChange(reason, leavingFocus: leavingFocus)

        let generation = navigationGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadFolder(folder, generation: generation)
        }
        listingTask = task
        await task.value

        guard generation == navigationGeneration, let target else { return }
        let standardized = target.standardizedFileURL
        if let row = listing.files.first(where: { $0.url.standardizedFileURL == standardized }) {
            select([row.url], focused: row.url)
        }
    }

    private func loadFolder(_ url: URL, generation: Int, notifyNotFound: Bool = true) async {
        do {
            let files = try await lister.mediaFiles(in: url)
            guard !Task.isCancelled, generation == navigationGeneration, listing.folder == url else { return }

            showsNotFound = false
            allFiles = sorted(files.map { $0.localizedKindName(using: kindNames) }, by: sortOrder)
            rebuildListing()
        } catch {
            guard !Task.isCancelled, generation == navigationGeneration, listing.folder == url else { return }

            allFiles = []
            listing.files = unreadableFolderRows()
            switch error {
            case .accessDenied:
                showsNotFound = false
                listing.state = .denied
            case .notFound:
                showsNotFound = true
                listing.state = .failed(.folderNotFound)
                if notifyNotFound {
                    onLocationEvent?(.notFound(HistoryLocation(folder: url)))
                }
            case let .other(message):
                showsNotFound = false
                listing.state = .failed(.systemFailure(systemReason: message))
            }
        }
    }

    // MARK: - History

    /// Validates a location without changing the display. Performs stat and zip index creation off the UI thread
    /// (R73).
    public func resolveHistoryLocation(_ location: HistoryLocation) async -> HistoryLocationResolution {
        let generation = navigationGeneration

        guard let archive = location.archive else {
            let path = location.folder.path
            let isDirectory = await Task.detached(priority: .userInitiated) {
                var isDirectory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                return exists && isDirectory.boolValue
            }.value
            guard generation == navigationGeneration else { return .superseded }
            guard isDirectory else { return .missing }
            return .available(ResolvedHistoryLocation(
                location: location,
                navigationGeneration: generation,
                archiveIndex: nil,
                archiveError: nil
            ))
        }

        let archivePath = archive.archive.path
        let isRegularFile = await Task.detached(priority: .userInitiated) {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: archivePath, isDirectory: &isDirectory)
            return exists && !isDirectory.boolValue
        }.value
        guard generation == navigationGeneration else { return .superseded }
        guard isRegularFile else { return .missing }

        if let index = archiveIndex, index.archive.path == archive.archive.path {
            guard index.containsDirectory(archive.directory) else { return .missing }
            return .available(ResolvedHistoryLocation(
                location: location,
                navigationGeneration: generation,
                archiveIndex: index,
                archiveError: nil
            ))
        }

        do throws(ArchiveError) {
            let index = try await archiveReader.open(archive.archive)
            guard generation == navigationGeneration else { return .superseded }
            guard index.containsDirectory(archive.directory) else { return .missing }
            return .available(ResolvedHistoryLocation(
                location: location,
                navigationGeneration: generation,
                archiveIndex: index,
                archiveError: nil
            ))
        } catch {
            guard generation == navigationGeneration else { return .superseded }
            return .available(ResolvedHistoryLocation(
                location: location,
                navigationGeneration: generation,
                archiveIndex: nil,
                archiveError: error
            ))
        }
    }

    /// Shows a validated location. Returns without waiting for loading to finish and selects only the `focusing` row
    /// after loading. Emits `treeSyncRequest` and saves `lastFolder`. Does not call `onLocationEvent` (R74).
    public func showHistoryLocation(_ resolved: ResolvedHistoryLocation, focusing: URL?) {
        let resolvedGeneration = navigationGeneration
        guard resolved.isCurrent(for: resolvedGeneration) else { return }
        let location = resolved.location
        let resolvedIndex = resolved.index(for: resolvedGeneration)
        let resolvedError = resolved.error(for: resolvedGeneration)

        resetForNavigation()
        leaveSearchIfNeeded()
        archiveIndex = nil
        archiveRenames.removeAll()

        treeSyncCounter += 1
        treeSyncRequest = TreeSyncRequest(folder: location.folder, id: treeSyncCounter)

        var viewSettings = settings.viewSettings
        if viewSettings.lastFolder?.standardizedFileURL != location.folder.standardizedFileURL {
            viewSettings.lastFolder = location.folder
            settings.viewSettings = viewSettings
        }

        if let archive = location.archive {
            if let index = resolvedIndex {
                archiveIndex = index
                listing = FolderListing(folder: location.folder, files: [], state: .loading)
                showArchiveLevel(archive, index: index)
                selectHistoryFocus(focusing)
            } else {
                archiveIndex = nil
                allFiles = []
                listing = FolderListing(
                    folder: location.folder,
                    files: [Self.parentRow(for: archive)],
                    state: .failed(resolvedError.map(ListingFailure.archive) ?? .archive(.notAZip)),
                    archive: archive
                )
            }
            return
        }

        showsNotFound = false
        listing = FolderListing(folder: location.folder, files: [], state: .loading)
        let generation = navigationGeneration
        listingTask = Task { [weak self] in
            guard let self else { return }
            await self.loadFolder(location.folder, generation: generation, notifyNotFound: false)
            guard generation == self.navigationGeneration,
                  self.listing.folder == location.folder,
                  self.listing.archive == nil else { return }
            self.selectHistoryFocus(focusing)
        }
    }

    private func selectHistoryFocus(_ focusing: URL?) {
        guard let focusing else {
            selection = SelectionState()
            previewTask?.cancel()
            previewTask = nil
            previewGeneration += 1
            preview = .empty
            return
        }

        let standardized = focusing.standardizedFileURL
        guard let row = listing.files.first(where: {
            $0.kind != .parent && $0.url.standardizedFileURL == standardized
        }) else {
            selection = SelectionState()
            previewTask?.cancel()
            previewTask = nil
            previewGeneration += 1
            preview = .empty
            return
        }
        select([row.url], focused: row.url)
    }

    // MARK: - Search Results

    /// Before ending search results, restores the Location sort to the persisted sort (FR-084, 086).
    /// Call before rebuilding `listing`.
    private func leaveSearchIfNeeded() {
        guard isShowingSearchResults else { return }
        if sortOrder.column == .location {
            sortOrder = settings.viewSettings.sortOrder
        }
    }

    /// Sorts an incoming batch with the current order, then merges it into the fully sorted results (R36).
    /// After renames, applies changes recorded since that enumeration started to rebase results and drops results
    /// that overlap with the additional enumeration (R63).
    private func appendSearchResults(_ incoming: [MediaFile], fromStream index: Int) {
        guard isShowingSearchResults, !incoming.isEmpty else { return }
        var batch = incoming.filter { !isMovedSearchPath($0.url) }
        guard !batch.isEmpty else { return }
        if !searchLedger.isEmpty {
            var seen = Set<String>()
            batch = batch.compactMap { file in
                guard let moved = searchLedger.place(file, fromStream: index), !isMovedSearchPath(moved.url) else { return nil }
                let path = moved.url.standardizedFileURL.path
                let listed = searchResultsByFolder[Self.searchFolderKey(moved.url)]?
                    .contains { $0.standardizedFileURL.path == path } == true
                guard !listed, seen.insert(path).inserted else { return nil }
                return moved
            }
            guard !batch.isEmpty else { return }
        }
        batch = batch.map { $0.localizedKindName(using: kindNames) }
        allFiles = sortedMerge(allFiles, sorted(batch, by: sortOrder), by: sortOrder)
        for file in batch {
            addToSearchIndex(file.url)
        }
        listing.search?.totalCount = allFiles.count
        rebuildListing()

        // Rows only increase, but restrict the selection so it does not keep rows hidden by the media type filter.
        // Do not reload the preview when the focus does not change.
        guard !selection.selected.isEmpty || selection.focused != nil else { return }
        let restricted = selection.restricted(toVisible: listing.files.map(\.url))
        if restricted.focused == selection.focused {
            selection = restricted
        } else {
            select(restricted.selected, focused: restricted.focused)
        }
    }

    private static func searchFolderKey(_ url: URL) -> String {
        url.deletingLastPathComponent().standardizedFileURL.path
    }

    private func addToSearchIndex(_ url: URL) {
        searchResultsByFolder[Self.searchFolderKey(url), default: []].insert(url)
    }

    private func removeFromSearchIndex(_ url: URL) {
        let key = Self.searchFolderKey(url)
        searchResultsByFolder[key]?.remove(url)
        if searchResultsByFolder[key]?.isEmpty == true {
            searchResultsByFolder[key] = nil
        }
    }

    /// Removes search results that no longer exist. Checks all results when `folders` is nil; otherwise checks only
    /// results under those folders off the UI thread. Does not add newly appeared files (FR-087, R38).
    private func pruneMissingResults(under folders: Set<URL>?) async {
        guard isShowingSearchResults else { return }
        let targets: [URL]
        if let folders {
            let prefixes = folders.map { $0.standardizedFileURL.path }
            if prefixes.contains("/") {
                targets = allFiles.map(\.url)
            } else {
                targets = searchResultsByFolder
                    .filter { key, _ in prefixes.contains { key == $0 || key.hasPrefix($0 + "/") } }
                    .flatMap(\.value)
            }
        } else {
            targets = allFiles.map(\.url)
        }
        guard !targets.isEmpty else { return }

        let generation = navigationGeneration
        let missing = await Task.detached(priority: .userInitiated) {
            Set(targets.filter { !FileManager.default.fileExists(atPath: $0.path) })
        }.value
        guard generation == navigationGeneration, !missing.isEmpty else { return }
        removeSearchResults(missing)
    }

    /// Removes results from the source of a move and delayed results from an old location that is still being
    /// enumerated.
    public func didMoveSearchItems(_ sources: [URL]) {
        guard isShowingSearchResults else { return }
        movedSearchPaths.formUnion(sources.map { $0.standardizedFileURL.path })
        let removed = Set(allFiles.filter { isMovedSearchPath($0.url) }.map(\.url))
        if !removed.isEmpty { removeSearchResults(removed) }
    }

    private func isMovedSearchPath(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return movedSearchPaths.contains { path == $0 || path.hasPrefix($0 == "/" ? "/" : $0 + "/") }
    }

    /// Removes rows from search results and restricts the selection. When focus is lost, clears the preview and stops
    /// the playing video.
    private func removeSearchResults(_ urls: Set<URL>) {
        allFiles.removeAll { urls.contains($0.url) }
        for url in urls {
            removeFromSearchIndex(url)
        }
        listing.search?.totalCount = allFiles.count
        rebuildListing()

        let previousFocused = selection.focused
        let available = Set(listing.files.map(\.url))
        let selected = selection.selected.intersection(available)
        let focused = previousFocused.flatMap { available.contains($0) ? $0 : nil }
        selection = SelectionState(selected: selected, focused: focused)
        if previousFocused != nil, focused == nil {
            if case .video = preview {
                stopPlaybackSignal &+= 1
            }
            previewTask?.cancel()
            previewTask = nil
            previewGeneration += 1
            preview = .empty
        }
    }

    // MARK: - Preview

    private func loadPreview(for url: URL?) {
        previewGeneration += 1
        let generation = previewGeneration
        previewTask?.cancel()
        previewTask = nil

        guard let url else {
            preview = .empty
            return
        }

        // Check the listing row kind first. Do not preview non-media rows (zip files, directories, and `..`) (FR-075).
        let kind: MediaKind
        if let file = listing.files.first(where: { $0.url == url }) {
            guard case let .media(mediaKind) = file.kind else {
                preview = .empty
                return
            }
            kind = mediaKind
        } else if let mediaKind = MediaKind(fileExtension: url.pathExtension) {
            kind = mediaKind
        } else {
            preview = .unavailable(name: url.lastPathComponent, reason: .unsupportedFormat)
            return
        }

        if kind.isVideo {
            preview = .video(url)
            return
        }

        if let parsed = ArchiveURL.parse(url) {
            loadArchivePreview(for: url, path: parsed.path, generation: generation)
            return
        }

        if decoder.isAnimated(url) {
            preview = .animatedImage(url)
            return
        }

        preview = .loading(url)
        previewTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.decodedImage(for: url)
            guard !Task.isCancelled, self.previewGeneration == generation else { return }

            switch result {
            case let .success(image):
                self.preview = .image(image)
            case let .failure(error):
                self.preview = .unavailable(
                    name: url.lastPathComponent,
                    reason: Self.reason(for: error)
                )
            }
        }
    }

    private func loadArchivePreview(for url: URL, path: String, generation: Int) {
        if let entry = archiveIndex?.entry(at: path) {
            switch entry.readability {
            case .readable:
                break
            case .encrypted:
                preview = .unavailable(name: url.lastPathComponent, reason: .archive(.entryEncrypted))
                return
            case .unsupportedMethod:
                preview = .unavailable(
                    name: url.lastPathComponent,
                    reason: .archive(.unsupportedMethod(entry.method))
                )
                return
            }
        }

        preview = .loading(url)
        let maxPixelSize = max(1, screenMaxPixel)
        previewTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.archiveImage(for: url, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled, self.previewGeneration == generation else { return }

            switch result {
            case let .image(image):
                self.preview = .image(image)
            case let .animated(data):
                self.preview = .animatedImageData(url, data)
            case let .failure(reason):
                self.preview = .unavailable(name: url.lastPathComponent, reason: reason)
            }
        }
    }

    /// Obtains an image inside a zip in this order: cache, read `Data`, decode. Returns animated images as `Data`.
    private func archiveImage(for url: URL, maxPixelSize: Int) async -> ArchiveImageResult {
        if let cached = await cache.get(url) {
            return .image(cached)
        }

        let data: Data
        do throws(ArchiveError) {
            data = try await archiveReader.data(for: url, limit: MemoryLimits.archiveImageBytes)
        } catch {
            return .failure(.archive(error))
        }
        guard !Task.isCancelled else { return .failure(.unreadable) }

        if decoder.isAnimated(data: data) {
            return .animated(data)
        }

        do {
            let image = try await decoder.decode(data: data, maxPixelSize: maxPixelSize)
            await cache.put(image, for: url)
            return .image(image)
        } catch {
            return .failure(Self.reason(for: error))
        }
    }

    private func decodedImage(for url: URL) async -> Result<DecodedImage, DecodeError> {
        if let cached = await cache.get(url) {
            return .success(cached)
        }

        do {
            let image = try await decoder.decode(url, maxPixelSize: max(1, screenMaxPixel))
            await cache.put(image, for: url)
            return .success(image)
        } catch {
            return .failure(error)
        }
    }

    private func schedulePrefetch(around url: URL?) {
        guard let url, let index = listing.files.firstIndex(where: { $0.url == url }) else {
            return
        }

        for neighborIndex in [index - 1, index + 1] where listing.files.indices.contains(neighborIndex) {
            let file = listing.files[neighborIndex]
            // Do not prefetch videos or non-media rows (zip files, directories, and `..`).
            guard file.kind.isMedia, !file.kind.isVideo else { continue }
            guard prefetchTasks[file.url] == nil else { continue }

            if let parsed = ArchiveURL.parse(file.url) {
                if let entry = archiveIndex?.entry(at: parsed.path), entry.readability != .readable {
                    continue
                }
                let maxPixelSize = max(1, screenMaxPixel)
                let task = Task { [weak self] in
                    guard let self else { return }
                    _ = await self.archiveImage(for: file.url, maxPixelSize: maxPixelSize)
                    self.prefetchTasks[file.url] = nil
                }
                prefetchTasks[file.url] = task
                continue
            }

            guard !decoder.isAnimated(file.url) else { continue }
            let task = Task { [weak self] in
                guard let self else { return }
                _ = await self.decodedImage(for: file.url)
                self.prefetchTasks[file.url] = nil
            }
            prefetchTasks[file.url] = task
        }
    }

    private static func reason(for error: DecodeError) -> PreviewFailure {
        switch error {
        case .unreadable:
            return .unreadable
        case .unsupported:
            return .unsupportedFormat
        case .corrupted:
            return .corrupted
        }
    }
}
