import Foundation
import FolzioCore

@MainActor
final class ImportStagingPool {
    private(set) var ready: [ImportStaging] = []
    private var replenishing: Task<Void, Never>?
    private var stopped = false
    private let factory: @Sendable () throws -> ImportStaging

    init(factory: @escaping @Sendable () throws -> ImportStaging = { try ImportStaging.create() }) {
        self.factory = factory
    }

    func prepare() async {
        replenish()
        await replenishing?.value
    }

    func replenish() {
        guard !stopped, replenishing == nil, ready.count < 2 else { return }
        replenishing = Task { [self] in
            while !stopped, ready.count < 2 {
                do {
                    let stage = try await Task.detached { [factory] in try factory() }.value
                    if stopped { await Self.remove(stage); break }
                    ready.append(stage)
                } catch { break }
            }
            replenishing = nil
        }
    }

    func fresh() async throws -> ImportStaging { try await Task.detached { [factory] in try factory() }.value }

    func take() -> ImportStaging? {
        defer { replenish() }
        return ready.isEmpty ? nil : ready.removeFirst()
    }

    func shutdown() async {
        stopped = true
        await replenishing?.value
        let unused = ready
        ready.removeAll()
        for stage in unused { await Self.remove(stage) }
    }

    nonisolated static func remove(_ stage: ImportStaging) async {
        await Task.detached { try? stage.remove() }.value
    }
}
