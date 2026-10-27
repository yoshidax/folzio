import CoreServices
import Foundation

public protocol FileSystemWatching: Sendable {
    /// Replaces the watched targets. `folders` emits URLs of folders where direct children were added, removed, or
    /// renamed. Folders in `subtrees` are watched recursively; changes emit the parent folder of the changed path by
    /// joining the relative components to the supplied root URL. Deleting or moving the root itself or an ancestor
    /// emits the root URL. Changes inside hidden folders below the root are not emitted (search result cleanup;
    /// FR-087, R38).
    func watch(_ folders: Set<URL>, subtrees: Set<URL>)
    var events: AsyncStream<Set<URL>> { get }
}

extension FileSystemWatching {
    public func watch(_ folders: Set<URL>) {
        watch(folders, subtrees: [])
    }
}

public final class FileSystemWatcher: FileSystemWatching, @unchecked Sendable {
    private static let debounceInterval: CFTimeInterval = 0.3
    /// Sends pending changes no later than this interval after the first pending change, even when changes continue
    /// (keeps notifications for FR-054, 042, and 087 flowing; R38).
    private static let maxLatency: CFTimeInterval = 1.0

    /// Root watched recursively. `url` is the form passed in (used when emitting); `realComponents` is the path
    /// components of the real path returned by FSEvents.
    private struct Subtree: Equatable {
        let url: URL
        let realComponents: [String]
    }

    private let queue = DispatchQueue(label: "FolzioCore.FileSystemWatcher")
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let eventStream: AsyncStream<Set<URL>>
    private let continuation: AsyncStream<Set<URL>>.Continuation

    private var watchedFolders: [String: URL] = [:]
    private var watchedSubtrees: [Subtree] = []
    /// `isHidden` per folder (real path) below `subtrees`. Discarded when `subtrees` changes.
    private var hiddenFolderCache: [String: Bool] = [:]
    private var pendingFolders: Set<URL> = []
    private var pendingSince: DispatchTime?
    private var debounceWorkItem: DispatchWorkItem?
    /// Stream for `folders`. Does not use WatchRoot (bug: fsevents-watchroot-fd-exhaustion).
    private var folderStream: FSEventStreamRef?
    /// Stream for `subtrees`. Uses WatchRoot to receive moves and deletions of the root and its ancestors (R38).
    private var subtreeStream: FSEventStreamRef?

    public init() {
        let (eventStream, continuation) = AsyncStream.makeStream(
            of: Set<URL>.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        self.eventStream = eventStream
        self.continuation = continuation
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            stopStream()
            debounceWorkItem?.cancel()
            debounceWorkItem = nil
            continuation.finish()
        } else {
            queue.sync {
                stopStream()
                debounceWorkItem?.cancel()
                debounceWorkItem = nil
                continuation.finish()
            }
        }
    }

    public var events: AsyncStream<Set<URL>> {
        eventStream
    }

    public func watch(_ folders: Set<URL>, subtrees: Set<URL>) {
        let normalized = Set(folders.map(\.standardizedFileURL))
        // Keep subtrees in the form passed in. Do not use standardizedFileURL because it removes /private from
        // existing paths (R38).
        let normalizedSubtrees = subtrees
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            applyFolders(normalized, subtrees: normalizedSubtrees)
        } else {
            queue.sync {
                applyFolders(normalized, subtrees: normalizedSubtrees)
            }
        }
    }

    // MARK: - State (queue-confined)

    private static func key(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Path components of the real path (`realpath(3)`; the `/private/var/...` form returned by FSEvents), or the
    /// path from `key(for:)` on failure. Does not use `standardizedFileURL` because it removes `/private` from
    /// existing paths and breaks comparisons with paths that no longer exist.
    private static func realComponents(of url: URL) -> [String] {
        let path: String
        if let resolved = realpath(url.path, nil) {
            path = String(cString: resolved)
            free(resolved)
        } else {
            path = key(for: url)
        }
        return URL(fileURLWithPath: path).pathComponents
    }

    private func applyFolders(_ folders: Set<URL>, subtrees: Set<URL>) {
        let mapping = Dictionary(
            folders.map { (Self.key(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let newSubtrees = subtrees
            .sorted { $0.path < $1.path }
            .map { Subtree(url: $0, realComponents: Self.realComponents(of: $0)) }
        let foldersChanged = mapping != watchedFolders
        let subtreesChanged = newSubtrees != watchedSubtrees
        guard foldersChanged || subtreesChanged else { return }

        watchedFolders = mapping
        if subtreesChanged {
            hiddenFolderCache.removeAll()
        }
        watchedSubtrees = newSubtrees
        pendingFolders.removeAll()
        pendingSince = nil
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        // Rebuild only the changed side. Do not recreate the subtree stream on every tree operation.
        if foldersChanged {
            rebuildFolderStream()
        }
        if subtreesChanged {
            rebuildSubtreeStream()
        }
    }

    /// WatchRoot opens a descriptor for each ancestor of a watched path (one per path depth). It is not used for
    /// `folders`, which watches every row visible in the tree, because it would exhaust the 256-descriptor limit for
    /// GUI apps. Changes to `folders` arrive as changes to the parent folder (bug:
    /// fsevents-watchroot-fd-exhaustion).
    private func rebuildFolderStream() {
        Self.stop(&folderStream)
        let paths = Set(watchedFolders.values.map(\.path))
        folderStream = makeStream(paths: paths, watchesRoot: false)
    }

    private func rebuildSubtreeStream() {
        Self.stop(&subtreeStream)
        var paths: Set<String> = []
        for subtree in watchedSubtrees {
            paths.insert(subtree.url.path)
            paths.insert(NSString.path(withComponents: subtree.realComponents))
        }
        // WatchRoot: also receive moves and deletions of the root itself and its ancestors (R38).
        subtreeStream = makeStream(paths: paths, watchesRoot: true)
    }

    private func makeStream(paths pathSet: Set<String>, watchesRoot: Bool) -> FSEventStreamRef? {
        guard !pathSet.isEmpty else { return nil }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let paths = Array(pathSet) as CFArray
        var flags = kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes
        if watchesRoot {
            flags |= kFSEventStreamCreateFlagWatchRoot
        }
        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileSystemWatcherCallback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.debounceInterval,
            FSEventStreamCreateFlags(flags)
        ) else {
            return nil
        }

        FSEventStreamSetDispatchQueue(newStream, queue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            return nil
        }
        return newStream
    }

    private func stopStream() {
        Self.stop(&folderStream)
        Self.stop(&subtreeStream)
    }

    private static func stop(_ stream: inout FSEventStreamRef?) {
        guard let current = stream else { return }
        FSEventStreamStop(current)
        FSEventStreamInvalidate(current)
        FSEventStreamRelease(current)
        stream = nil
    }

    fileprivate func handleEventPaths(_ rawPaths: UnsafeMutableRawPointer, count: Int) {
        guard count > 0 else { return }
        let paths = unsafeBitCast(rawPaths, to: NSArray.self) as? [String] ?? []
        guard !paths.isEmpty else { return }

        var changed: Set<URL> = []
        for path in paths.prefix(count) {
            let eventURL = URL(fileURLWithPath: path)
            let parent = eventURL.deletingLastPathComponent()
            if let watched = watchedFolders[Self.key(for: parent)] {
                changed.insert(watched)
            }
            if !watchedSubtrees.isEmpty {
                changed.formUnion(subtreeFolders(forEventAt: eventURL))
            }
        }
        guard !changed.isEmpty else { return }
        scheduleEmit(changed)
    }

    /// For an event at or below a `subtrees` root, returns the parent folder of the changed path by joining the
    /// relative components to the supplied root URL. Returns the root URL for changes to the root itself or an
    /// ancestor. Discards paths whose components from the root to the parent include a hidden folder (R38).
    private func subtreeFolders(forEventAt eventURL: URL) -> [URL] {
        // FSEvents paths are real paths (no `.` or `..`), so compare components without standardizedFileURL.
        let eventComponents = eventURL.pathComponents
        let parentComponents = Array(eventComponents.dropLast())
        var result: [URL] = []
        for subtree in watchedSubtrees {
            let real = subtree.realComponents
            if real.starts(with: eventComponents) || subtree.url.pathComponents.starts(with: eventComponents) {
                result.append(subtree.url)
                continue
            }
            guard parentComponents.starts(with: real) else { continue }
            let relative = Array(parentComponents.dropFirst(real.count))
            guard !containsHiddenFolder(relative, under: real) else { continue }
            result.append(relative.reduce(subtree.url) { $0.appendingPathComponent($1, isDirectory: true) })
        }
        return result
    }

    private func containsHiddenFolder(_ relative: [String], under real: [String]) -> Bool {
        guard !relative.contains(where: { $0.hasPrefix(".") }) else { return true }
        var components = real
        for name in relative {
            components.append(name)
            let path = NSString.path(withComponents: components)
            let hidden: Bool
            if let cached = hiddenFolderCache[path] {
                hidden = cached
            } else {
                hidden = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isHiddenKey]))?.isHidden == true
                hiddenFolderCache[path] = hidden
            }
            if hidden { return true }
        }
        return false
    }

    private func scheduleEmit(_ folders: Set<URL>) {
        pendingFolders.formUnion(folders)
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.emitPending()
        }
        debounceWorkItem = item
        let now = DispatchTime.now()
        let since = pendingSince ?? now
        pendingSince = since
        let deadline = min(now + Self.debounceInterval, since + Self.maxLatency)
        queue.asyncAfter(deadline: deadline, execute: item)
    }

    private func emitPending() {
        debounceWorkItem = nil
        pendingSince = nil
        let batch = pendingFolders
        pendingFolders.removeAll()
        guard !batch.isEmpty else { return }
        continuation.yield(batch)
    }
}

private func fileSystemWatcherCallback(
    _ stream: ConstFSEventStreamRef,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ numEvents: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo else { return }
    let watcher = Unmanaged<FileSystemWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
    watcher.handleEventPaths(eventPaths, count: numEvents)
}
