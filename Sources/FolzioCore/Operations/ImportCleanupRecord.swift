import Foundation

public struct ImportCleanupRecord: Sendable, Equatable {
    public let path: String
    public let volumeUUID: String
    public let createdAt: Date
    public init(path: String, volumeUUID: String, createdAt: Date) {
        self.path = path; self.volumeUUID = volumeUUID; self.createdAt = createdAt
    }
}

/// Serializes read/modify/write operations for the shared cleanup record. File work must run off the UI thread.
public final class ImportCleanupStore: @unchecked Sendable {
    public static let key = "internal.pendingImportFolders"
    public static let shared = ImportCleanupStore(defaults: .standard)
    private let defaults: UserDefaults
    private let lock = NSLock()
    public init(defaults: UserDefaults) { self.defaults = defaults }

    public func records() -> [ImportCleanupRecord] { lock.withLock { load() } }
    public func add(_ record: ImportCleanupRecord) {
        lock.withLock {
            var current = load().filter { $0.path != record.path }
            current.append(record)
            save(current)
        }
    }
    public func remove(path: String) { lock.withLock { save(load().filter { $0.path != path }) } }

    /// Only the exact app-owned folder shape under the OS temporary directory is eligible for deletion.
    public func sweep(
        now: Date = Date(), temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        volumeUUID: ((URL) -> String?)? = nil
    ) {
        lock.withLock {
            var retained: [ImportCleanupRecord] = []
            let base = temporaryDirectory.appendingPathComponent("Folzio-Import", isDirectory: true)
            for record in load() {
                let url = URL(fileURLWithPath: record.path)
                let age = now.timeIntervalSince(record.createdAt)
                guard age >= 0, age <= 30 * 86400,
                      Self.hasOwnedShape(url, temporaryDirectory: temporaryDirectory) else { continue }
                guard let currentVolume = (volumeUUID ?? ImportFileSystem.volumeUUID)(temporaryDirectory) else { retained.append(record); continue }
                guard currentVolume == record.volumeUUID else { continue }
                guard ImportFileSystem.info(url) != nil else { continue }
                guard ImportFileSystem.isDirectory(base), ImportFileSystem.isDirectory(url),
                      ImportFileSystem.canonicalPath(url.deletingLastPathComponent()) == ImportFileSystem.canonicalPath(base) else { continue }
                do { try FileManager.default.removeItem(at: url) }
                catch { retained.append(record) }
            }
            save(retained)
        }
    }

    static func hasOwnedShape(_ url: URL, temporaryDirectory: URL) -> Bool {
        guard UUID(uuidString: url.lastPathComponent) != nil,
              let temporary = ImportFileSystem.canonicalPath(temporaryDirectory) else { return false }
        let expected = URL(fileURLWithPath: temporary).appendingPathComponent("Folzio-Import").appendingPathComponent(url.lastPathComponent)
        // The temporary directory may itself have an OS-provided symlink such as /var -> /private/var.
        let suppliedParent = url.deletingLastPathComponent().standardizedFileURL.path
        let literalBase = temporaryDirectory.appendingPathComponent("Folzio-Import").standardizedFileURL.path
        return suppliedParent == expected.deletingLastPathComponent().path || suppliedParent == literalBase
    }

    private func load() -> [ImportCleanupRecord] {
        (defaults.array(forKey: Self.key) ?? []).compactMap { value in
            guard let item = value as? [String: Any], let path = item["path"] as? String, path.hasPrefix("/"),
                  let volume = item["volumeUUID"] as? String, !volume.isEmpty,
                  let date = item["createdAt"] as? Date else { return nil }
            return ImportCleanupRecord(path: path, volumeUUID: volume, createdAt: date)
        }
    }
    private func save(_ records: [ImportCleanupRecord]) {
        defaults.set(records.map { ["path": $0.path, "volumeUUID": $0.volumeUUID, "createdAt": $0.createdAt] as [String: Any] }, forKey: Self.key)
    }
}
