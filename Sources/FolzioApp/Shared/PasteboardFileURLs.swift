import AppKit

/// Reads file URLs from a pasteboard. Drags inside the app, drags from other apps, and paste all read file URLs the
/// same way, and other URLs and strings are ignored (FR-348).
@MainActor
enum PasteboardFileURLs {
    /// The file URLs on `pasteboard`, or an empty array when it has none.
    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL]
        return (objects ?? []).map { $0 as URL }
    }
}
