import Foundation
import UniformTypeIdentifiers

/// Identity of a zip file (the value when opened; compared after FSEvents to detect changes to the zip).
public struct ArchiveIdentity: Sendable, Hashable {
    public var fileSize: UInt64
    public var modificationDate: Date
    public var inode: UInt64

    public init(fileSize: UInt64, modificationDate: Date, inode: UInt64) {
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.inode = inode
    }
}

/// Entry inside a zip, including directories. ArchiveEntry in data-model.md.
public struct ArchiveEntry: Sendable, Equatable {
    public enum Readability: Sendable, Equatable {
        case readable
        case encrypted
        case unsupportedMethod
    }

    /// Path inside the zip based on the name determined by FR-074. Directories end with `/`.
    public var path: String
    /// Last path component
    public var name: String
    public var isDirectory: Bool
    /// Compression method (0 = stored, 8 = deflate, anything else is unsupported)
    public var method: UInt16
    /// Bit 0 of the general purpose flags
    public var isEncrypted: Bool
    public var compressedSize: UInt64
    public var uncompressedSize: UInt64
    /// Local header offset. The data start offset is computed when first read.
    public var localHeaderOffset: UInt64
    public var modificationDate: Date?

    public var readability: Readability {
        if isEncrypted { return .encrypted }
        if method != 0 && method != 8 { return .unsupportedMethod }
        return .readable
    }
}

/// Index of an open zip (built by reading the central directory once; research.md R22, R23).
public struct ArchiveIndex: Sendable {
    public let archive: URL
    public let identity: ArchiveIdentity
    /// Entry path → entry (including implied intermediate directories)
    public private(set) var entries: [String: ArchiveEntry]
    /// Directory path ("" for the root) → paths of direct entries and directories (in central directory order)
    public private(set) var children: [String: [String]]
    /// Directory path → rows returned by `items(in:)`. Built when opening (in the background); `items(in:)` on the
    /// MainActor does not build them (SC-015).
    private let rows: [String: [MediaFile]]

    private static let utf8Flag: UInt16 = 0x0800
    private static let encryptedFlag: UInt16 = 0x0001

    private struct Candidate {
        var elements: [String]
        var path: String
        var isDirectory: Bool
        var isMedia: Bool
        var central: ZipStructure.CentralEntry
    }

    init(
        archive: URL,
        identity: ArchiveIdentity,
        centralEntries: [ZipStructure.CentralEntry],
        kindNames: KindNames
    ) {
        self.archive = archive
        self.identity = identity

        // First pass: decode and normalize names. Drop entries that are not shown and keep the first duplicate.
        var candidates: [Candidate] = []
        candidates.reserveCapacity(centralEntries.count)
        var seen = Set<String>()
        var directoryPaths = Set<String>()
        for central in centralEntries {
            let name = ArchiveNameDecoder.decode(central.nameBytes, utf8Flag: central.flags & Self.utf8Flag != 0)
            let elements = name.split(separator: "/", omittingEmptySubsequences: true)
                .filter { $0 != "." }
                .map(String.init)
            guard let last = elements.last,
                  !elements.contains(where: { $0.hasPrefix(".") }),
                  elements[0] != "__MACOSX" else { continue }
            let isDirectory = name.hasSuffix("/")
            let path = elements.joined(separator: "/") + (isDirectory ? "/" : "")
            guard seen.insert(path).inserted else { continue }

            if elements.count > 1 {
                var prefix = ""
                for element in elements.dropLast() {
                    prefix += element + "/"
                    directoryPaths.insert(prefix)
                }
            }
            if isDirectory { directoryPaths.insert(path) }
            candidates.append(Candidate(
                elements: elements,
                path: path,
                isDirectory: isDirectory,
                isMedia: !isDirectory && Self.mediaKind(ofName: last) != nil,
                central: central
            ))
        }

        // Second pass: build the entries and hierarchy.
        var entries: [String: ArchiveEntry] = [:]
        var children: [String: [String]] = [:]
        entries.reserveCapacity(candidates.count)
        var dateCache: [UInt32: Date?] = [:]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        for candidate in candidates {
            // Add implied intermediate directories.
            var parentPath = ""
            for element in candidate.elements.dropLast() {
                let directoryPath = parentPath + element + "/"
                if entries[directoryPath] == nil {
                    entries[directoryPath] = ArchiveEntry(
                        path: directoryPath, name: element, isDirectory: true, method: 0,
                        isEncrypted: false, compressedSize: 0, uncompressedSize: 0,
                        localHeaderOffset: 0, modificationDate: nil
                    )
                    children[parentPath, default: []].append(directoryPath)
                }
                parentPath = directoryPath
            }

            if candidate.isDirectory {
                let isNew = entries[candidate.path] == nil
                entries[candidate.path] = Self.makeEntry(candidate, calendar: calendar, cache: &dateCache)
                if isNew { children[parentPath, default: []].append(candidate.path) }
            } else if candidate.isMedia, !directoryPaths.contains(candidate.path + "/") {
                entries[candidate.path] = Self.makeEntry(candidate, calendar: calendar, cache: &dateCache)
                children[parentPath, default: []].append(candidate.path)
            }
        }
        self.entries = entries
        self.children = children
        self.rows = Self.makeRows(archive: archive, entries: entries, children: children, kindNames: kindNames)
    }

    public func entry(at path: String) -> ArchiveEntry? {
        entries[path]
    }

    /// True for the root (empty string) or for a directory present in the index (R73).
    public func containsDirectory(_ path: String) -> Bool {
        if path.isEmpty { return true }
        if children[path] != nil { return true }
        return entries[path]?.isDirectory == true
    }

    /// Rows directly under a directory (`.directory` directories and supported `.media` files). Unsorted.
    /// Does not include `..`.
    public func items(in directory: String) -> [MediaFile] {
        rows[directory] ?? []
    }

    // MARK: - Helpers

    private static func makeRows(
        archive: URL,
        entries: [String: ArchiveEntry],
        children: [String: [String]],
        kindNames: KindNames
    ) -> [String: [MediaFile]] {
        var descriptions: [String: String] = [:]
        var rows: [String: [MediaFile]] = [:]
        rows.reserveCapacity(children.count)
        for (directory, paths) in children {
            var result: [MediaFile] = []
            result.reserveCapacity(paths.count)
            for path in paths {
                guard let entry = entries[path] else { continue }
                let url = ArchiveURL.entry(archive: archive, path: path)
                if entry.isDirectory {
                    result.append(MediaFile(
                        url: url, name: entry.name, kind: .directory, typeDescription: kindNames.folder,
                        creationDate: entry.modificationDate, fileSize: 0, kindNameSource: .folder
                    ))
                } else if let kind = mediaKind(ofName: entry.name) {
                    let fileExtension = fileExtension(ofName: entry.name)
                    let description: String
                    if let cached = descriptions[fileExtension] {
                        description = cached
                    } else {
                        description = UTType(filenameExtension: fileExtension)?.localizedDescription
                            ?? fileExtension.uppercased()
                        descriptions[fileExtension] = description
                    }
                    result.append(MediaFile(
                        url: url, name: entry.name, kind: .media(kind), typeDescription: description,
                        creationDate: entry.modificationDate,
                        fileSize: Int64(clamping: entry.uncompressedSize)
                    ))
                }
            }
            rows[directory] = result
        }
        return rows
    }

    private static func makeEntry(
        _ candidate: Candidate,
        calendar: Calendar,
        cache: inout [UInt32: Date?]
    ) -> ArchiveEntry {
        let central = candidate.central
        return ArchiveEntry(
            path: candidate.path,
            name: candidate.elements[candidate.elements.count - 1],
            isDirectory: candidate.isDirectory,
            method: central.method,
            isEncrypted: central.flags & encryptedFlag != 0,
            compressedSize: central.compressedSize,
            uncompressedSize: candidate.isDirectory ? 0 : central.uncompressedSize,
            localHeaderOffset: central.localHeaderOffset,
            modificationDate: modificationDate(of: central, calendar: calendar, cache: &cache)
        )
    }

    /// Converts each distinct DOS date and time once because the same values are common.
    private static func modificationDate(
        of central: ZipStructure.CentralEntry,
        calendar: Calendar,
        cache: inout [UInt32: Date?]
    ) -> Date? {
        if !central.extraField.isEmpty,
           let unix = ZipStructure.unixModificationTime(in: central.extraField) {
            return Date(timeIntervalSince1970: TimeInterval(unix))
        }
        let key = UInt32(central.dosDate) << 16 | UInt32(central.dosTime)
        if let cached = cache[key] { return cached }
        let date = ZipStructure.dosDateTime(dosDate: central.dosDate, dosTime: central.dosTime, calendar: calendar)
        cache[key] = .some(date)
        return date
    }

    private static func fileExtension(ofName name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return String(name[name.index(after: dot)...])
    }

    private static func mediaKind(ofName name: String) -> MediaKind? {
        let fileExtension = fileExtension(ofName: name)
        return fileExtension.isEmpty ? nil : MediaKind(fileExtension: fileExtension)
    }
}
