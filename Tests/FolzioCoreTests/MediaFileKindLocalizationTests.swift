import Foundation
import FolzioCore
import Testing

@Suite("Kind Names After Changing the Display Language")
struct MediaFileKindLocalizationTests {
    @Test("Changes only app-managed kind names and preserves OS kind names")
    func changesOnlyApplicationNames() {
        let names = KindNames(folder: "フォルダ", zipArchive: "ZIP アーカイブ")
        let folder = MediaFile(url: URL(fileURLWithPath: "/folder"), name: "folder", kind: .folder,
                               typeDescription: "Folder", creationDate: nil, fileSize: 0,
                               kindNameSource: .folder)
        let zipFallback = MediaFile(url: URL(fileURLWithPath: "/fallback.zip"), name: "fallback.zip", kind: .archive,
                                    typeDescription: "ZIP archive", creationDate: nil, fileSize: 0,
                                    kindNameSource: .zipArchive)
        let zipSystem = MediaFile(url: URL(fileURLWithPath: "/system.zip"), name: "system.zip", kind: .archive,
                                  typeDescription: "OS ZIP", creationDate: nil, fileSize: 0)
        #expect(folder.localizedKindName(using: names).typeDescription == "フォルダ")
        #expect(zipFallback.localizedKindName(using: names).typeDescription == "ZIP アーカイブ")
        #expect(zipSystem.localizedKindName(using: names).typeDescription == "OS ZIP")
        #expect(folder.localizedKindName(using: names).url == folder.url)
    }
}
