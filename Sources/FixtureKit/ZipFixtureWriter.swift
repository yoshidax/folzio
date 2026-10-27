import Compression
import Foundation

public struct ZipFixtureEntry: Sendable {
    public enum Content: Sendable {
        case bytes(Data)
        /// Zero-filled content written without holding it all in memory.
        case zeros(count: UInt64)
    }

    public enum Method: Sendable, Equatable {
        case stored
        case deflated
        /// Writes only the method number and stores the content uncompressed (for reproducing unsupported methods).
        case raw(UInt16)
    }

    public var name: String
    public var rawName: Data?
    public var content: Content
    public var method: Method
    public var utf8Flag: Bool
    public var encryptedFlag: Bool
    public var isDirectory: Bool
    public var usesDataDescriptor: Bool
    public var modificationDate: Date
    public var unixModificationTime: Date?

    public init(
        name: String,
        rawName: Data? = nil,
        content: Content = .bytes(Data()),
        method: Method = .stored,
        utf8Flag: Bool = true,
        encryptedFlag: Bool = false,
        isDirectory: Bool = false,
        usesDataDescriptor: Bool = false,
        modificationDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        unixModificationTime: Date? = nil
    ) {
        self.name = name
        self.rawName = rawName
        self.content = content
        self.method = method
        self.utf8Flag = utf8Flag
        self.encryptedFlag = encryptedFlag
        self.isDirectory = isDirectory
        self.usesDataDescriptor = usesDataDescriptor
        self.modificationDate = modificationDate
        self.unixModificationTime = unixModificationTime
    }
}

public enum ZipFixtureError: Error, Equatable {
    case commentTooLong
    case compressionFailed
    case sizeRequiresZip64(String)
    case cannotCreateFile(String)
}

public enum ZipFixtureWriter {
    private static let chunkSize = 1 << 20
    private static let max32: UInt64 = 0xFFFF_FFFF
    private static let max16 = 0xFFFF

    public static func write(
        _ entries: [ZipFixtureEntry],
        to url: URL,
        forceZip64: Bool = false,
        comment: Data = Data()
    ) throws {
        let manager = FileManager.default
        try? manager.removeItem(at: url)
        guard manager.createFile(atPath: url.path, contents: nil) else {
            throw ZipFixtureError.cannotCreateFile(url.path)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        let sink = Sink(handle: handle)
        try build(entries, into: sink, forceZip64: forceZip64, comment: comment)
    }

    public static func archiveData(
        _ entries: [ZipFixtureEntry],
        forceZip64: Bool = false,
        comment: Data = Data()
    ) throws -> Data {
        let sink = Sink(handle: nil)
        try build(entries, into: sink, forceZip64: forceZip64, comment: comment)
        return sink.memory
    }

    // MARK: - Output

    private final class Sink {
        let handle: FileHandle?
        var memory = Data()
        private(set) var offset: UInt64 = 0

        init(handle: FileHandle?) {
            self.handle = handle
        }

        func write(_ data: Data) throws {
            if let handle {
                try handle.write(contentsOf: data)
            } else {
                memory.append(data)
            }
            offset += UInt64(data.count)
        }

        func write(_ bytes: UnsafeRawBufferPointer) throws {
            guard let base = bytes.baseAddress, !bytes.isEmpty else { return }
            if let handle {
                let view = Data(
                    bytesNoCopy: UnsafeMutableRawPointer(mutating: base),
                    count: bytes.count,
                    deallocator: .none
                )
                try handle.write(contentsOf: view)
            } else {
                memory.append(contentsOf: bytes)
            }
            offset += UInt64(bytes.count)
        }

        func patch(at position: UInt64, _ data: Data) throws {
            if let handle {
                try handle.seek(toOffset: position)
                try handle.write(contentsOf: data)
                try handle.seek(toOffset: offset)
            } else {
                let start = Int(position)
                memory.replaceSubrange(start..<start + data.count, with: data)
            }
        }
    }

    // MARK: - Assembly

    private struct Record {
        var nameBytes: Data
        var flags: UInt16
        var methodCode: UInt16
        var dosTime: UInt16
        var dosDate: UInt16
        var crc: UInt32
        var compressedSize: UInt64
        var uncompressedSize: UInt64
        var offset: UInt64
        var localZip64: Bool
        var unixTime: UInt32?
        var isDirectory: Bool
    }

    private static func build(
        _ entries: [ZipFixtureEntry],
        into sink: Sink,
        forceZip64: Bool,
        comment: Data
    ) throws {
        guard comment.count <= max16 else { throw ZipFixtureError.commentTooLong }
        var records: [Record] = []
        records.reserveCapacity(entries.count)
        for entry in entries {
            records.append(try writeEntry(entry, into: sink, forceZip64: forceZip64))
        }

        let centralStart = sink.offset
        for record in records {
            try sink.write(centralHeader(for: record, forceZip64: forceZip64))
        }
        let centralSize = sink.offset - centralStart

        let needsZip64End = forceZip64 || records.count >= max16
            || centralStart >= max32 || centralSize >= max32
        if needsZip64End {
            let zip64EndOffset = sink.offset
            var end = Data()
            end.appendLE(UInt32(0x0606_4B50))
            end.appendLE(UInt64(44))
            end.appendLE(UInt16(45))
            end.appendLE(UInt16(45))
            end.appendLE(UInt32(0))
            end.appendLE(UInt32(0))
            end.appendLE(UInt64(records.count))
            end.appendLE(UInt64(records.count))
            end.appendLE(centralSize)
            end.appendLE(centralStart)
            end.appendLE(UInt32(0x0706_4B50))
            end.appendLE(UInt32(0))
            end.appendLE(zip64EndOffset)
            end.appendLE(UInt32(1))
            try sink.write(end)
        }

        var eocd = Data()
        eocd.appendLE(UInt32(0x0605_4B50))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(UInt16(0))
        eocd.appendLE(needsZip64End ? UInt16(0xFFFF) : UInt16(records.count))
        eocd.appendLE(needsZip64End ? UInt16(0xFFFF) : UInt16(records.count))
        eocd.appendLE(needsZip64End ? UInt32(0xFFFF_FFFF) : UInt32(centralSize))
        eocd.appendLE(needsZip64End ? UInt32(0xFFFF_FFFF) : UInt32(centralStart))
        eocd.appendLE(UInt16(comment.count))
        eocd.append(comment)
        try sink.write(eocd)
    }

    private static func writeEntry(_ entry: ZipFixtureEntry, into sink: Sink, forceZip64: Bool) throws -> Record {
        var nameBytes = entry.rawName ?? Data(entry.name.utf8)
        if entry.isDirectory, nameBytes.last != UInt8(ascii: "/") {
            nameBytes.append(UInt8(ascii: "/"))
        }

        let content: ZipFixtureEntry.Content = entry.isDirectory ? .bytes(Data()) : entry.content
        let methodCode: UInt16
        var deflate = false
        if entry.isDirectory {
            methodCode = 0
        } else {
            switch entry.method {
            case .stored: methodCode = 0
            case .deflated: methodCode = 8; deflate = true
            case .raw(let code): methodCode = code
            }
        }
        let uncompressedSize: UInt64
        switch content {
        case .bytes(let data): uncompressedSize = UInt64(data.count)
        case .zeros(let count): uncompressedSize = count
        }

        var flags: UInt16 = 0
        if entry.encryptedFlag { flags |= 1 << 0 }
        if entry.usesDataDescriptor { flags |= 1 << 3 }
        if entry.utf8Flag { flags |= 1 << 11 }

        let (dosTime, dosDate) = dosDateTime(entry.modificationDate)
        let unixTime = entry.unixModificationTime.map { UInt32(clamping: Int64($0.timeIntervalSince1970)) }
        let localZip64 = forceZip64 || uncompressedSize >= max32
        let headerOffset = sink.offset

        var extra = Data()
        if localZip64 {
            extra.appendLE(UInt16(0x0001))
            extra.appendLE(UInt16(16))
            extra.appendLE(UInt64(0))
            extra.appendLE(UInt64(0))
        }
        if let unixTime {
            extra.appendLE(UInt16(0x5455))
            extra.appendLE(UInt16(5))
            extra.append(1)
            extra.appendLE(unixTime)
        }

        let sizeMarker: UInt32 = localZip64 && !entry.usesDataDescriptor ? 0xFFFF_FFFF : 0
        var header = Data()
        header.appendLE(UInt32(0x0403_4B50))
        header.appendLE(UInt16(localZip64 ? 45 : 20))
        header.appendLE(flags)
        header.appendLE(methodCode)
        header.appendLE(dosTime)
        header.appendLE(dosDate)
        header.appendLE(UInt32(0))
        header.appendLE(sizeMarker)
        header.appendLE(sizeMarker)
        header.appendLE(UInt16(nameBytes.count))
        header.appendLE(UInt16(extra.count))
        header.append(nameBytes)
        header.append(extra)
        try sink.write(header)

        var crc: UInt32 = 0
        var compressedSize: UInt64 = 0
        let deflater = deflate ? try Deflater() : nil
        defer { deflater?.destroy() }

        try feed(content) { chunk in
            crc = CRC32.update(crc, chunk)
            if let deflater {
                try deflater.process(chunk, finalize: false) { out in
                    compressedSize += UInt64(out.count)
                    try sink.write(out)
                }
            } else {
                compressedSize += UInt64(chunk.count)
                try sink.write(chunk)
            }
        }
        if let deflater {
            try deflater.process(UnsafeRawBufferPointer(start: nil, count: 0), finalize: true) { out in
                compressedSize += UInt64(out.count)
                try sink.write(out)
            }
        }

        if !localZip64, compressedSize >= max32 {
            throw ZipFixtureError.sizeRequiresZip64(entry.name)
        }

        if entry.usesDataDescriptor {
            var descriptor = Data()
            descriptor.appendLE(UInt32(0x0807_4B50))
            descriptor.appendLE(crc)
            if localZip64 {
                descriptor.appendLE(compressedSize)
                descriptor.appendLE(uncompressedSize)
            } else {
                descriptor.appendLE(UInt32(compressedSize))
                descriptor.appendLE(UInt32(uncompressedSize))
            }
            try sink.write(descriptor)
        } else {
            var crcBytes = Data()
            crcBytes.appendLE(crc)
            try sink.patch(at: headerOffset + 14, crcBytes)
            var sizes = Data()
            if localZip64 {
                sizes.appendLE(uncompressedSize)
                sizes.appendLE(compressedSize)
                try sink.patch(at: headerOffset + 30 + UInt64(nameBytes.count) + 4, sizes)
            } else {
                sizes.appendLE(UInt32(compressedSize))
                sizes.appendLE(UInt32(uncompressedSize))
                try sink.patch(at: headerOffset + 18, sizes)
            }
        }

        return Record(
            nameBytes: nameBytes, flags: flags, methodCode: methodCode,
            dosTime: dosTime, dosDate: dosDate, crc: crc,
            compressedSize: compressedSize, uncompressedSize: uncompressedSize,
            offset: headerOffset, localZip64: localZip64, unixTime: unixTime,
            isDirectory: entry.isDirectory
        )
    }

    private static func centralHeader(for record: Record, forceZip64: Bool) -> Data {
        let zip64 = record.localZip64 || forceZip64
            || record.compressedSize >= max32 || record.offset >= max32
        var extra = Data()
        if zip64 {
            extra.appendLE(UInt16(0x0001))
            extra.appendLE(UInt16(24))
            extra.appendLE(record.uncompressedSize)
            extra.appendLE(record.compressedSize)
            extra.appendLE(record.offset)
        }
        if let unixTime = record.unixTime {
            extra.appendLE(UInt16(0x5455))
            extra.appendLE(UInt16(5))
            extra.append(1)
            extra.appendLE(unixTime)
        }

        var data = Data()
        data.appendLE(UInt32(0x0201_4B50))
        data.appendLE(UInt16(zip64 ? 45 : 20))
        data.appendLE(UInt16(zip64 ? 45 : 20))
        data.appendLE(record.flags)
        data.appendLE(record.methodCode)
        data.appendLE(record.dosTime)
        data.appendLE(record.dosDate)
        data.appendLE(record.crc)
        data.appendLE(zip64 ? UInt32(0xFFFF_FFFF) : UInt32(record.compressedSize))
        data.appendLE(zip64 ? UInt32(0xFFFF_FFFF) : UInt32(record.uncompressedSize))
        data.appendLE(UInt16(record.nameBytes.count))
        data.appendLE(UInt16(extra.count))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt16(0))
        data.appendLE(UInt32(record.isDirectory ? 0x10 : 0))
        data.appendLE(zip64 ? UInt32(0xFFFF_FFFF) : UInt32(record.offset))
        data.append(record.nameBytes)
        data.append(extra)
        return data
    }

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = min(max(parts.year ?? 1980, 1980), 2107)
        let dosDate = UInt16((year - 1980) << 9 | (parts.month ?? 1) << 5 | (parts.day ?? 1))
        let dosTime = UInt16((parts.hour ?? 0) << 11 | (parts.minute ?? 0) << 5 | ((parts.second ?? 0) / 2))
        return (dosTime, dosDate)
    }

    /// Passes content in chunks of at most 1 MB. `.zeros` reuses a 1 MB buffer.
    private static func feed(
        _ content: ZipFixtureEntry.Content,
        _ body: (UnsafeRawBufferPointer) throws -> Void
    ) throws {
        switch content {
        case .bytes(let data):
            try data.withUnsafeBytes { buffer in
                var position = 0
                while position < buffer.count {
                    let length = min(chunkSize, buffer.count - position)
                    try body(UnsafeRawBufferPointer(rebasing: buffer[position..<position + length]))
                    position += length
                }
            }
        case .zeros(let count):
            let zeros = [UInt8](repeating: 0, count: Int(min(UInt64(chunkSize), count)))
            try zeros.withUnsafeBytes { buffer in
                var remaining = count
                while remaining > 0 {
                    let length = Int(min(UInt64(buffer.count), remaining))
                    try body(UnsafeRawBufferPointer(rebasing: buffer[0..<length]))
                    remaining -= UInt64(length)
                }
            }
        }
    }

    // MARK: - deflate

    /// Compresses in 1 MB chunks with `compression_stream` (`COMPRESSION_ZLIB` produces raw DEFLATE).
    private final class Deflater {
        private var stream: compression_stream
        private let output: UnsafeMutablePointer<UInt8>
        private let placeholder: UnsafeMutablePointer<UInt8>
        private var destroyed = false

        init() throws {
            placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
            output = UnsafeMutablePointer<UInt8>.allocate(capacity: ZipFixtureWriter.chunkSize)
            stream = compression_stream(
                dst_ptr: placeholder, dst_size: 0,
                src_ptr: UnsafePointer(placeholder), src_size: 0, state: nil
            )
            guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
                == COMPRESSION_STATUS_OK else {
                output.deallocate()
                placeholder.deallocate()
                destroyed = true
                throw ZipFixtureError.compressionFailed
            }
        }

        func process(
            _ input: UnsafeRawBufferPointer,
            finalize: Bool,
            emit: (UnsafeRawBufferPointer) throws -> Void
        ) throws {
            stream.src_ptr = input.baseAddress?.assumingMemoryBound(to: UInt8.self) ?? UnsafePointer(placeholder)
            stream.src_size = input.count
            let flags: Int32 = finalize ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
            while true {
                stream.dst_ptr = output
                stream.dst_size = ZipFixtureWriter.chunkSize
                let status = compression_stream_process(&stream, flags)
                guard status != COMPRESSION_STATUS_ERROR else { throw ZipFixtureError.compressionFailed }
                let produced = ZipFixtureWriter.chunkSize - stream.dst_size
                if produced > 0 {
                    try emit(UnsafeRawBufferPointer(start: output, count: produced))
                }
                if status == COMPRESSION_STATUS_END { return }
                if !finalize, stream.src_size == 0, stream.dst_size > 0 { return }
            }
        }

        func destroy() {
            guard !destroyed else { return }
            destroyed = true
            compression_stream_destroy(&stream)
            output.deallocate()
            placeholder.deallocate()
        }
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    mutating func appendLE(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}
