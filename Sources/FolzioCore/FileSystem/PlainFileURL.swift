import Foundation

/// Rebuilds a file URL from its own bytes (TAK-129, research.md R12).
///
/// URLs returned by `FileManager` enumeration and `contentsOfDirectory(at:)` read their path from the file system
/// representation each time it is needed, so hashing and comparing tens of thousands of them on the main thread is
/// slow (about 14 µs per URL on an M-series Mac). A URL rebuilt from the same bytes compares equal (`==`) to the
/// original and has the same `absoluteString`, but hashes in a fraction of the time. Rebuild once, off the main
/// thread, after reading the resource values the enumeration prefetched into the original URL.
enum PlainFileURL {
    static func make(_ url: URL) -> URL {
        let absolute = url.absoluteURL
        return URL(dataRepresentation: absolute.dataRepresentation, relativeTo: nil, isAbsolute: true) ?? absolute
    }
}
