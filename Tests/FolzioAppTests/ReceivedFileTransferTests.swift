import AppKit
import FolzioCore
import FolzioLocalization
import Testing
@testable import FolzioApp

private actor RecordingImportService: FileOperating {
    var operations: [FileOperation] = []
    nonisolated func conflicts(for operation: FileOperation) -> [URL] { FileOperationService().conflicts(for: operation) }
    func execute(_ operation: FileOperation, resolution: ConflictResolution) async -> FileOperationResult {
        operations.append(operation)
        return await FileOperationService().execute(operation, resolution: resolution)
    }
    func createFolder(in parent: URL, baseName: String) async -> Result<URL, OperationFailureReason> { .failure(.sourceNotFound) }
}

@Suite("Received file transfers", .serialized)
@MainActor
struct ReceivedFileTransferTests {
    private func withFiles(_ body: (URL, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("cat.png")
        try Data([1, 2, 3]).write(to: source)
        try await body(source, destination)
    }
    private var control: ImportSaveControl { ImportSaveControl(isActive: { true }, willConfirm: {}, didConfirm: {}) }

    @Test(arguments: [true, false]) func confirmsCopyAndTransfersWithVolumePolicy(sameVolume: Bool) async throws {
        try await withFiles { source, destination in
            let service = RecordingImportService()
            let request = ImportSaveRequest(files: [source], failures: [], destination: destination, sameVolume: sameVolume)
            var asked = false
            let (result, outcome) = await FileOperationCoordinator.transferReceived(request, service: service, confirm: { operation in
                if case .copy = operation.kind { asked = true }
                else { Issue.record("Import confirmation must use copy policy") }
                return true
            }, resolveConflict: { _, _, _ in .init(resolution: .keepBoth, applyToAll: false) }, control: control)
            #expect(asked && outcome == .finished)
            #expect(result.succeeded.count == 1)
            let operations = await service.operations
            #expect(operations.count == 1)
            if sameVolume { if case .move = operations[0].kind {} else { Issue.record("Expected a move") } }
            else { if case .copy = operations[0].kind {} else { Issue.record("Expected a copy") } }
            #expect(FileManager.default.fileExists(atPath: source.path) == !sameVolume)
            let content = try Data(contentsOf: destination.appendingPathComponent("cat.png"))
            #expect(content == Data([1, 2, 3]))
        }
    }

    @Test(arguments: [false, true]) func detectsDestinationLossBeforeOrDuringConfirmation(duringConfirmation: Bool) async throws {
        try await withFiles { source, destination in
            let service = RecordingImportService()
            if !duringConfirmation { try FileManager.default.removeItem(at: destination) }
            var asked = false
            let (result, outcome) = await FileOperationCoordinator.transferReceived(
                ImportSaveRequest(files: [source], failures: [], destination: destination, sameVolume: true),
                service: service, confirm: { _ in
                    asked = true
                    try? FileManager.default.removeItem(at: destination)
                    return true
                }, resolveConflict: { _, _, _ in .init(resolution: .abort, applyToAll: false) }, control: control)
            #expect(asked == duringConfirmation)
            #expect(outcome == .failed)
            #expect(result.failed.first?.reason == .destinationNotFound)
            #expect(await service.operations.isEmpty)
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test func confirmationCancellationIsSilent() async throws {
        try await withFiles { source, destination in
            let service = RecordingImportService()
            let (result, outcome) = await FileOperationCoordinator.transferReceived(
                ImportSaveRequest(files: [source], failures: [(source, .importRejected(.notImageOrVideo))], destination: destination, sameVolume: true),
                service: service, confirm: { _ in false },
                resolveConflict: { _, _, _ in .init(resolution: .abort, applyToAll: false) }, control: control)
            #expect(outcome == .cancelled)
            #expect(result.failed.isEmpty && result.succeeded.isEmpty)
            #expect(await service.operations.isEmpty)
        }
    }

    @Test func rejectsUnwritableDestination() async throws {
        try await withFiles { source, destination in
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: destination.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path) }
            let service = RecordingImportService()
            let (result, outcome) = await FileOperationCoordinator.transferReceived(
                ImportSaveRequest(files: [source], failures: [], destination: destination, sameVolume: true),
                service: service, confirm: { _ in Issue.record("Read-only destination must fail before confirmation"); return true },
                resolveConflict: { _, _, _ in .init(resolution: .abort, applyToAll: false) }, control: control)
            #expect(outcome == .failed && result.failed.count == 1)
            #expect(await service.operations.isEmpty)
        }
    }

    @Test func cancellationDuringDestinationPreflightSkipsConfirmation() async throws {
        try await withFiles { source, destination in
            let service = RecordingImportService()
            var active = true
            var confirming = false
            var asked = false
            var resume: CheckedContinuation<OperationFailureReason?, Never>?
            let task = Task { @MainActor in
                await FileOperationCoordinator.transferReceived(
                    ImportSaveRequest(files: [source], failures: [], destination: destination, sameVolume: true),
                    service: service, confirm: { _ in asked = true; return true },
                    resolveConflict: { _, _, _ in .init(resolution: .abort, applyToAll: false) },
                    control: ImportSaveControl(isActive: { active }, willConfirm: { confirming = true }, didConfirm: {}),
                    checkDestination: { _ in
                        #expect(!confirming)
                        return await withCheckedContinuation { resume = $0 }
                    })
            }
            while resume == nil { await Task.yield() }
            #expect(!confirming)
            active = false
            resume?.resume(returning: nil)
            let (result, outcome) = await task.value
            #expect(outcome == .cancelled)
            #expect(!asked && !confirming)
            #expect(result.succeeded.isEmpty && result.failed.isEmpty)
            #expect(await service.operations.isEmpty)
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test func coordinatorNotifiesOnlyDestination() async throws {
        _ = NSApplication.shared
        try await withFiles { source, destination in
            let suite = "Folzio.Import.Transfer.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = SettingsStore(defaults: defaults)
            settings.confirmation.confirmBeforeFileOperations = false
            let model = BrowserModel(kindNames: l10n.kindNames, lister: DirectoryLister(kindNames: l10n.kindNames),
                decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
            let coordinator = FileOperationCoordinator(model: model, service: FileOperationService(), settings: settings)
            var changed: Set<URL> = []
            var calledLegacyMoveCompletion = false
            coordinator.onFoldersChanged = { changed.formUnion($0) }
            coordinator.onOperationFinished = { _, _ in calledLegacyMoveCompletion = true }
            let outcome = await coordinator.saveReceived([source], to: destination, sameVolume: true)
            #expect(outcome == .finished)
            #expect(changed == [destination.standardizedFileURL])
            #expect(!calledLegacyMoveCompletion)
        }
    }
}
