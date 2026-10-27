import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("Folder Search Fixtures")
struct FolderSearchFixtureTests {
    private func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderSearchFixtureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("folderSearch creates the quickstart fixtures")
    func folderSearchLayout() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        try FixtureSets.folderSearch(in: base)

        let fileManager = FileManager.default
        let kyoto = base.appendingPathComponent("folder-search/Kyoto", isDirectory: true)

        func expectDirectory(_ path: String) {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: kyoto.appendingPathComponent(path).path, isDirectory: &isDirectory)
            #expect(exists && isDirectory.boolValue, "Folder is missing: \(path)")
        }
        func expectFile(_ path: String) {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: kyoto.appendingPathComponent(path).path, isDirectory: &isDirectory)
            #expect(exists && !isDirectory.boolValue, "File is missing: \(path)")
        }

        expectFile("2024_Kyoto/IMG_0001.jpg")
        expectDirectory("2024_Kyoto_old")
        expectFile("kyoto_map.png")
        expectFile("kyoto/kyoto_01.jpg")
        expectDirectory("kyoto/kyoto_day2")
        expectFile("kyoto/IMG_0002.jpg")
        expectDirectory(".kyoto")
        expectDirectory("Kyoto.app/Contents")
        expectFile("kyoto.zip")
        expectDirectory("2024.10_trip")
        expectDirectory("photos.jpg")
        expectDirectory("east/kyoto_day1")
        expectDirectory("west/kyoto_day1")
        expectFile("clips/kyoto_clip.mov")
        expectFile("locked_kyoto/secret_kyoto.jpg")

        let link = kyoto.appendingPathComponent("kyoto_link")
        let destination = try fileManager.destinationOfSymbolicLink(atPath: link.path)
        #expect(destination.hasSuffix("/2024_Kyoto"), "Link destination: \(destination)")
        #expect(
            link.resolvingSymlinksInPath().lastPathComponent == "2024_Kyoto",
            "Link does not point to a folder: \(link.resolvingSymlinksInPath().path)"
        )

        #expect(
            fileManager.isReadableFile(atPath: kyoto.appendingPathComponent("locked_kyoto").path),
            "locked_kyoto must be readable immediately after creation"
        )

        let open = base.appendingPathComponent("folder-search/.hidden-parent/search-root/kyoto_open", isDirectory: true)
        var isDirectory: ObjCBool = false
        let openExists = fileManager.fileExists(atPath: open.path, isDirectory: &isDirectory)
        #expect(openExists && isDirectory.boolValue)
        #expect(fileManager.fileExists(atPath: open.appendingPathComponent("IMG_0003.jpg").path))
    }

    @Test("folderSearchScale creates the SC-053 hierarchy with default counts and returns the root")
    func folderSearchScaleDefaultCounts() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let root = try FixtureSets.folderSearchScale(in: base)

        #expect(root.lastPathComponent == "kyoto_root")
        #expect(
            root.standardizedFileURL.path
                == base.appendingPathComponent("folder-search-scale/kyoto_root", isDirectory: true).standardizedFileURL.path
        )

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.filter { $0.hasPrefix("kyoto-folder-") && !$0.hasPrefix("kyoto-folder-000.app") }.count == 50)
        #expect(names.filter { $0.hasPrefix("kyoto_") && $0.hasSuffix(".jpg") }.count == 50)
        #expect(names.filter { $0.hasPrefix("other-") }.count == 50)
        #expect(names.filter { $0.hasPrefix(".kyoto-hidden-") }.count == 5)
        #expect(names.filter { $0.hasPrefix("kyoto-package-") && $0.hasSuffix(".app") }.count == 5)
        #expect(names.filter { $0.hasPrefix("kyoto-link-") }.count == 5)
        #expect(names.filter { $0.hasPrefix("kyoto-0") && $0.hasSuffix(".zip") }.count == 5)
    }

    @Test("folderSearchScale accepts custom counts")
    func folderSearchScaleCustomCounts() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let root = try FixtureSets.folderSearchScale(
            in: base,
            matchingFolders: 2,
            matchingFiles: 3,
            otherFolders: 4,
            excludedEach: 1
        )

        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.filter { $0.hasPrefix("kyoto-folder-") }.count == 2)
        #expect(names.filter { $0.hasPrefix("kyoto_") && $0.hasSuffix(".jpg") }.count == 3)
        #expect(names.filter { $0.hasPrefix("other-") }.count == 4)
        #expect(names.filter { $0.hasPrefix(".kyoto-hidden-") }.count == 1)
        #expect(names.filter { $0.hasPrefix("kyoto-package-") }.count == 1)
        #expect(names.filter { $0.hasPrefix("kyoto-link-") }.count == 1)
        #expect(names.filter { $0.hasSuffix(".zip") }.count == 1)
    }
}
