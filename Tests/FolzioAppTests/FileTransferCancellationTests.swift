import Foundation
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("File transfer cancellation")
@MainActor
struct FileTransferCancellationTests {
    @Test("Stops at a conflict and retains earlier results", arguments: 0..<8)
    func abortStopsTransfer(scenario: Int) async throws {
        let move = scenario & 1 != 0
        let applyToAll = scenario & 2 != 0
        let conflictFirst = scenario & 4 != 0
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceFolder = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let names = conflictFirst ? ["conflict", "later"] : ["earlier", "conflict", "later"]
        let sources = names.map { sourceFolder.appendingPathComponent($0) }
        for source in sources {
            try Data(source.lastPathComponent.utf8).write(to: source)
        }
        let existing = destination.appendingPathComponent("conflict")
        try Data("existing".utf8).write(to: existing)
        var prompts = 0

        let (result, attempted) = await FileOperationCoordinator.transferItems(
            sources, to: destination, kind: move ? .move : .copy, service: FileOperationService(),
            resolveConflict: { _, _, _ in
                prompts += 1
                return ConflictPrompt.Choice(resolution: .abort, applyToAll: applyToAll)
            },
            validate: { _ in true }
        )

        let expectedEarlier = conflictFirst ? [] : [sources[0]]
        #expect(prompts == 1)
        #expect(attempted == expectedEarlier)
        #expect(result.succeeded == expectedEarlier.map { destination.appendingPathComponent($0.lastPathComponent) })
        #expect(result.failed.isEmpty)
        #expect(try Data(contentsOf: existing) == Data("existing".utf8))
        #expect(FileManager.default.fileExists(atPath: sources[names.firstIndex(of: "conflict")!].path))
        #expect(FileManager.default.fileExists(atPath: sources.last!.path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("later").path))
        if !conflictFirst {
            #expect(FileManager.default.fileExists(atPath: sources[0].path) == !move)
            #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("earlier").path))
        }
    }
}
