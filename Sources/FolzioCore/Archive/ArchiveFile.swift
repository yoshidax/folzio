import Darwin
import Foundation

/// Descriptor for a zip file opened read-only. Shared by reference counting and closed when the last reference is
/// released. All reads use `pread` with explicit offsets, so concurrent readers do not interfere with each other
/// (research.md R22). Does not read the whole zip or memory-map it.
final class ArchiveFile: Sendable {
    let url: URL
    let size: UInt64
    let identity: ArchiveIdentity
    private let descriptor: Int32

    private init(url: URL, descriptor: Int32, size: UInt64, identity: ArchiveIdentity) {
        self.url = url
        self.descriptor = descriptor
        self.size = size
        self.identity = identity
    }

    deinit {
        close(descriptor)
    }

    static func open(_ url: URL) throws(ArchiveError) -> ArchiveFile {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw error(forErrno: errno) }

        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            let code = errno
            close(descriptor)
            throw error(forErrno: code)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            throw .notAZip
        }
        let identity = makeIdentity(info)
        return ArchiveFile(url: url, descriptor: descriptor, size: identity.fileSize, identity: identity)
    }

    /// `stat` for the path, or nil when the file no longer exists.
    static func currentIdentity(of url: URL) -> ArchiveIdentity? {
        var info = stat()
        guard stat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return makeIdentity(info)
    }

    /// Reads up to `length` bytes from `offset`. Does not read past the end of the file (the result is shorter).
    func read(at offset: UInt64, length: Int) throws(ArchiveError) -> Data {
        guard length > 0, offset < size else { return Data() }
        let count = Int(min(UInt64(length), size - offset))
        let raw = UnsafeMutableRawBufferPointer.allocate(byteCount: count, alignment: 1)
        defer { raw.deallocate() }
        let read = try read(into: raw, at: offset)
        guard read > 0, let base = raw.baseAddress else { return Data() }
        return Data(bytes: base, count: read)
    }

    /// Reads from `offset` up to the size of `buffer` and returns the number of bytes read (0 at the end of the file).
    func read(into buffer: UnsafeMutableRawBufferPointer, at offset: UInt64) throws(ArchiveError) -> Int {
        guard let base = buffer.baseAddress, !buffer.isEmpty,
              offset < size, offset <= UInt64(Int64.max) else { return 0 }
        var total = 0
        while total < buffer.count {
            let position = offset + UInt64(total)
            guard position <= UInt64(Int64.max) else { break }
            let result = pread(descriptor, base + total, buffer.count - total, off_t(position))
            if result > 0 {
                total += result
            } else if result == 0 {
                break
            } else if errno == EINTR {
                continue
            } else {
                throw .corrupted(.readFailed)
            }
        }
        return total
    }

    private static func makeIdentity(_ info: stat) -> ArchiveIdentity {
        let seconds = TimeInterval(info.st_mtimespec.tv_sec)
        let fraction = TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        return ArchiveIdentity(
            fileSize: UInt64(clamping: info.st_size),
            modificationDate: Date(timeIntervalSince1970: seconds + fraction),
            inode: UInt64(info.st_ino)
        )
    }

    private static func error(forErrno code: Int32) -> ArchiveError {
        switch code {
        case ENOENT, ENOTDIR:
            return .notFound
        case EACCES, EPERM:
            return .accessDenied
        default:
            return .corrupted(.unreadable)
        }
    }
}
