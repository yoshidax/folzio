import Foundation

/// Zip reader (FR-068–075, research.md R22, R24).
public protocol ArchiveReading: Sendable {
    /// Reads the central directory and builds the index. Do not call on the UI thread (R22).
    func open(_ archive: URL) async throws(ArchiveError) -> ArchiveIndex
    /// Reads an entire entry (for images). Throws `.tooLarge` when the inflated size exceeds `limit`.
    func data(for entryURL: URL, limit: Int) async throws(ArchiveError) -> Data
    /// Streams an entry (for video; R25). Fails for encrypted entries and unsupported methods. Do not call on the UI
    /// thread.
    func stream(for entryURL: URL) async throws(ArchiveError) -> ArchiveEntryStream
    /// Current identity of the zip file, or nil when it no longer exists.
    func identity(of archive: URL) -> ArchiveIdentity?
}

/// Zip reader implemented in this package. Reads only through `pread` on a file descriptor; does not read the
/// whole zip, memory-map it, or create temporary files. Caches the indexes and descriptors of the last two zips
/// opened, keyed by path, and uses them to look up entries in `data(for:)`.
public final class ZipArchiveReader: ArchiveReading, @unchecked Sendable {
    /// Number of zips to cache
    private static let cacheLimit = 2
    /// Maximum size to read as a central directory. Larger values are treated as damaged.
    private static let maxCentralDirectoryBytes: UInt64 = 256 * 1024 * 1024
    private static let ioChunkSize = 1 << 20
    /// Sizes that differ by more than the maximum deflate ratio (about 1032:1) are treated as damaged.
    private static let maxInflateRatio: UInt64 = 1100

    private final class State {
        let index: ArchiveIndex
        let file: ArchiveFile
        /// Entry path → data start offset. Computed once when first read.
        var dataOffsets: [String: UInt64] = [:]

        init(index: ArchiveIndex, file: ArchiveFile) {
            self.index = index
            self.file = file
        }
    }

    private let lock = NSLock()
    /// Newest first
    private var states: [(key: String, state: State)] = []
    private let kindNames: KindNames

    public init(kindNames: KindNames) {
        self.kindNames = kindNames
    }

    // MARK: - ArchiveReading

    public func open(_ archive: URL) async throws(ArchiveError) -> ArchiveIndex {
        try await runDetached { [self] () throws(ArchiveError) -> ArchiveIndex in
            try openSynchronously(archive).index
        }
    }

    public func data(for entryURL: URL, limit: Int) async throws(ArchiveError) -> Data {
        try await runDetached { [self] () throws(ArchiveError) -> Data in
            try readEntry(entryURL, limit: limit)
        }
    }

    public func stream(for entryURL: URL) async throws(ArchiveError) -> ArchiveEntryStream {
        try await runDetached { [self] () throws(ArchiveError) -> ArchiveEntryStream in
            try makeStream(entryURL)
        }
    }

    public func identity(of archive: URL) -> ArchiveIdentity? {
        ArchiveFile.currentIdentity(of: archive)
    }

    // MARK: - Execution

    /// Performs expensive work off the UI thread in a detached task. Propagates caller cancellation to the work.
    private func runDetached<T: Sendable>(
        _ work: @escaping @Sendable () throws(ArchiveError) -> T
    ) async throws(ArchiveError) -> T {
        let task = Task.detached(priority: .userInitiated) { () -> Result<T, ArchiveError> in
            do throws(ArchiveError) {
                return .success(try work())
            } catch {
                return .failure(error)
            }
        }
        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        return try result.get()
    }

    // MARK: - Opening

    private func openSynchronously(_ archive: URL) throws(ArchiveError) -> State {
        let file = try ArchiveFile.open(archive)
        let fileSize = file.size
        guard fileSize >= UInt64(ZipStructure.endOfCentralDirectorySize) else { throw .notAZip }

        let tailLength = Int(min(fileSize, UInt64(ZipStructure.maxEndSearchBytes)))
        let tail = try file.read(at: fileSize - UInt64(tailLength), length: tailLength)
        guard tail.count == tailLength else { throw .notAZip }
        let end = try ZipStructure.endOfCentralDirectory(inTail: tail, fileSize: fileSize)

        let location = try centralDirectoryLocation(of: end, in: file)
        guard location.size <= Self.maxCentralDirectoryBytes else {
            throw .corrupted(.centralDirectoryTooLarge)
        }
        let directory = try file.read(at: location.offset, length: Int(location.size))
        guard UInt64(directory.count) == location.size else { throw .notAZip }

        let entries = try ZipStructure.centralDirectoryEntries(directory, count: location.entryCount)
        let index = ArchiveIndex(archive: archive, identity: file.identity, centralEntries: entries, kindNames: kindNames)
        let state = State(index: index, file: file)
        remember(state, forKey: archive.path)
        return state
    }

    /// For ZIP64, follows the locator to the ZIP64 end of central directory record to find the central directory.
    private func centralDirectoryLocation(
        of end: ZipStructure.EndOfCentralDirectory,
        in file: ArchiveFile
    ) throws(ArchiveError) -> ZipStructure.CentralDirectoryLocation {
        guard end.needsZip64 else { return end.location }

        let locatorSize = UInt64(ZipStructure.zip64LocatorSize)
        var zip64Offset: UInt64?
        if end.recordOffset >= locatorSize {
            let bytes = try file.read(at: end.recordOffset - locatorSize, length: ZipStructure.zip64LocatorSize)
            do throws(ArchiveError) {
                zip64Offset = try ZipStructure.zip64Locator(bytes)
            } catch {
                // No locator signature: this may be a regular zip whose entry count alone is 0xFFFF.
                if error != .notAZip { throw error }
            }
        }
        guard let zip64Offset else {
            if end.location.size == 0xFFFF_FFFF || end.location.offset == 0xFFFF_FFFF { throw .notAZip }
            guard end.location.offset + end.location.size <= end.recordOffset else { throw .notAZip }
            return end.location
        }

        let recordSize = UInt64(ZipStructure.zip64EndOfCentralDirectorySize)
        let (recordEnd, overflow) = zip64Offset.addingReportingOverflow(recordSize)
        guard !overflow, recordEnd <= file.size else { throw .notAZip }
        let record = try file.read(at: zip64Offset, length: ZipStructure.zip64EndOfCentralDirectorySize)
        return try ZipStructure.zip64EndOfCentralDirectory(record, fileSize: file.size)
    }

    private func remember(_ state: State, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        states.removeAll { $0.key == key }
        states.insert((key: key, state: state), at: 0)
        if states.count > Self.cacheLimit { states.removeLast(states.count - Self.cacheLimit) }
    }

    /// Returns the cached zip state, reopening the zip when it is not cached.
    private func state(for archive: URL) throws(ArchiveError) -> State {
        let key = archive.path
        lock.lock()
        if let position = states.firstIndex(where: { $0.key == key }) {
            let found = states.remove(at: position)
            states.insert(found, at: 0)
            lock.unlock()
            return found.state
        }
        lock.unlock()
        return try openSynchronously(archive)
    }

    // MARK: - Reading Entries

    /// Looks up the entry for a URL in the index. Rejects encrypted entries and unsupported methods here.
    private func locateEntry(_ entryURL: URL) throws(ArchiveError) -> (state: State, entry: ArchiveEntry) {
        guard let parsed = ArchiveURL.parse(entryURL), !parsed.isParentLink else {
            throw .corrupted(.invalidLocation)
        }
        let state = try state(for: parsed.archive)
        guard let entry = state.index.entry(at: parsed.path), !entry.isDirectory else {
            throw .corrupted(.entryNotFound)
        }

        switch entry.readability {
        case .encrypted: throw .entryEncrypted
        case .unsupportedMethod: throw .unsupportedMethod(entry.method)
        case .readable: break
        }
        return (state, entry)
    }

    /// Creates a stream for ranged reads. Size mismatches are treated as damage using the same rule as
    /// `data(for:limit:)`.
    private func makeStream(_ entryURL: URL) throws(ArchiveError) -> ArchiveEntryStream {
        let (state, entry) = try locateEntry(entryURL)
        try validateSizes(of: entry)
        let start = try dataOffset(of: entry, in: state)
        return ArchiveEntryStream(
            file: state.file, dataOffset: start, isStored: entry.method == 0,
            compressedSize: entry.compressedSize, uncompressedSize: entry.uncompressedSize
        )
    }

    /// Checks whether the inflated size is consistent with the compression method.
    private func validateSizes(of entry: ArchiveEntry) throws(ArchiveError) {
        if entry.method == 0 {
            guard entry.uncompressedSize <= entry.compressedSize else {
                throw .corrupted(.sizeMismatch)
            }
            return
        }
        let (limitBytes, overflow) = entry.compressedSize.multipliedReportingOverflow(by: Self.maxInflateRatio)
        guard overflow || entry.uncompressedSize <= limitBytes + 1024 else {
            throw .corrupted(.sizeMismatch)
        }
    }

    private func readEntry(_ entryURL: URL, limit: Int) throws(ArchiveError) -> Data {
        let (state, entry) = try locateEntry(entryURL)
        guard limit >= 0, entry.uncompressedSize <= UInt64(limit) else { throw .tooLarge }
        guard entry.uncompressedSize > 0 else { return Data() }
        guard entry.uncompressedSize <= UInt64(Int.max) else { throw .tooLarge }
        let expected = Int(entry.uncompressedSize)

        let start = try dataOffset(of: entry, in: state)
        let file = state.file

        if entry.method == 0 {
            try validateSizes(of: entry)
            return try Self.makeData(count: expected) { buffer throws(ArchiveError) in
                var done = 0
                while done < buffer.count {
                    try Self.checkCancellation()
                    let length = min(Self.ioChunkSize, buffer.count - done)
                    let slice = UnsafeMutableRawBufferPointer(rebasing: buffer[done..<done + length])
                    guard try file.read(into: slice, at: start + UInt64(done)) == length else {
                        throw .corrupted(.dataTruncated)
                    }
                    done += length
                }
            }
        }

        try validateSizes(of: entry)
        let cursor = InflateCursor(file: file, dataOffset: start, compressedSize: entry.compressedSize)
        return try Self.makeData(count: expected) { buffer throws(ArchiveError) in
            var done = 0
            while done < buffer.count {
                try Self.checkCancellation()
                let length = min(Self.ioChunkSize, buffer.count - done)
                let slice = UnsafeMutableRawBufferPointer(rebasing: buffer[done..<done + length])
                let produced = try cursor.read(into: slice, maxLength: length)
                guard produced > 0 else { throw .corrupted(.compressedDataTruncated) }
                done += produced
            }
        }
    }

    /// Data start offset of an entry. Reads the local header to compute it and caches it per entry.
    private func dataOffset(of entry: ArchiveEntry, in state: State) throws(ArchiveError) -> UInt64 {
        lock.lock()
        let known = state.dataOffsets[entry.path]
        lock.unlock()
        if let known { return known }

        let header = try state.file.read(at: entry.localHeaderOffset, length: ZipStructure.localHeaderSize)
        let start = try ZipStructure.dataOffset(localHeader: header, localHeaderOffset: entry.localHeaderOffset)
        let fileSize = state.file.size
        guard start <= fileSize, entry.compressedSize <= fileSize - start else {
            throw .corrupted(.dataOutsideFile)
        }
        lock.lock()
        state.dataOffsets[entry.path] = start
        lock.unlock()
        return start
    }

    private static func checkCancellation() throws(ArchiveError) {
        if Task.isCancelled { throw .corrupted(.readCancelled) }
    }

    /// Allocates `count` bytes, fills them with `fill`, and returns a `Data` without copying.
    private static func makeData(
        count: Int,
        _ fill: (UnsafeMutableRawBufferPointer) throws(ArchiveError) -> Void
    ) throws(ArchiveError) -> Data {
        guard count > 0 else { return Data() }
        guard let pointer = malloc(count) else { throw .tooLarge }
        do {
            try fill(UnsafeMutableRawBufferPointer(start: pointer, count: count))
        } catch {
            free(pointer)
            throw error
        }
        return Data(bytesNoCopy: pointer, count: count, deallocator: .free)
    }
}
