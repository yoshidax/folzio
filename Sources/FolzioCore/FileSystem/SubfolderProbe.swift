import Foundation

public struct SubfolderProbeResult: Sendable {
    public let url: URL
    public let result: Result<Bool, ListingError>

    public init(url: URL, result: Result<Bool, ListingError>) {
        self.url = url
        self.result = result
    }
}

public enum SubfolderProbe {
    public static func results(
        for urls: [URL],
        lister: any DirectoryListing,
        maxConcurrent: Int = 4
    ) -> AsyncStream<SubfolderProbeResult> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: SubfolderProbeResult.self) { group in
                    var pending = urls.makeIterator()
                    for _ in 0..<max(1, maxConcurrent) {
                        guard let url = pending.next() else { break }
                        group.addTask { await probe(url, lister: lister) }
                    }

                    while let result = await group.next() {
                        continuation.yield(result)
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            break
                        }
                        if let url = pending.next() {
                            group.addTask { await probe(url, lister: lister) }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func probe(_ url: URL, lister: any DirectoryListing) async -> SubfolderProbeResult {
        do {
            let hasSubfolders = try await lister.hasSubfolders(in: url)
            return SubfolderProbeResult(url: url, result: .success(hasSubfolders))
        } catch {
            return SubfolderProbeResult(url: url, result: .failure(error))
        }
    }
}
