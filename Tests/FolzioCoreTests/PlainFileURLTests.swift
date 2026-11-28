import Foundation
import Testing
@testable import FolzioCore

@Suite("PlainFileURL")
struct PlainFileURLTests {
    @Test("A rebuilt URL equals the enumerated one, keeps its bytes and directory flag, and hashes the same (TAK-129)")
    func rebuiltURLMatchesEnumeratedURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlainFileURLTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Names that differ between composed and decomposed Unicode forms, and a plain ASCII name.
        let folder = root.appendingPathComponent("フォルダ", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["写真_ダ.jpg", "plain.png"] {
            FileManager.default.createFile(atPath: folder.appendingPathComponent(name).path, contents: Data())
        }

        var enumerated: [URL] = []
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        while let url = enumerator.nextObject() as? URL {
            enumerated.append(url)
        }
        enumerated += try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        #expect(enumerated.count == 5)

        for url in enumerated {
            let plain = PlainFileURL.make(url)
            #expect(plain == url, "\(url.lastPathComponent)")
            #expect(plain.absoluteString == url.absoluteString, "\(url.lastPathComponent)")
            #expect(plain.hasDirectoryPath == url.hasDirectoryPath, "\(url.lastPathComponent)")
            #expect(plain.hashValue == url.hashValue, "\(url.lastPathComponent)")
            #expect(Set([url]).contains(plain))
        }
    }
}
