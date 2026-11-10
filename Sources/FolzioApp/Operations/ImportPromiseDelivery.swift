import Foundation
import FolzioCore

/// A discarded payload still acknowledges the producer's completed write.
struct ImportPromiseDelivery: Sendable {
    let result: Result<ImportSnapshot, ImportRejection>?
    let identity: String?
    let snapshotSeconds: TimeInterval
    let failed: Bool

    init(result: Result<ImportSnapshot, ImportRejection>?, identity: String? = nil,
         snapshotSeconds: TimeInterval = 0, failed: Bool = false) {
        self.result = result
        if case let .success(snapshot)? = result { self.identity = snapshot.canonicalSourcePath }
        else { self.identity = identity }
        self.snapshotSeconds = snapshotSeconds
        if case .failure? = result { self.failed = true }
        else { self.failed = failed }
    }
}
