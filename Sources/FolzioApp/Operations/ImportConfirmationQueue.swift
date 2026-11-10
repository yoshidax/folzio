import Foundation

/// Serializes the confirmation and collision prompts for independent import sessions.
@MainActor
final class ImportConfirmationQueue {
    static let shared = ImportConfirmationQueue()
    private var locked = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func perform<T>(_ action: @MainActor () async -> T) async -> T {
        if locked { await withCheckedContinuation { waiting.append($0) } }
        else { locked = true }
        defer {
            if waiting.isEmpty { locked = false }
            else { waiting.removeFirst().resume() }
        }
        return await action()
    }
}
