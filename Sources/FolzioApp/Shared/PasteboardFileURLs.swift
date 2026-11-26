import AppKit
import FolzioCore

/// Reads file URLs from a pasteboard. Drags inside the app, drags from other apps, and paste all read file URLs the
/// same way, and other URLs and strings are ignored (FR-348).
@MainActor
enum PasteboardFileURLs {
    /// Puts each entry on `pasteboard` as its own item with the file URL and the file name, as Finder does (FR-413,
    /// A-248). Writes nothing and returns false when the pasteboard changed after `changeCount` was read, so a later
    /// copy, in this app or another, is kept (EC-281).
    @discardableResult
    static func write(_ entries: [ClipboardFileEntry], to pasteboard: NSPasteboard, ifChangeCount changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount, !entries.isEmpty else { return false }
        let items = entries.map { entry in
            let item = NSPasteboardItem()
            item.setString(entry.url, forType: .fileURL)
            if let name = entry.name {
                item.setString(name, forType: .string)
            }
            return item
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
        return true
    }

    /// Copies `urls` to `pasteboard` as file references. Makes the references off the UI thread, then writes them
    /// only if the pasteboard has not changed meanwhile (FR-413, EC-281).
    static func copy(_ urls: [URL], to pasteboard: NSPasteboard) async {
        guard !urls.isEmpty else { return }
        let changeCount = pasteboard.changeCount
        let entries = await Task.detached(priority: .userInitiated) {
            ClipboardFileReferences.entries(for: urls)
        }.value
        write(entries, to: pasteboard, ifChangeCount: changeCount)
    }

    /// The file URL string and the file name of each item, kept as strings so file references are not turned into
    /// path URLs on the UI thread (research.md R2). Items without a file URL are skipped. Read only when the user
    /// pastes (FR-354).
    static func entries(in pasteboard: NSPasteboard) -> [ClipboardFileEntry] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            guard let url = item.string(forType: .fileURL),
                  url.lowercased().hasPrefix("file:") else { return nil }
            return ClipboardFileEntry(url: url, name: item.string(forType: .string))
        }
    }

    /// The file URLs on `pasteboard`, or an empty array when it has none.
    static func fileURLs(in pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL]
        return (objects ?? []).map { $0 as URL }
    }
}
