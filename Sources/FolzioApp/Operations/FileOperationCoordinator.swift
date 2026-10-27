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

    func internalDrop(_ urls: [URL], to destination: URL, copy: Bool) async {
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

    /// From the tree (`origin: .tree`), confirms with the target's absolute path regardless of the skip setting
    /// (FR-079, R66).
    func trash(_ urls: [URL], origin: OperationOrigin = .fileList) async {
        guard !urls.isEmpty else { return }
        let operation = FileOperation(kind: .trash, sources: urls)
        guard await confirmation.confirm(
            operation,
            includesFolders: await containsFolder(urls),
            origin: origin,
            location: origin == .tree ? urls.first?.path : nil
        ) else { return }

        let result = await service.execute(operation, resolution: .abort)
        await presentFailures(result)
        // Notify the tree first so rows moved to the Trash disappear without waiting for the parent listing to load
        // (FR-027).
        notifyFoldersChanged(sources: urls, destination: nil)
        // result.succeeded contains URLs inside the Trash, so pass the original locations that did not fail instead.
        let failedPaths = Set(result.failed.map { $0.url.standardizedFileURL.path })
        let trashedSources = urls.filter { !failedPaths.contains($0.standardizedFileURL.path) }
        historyNavigator?.didRemoveItems(trashedSources)
        // Move to the parent only when the displayed folder or an ancestor was trashed (FR-079). In search results, an
        // ancestor of the pre-search folder can be selected, so tree and file list operations behave differently. Leave
        // the decision to `BrowserModel` and only pass the origin here (EC-101). Call only when the result is false,
        // because reloading after moving would briefly show "Folder not found" for the vanished folder.
        if await !model.leaveTrashedFolders(trashedSources, origin: origin) {
            await model.reloadCurrentFolder()
        }
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

    /// From the tree (`origin: .tree`), includes the target's absolute path in the confirmation modal (FR-103, R58).
    func rename(_ file: URL, to newName: String, origin: OperationOrigin = .fileList) async {
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
        guard await confirmation.confirm(
            operation,
            includesFolders: isDirectory,
            origin: origin,
            location: origin == .tree ? file.path : nil
        ) else { return }

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
        if validateDrop, await !validateInternalDrop(urls, destination: destination, kind: kind) { return }
        let operation = FileOperation(kind: kind, sources: urls, destination: destination)
        guard await confirmation.confirm(operation, includesFolders: await containsFolder(urls)) else { return }
        if validateDrop, await !validateInternalDrop(urls, destination: destination, kind: kind) { return }

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
                let service = service
                let conflicts = await Task.detached(priority: .userInitiated) {
                    service.conflicts(for: itemOperation)
                }.value
                if conflicts.isEmpty {
                    resolution = .keepBoth
                } else {
                    let choice = await conflictPrompt.resolve(
                        conflictingNames: conflicts.map(\.lastPathComponent),
                        destination: destination,
                        allowReplace: !sameCopyItem
                    )
                    if choice.applyToAll {
                        sharedResolution = choice.resolution
                    }
                    resolution = choice.resolution
                }
            }

            if case .abort = resolution {
                continue
            }
            if validateDrop, await !validateInternalDrop([source], destination: destination, kind: kind) { continue }
            attemptedSources.append(source)
            let partial = await service.execute(itemOperation, resolution: resolution)
            result.merge(partial)
        }

        await presentFailures(result)
        var removed: [URL] = []
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
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL]
        return (objects ?? []).map { $0 as URL }
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
