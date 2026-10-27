import Foundation
import ImageIO
import Testing
@testable import FixtureKit

@Suite("Search Root Folder Picker Fixtures")
struct SearchFolderPickerFixtureTests {
    @Test("Creates the quickstart normal, hidden, and error cases plus 10,000 direct folders")
    func pickerLayout() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("SearchFolderPickerFixtureTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: base) }

        try FixtureSets.searchFolderPicker(in: base)
        let root = base.appendingPathComponent("search-folder-picker", isDirectory: true)
        func url(_ path: String) -> URL { root.appendingPathComponent(path) }
        func expectDirectory(_ path: String) throws {
            #expect(try url(path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                    "Folder: \(path)")
        }
        func expectJPEG(_ path: String) throws {
            let source = try #require(CGImageSourceCreateWithURL(url(path) as CFURL, nil),
                                      "Image: \(path)")
            #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
            #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
        }

        for path in ["default", "other/child", "日本語", "Space Folder", "Photos", "Photos ",
                     "empty", ".hidden/inside", "flag-hidden/inside", "Picker.app/Contents/inside",
                     "locked", "vanishing", "many-folders"] {
            try expectDirectory(path)
        }
        for path in ["default/default-hit.jpg", "other/other-hit.jpg", "other/child/child-hit.jpg",
                     "日本語/hit.jpg", "Space Folder/hit.jpg", "Photos/plain-hit.jpg",
                     "Photos /space-hit.jpg", "file.jpg"] {
            try expectJPEG(path)
        }

        let names = try fileManager.contentsOfDirectory(atPath: root.path)
        #expect(names.contains("Photos") && names.contains("Photos "))
        let plain = try fileManager.contentsOfDirectory(at: url("Photos"), includingPropertiesForKeys: [.isDirectoryKey])
        let spaced = try fileManager.contentsOfDirectory(at: url("Photos "), includingPropertiesForKeys: [.isDirectoryKey])
        let plainChildren = try plain.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
        let spacedChildren = try spaced.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
        #expect(!plainChildren.isEmpty && !spacedChildren.isEmpty)
        #expect(Set(plainChildren.map(\.lastPathComponent)).isDisjoint(with: spacedChildren.map(\.lastPathComponent)))
        #expect(!fileManager.fileExists(atPath: url("Photos/space-hit.jpg").path))
        #expect(!fileManager.fileExists(atPath: url("Photos /plain-hit.jpg").path))

        #expect(try url(".hidden").resourceValues(forKeys: [.isHiddenKey]).isHidden == true)
        #expect(try url("flag-hidden").resourceValues(forKeys: [.isHiddenKey]).isHidden == true)
        #expect(!url("flag-hidden").lastPathComponent.hasPrefix("."))
        #expect(try url("Picker.app").resourceValues(forKeys: [.isPackageKey]).isPackage == true)
        for (name, target) in [("visible-link", "other"), ("hidden-link", ".hidden/inside"),
                               ("package-link", "Picker.app/Contents/inside")] {
            #expect(try url(name).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
            #expect(url(name).resolvingSymlinksInPath() == url(target).resolvingSymlinksInPath())
        }
        #expect(try fileManager.contentsOfDirectory(atPath: url("empty").path).isEmpty)
        for name in ["locked", "vanishing"] {
            #expect(fileManager.isReadableFile(atPath: url(name).path))
            #expect(try fileManager.contentsOfDirectory(atPath: url(name).path).isEmpty)
            let attributes = try fileManager.attributesOfItem(atPath: url(name).path)
            let permissions = try #require(attributes[.posixPermissions] as? NSNumber).intValue
            #expect(permissions & 0o500 == 0o500)
        }
        #expect(try url("file.jpg").resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true)
        #expect(try url("archive.zip").resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true)
        let archive = try Data(contentsOf: url("archive.zip"))
        #expect(Array(archive.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
        #expect(Array(archive.suffix(22).prefix(4)) == [0x50, 0x4B, 0x05, 0x06])

        let many = try fileManager.contentsOfDirectory(at: url("many-folders"), includingPropertiesForKeys: [.isDirectoryKey])
        #expect(many.count == 10_000)
        var jpegData: Data?
        for folder in many {
            #expect(try folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
            let children = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
            let image = try #require(children.count == 1 ? children.first : nil)
            #expect(image.pathExtension == "jpg")
            #expect(try image.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true)
            let data = try Data(contentsOf: image)
            if let jpegData {
                #expect(data == jpegData)
            } else {
                let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
                let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
                #expect(decoded.width <= 64 && decoded.height <= 64)
                jpegData = data
            }
        }
    }
}
