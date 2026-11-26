import CoreFoundation
import Foundation

/// One file or folder on the clipboard: the string for `public.file-url` and the file name for the plain text type.
/// Copies in Finder put a file reference URL (`file:///.file/id=...`) and the file name, so pasting still finds the
/// item after it is moved or renamed on the same volume (FR-413, A-248).
public struct ClipboardFileEntry: Sendable, Equatable {
    /// A file reference URL, or a file path URL when no reference could be made (EC-282).
    public let url: String
    /// The file name, or nil when the clipboard item has none.
    public let name: String?

    public init(url: String, name: String?) {
        self.url = url
        self.name = name
    }
}

/// Where a clipboard item is now.
public enum ClipboardFileResolution: Sendable, Equatable {
    /// The current location as a file path URL.
    case found(URL)
    /// The reference no longer resolves (moved to another volume or deleted). `name` is shown in the failure (EC-283).
    case missing(name: String)
}

/// Makes and resolves the file references that copy and paste put on the clipboard (FR-413, FR-414).
/// Both functions query the file system, so call them off the UI thread.
///
/// Works with `CFURL` and strings only. Converting a file reference URL to Swift's `URL` may turn it into a path URL,
/// which would lose the reference (research.md R2).
public enum ClipboardFileReferences {
    /// Entries for `urls` in the same order. An item whose reference cannot be made (for example, one that no longer
    /// exists) keeps its path URL (EC-282).
    public static func entries(for urls: [URL]) -> [ClipboardFileEntry] {
        urls.map { url in
            let name = url.lastPathComponent
            guard url.isFileURL,
                  let reference = CFURLCreateFileReferenceURL(nil, url as CFURL, nil)?.takeRetainedValue() else {
                return ClipboardFileEntry(url: url.absoluteString, name: name)
            }
            return ClipboardFileEntry(url: CFURLGetString(reference) as String, name: name)
        }
    }

    /// The current location of each entry, in the same order. A file path URL resolves to its own path, as before this
    /// change (EC-285). A file reference URL resolves to wherever the item is now, including the Trash (FR-414).
    public static func resolve(_ entries: [ClipboardFileEntry]) -> [ClipboardFileResolution] {
        entries.map(resolve)
    }

    private static func resolve(_ entry: ClipboardFileEntry) -> ClipboardFileResolution {
        let missing = ClipboardFileResolution.missing(name: entry.name ?? entry.url)
        guard let url = CFURLCreateWithString(nil, entry.url as CFString, nil) else { return missing }
        guard CFURLIsFileReferenceURL(url) else {
            guard let pathURL = URL(string: entry.url), pathURL.isFileURL else { return missing }
            return .found(pathURL)
        }
        guard let pathURL = CFURLCreateFilePathURL(nil, url, nil)?.takeRetainedValue() else { return missing }
        return .found(pathURL as URL)
    }
}
