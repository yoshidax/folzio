import Foundation

public struct FileOperation: Sendable {
    public enum Kind: Sendable {
        case copy
        case move
        case rename(newName: String)
        case trash
    }

    public var kind: Kind
    public var sources: [URL]
    public var destination: URL?

    public init(kind: Kind, sources: [URL], destination: URL? = nil) {
        self.kind = kind
        self.sources = sources
        self.destination = destination
    }
}

public enum ConflictResolution: Sendable {
    case replace
    case keepBoth
    case abort
}

public struct FileOperationResult: Sendable {
    public var succeeded: [URL]
    public var failed: [(url: URL, reason: OperationFailureReason)]

    public init(succeeded: [URL] = [], failed: [(url: URL, reason: OperationFailureReason)] = []) {
        self.succeeded = succeeded
        self.failed = failed
    }
}
