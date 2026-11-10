import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ContentKind: Sendable, Equatable {
    case image(UTType)
    case video(MediaKind)

    public var contentType: UTType {
        switch self {
        case let .image(type): return type
        case .video(.mov): return .quickTimeMovie
        case .video: return .mpeg4Movie
        }
    }
    public var byteLimit: UInt64 {
        if case .video = self { return ExpectedKind.video.byteLimit }
        return ExpectedKind.image.byteLimit
    }
}

public struct ImportSnapshot: Sendable, Equatable {
    public let url: URL
    public let originalName: String
    public let canonicalSourcePath: String
}

public struct InspectedFile: Sendable, Equatable {
    public let url: URL
    public let name: String
    public let contentKind: ContentKind
}

public enum ImportInspector {
    /// Call on the reader queue before its coordinated read returns, never on the UI thread.
    public static func snapshot(
        _ source: URL, receptionFolder: URL, inspectionFolder: URL
    ) -> Result<ImportSnapshot, ImportRejection> {
        guard source.isFileURL, let info = ImportFileSystem.info(source), info.st_mode & S_IFMT == S_IFREG,
              ImportFileSystem.isDirectory(receptionFolder), ImportFileSystem.isDirectory(inspectionFolder),
              let parent = ImportFileSystem.canonicalPath(source.deletingLastPathComponent()),
              let reception = ImportFileSystem.canonicalPath(receptionFolder), parent == reception,
              let inspection = ImportFileSystem.canonicalPath(inspectionFolder), inspection != reception,
              let canonical = ImportFileSystem.canonicalPath(source),
              (try? source.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) != true else {
            return .failure(.notRegularFile)
        }
        guard info.st_size <= Int64(ExpectedKind.video.byteLimit) else {
            // Choose the rejection limit from the header without cloning an unbounded file.
            if let image = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               let identifier = CGImageSourceGetType(image) as String?, let type = UTType(identifier),
               ImportPayloadPolicy.isRasterImage(type) {
                return .failure(.tooLarge(limit: ExpectedKind.image.byteLimit))
            }
            return .failure(.tooLarge(limit: ExpectedKind.video.byteLimit))
        }
        let target = URL(fileURLWithPath: inspection).appendingPathComponent(UUID().uuidString)
        let flags = copyfile_flags_t(COPYFILE_CLONE | COPYFILE_ALL | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
        guard copyfile(source.path, target.path, nil, flags) == 0,
              let copied = ImportFileSystem.info(target), copied.st_mode & S_IFMT == S_IFREG else {
            try? FileManager.default.removeItem(at: target)
            return .failure(.sourceFailed)
        }
        return .success(ImportSnapshot(url: target, originalName: source.lastPathComponent, canonicalSourcePath: canonical))
    }

    /// Inspects only the private snapshot. Does not decode pixels or open a video decoder.
    public static func inspect(
        _ snapshot: ImportSnapshot, prefix: String = "Image", date: Date = Date()
    ) -> Result<InspectedFile, ImportRejection> {
        guard let info = ImportFileSystem.info(snapshot.url), info.st_mode & S_IFMT == S_IFREG else {
            return .failure(.notRegularFile)
        }
        do {
            let file = try FileHandle(forReadingFrom: snapshot.url)
            defer { try? file.close() }
            let header = try file.read(upToCount: 64) ?? Data()
            let kind: ContentKind
            if let image = CGImageSourceCreateWithURL(snapshot.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
               let identifier = CGImageSourceGetType(image) as String?, let type = UTType(identifier) {
                guard ImportPayloadPolicy.isRasterImage(type) else { return .failure(.unsupportedImageFormat) }
                guard CGImageSourceGetCount(image) > 0 else { return .failure(.notImageOrVideo) }
                kind = .image(type)
            } else {
                let text = String(decoding: header, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if text.hasPrefix("%PDF") || text.hasPrefix("%!PS") || text.lowercased().contains("<svg") {
                    return .failure(.unsupportedImageFormat)
                }
                switch videoKind(header: header, size: UInt64(max(0, info.st_size))) {
                case let .success(video): kind = .video(video)
                case let .failure(error): return .failure(error)
                }
            }
            guard UInt64(max(0, info.st_size)) <= kind.byteLimit else { return .failure(.tooLarge(limit: kind.byteLimit)) }
            ensureQuarantine(on: snapshot.url, date: date)
            return .success(InspectedFile(url: snapshot.url,
                name: ImportedFileName.corrected(name: snapshot.originalName, contentType: kind.contentType, prefix: prefix, date: date),
                contentKind: kind))
        } catch { return .failure(.sourceFailed) }
    }

    private static func videoKind(header: Data, size: UInt64) -> Result<MediaKind, ImportRejection> {
        let bytes = Array(header.prefix(64))
        guard bytes.count >= 8 else { return .failure(.notImageOrVideo) }
        func word(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
        let type = word(4..<8)
        let shortSize = bytes[0..<4].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let offset: Int
        let boxSize: UInt64
        if shortSize == 1 {
            guard bytes.count >= 16 else { return .failure(.notImageOrVideo) }
            boxSize = bytes[8..<16].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            offset = 16
        } else { boxSize = shortSize == 0 ? size : shortSize; offset = 8 }
        if type == "ftyp" {
            guard boxSize >= UInt64(offset + 8), boxSize <= size, bytes.count >= offset + 8 else {
                return .failure(.notImageOrVideo)
            }
            let brand = word(offset..<(offset + 4))
            if brand == "qt  " { return .success(.mov) }
            let supported = ["isom", "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9", "mp41", "mp42", "avc1", "M4V ", "dash"]
            if supported.contains(brand) { return .success(.mp4) }
            let end = min(bytes.count, Int(min(boxSize, 64)))
            if end >= offset + 12 {
                for index in stride(from: offset + 8, through: end - 4, by: 4) {
                    if supported.contains(word(index..<(index + 4))) { return .success(.mp4) }
                }
            }
            return .failure(.unsupportedVideoFormat)
        }
        if ["moov", "mdat", "wide", "free", "skip"].contains(type), boxSize >= UInt64(offset), boxSize <= size {
            return .success(.mov)
        }
        if word(0..<4) == "RIFF" || bytes.starts(with: [0x1a, 0x45, 0xdf, 0xa3]) { return .failure(.unsupportedVideoFormat) }
        return .failure(.notImageOrVideo)
    }

    /// Best effort on file systems without quarantine support; never replace an existing mark.
    public static func ensureQuarantine(on url: URL, date: Date = Date()) {
        if let existing = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties,
           !existing.isEmpty { return }
        var values = URLResourceValues()
        values.quarantineProperties = [
            "LSQuarantineAgentName": "Folzio", "LSQuarantineTimeStamp": date,
            "LSQuarantineType": "LSQuarantineTypeOtherDownload",
        ]
        var writable = url
        try? writable.setResourceValues(values)
    }
}
