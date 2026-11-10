import Darwin
import Foundation

public struct ImportStaging: Sendable {
    public let root: URL
    public var receptionFolder: URL { root.appendingPathComponent("received", isDirectory: true) }
    public var inspectionFolder: URL { root.appendingPathComponent("checked", isDirectory: true) }
    private let store: ImportCleanupStore
    private let temporaryDirectory: URL

    /// Creates one prewarmed pair. The caller supplies it to a drop only after this background work finishes.
    public static func create(
        store: ImportCleanupStore = .shared, temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        date: Date = Date()
    ) throws -> ImportStaging {
        guard let temporary = ImportFileSystem.canonicalPath(temporaryDirectory) else { throw ImportRejection.sourceFailed }
        let base = URL(fileURLWithPath: temporary).appendingPathComponent("Folzio-Import", isDirectory: true)
        if ImportFileSystem.info(base) != nil, !ImportFileSystem.isDirectory(base) { throw ImportRejection.sourceFailed }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let root = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
        guard let volume = ImportFileSystem.volumeUUID(base) else { throw ImportRejection.sourceFailed }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        store.add(ImportCleanupRecord(path: root.path, volumeUUID: volume, createdAt: date))
        let staging = ImportStaging(root: root, store: store, temporaryDirectory: URL(fileURLWithPath: temporary))
        do {
            try FileManager.default.createDirectory(at: staging.receptionFolder, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: staging.inspectionFolder, withIntermediateDirectories: false)
            return staging
        } catch {
            if (try? FileManager.default.removeItem(at: root)) != nil { store.remove(path: root.path) }
            throw error
        }
    }

    public func sameVolume(as destination: URL) -> Bool {
        ExternalDropPolicy.allOnSameVolume([root], destination: destination)
    }

    /// Counts producer output only; snapshots and symlink targets are not counted twice.
    public func currentSize() throws -> UInt64 {
        guard ImportFileSystem.isDirectory(receptionFolder) else { throw ImportRejection.sourceFailed }
        guard let items = FileManager.default.enumerator(at: receptionFolder, includingPropertiesForKeys: nil) else {
            throw ImportRejection.sourceFailed
        }
        var total: UInt64 = 0
        for case let file as URL in items {
            guard let info = ImportFileSystem.info(file), info.st_mode & S_IFMT == S_IFREG else { continue }
            let (sum, overflow) = total.addingReportingOverflow(UInt64(max(0, info.st_size)))
            total = overflow ? .max : sum
        }
        return total
    }

    public func remove() throws {
        guard ImportCleanupStore.hasOwnedShape(root, temporaryDirectory: temporaryDirectory),
              ImportFileSystem.isDirectory(root.deletingLastPathComponent()) else { throw ImportRejection.sourceFailed }
        if ImportFileSystem.info(root) != nil { try FileManager.default.removeItem(at: root) }
        store.remove(path: root.path)
    }
}
