import Foundation

/// Original and new locations of a renamed folder. Rebases URLs under the old location to the new location
/// (research.md R61).
public struct RenamedFolder: Sendable, Equatable {
    public let from: URL
    public let to: URL
    /// Precomputes paths to avoid normalizing on every comparison (10,000 rebases; R67). Does not use
    /// `standardizedFileURL` because it removes `/private` depending on whether the location exists, which makes the
    /// form differ between the old location (which no longer exists) and the new location.
    private let fromBytes: [UInt8]
    private let toPath: String

    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
        self.fromBytes = Array(Self.normalized(from.path).utf8)
        self.toPath = Self.normalized(to.path)
    }

    /// Rebases a URL for `from` itself or a URL under it (`file` URLs and zip entries) to the new location.
    /// Returns nil when there is no relationship. Does not rebase `..` (`mvparent`) for regular folders because it
    /// is recreated from the displayed folder.
    public func rebase(_ url: URL) -> URL? {
        if url.isFileURL {
            return rebaseFileURL(url)
        }
        guard let parsed = ArchiveURL.parse(url),
              let archive = rebaseFileURL(parsed.archive) else {
            return nil
        }
        if parsed.isParentLink {
            return ArchiveURL.parentLink(of: ArchiveLocation(archive: archive, directory: parsed.path))
        }
        return ArchiveURL.entry(archive: archive, path: parsed.path)
    }

    public func rebaseOrSelf(_ url: URL) -> URL {
        rebase(url) ?? url
    }

    /// Reverses the rebase (from the new location back to the original). Used to return search records to the
    /// location before the rename (R2).
    public var reversed: RenamedFolder {
        RenamedFolder(from: to, to: from)
    }

    /// Compares through the `/` separator so siblings whose names share a prefix (`Photo` and `Photos`) are not
    /// confused. Because the separator is ASCII `/`, comparing UTF-8 bytes never splits a character (10,000 rebases;
    /// R67).
    private func rebaseFileURL(_ url: URL) -> URL? {
        // URL.path may be a bridged string without contiguous UTF-8 storage, so make it contiguous first.
        var path = Self.normalized(url.path)
        path.makeContiguousUTF8()
        let rest = path.withUTF8 { bytes in
            fromBytes.withUnsafeBufferPointer { prefix in
                Self.remainder(of: bytes, after: prefix)
            }
        }
        guard let remainder = rest else { return nil }
        let newPath = remainder.isEmpty ? toPath : (toPath == "/" ? "" : toPath) + "/" + remainder
        return URL(fileURLWithPath: newPath, isDirectory: url.hasDirectoryPath)
    }

    /// Returns an empty string when `path` equals `prefix`, the remainder after the separator when `path` is under
    /// `prefix`, and nil otherwise.
    private static func remainder(of path: UnsafeBufferPointer<UInt8>, after prefix: UnsafeBufferPointer<UInt8>) -> String? {
        guard let pathBase = path.baseAddress, let prefixBase = prefix.baseAddress,
              path.count >= prefix.count,
              memcmp(pathBase, prefixBase, prefix.count) == 0 else { return nil }
        if path.count == prefix.count { return "" }
        let isRoot = prefix.count == 1 && prefixBase.pointee == UInt8(ascii: "/")
        let start = isRoot ? prefix.count : prefix.count + 1
        guard isRoot || pathBase[prefix.count] == UInt8(ascii: "/") else { return nil }
        return String(decoding: UnsafeBufferPointer(rebasing: path[start...]), as: UTF8.self)
    }

    /// Removes `.` and `..` components. Returns paths that contain neither unchanged (the usual case).
    private static func normalized(_ path: String) -> String {
        var contiguous = path
        contiguous.makeContiguousUTF8()
        let hasDotComponent = contiguous.withUTF8 { bytes -> Bool in
            guard let base = bytes.baseAddress else { return false }
            return memmem(base, bytes.count, "/.", 2) != nil
        }
        guard hasDotComponent else { return contiguous }
        var parts: [Substring] = []
        for component in path.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !parts.isEmpty { parts.removeLast() }
            default:
                parts.append(component)
            }
        }
        return "/" + parts.joined(separator: "/")
    }
}
