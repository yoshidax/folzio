import Darwin
import Foundation

enum ImportFileSystem {
    static func canonicalPath(_ url: URL) -> String? {
        guard url.isFileURL, let buffer = realpath(url.path, nil) else { return nil }
        defer { free(buffer) }
        return String(cString: buffer)
    }

    static func info(_ url: URL) -> stat? {
        var value = stat()
        return lstat(url.path, &value) == 0 ? value : nil
    }

    static func isDirectory(_ url: URL) -> Bool {
        guard let value = info(url) else { return false }
        return value.st_mode & S_IFMT == S_IFDIR
    }

    static func volumeUUID(_ url: URL) -> String? {
        try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
    }
}
