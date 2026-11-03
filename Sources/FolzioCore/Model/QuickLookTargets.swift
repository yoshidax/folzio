import Foundation

/// Chooses the files handed to the Quick Look panel when Space is pressed in the file list
/// (FR-247, FR-249, FR-250, FR-254; data-model.md).
public enum QuickLookTargets {
    /// Returns the URLs of the selected media files in listing order.
    ///
    /// Folders, zip files, and `..` rows are excluded. Nothing is returned while browsing a zip, or for URLs that
    /// point inside a zip, because they have no real file (A-150). URLs missing from `files` are ignored.
    ///
    /// - Parameters:
    ///   - files: The rows of the displayed listing, including search results, in display order.
    ///   - selected: The selected row URLs.
    ///   - isBrowsingArchive: Whether the listing shows the inside of a zip.
    public static func urls(files: [MediaFile], selected: Set<URL>, isBrowsingArchive: Bool) -> [URL] {
        guard !isBrowsingArchive, !selected.isEmpty else { return [] }
        return files.compactMap { file in
            guard selected.contains(file.url),
                  file.kind.opensInDefaultApp(isBrowsingArchive: false),
                  ArchiveURL.parse(file.url) == nil else {
                return nil
            }
            return file.url
        }
    }
}
