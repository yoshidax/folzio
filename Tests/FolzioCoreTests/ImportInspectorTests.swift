import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import FolzioCore

@Suite("Import inspector")
struct ImportInspectorTests {
    @Test("Inspects raster snapshots regardless of misleading extensions", arguments: [UTType.png, .jpeg, .gif, .tiff])
    func raster(_ type: UTType) throws {
        try ImportTestFiles.directory { root in
            let receive = root.appendingPathComponent("receive")
            let checked = root.appendingPathComponent("checked")
            try FileManager.default.createDirectory(at: receive, withIntermediateDirectories: false)
            try FileManager.default.createDirectory(at: checked, withIntermediateDirectories: false)
            let source = receive.appendingPathComponent("cat.svg")
            try ImportTestFiles.image(type).write(to: source)
            let snapshot = try ImportInspector.snapshot(source, receptionFolder: receive, inspectionFolder: checked).get()
            try Data("changed source".utf8).write(to: source)
            let result = try ImportInspector.inspect(snapshot).get()
            #expect(result.contentKind == .image(type))
            #expect(result.name == "cat.\((type == .jpeg ? "jpg" : type.preferredFilenameExtension!))")
            #expect(result.url.deletingLastPathComponent().resolvingSymlinksInPath() == checked.resolvingSymlinksInPath())
        }
    }

    @Test func rejectsLinksAndDirectories() throws {
        try ImportTestFiles.directory { root in
            let checked = root.appendingPathComponent("checked")
            try FileManager.default.createDirectory(at: checked, withIntermediateDirectories: false)
            let file = root.appendingPathComponent("real.png")
            try ImportTestFiles.image().write(to: file)
            let link = root.appendingPathComponent("link.png")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            #expect(ImportInspector.snapshot(link, receptionFolder: root, inspectionFolder: checked) == .failure(.notRegularFile))
            let alias = root.appendingPathComponent("alias.png")
            let bookmark = try file.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
            try URL.writeBookmarkData(bookmark, to: alias)
            #expect(ImportInspector.snapshot(alias, receptionFolder: root, inspectionFolder: checked) == .failure(.notRegularFile))
            #expect(ImportInspector.snapshot(checked, receptionFolder: root, inspectionFolder: checked) == .failure(.notRegularFile))
            let package = root.appendingPathComponent("bad.app")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
            #expect(ImportInspector.snapshot(package, receptionFolder: root, inspectionFolder: checked) == .failure(.notRegularFile))
            #expect(ImportInspector.snapshot(file, receptionFolder: checked, inspectionFolder: checked) == .failure(.notRegularFile))
        }
    }

    @Test func contentsAndLimits() throws {
        try ImportTestFiles.directory { root in
            let checked = root.appendingPathComponent("checked")
            try FileManager.default.createDirectory(at: checked, withIntermediateDirectories: false)
            func inspect(_ bytes: Data, size: Int64? = nil) throws -> Result<InspectedFile, ImportRejection> {
                let file = root.appendingPathComponent("input.png")
                if let size { try ImportTestFiles.sparse(file, header: bytes, size: size) }
                else { try bytes.write(to: file) }
                return ImportInspector.snapshot(file, receptionFolder: root, inspectionFolder: checked).flatMap { ImportInspector.inspect($0) }
            }
            for text in ["<svg xmlns='http://www.w3.org/2000/svg'></svg>", "%PDF-1.7", "%!PS-Adobe-3.0"] {
                #expect(try inspect(Data(text.utf8)) == .failure(.unsupportedImageFormat))
            }
            #expect(try inspect(Data("#!/bin/sh\nexit 0".utf8)) == .failure(.notImageOrVideo))
            for (brand, kind) in [("qt  ", MediaKind.mov), ("isom", .mp4), ("mp42", .mp4)] {
                let bytes = Data([0, 0, 0, 16] + Array("ftyp\(brand)".utf8) + [0, 0, 0, 0])
                #expect(try inspect(bytes).get().contentKind == .video(kind))
            }
            #expect(try inspect(Data([0, 0, 0, 8] + Array("moov".utf8))).get().contentKind == .video(.mov))
            #expect(try inspect(Data("RIFF0000AVI ".utf8)) == .failure(.unsupportedVideoFormat))
            #expect(try inspect(ImportTestFiles.image(), size: 256_000_001) == .failure(.tooLarge(limit: 256_000_000)))
            #expect(try inspect(ImportTestFiles.image(), size: 5_000_000_000) == .failure(.tooLarge(limit: 256_000_000)))
            let video = Data([0, 0, 0, 16] + Array("ftypmp42".utf8) + [0, 0, 0, 0])
            #expect(try inspect(video, size: 4_000_000_001) == .failure(.tooLarge(limit: 4_000_000_000)))
        }
    }

    @Test func preservesQuarantineAndAddsMinimalMark() throws {
        try ImportTestFiles.directory { root in
            let source = root.appendingPathComponent("source.png")
            let checked = root.appendingPathComponent("checked")
            try FileManager.default.createDirectory(at: checked, withIntermediateDirectories: false)
            try ImportTestFiles.image().write(to: source)
            ImportInspector.ensureQuarantine(on: source, date: Date(timeIntervalSince1970: 1))
            let original = try #require(source.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
            #expect(original["LSQuarantineAgentName"] as? String == "Folzio")
            #expect(original["LSQuarantineDataURL"] == nil)
            #expect(original["LSQuarantineOriginURL"] == nil)
            let snapshot = try ImportInspector.snapshot(source, receptionFolder: root, inspectionFolder: checked).get()
            ImportInspector.ensureQuarantine(on: snapshot.url, date: Date(timeIntervalSince1970: 900))
            let preserved = try #require(snapshot.url.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties)
            #expect(NSDictionary(dictionary: original).isEqual(to: preserved))
        }
    }
}
