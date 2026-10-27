import Foundation

public enum SlideshowAdvance: Equatable, Sendable {
    case target(URL)
    case finish
    case empty
}

/// Pure computation that derives the slideshow candidates, start position, and next target from the latest
/// listing and selection. Does not keep a fixed playlist while running; derives them from `listing.files` on
/// each call.
public struct SlideshowSequence: Sendable {
    public init() {}

    /// Extracts only supported media URLs while preserving display order. Folders, zip files themselves,
    /// directories inside a zip, and parent links are not `kind.isMedia` and are excluded.
    public static func candidates(in files: [MediaFile]) -> [URL] {
        files.compactMap { $0.kind.isMedia ? $0.url : nil }
    }

    /// Start position: the focused media item in the selection, then the first selected media item in display order,
    /// then the first candidate. If the selection contains only non-media items or is empty, uses the first
    /// candidate.
    public static func startTarget(
        in files: [MediaFile],
        selected: Set<URL>,
        focused: URL?
    ) -> URL? {
        let candidates = candidates(in: files)
        guard !candidates.isEmpty else { return nil }

        if let focused, selected.contains(focused), candidates.contains(focused) {
            return focused
        }
        if let firstSelected = candidates.first(where: { selected.contains($0) }) {
            return firstSelected
        }
        return candidates.first
    }

    /// Returns the item after the latest focus when it is still a candidate (wrapping to the first at the end), or
    /// the first candidate when it is not. Returns nil when there are no candidates.
    public static func nextTarget(in files: [MediaFile], focused: URL?) -> URL? {
        if case .target(let url) = advance(in: files, focused: focused, repeats: true) {
            return url
        }
        return nil
    }

    /// Determines the next target from the latest listing. When not repeating, finishes at the end instead of
    /// advancing. When the selection disappears, continues from the first candidate regardless of the repeat setting.
    public static func advance(in files: [MediaFile], focused: URL?, repeats: Bool) -> SlideshowAdvance {
        let candidates = candidates(in: files)
        guard let first = candidates.first else { return .empty }

        guard let focused, let index = candidates.firstIndex(of: focused) else {
            return .target(first)
        }
        if index + 1 < candidates.count {
            return .target(candidates[index + 1])
        }
        return repeats ? .target(first) : .finish
    }

    public static func hasMedia(in files: [MediaFile]) -> Bool {
        files.contains { $0.kind.isMedia }
    }
}
