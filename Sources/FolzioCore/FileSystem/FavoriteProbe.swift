import Foundation

public struct FavoriteProbeResult: Sendable, Equatable {
    public let url: URL
    public let exists: Bool

    public init(url: URL, exists: Bool) {
        self.url = url
        self.exists = exists
    }
}

public enum FavoriteProbe {
    /// Whether `fileExists(atPath:isDirectory:)` reports a directory. Do not call on the UI thread.
    public static func folderExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public static func results(
        for urls: [URL],
        maxConcurrent: Int = 4,
        exists: @escaping @Sendable (URL) async -> Bool = { folderExists($0) }
    ) -> AsyncStream<FavoriteProbeResult> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: FavoriteProbeResult.self) { group in
                    var pending = urls.makeIterator()
                    for _ in 0..<max(1, maxConcurrent) {
                        guard let url = pending.next() else { break }
                        group.addTask { FavoriteProbeResult(url: url, exists: await exists(url)) }
                    }

                    while let result = await group.next() {
                        continuation.yield(result)
                        guard !Task.isCancelled else {
                            group.cancelAll()
                            break
                        }
                        if let url = pending.next() {
                            group.addTask { FavoriteProbeResult(url: url, exists: await exists(url)) }
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
}
