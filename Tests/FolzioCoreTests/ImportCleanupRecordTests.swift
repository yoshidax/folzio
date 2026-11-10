import Foundation
import Testing
@testable import FolzioCore

@Suite("Import cleanup records")
struct ImportCleanupRecordTests {
    @Test func validatesBeforeDeletingAndKeepsMissingVolumes() throws {
        try ImportTestFiles.directory { root in
            let suite = "Folzio.Import.Test.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = ImportCleanupStore(defaults: defaults)
            let now = Date()
            let staging = try ImportStaging.create(store: store, temporaryDirectory: root, date: now)
            let recorded = try #require(store.records().first)
            store.sweep(now: now, temporaryDirectory: root, volumeUUID: { _ in nil })
            #expect(store.records() == [recorded])
            store.sweep(now: now, temporaryDirectory: root, volumeUUID: { _ in "different-volume" })
            #expect(store.records().isEmpty)
            #expect(FileManager.default.fileExists(atPath: staging.root.path))
            store.add(ImportCleanupRecord(path: staging.root.path, volumeUUID: recorded.volumeUUID, createdAt: now.addingTimeInterval(-30 * 86400 - 1)))
            store.add(ImportCleanupRecord(path: root.path, volumeUUID: recorded.volumeUUID, createdAt: now))
            store.sweep(now: now, temporaryDirectory: root)
            #expect(store.records().isEmpty)
            #expect(FileManager.default.fileExists(atPath: staging.root.path))
            store.add(recorded)
            store.sweep(now: now, temporaryDirectory: root)
            #expect(!FileManager.default.fileExists(atPath: staging.root.path))
            #expect(store.records().isEmpty)
        }
    }

    @Test func dropsMalformedRecordsAndSerializesUpdates() {
        let suite = "Folzio.Import.Test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([["path": 1], ["path": "/tmp/x", "volumeUUID": "disk", "createdAt": "bad"]], forKey: ImportCleanupStore.key)
        let store = ImportCleanupStore(defaults: defaults)
        #expect(store.records().isEmpty)
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            store.add(ImportCleanupRecord(path: "/test/\(index)", volumeUUID: "disk", createdAt: Date()))
        }
        #expect(store.records().count == 20)
        store.remove(path: "/test/0")
        #expect(store.records().count == 19)
    }

    @Test func neverFollowsSymlinkedCleanupFolders() throws {
        try ImportTestFiles.directory { root in
            let suite = "Folzio.Import.Test.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = ImportCleanupStore(defaults: defaults)
            // Check the real home path without ever passing it to a deletion operation.
            #expect(!ImportCleanupStore.hasOwnedShape(URL(fileURLWithPath: NSHomeDirectory()), temporaryDirectory: root))
            let outside = root.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
            let base = root.appendingPathComponent("Folzio-Import")
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false)
            let link = base.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            store.add(ImportCleanupRecord(path: link.path, volumeUUID: "disk", createdAt: Date()))
            store.sweep(temporaryDirectory: root, volumeUUID: { _ in "disk" })
            #expect(FileManager.default.fileExists(atPath: outside.path))
            #expect(FileManager.default.fileExists(atPath: link.path))
            #expect(store.records().isEmpty)
        }
    }
}
