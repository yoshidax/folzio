import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
final class FileOperationCoordinator {
    private let model: BrowserModel
    private let service: any FileOperating
    private let confirmation: ConfirmationPresenter
    private let conflictPrompt: ConflictPrompt

    /// Passes affected folders (the sources' parent folders and the destination) when an operation finishes.
    /// Lets the tree apply changes without waiting for FSEvents (FR-027, R32).
    var onFoldersChanged: ((Set<URL>) -> Void)?
    /// Passes the old and new locations after a successful folder rename. Called before `BrowserModel` rebases so the
    /// tree can rebase without recreating nodes (R62, R64).
    var onFolderRenamed: ((URL, URL) -> Void)?
    /// Removes locations that disappeared due to moves or renames from history (FR-109).
    weak var historyNavigator: HistoryNavigator?
    /// Called when a copy, move, or Move to Trash ends, including when it is cancelled or rejected. Passes the
    /// requested sources and the original locations of the items it removed (empty for a copy, a cancellation, or a
    /// rejection), after the file list has been updated. Lets the tree finish its own operation and update its
    /// selection (FR-219).
    var onOperationFinished: ((_ sources: [URL], _ removed: [URL]) -> Void)?

    init(model: BrowserModel, service: any FileOperating, settings: SettingsStore) {
        self.model = model
        self.service = service
        self.confirmation = ConfirmationPresenter(settings: settings)
        self.conflictPrompt = ConflictPrompt()
    }

    func copy(_ urls: [URL], to destination: URL) async {
        await transfer(urls, to: destination, kind: .copy)
    }

    func move(_ urls: [URL], to destination: URL) async {
        await transfer(urls, to: destination, kind: .move)
    }

    /// A drop from this app's views or from another app (FR-020, FR-347). Validates the selection before confirming and
    /// again before each item (EC-16, EC-121, EC-122).
    func drop(_ urls: [URL], to destination: URL, copy: Bool) async {
        await transfer(urls, to: destination, kind: copy ? .copy : .move, validateDrop: true)
    }

    /// Duplicate does not modify the original and creates a copy in the same folder with Keep Both, so it does not
    /// confirm (FR-018, FR-024).
    func duplicate(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }

        var result = FileOperationResult()
        for source in urls {
            let copyOperation = FileOperation(
                kind: .copy,
                sources: [source],
                destination: source.deletingLastPathComponent()
            )
            let partial = await service.execute(copyOperation, resolution: .keepBoth)
            result.merge(partial)
        }
        await presentFailures(result)
        await model.reloadCurrentFolder()
        notifyFoldersChanged(sources: urls, destination: nil)
    }

    /// From the tree (`origin: .tree`), confirms with each target's absolute path regardless of the skip setting
    /// (FR-079, R66). A single folder shows its path after the list; multiple folders show the path below each name
    /// (A-127).
    func trash(_ urls: [URL], origin: OperationOrigin = .fileList) async {
        guard !urls.isEmpty else { return }
        var trashedSources: [URL] = []
        defer { onOperationFinished?(urls, trashedSources) }
        let operation = FileOperation(kind: .trash, sources: urls)
        let showsEachLocation = origin == .tree && urls.count > 1
        guard await confirmation.confirm(
            operation,
            includesFolders: await containsFolder(urls),
            origin: origin,
            location: origin == .tree && !showsEachLocation ? urls.first?.path : nil,
            itemLocations: showsEachLocation ? urls.map(\.path) : []
        ) else { return }

        let result = await service.execute(operation, resolution: .abort)
        await presentFailures(result)
        // Notify the tree first so rows moved to the Trash disappear without waiting for the parent listing to load
        // (FR-027).
        notifyFoldersChanged(sources: urls, destination: nil)
        // result.succeeded contains URLs inside the Trash, so pass the original locations that did not fail instead.
        let failedPaths = Set(result.failed.map { $0.url.standardizedFileURL.path })
        trashedSources = urls.filter { !failedPaths.contains($0.standardizedFileURL.path) }
        historyNavigator?.didRemoveItems(trashedSources)
        // Move to the parent only when the displayed folder or an ancestor was trashed (FR-079). In search results, an
        // ancestor of the pre-search folder can be selected, so tree and file list operations behave differently. Leave
        // the decision to `BrowserModel` and only pass the origin here (EC-101). Call only when the result is false,
        // because reloading after moving would briefly show "Folder not found" for the vanished folder.
        if await !model.leaveTrashedFolders(trashedSources, origin: origin) {
            await model.reloadCurrentFolder()
        }
    }

    /// Explains why folders selected in the tree together with their descendants are not moved to the Trash. Nothing
    /// is changed (EC-146).
    func presentOverlappingTreeTrash() async {
        await showError(
            message: { l10n.text(.dialogTreeTrashOverlapTitle) },
            detail: { l10n.text(.dialogTreeTrashOverlapMessage) }
        )
    }

    func paste(into destination: URL, move: Bool) async {
        let urls = pasteboardFileURLs()
        guard !urls.isEmpty else { return }
        if move {
            await self.move(urls, to: destination)
        } else {
            await self.copy(urls, to: destination)
        }
    }

    /// Creates a folder with the default name (or the next numbered name) in `parent` without confirmation, because it
    /// does not change existing items (FR-209). On success, reloads the listing when it shows `parent` and notifies the
    /// tree, then returns the new folder. On failure, shows the destination name and the reason and returns nil
    /// (FR-026, EC-141). Does not change history or the last selected folder (FR-214).
    func createFolder(in parent: URL) async -> URL? {
        let result = await service.createFolder(in: parent, baseName: l10n.text(.folderDefaultName))
        switch result {
        case .success(let created):
            if model.listing.folder.standardizedFileURL.path == parent.standardizedFileURL.path {
                await model.reloadCurrentFolder()
            }
            onFoldersChanged?([parent.standardizedFileURL])
            return created
        case .failure(let reason):
            await presentFailures(FileOperationResult(failed: [(url: parent, reason: reason)]))
            return nil
        }
    }

    /// From the tree (`origin: .tree`), includes the target's absolute path in the confirmation modal (FR-103, R58).
    /// Passing `confirms: false` skips the confirmation modal; only naming a folder right after New Folder does this
    /// (FR-211, research.md R4). Validation, failure display, and updates stay the same.
    func rename(_ file: URL, to newName: String, origin: OperationOrigin = .fileList, confirms: Bool = true) async {
        let parent = file.deletingLastPathComponent()
        let existingNames = await siblingNames(in: parent).subtracting([file.lastPathComponent])

        let isDirectory = await containsFolder([file])
        switch validateNewName(newName, for: file, existingNames: existingNames, isDirectory: isDirectory) {
        case .invalid(let reason):
            await showError(message: { l10n.text(.dialogRenameFailed) }, detail: { l10n.text(for: reason) })
            return
        case .needsExtensionChangeConfirmation:
            guard await confirmExtensionChange(for: file, to: newName) else { return }
        case .ok:
            break
        }

        let operation = FileOperation(kind: .rename(newName: newName), sources: [file])
        if confirms {
            guard await confirmation.confirm(
                operation,
                includesFolders: isDirectory,
                origin: origin,
                location: origin == .tree ? file.path : nil
            ) else { return }
        }

        let result = await service.execute(operation, resolution: .abort)
        await presentFailures(result)
        if let renamed = result.succeeded.first {
            if isDirectory {
                // Rebase the tree, listing, and search results to the new location before reloading and FSEvents
                // (FR-104, 105; R62, R64).
                onFolderRenamed?(file, renamed)
                model.didRenameFolder(from: file, to: renamed)
                historyNavigator?.didRenameFolder(from: file, to: renamed)
            } else {
                // In search results, the original URL disappears and the row would be dropped, so replace the row
                // before reloading (FR-087, R38). In a regular folder, didRenameItem does nothing and the reload
                // applies the change as before.
                model.didRenameItem(at: file, to: renamed)
                historyNavigator?.didRenameItem(from: file, to: renamed)
            }
        }
        await model.reloadCurrentFolder()
        notifyFoldersChanged(sources: [file], destination: nil)
    }

    private func transfer(_ urls: [URL], to destination: URL, kind: FileOperation.Kind, validateDrop: Bool = false) async {
        guard !urls.isEmpty else { return }
        var removed: [URL] = []
        defer { onOperationFinished?(urls, removed) }
        if validateDrop, await !validateInternalDrop(urls, destination: destination, kind: kind) { return }
        let operation = FileOperation(kind: kind, sources: urls, destination: destination)
        guard await confirmation.confirm(operation, includesFolders: await containsFolder(urls)) else { return }
        if validateDrop, await !validateInternalDrop(urls, destination: destination, kind: kind) { return }

        let (result, attemptedSources) = await Self.transferItems(
            urls, to: destination, kind: kind, service: service,
            resolveConflict: { [conflictPrompt] conflicts, destination, allowReplace in
                await conflictPrompt.resolve(
                    conflictingNames: conflicts.map(\.lastPathComponent),
                    destination: destination,
                    allowReplace: allowReplace
                )
            },
            validate: { source in
                if validateDrop {
                    return await self.validateInternalDrop([source], destination: destination, kind: kind)
                }
                return true
            }
        )

        await presentFailures(result)
        if case .move = kind {
            // result.succeeded contains destination URLs, so remove history using the original locations that did not
            // fail (FR-109).
            let failedPaths = Set(result.failed.map { $0.url.standardizedFileURL.path })
            removed = attemptedSources.filter { !failedPaths.contains($0.standardizedFileURL.path) }
            model.didMoveSearchItems(removed)
            historyNavigator?.didRemoveItems(removed)
        }
        let relocated = model.isShowingSearchResults ? false : await model.leaveTrashedFolders(removed, origin: .fileList)
        if !relocated { await model.reloadCurrentFolder() }
        notifyFoldersChanged(sources: urls, destination: destination)
    }

    static func transferItems(
        _ urls: [URL],
        to destination: URL,
        kind: FileOperation.Kind,
        service: any FileOperating,
        resolveConflict: ([URL], URL, Bool) async -> ConflictPrompt.Choice,
        validate: (URL) async -> Bool
    ) async -> (FileOperationResult, [URL]) {
        var result = FileOperationResult()
        var sharedResolution: ConflictResolution?
        var attemptedSources: [URL] = []

        for source in urls {
            let itemOperation = FileOperation(
                kind: kind,
                sources: [source],
                destination: destination
            )
            let target = destination.appendingPathComponent(source.lastPathComponent)
            let sameCopyItem = if case .copy = kind {
                await Task.detached(priority: .userInitiated) {
                    FileOperationService.sameItem(source, target)
                }.value
            } else { false }
            let resolution: ConflictResolution
            if let sharedResolution, !(sameCopyItem && { if case .replace = sharedResolution { true } else { false } }()) {
                resolution = sharedResolution
            } else {
                let conflicts = await Task.detached(priority: .userInitiated) {
                    service.conflicts(for: itemOperation)
                }.value
                if conflicts.isEmpty {
                    resolution = .keepBoth
                } else {
                    let choice = await resolveConflict(conflicts, destination, !sameCopyItem)
                    if choice.applyToAll {
                        sharedResolution = choice.resolution
                    }
                    resolution = choice.resolution
                }
            }

            if case .abort = resolution {
                break
            }
            if await !validate(source) { continue }
            attemptedSources.append(source)
            let partial = await service.execute(itemOperation, resolution: resolution)
            result.merge(partial)
        }

        return (result, attemptedSources)
    }

    private func validateInternalDrop(_ urls: [URL], destination: URL, kind: FileOperation.Kind) async -> Bool {
        let dropKind: InternalDropValidation.Kind
        if case .copy = kind { dropKind = .copy } else { dropKind = .move }
        let validation = await Task.detached(priority: .userInitiated) {
            InternalDropValidation.validate(sources: urls, destination: destination, kind: dropKind)
        }.value
        let reason: OperationFailureReason
        switch validation {
        case .valid: return true
        case .missingSource, .empty: reason = .sourceNotFound
        case .invalidDestination: reason = .destinationNotFound
        case .sameParent: reason = .sameNameAtDestination
        case .intoItself, .overlappingSources: reason = .intoItself
        }
        await presentFailures(FileOperationResult(failed: urls.map { (url: $0, reason: reason) }))
        return false
    }

    /// Whether the targets include a folder. Does not perform stat on the UI thread.
    private func containsFolder(_ urls: [URL]) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            urls.contains { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
        }.value
    }

    private func notifyFoldersChanged(sources: [URL], destination: URL?) {
        var folders = Set(sources.map { $0.deletingLastPathComponent().standardizedFileURL })
        if let destination {
            folders.insert(destination.standardizedFileURL)
        }
        onFoldersChanged?(folders)
    }

    private func pasteboardFileURLs() -> [URL] {
        PasteboardFileURLs.fileURLs(in: .general)
    }

    private func siblingNames(in folder: URL) async -> Set<String> {
        await Task.detached(priority: .userInitiated) {
            Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        }.value
    }

    private func confirmExtensionChange(for file: URL, to newName: String) async -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return true }

        let alert = NSAlert()
        alert.messageText = l10n.text(.dialogExtensionTitle)
        alert.informativeText = l10n.text(.dialogExtensionMessage, .text(file.lastPathComponent), .text((newName as NSString).pathExtension))
        alert.addButton(withTitle: l10n.text(.dialogExtensionConfirm))
        alert.addButton(withTitle: l10n.text(.dialogCancel))
        alert.buttons[1].keyEquivalent = "\u{1b}"

        let languageObserver = LanguageChangeObserver {
            alert.messageText = l10n.text(.dialogExtensionTitle)
            alert.informativeText = l10n.text(.dialogExtensionMessage, .text(file.lastPathComponent), .text((newName as NSString).pathExtension))
            alert.buttons[0].title = l10n.text(.dialogExtensionConfirm)
            alert.buttons[1].title = l10n.text(.dialogCancel)
        }

        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
        withExtendedLifetime(languageObserver) {}
        return response == .alertFirstButtonReturn
    }

    private func presentFailures(_ result: FileOperationResult) async {
        guard !result.failed.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.addButton(withTitle: l10n.text(.dialogOK))
        _ = await runSheet(alert) {
            var lines = result.failed.prefix(10).map { failure in
                l10n.text(.dialogOperationFailureLine, .text(failure.url.lastPathComponent), .text(l10n.text(for: failure.reason)))
            }
            if result.failed.count > 10 {
                lines.append(l10n.text(.dialogOperationMore, .number(result.failed.count - 10)))
            }
            alert.messageText = l10n.text(.dialogOperationFailed)
            alert.informativeText = l10n.text(.dialogOperationSummary, .number(result.succeeded.count), .number(result.failed.count))
                + "\n\n" + lines.joined(separator: "\n")
            alert.buttons[0].title = l10n.text(.dialogOK)
        }
    }

    private func showError(message: @escaping @MainActor () -> String, detail: @escaping @MainActor () -> String) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.addButton(withTitle: l10n.text(.dialogOK))
        _ = await runSheet(alert) {
            alert.messageText = message()
            alert.informativeText = detail()
            alert.buttons[0].title = l10n.text(.dialogOK)
        }
    }

    private func runSheet(_ alert: NSAlert, update: @escaping @MainActor () -> Void) async -> NSApplication.ModalResponse? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            return nil
        }
        update()
        let languageObserver = LanguageChangeObserver(update: update)
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response)
            }
        }
        withExtendedLifetime(languageObserver) {}
        return response
    }
}

private extension FileOperationResult {
    mutating func merge(_ other: FileOperationResult) {
        succeeded.append(contentsOf: other.succeeded)
        failed.append(contentsOf: other.failed)
    }
}
