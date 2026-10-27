import Foundation

/// Ranged reads of an entry inside a zip (FR-072, research.md R25). Not persisted and creates no temporary files.
/// Stored entries read the requested range directly with `pread`. Deflated entries keep 1 MB chunks in an LRU
/// cache; a missing chunk is produced by advancing the closest of up to two `InflateCursor` instances.
/// Memory does not depend on the entry size (32 MB cache + two cursors + the chunk being returned).
/// Retains `ArchiveFile`, so reads work after the zip is closed. Each `read` is serialized with `NSLock`.
public final class ArchiveEntryStream: @unchecked Sendable {
    private static let chunkSize = 1 << 20
    private static let storedIOChunkSize = 512 * 1024
    private static let maxCursors = 2

    /// Inflated size
    public let length: UInt64

    private let file: ArchiveFile
    private let dataOffset: UInt64
    private let isStored: Bool
    private let compressedSize: UInt64

    private let lock = NSLock()
    /// Usage order (oldest first)
    private var cursors: [InflateCursor] = []
    private var chunks: [Int: Data] = [:]
    /// Chunk numbers, oldest first
    private var chunkOrder: [Int] = []
    private var cachedBytes = 0

    init(file: ArchiveFile, dataOffset: UInt64, isStored: Bool, compressedSize: UInt64, uncompressedSize: UInt64) {
        self.file = file
        self.dataOffset = dataOffset
        self.isStored = isStored
        self.compressedSize = compressedSize
        self.length = uncompressedSize
    }

    /// Returns up to `maxLength` bytes starting at `offset`. Truncates at the end and returns empty `Data` at or
    /// past the end.
    public func read(offset: UInt64, maxLength: Int) throws(ArchiveError) -> Data {
        guard maxLength > 0, offset < length else { return Data() }
        let count = Int(min(UInt64(maxLength), length - offset))
        lock.lock()
        defer { lock.unlock() }
        return isStored ? try readStored(offset: offset, count: count) : try readDeflated(offset: offset, count: count)
    }

    // MARK: - Stored

    private func readStored(offset: UInt64, count: Int) throws(ArchiveError) -> Data {
        var result = Data(count: count)
        try result.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) throws(ArchiveError) in
            var done = 0
            while done < count {
                let piece = min(Self.storedIOChunkSize, count - done)
                let slice = UnsafeMutableRawBufferPointer(rebasing: buffer[done..<done + piece])
                guard try file.read(into: slice, at: dataOffset + offset + UInt64(done)) == piece else {
                    throw .corrupted(.dataTruncated)
                }
                done += piece
            }
        }
        return result
    }

    // MARK: - deflate

    private func readDeflated(offset: UInt64, count: Int) throws(ArchiveError) -> Data {
        var result = Data()
        result.reserveCapacity(count)
        var position = offset
        let end = offset + UInt64(count)
        while position < end {
            let index = Int(position / UInt64(Self.chunkSize))
            let chunk = try chunk(at: index)
            let chunkStart = UInt64(index) * UInt64(Self.chunkSize)
            let from = Int(position - chunkStart)
            let to = Int(min(UInt64(chunk.count), end - chunkStart))
            guard from < to else { throw .corrupted(.compressedDataTruncated) }
            result.append(chunk.subdata(in: from..<to))
            position = chunkStart + UInt64(to)
        }
        return result
    }

    private func chunk(at index: Int) throws(ArchiveError) -> Data {
        if let cached = chunks[index] {
            touch(index)
            return cached
        }
        let start = UInt64(index) * UInt64(Self.chunkSize)
        let size = Int(min(UInt64(Self.chunkSize), length - start))
        let cursor = cursor(forPosition: start)
        try cursor.skip(to: start)
        guard cursor.position == start else { throw .corrupted(.compressedDataTruncated) }

        var data = Data(count: size)
        try data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) throws(ArchiveError) in
            var done = 0
            while done < size {
                let slice = UnsafeMutableRawBufferPointer(rebasing: buffer[done...])
                let produced = try cursor.read(into: slice, maxLength: size - done)
                guard produced > 0 else { throw .corrupted(.compressedDataTruncated) }
                done += produced
            }
        }
        store(data, at: index)
        return data
    }

    /// Selects the closest cursor at or before `start`. If none exists, creates one when there is room; otherwise
    /// resets the oldest cursor to the beginning.
    private func cursor(forPosition start: UInt64) -> InflateCursor {
        var best: Int?
        for (offset, cursor) in cursors.enumerated() where cursor.position <= start {
            if best == nil || cursor.position > cursors[best!].position { best = offset }
        }
        let cursor: InflateCursor
        if let best {
            cursor = cursors.remove(at: best)
        } else if cursors.count < Self.maxCursors {
            cursor = InflateCursor(file: file, dataOffset: dataOffset, compressedSize: compressedSize)
        } else {
            cursor = cursors.removeFirst()
            cursor.reset()
        }
        cursors.append(cursor)
        return cursor
    }

    // MARK: - Chunk LRU

    private func touch(_ index: Int) {
        if let position = chunkOrder.firstIndex(of: index) { chunkOrder.remove(at: position) }
        chunkOrder.append(index)
    }

    private func store(_ data: Data, at index: Int) {
        chunks[index] = data
        cachedBytes += data.count
        touch(index)
        while cachedBytes > MemoryLimits.archiveStreamCacheBytes, chunkOrder.count > 1 {
            let oldest = chunkOrder.removeFirst()
            cachedBytes -= chunks.removeValue(forKey: oldest)?.count ?? 0
        }
    }
}
