import Foundation

/// Whether zip file rows appear in the file list and how the setting is applied to a listing
/// (FR-095, 097; research.md R46).
///
/// Applied in exactly one place, `BrowserModel.rebuildListing()`, after the media type filter (`MediaTypeFilter`).
/// This value type is not persisted; `ViewSettings.showsZipFiles` owns persistence.
public struct ZipFileVisibility: Sendable, Equatable {
    public var showsZipFiles: Bool

    public init(showsZipFiles: Bool = false) {
        self.showsZipFiles = showsZipFiles
    }

    /// Returns the input unchanged when `showsZipFiles` is true; otherwise removes only `kind == .archive` rows.
    /// Preserves order and keeps media, folders, directories inside a zip, and `..`.
    public func apply(to files: [MediaFile]) -> [MediaFile] {
        guard !showsZipFiles else { return files }
        return files.filter { $0.kind != .archive }
    }
}
