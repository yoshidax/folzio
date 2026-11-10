import Foundation
import Testing
@testable import FolzioCore

@Suite("Import staging")
struct ImportStagingTests {
    @Test func foldersBudgetAndRemoval() throws {
        try ImportTestFiles.directory { root in
            let suite = "Folzio.Import.Test.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = ImportCleanupStore(defaults: defaults)
            let staging = try ImportStaging.create(store: store, temporaryDirectory: root)
            #expect(staging.receptionFolder != staging.inspectionFolder)
            #expect(staging.receptionFolder.deletingLastPathComponent() == staging.root)
            #expect(staging.inspectionFolder.deletingLastPathComponent() == staging.root)
            #expect(staging.sameVolume(as: root))
            #expect(!staging.sameVolume(as: URL(fileURLWithPath: "/not-a-mounted-volume/missing")))
            #expect(store.records().count == 1)
            try Data([1, 2, 3]).write(to: staging.receptionFolder.appendingPathComponent("one"))
            try Data([1, 2, 3, 4]).write(to: staging.inspectionFolder.appendingPathComponent("snapshot"))
            try FileManager.default.createSymbolicLink(at: staging.receptionFolder.appendingPathComponent("link"), withDestinationURL: staging.inspectionFolder)
            #expect(try staging.currentSize() == 3)
            try staging.remove()
            #expect(store.records().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: staging.root.path))
        }
    }
}
