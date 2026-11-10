import Foundation
import FolzioCore

struct ImportTiming: Sendable {
    enum Stage: String, Sendable {
        case requested, reader, checking, checked, confirming, saving, finished, cancelled, failed, cleanupRequested
    }
    let sessionID: UUID
    let stage: Stage
    let elapsed: TimeInterval
    let duration: TimeInterval
    let kinds: [ExpectedKind]
}
