import Compression
import Foundation

/// A cursor that inflates a zip deflate entry sequentially from the start (research.md R24, R25).
/// It wraps `compression_stream` (`COMPRESSION_ZLIB` is raw DEFLATE with no header) and reads the compressed
/// range in 64 KB chunks with `pread`.
/// It tracks the inflated position in `position`; to move backward it inflates again from the beginning with `reset()`.
/// This type is not thread-safe. Callers must serialize access when using it from multiple threads.
final class InflateCursor {
    private static let inputChunkSize = 64 * 1024
    private static let scratchSize = 64 * 1024

    private let file: ArchiveFile
    private let dataOffset: UInt64
    private let compressedSize: UInt64

    private var stream: compression_stream
    private var streamReady = false
    private let input: UnsafeMutablePointer<UInt8>
    private let placeholder: UnsafeMutablePointer<UInt8>
    private var scratch: UnsafeMutablePointer<UInt8>?

    /// Number of compressed bytes read from the file so far
    private var inputRead: UInt64 = 0
    /// Whether the end of the compressed data has been read
    private var inputExhausted = false
    /// Whether inflation has finished because the end of the compressed data was reached,
    /// or because no further data can be inflated
    private var finished = false
    private var failed = false

    /// Offset in the inflated data
    private(set) var position: UInt64 = 0

    init(file: ArchiveFile, dataOffset: UInt64, compressedSize: UInt64) {
        self.file = file
        self.dataOffset = dataOffset
        self.compressedSize = compressedSize
        input = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.inputChunkSize)
        placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        stream = compression_stream(
            dst_ptr: placeholder, dst_size: 0,
            src_ptr: UnsafePointer(placeholder), src_size: 0, state: nil
        )
        failed = !startStream()
    }

    deinit {
        if streamReady { compression_stream_destroy(&stream) }
        input.deallocate()
        placeholder.deallocate()
        scratch?.deallocate()
    }

    /// Inflates again from the beginning.
    func reset() {
        if streamReady {
            compression_stream_destroy(&stream)
            streamReady = false
        }
        inputRead = 0
        inputExhausted = false
        finished = false
        position = 0
        failed = !startStream()
    }

    /// Advances to offset `target` in the inflated data, discarding the bytes in between. If `target` is before the
    /// current position, inflates again from the beginning.
    /// Stops early if the compressed data ends first; check `position` to confirm.
    func skip(to target: UInt64) throws(ArchiveError) {
        if target < position { reset() }
        guard position < target else { return }
        let buffer: UnsafeMutablePointer<UInt8>
        if let scratch {
            buffer = scratch
        } else {
            buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.scratchSize)
            scratch = buffer
        }
        while position < target {
            let wanted = Int(min(UInt64(Self.scratchSize), target - position))
            let produced = try read(into: UnsafeMutableRawBufferPointer(start: buffer, count: wanted), maxLength: wanted)
            if produced == 0 { return }
        }
    }

    /// Inflates at most `maxLength` bytes into `buffer` and returns the number of bytes written.
    /// If asked for data past the end of the compressed data, returns only the bytes that could be inflated
    /// (0 at the end).
    func read(into buffer: UnsafeMutableRawBufferPointer, maxLength: Int) throws(ArchiveError) -> Int {
        guard !failed else { throw .corrupted(.cannotStartInflate) }
        let limit = min(maxLength, buffer.count)
        guard limit > 0, !finished, let base = buffer.baseAddress else { return 0 }

        stream.dst_ptr = base.assumingMemoryBound(to: UInt8.self)
        stream.dst_size = limit
        defer {
            stream.dst_ptr = placeholder
            stream.dst_size = 0
        }

        while stream.dst_size > 0, !finished {
            if stream.src_size == 0, !inputExhausted {
                try refillInput()
            }
            let before = (source: stream.src_size, destination: stream.dst_size)
            let flags: Int32 = inputExhausted && stream.src_size == 0
                ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            let status = compression_stream_process(&stream, flags)
            if status == COMPRESSION_STATUS_END {
                finished = true
            } else if status == COMPRESSION_STATUS_OK {
                // If the input is exhausted and no output is produced, no more data can be inflated (the compressed
                // data ends prematurely).
                if stream.src_size == before.source, stream.dst_size == before.destination, inputExhausted {
                    finished = true
                }
            } else {
                finished = true
                failed = true
                position += UInt64(limit - stream.dst_size)
                throw .corrupted(.compressedDataDamaged)
            }
        }
        let produced = limit - stream.dst_size
        position += UInt64(produced)
        return produced
    }

    // MARK: - Internals

    private func startStream() -> Bool {
        stream.dst_ptr = placeholder
        stream.dst_size = 0
        stream.src_ptr = UnsafePointer(placeholder)
        stream.src_size = 0
        let status = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        streamReady = status == COMPRESSION_STATUS_OK
        return streamReady
    }

    private func refillInput() throws(ArchiveError) {
        let remaining = compressedSize - inputRead
        let (start, overflow) = dataOffset.addingReportingOverflow(inputRead)
        guard remaining > 0, !overflow else {
            inputExhausted = true
            return
        }
        let wanted = Int(min(UInt64(Self.inputChunkSize), remaining))
        let count = try file.read(
            into: UnsafeMutableRawBufferPointer(start: input, count: wanted), at: start
        )
        guard count > 0 else {
            inputExhausted = true
            return
        }
        inputRead += UInt64(count)
        if inputRead >= compressedSize { inputExhausted = true }
        stream.src_ptr = UnsafePointer(input)
        stream.src_size = count
    }
}
