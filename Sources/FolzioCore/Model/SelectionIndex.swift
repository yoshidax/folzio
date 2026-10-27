import Foundation

/// Builds row indexes for selected URLs from the listing order.
///
/// A linear search of the whole listing for each selected URL would require about 50 million comparisons for
/// 10,000 rows and 5,000 selections, freezing the UI for tens of seconds. Build the URL-to-index table once and
/// make the work proportional to the number of selections (FR-016, SC-003, SC-016).
public enum SelectionIndex {
    /// When the same URL appears multiple times, uses the first row (the same behavior as `firstIndex(of:)`).
    /// Selected URLs that are not in the listing are ignored.
    public static func indexes(of selected: Set<URL>, in urls: [URL]) -> IndexSet {
        guard !selected.isEmpty, !urls.isEmpty else { return IndexSet() }

        var indexByURL: [URL: Int] = [:]
        indexByURL.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() where indexByURL[url] == nil {
            indexByURL[url] = index
        }

        var indexes = IndexSet()
        for url in selected {
            if let index = indexByURL[url] {
                indexes.insert(index)
            }
        }
        return indexes
    }
}
