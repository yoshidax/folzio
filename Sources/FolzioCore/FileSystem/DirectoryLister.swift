import Foundation

public enum ListingError: Error, Sendable, Equatable {
    case accessDenied
    case notFound
    case other(String)
}

public protocol DirectoryListing: Sendable {
    /// Returns direct subfolders (`.folder`; the same rule as `subfolders(of:)`, excluding hidden folders and
    /// packages), supported media files, and zip files (`.zip`, `.archive`), excluding hidden files and unsupported
    /// formats (FR-008, 068, 076). Builds the result from a single directory enumeration and does not sort it.
    func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile]
    func subfolders(of folder: URL) async throws(ListingError) -> [URL]
    func hasSubfolders(in folder: URL) async throws(ListingError) -> Bool
}

extension DirectoryListing {
    public func hasSubfolders(in folder: URL) async throws(ListingError) -> Bool {
        try await !subfolders(of: folder).isEmpty
    }
}

public struct DirectoryLister: DirectoryListing {
    private static let fileKeys: Set<URLResourceKey> = [
        .creationDateKey,
        .isDirectoryKey,
        .contentTypeKey,
        .fileSizeKey,
        .localizedTypeDescriptionKey,
    ]

    /// Keys used for media row values (used by search, which reads only matching files)
    private static let mediaKeys: Set<URLResourceKey> = [
        .creationDateKey,
        .fileSizeKey,
        .localizedTypeDescriptionKey,
    ]

    private static let archiveExtension = "zip"

    private static let folderKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isPackageKey,
        .localizedNameKey,
    ]

    /// Kind names managed by the app. Core has no Japanese defaults.
    private let kindNames: KindNames

    public init(kindNames: KindNames) {
        self.kindNames = kindNames
    }

    public func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] {
        try await run {
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
                throw ListingError.notFound
            }
            guard isDirectory.boolValue else {
                throw ListingError.notFound
            }

            let urls: [URL]
            do {
                urls = try fileManager.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: Array(Self.fileKeys),
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw Self.listingError(from: error)
            }

            return urls.compactMap { url -> MediaFile? in
                let values = try? url.resourceValues(forKeys: Self.fileKeys)
                if values?.isDirectory == true {
                    // As in the tree, do not show packages (such as .app) as folders (R29).
                    // isPackage is expensive, so query it only for directories.
                    guard (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage != true else { return nil }
                    return Self.folderRow(at: url, creationDate: values?.creationDate, kindNames: kindNames)
                }

                if url.pathExtension.lowercased() == Self.archiveExtension {
                    return MediaFile(
                        url: url,
                        name: url.lastPathComponent,
                        kind: .archive,
                        typeDescription: values?.localizedTypeDescription ?? kindNames.zipArchive,
                        creationDate: values?.creationDate,
                        fileSize: Int64(values?.fileSize ?? 0),
                        kindNameSource: values?.localizedTypeDescription == nil ? .zipArchive : nil
                    )
                }
                guard let kind = MediaKind(fileExtension: url.pathExtension) else { return nil }
                return Self.mediaFile(at: url, kind: kind, values: values)
            }
        }
    }

    /// Builds a folder row. Shared with `FileNameSearcher` so listings and search results use the same values
    /// (FR-139, R1).
    static func folderRow(at url: URL, creationDate: Date?, kindNames: KindNames) -> MediaFile {
        MediaFile(
            url: url,
            name: url.lastPathComponent,
            kind: .folder,
            typeDescription: kindNames.folder,
            creationDate: creationDate,
            fileSize: 0,
            kindNameSource: .folder
        )
    }

    /// Builds a media file row. Shared with `FileNameSearcher` so listings and search results use the same values
    /// (R36).
    static func mediaFile(at url: URL, kind: MediaKind) -> MediaFile? {
        mediaFile(at: url, kind: kind, values: try? url.resourceValues(forKeys: mediaKeys))
    }

    private static func mediaFile(at url: URL, kind: MediaKind, values: URLResourceValues?) -> MediaFile {
        MediaFile(
            url: url,
            name: url.lastPathComponent,
            kind: .media(kind),
            typeDescription: values?.localizedTypeDescription ?? kind.rawValue.uppercased(),
            creationDate: values?.creationDate,
            fileSize: Int64(values?.fileSize ?? 0)
        )
    }

    public func subfolders(of folder: URL) async throws(ListingError) -> [URL] {
        try await run {
            try Self.ensureDirectory(folder)

            let urls: [URL]
            do {
                urls = try FileManager.default.contentsOfDirectory(
                    at: folder,
                    includingPropertiesForKeys: Array(Self.folderKeys),
                    options: [.skipsHiddenFiles]
                )
            } catch {
                throw Self.listingError(from: error)
            }

            return urls.filter(Self.isVisibleSubfolder).sorted {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }
        }
    }

    public func hasSubfolders(in folder: URL) async throws(ListingError) -> Bool {
        try await run {
            try Self.ensureDirectory(folder)

            // Finish quickly even for folders with 10,000 items: skip non-directories using d_type from readdir, and
            // check hidden attributes and packages only for directories. The conditions match subfolders(of:).
            guard let directory = opendir(folder.path) else {
                throw Self.listingError(errno: errno)
            }
            defer { closedir(directory) }

            while true {
                errno = 0
                guard let entry = readdir(directory) else {
                    if errno != 0 {
                        throw Self.listingError(errno: errno)
                    }
                    return false
                }

                let type = entry.pointee.d_type
                guard type == DT_DIR || type == DT_UNKNOWN else { continue }

                let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                        String(cString: $0)
                    }
                }
                guard !name.hasPrefix(".") else { continue }

                let url = folder.appendingPathComponent(name, isDirectory: true)
                if Self.isVisibleSubfolder(url), (try? url.resourceValues(forKeys: [.isHiddenKey]))?.isHidden != true {
                    return true
                }
            }
        }
    }

    private static func ensureDirectory(_ folder: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            throw ListingError.notFound
        }
        guard isDirectory.boolValue else {
            throw ListingError.notFound
        }
    }

    private static func isVisibleSubfolder(_ url: URL) -> Bool {
        // isPackage is expensive, so query it only for directories.
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return false }
        return (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage != true
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws(ListingError) -> T {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try work()
            }.value
        } catch let error as ListingError {
            throw error
        } catch {
            throw ListingError.other(error.localizedDescription)
        }
    }

    private static func listingError(errno code: Int32) -> ListingError {
        switch code {
        case EACCES, EPERM:
            return .accessDenied
        case ENOENT, ENOTDIR:
            return .notFound
        default:
            return .other(String(cString: strerror(code)))
        }
    }

    private static func listingError(from error: Error) -> ListingError {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileReadUnknownError:
                return .accessDenied
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return .notFound
            default:
                break
            }
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(EACCES) {
            return .accessDenied
        }
        return .other(error.localizedDescription)
    }
}
