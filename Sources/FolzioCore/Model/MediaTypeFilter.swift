import Foundation

public struct MediaTypeFilter: Sendable, Equatable {
    public var imagesOnly: Bool
    public var videosOnly: Bool

    public init(imagesOnly: Bool = false, videosOnly: Bool = false) {
        self.imagesOnly = imagesOnly
        self.videosOnly = videosOnly
    }

    /// Filters only when exactly one side is on. Does not filter when both are off or both are on.
    public var isFiltering: Bool {
        imagesOnly != videosOnly
    }

    public func includes(_ kind: MediaKind) -> Bool {
        guard isFiltering else { return true }
        return imagesOnly ? !kind.isVideo : kind.isVideo
    }

    public func apply(to files: [MediaFile]) -> [MediaFile] {
        guard isFiltering else { return files }
        // Always keeps non-.media rows (zip files, directories, ...) (FR-056).
        return files.filter { file in file.kind.mediaKind.map(includes) ?? true }
    }

    /// Empty state to show when the filtered listing has no items. The presentation layer chooses the text.
    public var emptyState: EmptyState? {
        guard isFiltering else { return nil }
        return imagesOnly ? .imagesOnly : .videosOnly
    }

    public enum EmptyState: Sendable, Equatable {
        case imagesOnly
        case videosOnly
    }
}
