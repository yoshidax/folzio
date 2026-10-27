import Foundation

/// Searches for supported media files and folders whose names match at every level below the search root
/// (FR-083, 085, 139; research.md R1).
public protocol FileNameSearching: Sendable {
    /// Yields matching media files and folders in small batches and finishes the stream after traversing every level.
    /// Terminating the stream (including cancellation) stops enumeration.
    func search(_ request: SearchRequest) -> AsyncStream<[MediaFile]>
}

extension FileNameSearching {
    /// Starts a search that does not match the root itself (`matchesRoot: false`) with a new visit log.
    public func search(in root: URL, matching pattern: SearchPattern) -> AsyncStream<[MediaFile]> {
        search(SearchRequest(root: root, pattern: pattern))
    }
}

/// Searches file and folder names with a `FileManager` enumerator (FR-083, 085, 139).
///
/// - Does not descend into hidden files or folders (or their contents), packages, or folders reached through
///   symbolic links. A link whose target is a folder is not a match.
/// - Treats a symbolic link to a file as a regular file, as `DirectoryLister` does, and uses the link's own path
///   as the URL.
/// - Matches a folder by name (the whole name, even when it contains ".") unless it is hidden, a package, or a
///   link to a folder, and returns a row with the same values as `DirectoryLister`.
/// - Records a directory in `SearchRequest.visits` immediately before matching it (files are not recorded). When
///   `matchesRoot` is true, also records and matches the root itself (FR-105, EC-94).
/// - Skips folders without read permission and continues. Returns a row when the name matches.
/// - Does not enumerate on the UI thread. Does not open zips (`.zip` is neither supported media nor a folder).
public struct FileNameSearcher: FileNameSearching {
    private let kindNames: KindNames
    private let batchSize: Int
    private let batchInterval: Duration

    public init(kindNames: KindNames, batchSize: Int = 256, batchInterval: Duration = .milliseconds(100)) {
        self.kindNames = kindNames
        self.batchSize = max(1, batchSize)
        self.batchInterval = batchInterval
    }

    public func search(_ request: SearchRequest) -> AsyncStream<[MediaFile]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [MediaFile].self)
        let kindNames = kindNames
        let batchSize = batchSize
        let batchInterval = batchInterval

        let task = Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            let root = request.root
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { return }

            let rebase = Self.rebaser(for: root)
            let clock = ContinuousClock()
            var pending: [MediaFile] = []
            var lastYield = clock.now

            func flush() {
                guard !pending.isEmpty else { return }
                continuation.yield(pending)
                pending.removeAll(keepingCapacity: true)
                lastYield = clock.now
            }

            if request.matchesRoot, let row = Self.matchedRoot(request: request, kindNames: kindNames) {
                pending.append(row)
            }

            while let next = enumerator.nextObject() {
                if Task.isCancelled { return }
                guard let url = next as? URL else { continue }

                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true {
                    // Record before matching. Without a record, the directory has not been matched yet (R2).
                    request.visits.record(SearchPath.normalized(rebase(url)))
                    if let row = Self.matchedFolder(at: url, pattern: request.pattern, rebase: rebase, kindNames: kindNames) {
                        pending.append(row)
                    }
                } else if let file = Self.matchedFile(
                    at: url,
                    values: values,
                    pattern: request.pattern,
                    rebase: rebase
                ) {
                    pending.append(file)
                }

                // Check elapsed time for each enumerated item so found results do not wait for the next match or the
                // end of enumeration.
                if pending.count >= batchSize || (!pending.isEmpty && clock.now - lastYield >= batchInterval) {
                    flush()
                    // Do not occupy the cooperative thread during long enumeration; let the receiver (including
                    // cancellation) run first.
                    await Task.yield()
                }
            }
            if Task.isCancelled { return }
            flush()
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
        return stream
    }

    /// The enumerator sometimes returns URLs in a different form from the root (for example, `/private/var/...`
    /// for a `/var/...` root, or the reverse), so rebases result URLs to the form of the supplied root. This aligns
    /// them with the URLs emitted by watching (`FileSystemWatching` subtrees) so a location opened from a listing
    /// compares as the same place in history and result organization (R38).
    private static func rebaser(for root: URL) -> @Sendable (URL) -> URL {
        let rootPath = SearchPath.normalized(root)
        guard rootPath != "/" else { return { $0 } }

        // Accept the original root form (`/var/...`), the resolved form (`/private/var/...`), and forms with
        // `/private` added or removed.
        var prefixes: Set<String> = []
        func addForms(of path: String) {
            let variants = [path, path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : "/private" + path]
            for variant in variants where variant != "/" {
                prefixes.insert(variant + "/")
            }
        }
        addForms(of: rootPath)
        if let resolved = realpath(rootPath, nil) {
            addForms(of: String(cString: resolved))
            free(resolved)
        }
        prefixes.remove(rootPath + "/")
        let ordered = prefixes.sorted { $0.count > $1.count }
        guard !ordered.isEmpty else { return { $0 } }

        return { url in
            let path = url.path
            for prefix in ordered where path.hasPrefix(prefix) {
                return URL(fileURLWithPath: rootPath + "/" + path.dropFirst(prefix.count), isDirectory: url.hasDirectoryPath)
            }
            return url
        }
    }

    /// Matches the root itself with the same rules when `matchesRoot` is true. Also checks hidden and package
    /// attributes (R3).
    private static func matchedRoot(request: SearchRequest, kindNames: KindNames) -> MediaFile? {
        let root = request.root
        let values = try? root.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey, .isPackageKey]
        )
        guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
        request.visits.record(SearchPath.normalized(root))
        guard values?.isHidden != true,
              values?.isPackage != true,
              request.pattern.matches(fileName: root.lastPathComponent) else { return nil }
        return folderRow(at: root, kindNames: kindNames)
    }

    /// Row for a directory whose name matches. Packages do not produce a row (FR-083, A-78).
    /// Does not query `isPackage` or the creation date for directories that do not match (SC-054).
    private static func matchedFolder(
        at url: URL,
        pattern: SearchPattern,
        rebase: (URL) -> URL,
        kindNames: KindNames
    ) -> MediaFile? {
        guard pattern.matches(fileName: url.lastPathComponent) else { return nil }
        guard (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage != true else { return nil }
        return folderRow(at: rebase(url), kindNames: kindNames)
    }

    private static func folderRow(at url: URL, kindNames: KindNames) -> MediaFile {
        let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        return DirectoryLister.folderRow(at: url, creationDate: creationDate, kindNames: kindNames)
    }

    private static func matchedFile(
        at enumeratedURL: URL,
        values: URLResourceValues?,
        pattern: SearchPattern,
        rebase: (URL) -> URL
    ) -> MediaFile? {
        let url = enumeratedURL
        if values?.isDirectory == true { return nil }
        guard let kind = MediaKind(fileExtension: url.pathExtension),
              pattern.matches(fileName: url.lastPathComponent) else { return nil }
        if values?.isSymbolicLink == true,
           (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return nil
        }
        return DirectoryLister.mediaFile(at: rebase(url), kind: kind)
    }
}
