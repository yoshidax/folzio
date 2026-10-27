import Foundation

public protocol FileOperating: Sendable {
    func conflicts(for operation: FileOperation) -> [URL]
    func execute(_ operation: FileOperation, resolution: ConflictResolution) async -> FileOperationResult
}

public struct FileOperationService: FileOperating {
    public init() {}

    public func conflicts(for operation: FileOperation) -> [URL] {
        guard let destination = operation.destination else { return [] }
        switch operation.kind {
        case .copy:
            return operation.sources.filter { source in
                FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent(source.lastPathComponent).path
                )
            }
        case .move:
            return operation.sources.filter { source in
                guard !Self.sameFolder(source.deletingLastPathComponent(), destination) else { return false }
                return FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent(source.lastPathComponent).path
                )
            }
        case .rename, .trash:
            return []
        }
    }

    /// `resolution` is used only when an item with the same name conflicts. `.abort` returns conflicting items as
    /// failures and executes non-conflicting items (such as moving to the Trash or renaming without a name conflict).
    public func execute(_ operation: FileOperation, resolution: ConflictResolution) async -> FileOperationResult {
        await Task.detached(priority: .userInitiated) {
            Self.perform(operation, resolution: resolution)
        }.value
    }

    private static func perform(_ operation: FileOperation, resolution: ConflictResolution) -> FileOperationResult {
        let fileManager = FileManager.default
        var succeeded: [URL] = []
        var failed: [(url: URL, reason: OperationFailureReason)] = []
        var createdNames: Set<String> = []

        for source in operation.sources {
            do {
                let resultURL: URL
                switch operation.kind {
                case .copy, .move:
                    resultURL = try transfer(
                        source,
                        operation: operation,
                        resolution: resolution,
                        createdNames: &createdNames,
                        fileManager: fileManager
                    )
                case .rename(let newName):
                    resultURL = try rename(
                        source,
                        to: newName,
                        resolution: resolution,
                        fileManager: fileManager
                    )
                case .trash:
                    resultURL = try moveToTrash(source, fileManager: fileManager)
                }
                succeeded.append(resultURL)
            } catch let failure as OperationFailure {
                failed.append((source, failure.reason))
            } catch {
                failed.append((source, .systemFailure(systemReason: error.localizedDescription)))
            }
        }

        return FileOperationResult(succeeded: succeeded, failed: failed)
    }

    private static func transfer(
        _ source: URL,
        operation: FileOperation,
        resolution: ConflictResolution,
        createdNames: inout Set<String>,
        fileManager: FileManager
    ) throws -> URL {
        guard let destination = operation.destination else {
            throw OperationFailure(reason: .noDestination)
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw OperationFailure(reason: .destinationNotFound)
        }
        var sourceIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDirectory) else {
            throw OperationFailure(reason: .sourceNotFound)
        }

        let isMove: Bool
        switch operation.kind {
        case .move:
            isMove = true
        default:
            isMove = false
        }

        if isMove, sameFolder(source.deletingLastPathComponent(), destination) {
            return source
        }

        let provisionalTarget = destination.appendingPathComponent(source.lastPathComponent)
        if sourceIsDirectory.boolValue, isDescendant(destination, of: source) {
            throw OperationFailure(reason: .intoItself)
        }

        if case .copy = operation.kind, case .replace = resolution,
           Self.sameItem(source, provisionalTarget, fileManager: fileManager) {
            throw OperationFailure(reason: .sameNameAtDestination)
        }

        let target = try resolveTarget(
            for: source,
            in: destination,
            resolution: resolution,
            createdNames: &createdNames,
            fileManager: fileManager
        )

        if isMove {
            do {
                try fileManager.moveItem(at: source, to: target)
            } catch {
                throw OperationFailure(reason: .systemFailure(systemReason: error.localizedDescription))
            }
        } else {
            let destinationWasEmpty = !fileManager.fileExists(atPath: target.path)
            do {
                try fileManager.copyItem(at: source, to: target)
            } catch {
                if destinationWasEmpty, fileManager.fileExists(atPath: target.path) {
                    try? fileManager.removeItem(at: target)
                }
                throw OperationFailure(reason: .systemFailure(systemReason: error.localizedDescription))
            }
        }

        createdNames.insert(target.lastPathComponent)
        return target
    }

    private static func rename(
        _ source: URL,
        to newName: String,
        resolution: ConflictResolution,
        fileManager: FileManager
    ) throws -> URL {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OperationFailure(reason: .invalidName(.empty))
        }
        guard !newName.contains("/") && !newName.contains(":") else {
            throw OperationFailure(reason: .invalidName(.forbiddenCharacter))
        }
        guard !newName.hasPrefix(".") else {
            throw OperationFailure(reason: .invalidName(.leadingDot))
        }
        guard fileManager.fileExists(atPath: source.path) else {
            throw OperationFailure(reason: .sourceNotFound)
        }

        let parent = source.deletingLastPathComponent()
        var target = parent.appendingPathComponent(newName)
        if target.standardizedFileURL == source.standardizedFileURL {
            return source
        }

        if fileManager.fileExists(atPath: target.path) {
            switch resolution {
            case .abort:
                throw OperationFailure(reason: .sameNameExists)
            case .replace:
                _ = try moveToTrash(target, fileManager: fileManager)
            case .keepBoth:
                let names = Set((try? fileManager.contentsOfDirectory(atPath: parent.path)) ?? [])
                let unique = uniqueName(for: newName, existingNames: names)
                target = parent.appendingPathComponent(unique)
            }
        }

        do {
            try fileManager.moveItem(at: source, to: target)
        } catch {
            throw OperationFailure(reason: .systemFailure(systemReason: error.localizedDescription))
        }
        return target
    }

    private static func resolveTarget(
        for source: URL,
        in destination: URL,
        resolution: ConflictResolution,
        createdNames: inout Set<String>,
        fileManager: FileManager
    ) throws -> URL {
        let target = destination.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: target.path) else {
            return target
        }

        switch resolution {
        case .abort:
            throw OperationFailure(reason: .sameNameAtDestination)
        case .replace:
            _ = try moveToTrash(target, fileManager: fileManager)
            return target
        case .keepBoth:
            var names = Set((try? fileManager.contentsOfDirectory(atPath: destination.path)) ?? [])
            names.formUnion(createdNames)
            let name = uniqueName(for: source.lastPathComponent, existingNames: names)
            createdNames.insert(name)
            return destination.appendingPathComponent(name)
        }
    }

    private static func moveToTrash(_ url: URL, fileManager: FileManager) throws -> URL {
        guard fileManager.fileExists(atPath: url.path) else {
            throw OperationFailure(reason: .sourceNotFound)
        }
        var resultingURL: NSURL?
        do {
            try fileManager.trashItem(at: url, resultingItemURL: &resultingURL)
        } catch {
            throw OperationFailure(reason: .trashExistingFailed(systemReason: error.localizedDescription))
        }
        return (resultingURL as URL?) ?? url
    }

    /// Also protects aliases and hard links to the source before moving a conflict to Trash.
    public static func sameItem(_ lhs: URL, _ rhs: URL, fileManager: FileManager = .default) -> Bool {
        if lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path { return true }
        guard let left = try? fileManager.attributesOfItem(atPath: lhs.path),
              let right = try? fileManager.attributesOfItem(atPath: rhs.path),
              let leftDevice = left[.systemNumber] as? NSNumber,
              let rightDevice = right[.systemNumber] as? NSNumber,
              let leftID = left[.systemFileNumber] as? NSNumber,
              let rightID = right[.systemFileNumber] as? NSNumber else { return false }
        return leftDevice == rightDevice && leftID == rightID
    }

    private static func sameFolder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path
            == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isDescendant(_ candidate: URL, of directory: URL) -> Bool {
        let directoryPath = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let candidatePath = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        if candidatePath == directoryPath {
            return true
        }
        return candidatePath.hasPrefix(directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/")
    }
}

private struct OperationFailure: Error, Sendable {
    let reason: OperationFailureReason
}
