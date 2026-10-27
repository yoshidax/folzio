import Foundation
import Testing
@testable import FolzioCore
import FixtureKit

@Suite("SearchRenameLedger")
struct SearchRenameLedgerTests {
    private func url(_ path: String, isDirectory: Bool = false) -> URL {
        URL(fileURLWithPath: path, isDirectory: isDirectory)
    }

    private func folder(_ path: String) -> MediaFile {
        DirectoryLister.folderRow(at: url(path, isDirectory: true), creationDate: nil, kindNames: FixtureKit.kindNames)
    }

    private func media(_ path: String) -> MediaFile {
        let url = url(path)
        return MediaFile(
            url: url,
            name: url.lastPathComponent,
            kind: .media(.jpeg),
            typeDescription: "JPEG イメージ",
            creationDate: nil,
            fileSize: 0
        )
    }

    private func renamed(_ from: String, _ to: String) -> RenamedFolder {
        RenamedFolder(from: url(from, isDirectory: true), to: url(to, isDirectory: true))
    }

    @Test("Starts empty; addStream returns 0, 1, ...")
    func streamsAreNumbered() {
        var ledger = SearchRenameLedger()
        #expect(ledger.isEmpty)
        #expect(ledger.addStream(visits: SearchVisitLog()) == 0)
        #expect(ledger.addStream(visits: SearchVisitLog()) == 1)
        #expect(ledger.isEmpty)
    }

    @Test("place applies only renames recorded after that enumeration started, in order")
    func placeAppliesOnlyLaterRenames() {
        var ledger = SearchRenameLedger()
        ledger.recordRename(renamed("/r/q", "/r/qq"), visited: true)
        let index = ledger.addStream(visits: SearchVisitLog())
        ledger.recordRename(renamed("/r/a", "/r/b"), visited: true)
        ledger.recordRename(renamed("/r/b", "/r/c"), visited: true)

        #expect(ledger.place(media("/r/a/one.jpg"), fromStream: index)?.url.path == "/r/c/one.jpg")
        #expect(ledger.place(media("/r/z/one.jpg"), fromStream: index)?.url.path == "/r/z/one.jpg")
        // Do not apply renames from before the enumeration started.
        #expect(ledger.place(media("/r/q/one.jpg"), fromStream: index)?.url.path == "/r/q/one.jpg")
    }

    @Test("For a folder row, changes name only when the last URL component changes")
    func folderNameFollowsLastComponent() {
        var ledger = SearchRenameLedger()
        let index = ledger.addStream(visits: SearchVisitLog())
        ledger.recordRename(renamed("/r/F", "/r/zzz"), visited: true)

        let row = ledger.place(folder("/r/F"), fromStream: index)
        #expect(row?.url.path == "/r/zzz")
        #expect(row?.name == "zzz")
        #expect(row?.kind == .folder)

        let child = ledger.place(media("/r/F/g.jpg"), fromStream: index)
        #expect(child?.url.path == "/r/zzz/g.jpg")
        #expect(child?.name == "g.jpg")

        // The name of a folder row whose only ancestor changed stays the same.
        let descendantFolder = ledger.place(folder("/r/F/sub"), fromStream: index)
        #expect(descendantFolder?.url.path == "/r/zzz/sub")
        #expect(descendantFolder?.name == "sub")
    }

    @Test("hasVisited checks records at the location obtained by reversing renames after each enumeration started")
    func hasVisitedReversesRenames() {
        let log = SearchVisitLog()
        var ledger = SearchRenameLedger()
        let index = ledger.addStream(visits: log)
        log.record("/r/F")
        ledger.recordRename(renamed("/r/F", "/r/F1"), visited: true)
        ledger.recordRename(renamed("/r/F1", "/r/F2"), visited: true)

        #expect(ledger.hasVisited(url("/r/F")))
        #expect(ledger.hasVisited(url("/r/F1")))
        #expect(ledger.hasVisited(url("/r/F2")))
        #expect(!ledger.hasVisited(url("/r/other")))
        #expect(index == 0)

        // True when any of multiple enumerations has a record.
        var second = SearchVisitLog()
        second.record("/r/G")
        _ = ledger.addStream(visits: second)
        #expect(ledger.hasVisited(url("/r/G")))
        #expect(ledger.hasVisited(url("/r/F2")))
    }

    @Test("A rename treated as unevaluated drops the old-location row and rebases descendant results")
    func rejudgedRenamesDropTheFolderRow() {
        var ledger = SearchRenameLedger()
        let index = ledger.addStream(visits: SearchVisitLog())
        ledger.recordRename(renamed("/r/F", "/r/F2"), visited: false)

        #expect(ledger.place(folder("/r/F"), fromStream: index) == nil)
        #expect(ledger.place(media("/r/F/g.jpg"), fromStream: index)?.url.path == "/r/F2/g.jpg")

        // When matched, rebase and keep the row at the new location.
        var visited = SearchRenameLedger()
        let visitedIndex = visited.addStream(visits: SearchVisitLog())
        visited.recordRename(renamed("/r/F", "/r/F2"), visited: true)
        let row = visited.place(folder("/r/F"), fromStream: visitedIndex)
        #expect(row?.url.path == "/r/F2")
        #expect(row?.name == "F2")
    }

    @Test("Results from an enumeration started after the rename remain unchanged")
    func laterStreamsAreUnaffected() {
        var ledger = SearchRenameLedger()
        ledger.recordRename(renamed("/r/F", "/r/F2"), visited: false)
        let index = ledger.addStream(visits: SearchVisitLog())

        #expect(ledger.place(folder("/r/F2"), fromStream: index)?.url.path == "/r/F2")
        #expect(ledger.place(media("/r/F2/g.jpg"), fromStream: index)?.url.path == "/r/F2/g.jpg")
    }
}
