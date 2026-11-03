import Testing
import FolzioCore

@Suite("List item icon tone")
struct ListItemIconToneTests {
    @Test("Folders and directories inside a zip are blue (FR-269)", arguments: [ListItemKind.folder, .directory])
    func folderTone(kind: ListItemKind) {
        #expect(kind.iconTone == .folderBlue)
    }

    @Test("Zip files are yellow (FR-270)")
    func archiveTone() {
        #expect(ListItemKind.archive.iconTone == .archiveYellow)
    }

    @Test("The parent row keeps the secondary tone (FR-271)")
    func parentTone() {
        #expect(ListItemKind.parent.iconTone == .secondary)
    }

    @Test("Media rows keep the secondary tone (FR-271)", arguments: MediaKind.allCases)
    func mediaTone(kind: MediaKind) {
        #expect(ListItemKind.media(kind).iconTone == .secondary)
    }
}
