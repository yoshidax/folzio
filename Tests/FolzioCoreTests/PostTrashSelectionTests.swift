import Foundation
import Testing
@testable import FolzioCore

@Suite("Post-trash selection")
struct PostTrashSelectionTests {
    private func urls(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/trash-selection/" + $0) }
    }

    private func makeSnapshot(orderedURLs: [URL], targets: Set<URL>, selection: SelectionState) -> PostTrashSelection? {
        PostTrashSelection(orderedFiles: files(orderedURLs), targets: targets, selection: selection,
            navigationGeneration: 0, intentGeneration: 0)
    }

    private func files(_ urls: [URL]) -> [MediaFile] {
        urls.map { MediaFile(url: $0, name: $0.lastPathComponent, kind: .media(.mov),
            typeDescription: "Movie", creationDate: nil, fileSize: 0) }
    }

    @Test("Selects the first surviving row after the bottommost target", arguments: [[1], [1, 2], [1, 3], [1, 4]])
    func nextRow(_ indexes: [Int]) throws {
        let rows = urls(["a", "b", "c", "d", "e"])
        let targets = Set(indexes.map { rows[$0] })
        let snapshot = try #require(makeSnapshot(orderedURLs: rows, targets: targets,
            selection: SelectionState(selected: targets, focused: rows[indexes.last!])))
        let result = try #require(snapshot.selection(afterRemoving: targets, remainingURLs: rows.filter { !targets.contains($0) }))
        let next = rows.indices.first { $0 > indexes.max()! }
        #expect(result.selected == Set(next.map { [rows[$0]] } ?? []))
        #expect(result.focused == next.map { rows[$0] })
    }

    @Test("Keeps failed selections and focuses the last survivor only when needed", arguments: [true, false])
    func partialFailure(_ removedFocus: Bool) throws {
        let rows = urls(["a", "b", "c", "d", "e"])
        let snapshot = try #require(makeSnapshot(orderedURLs: rows, targets: [rows[1], rows[3]],
            selection: SelectionState(selected: [rows[1], rows[3]], focused: removedFocus ? rows[1] : rows[3])))
        let result = try #require(snapshot.selection(afterRemoving: [rows[1]], remainingURLs: [rows[0], rows[2], rows[3], rows[4]]))
        #expect(result.selected == [rows[3]])
        #expect(result.focused == rows[3])
    }

    @Test("No success, empty targets, or unselected targets do not produce a replacement")
    func noOperation() throws {
        let rows = urls(["a", "b"])
        let selected = SelectionState(selected: [rows[0]], focused: rows[0])
        #expect(makeSnapshot(orderedURLs: rows, targets: [], selection: selected) == nil)
        #expect(makeSnapshot(orderedURLs: rows, targets: [rows[1]], selection: selected) == nil)
        let snapshot = try #require(makeSnapshot(orderedURLs: rows, targets: [rows[0]], selection: selected))
        #expect(snapshot.selection(afterRemoving: [], remainingURLs: rows) == nil)
    }

    @Test("Skips vanished rows and newly arrived rows, retaining the original order")
    func originalOrder() throws {
        let rows = urls(["a", "b", "c", "d", "new"])
        let snapshot = try #require(makeSnapshot(orderedURLs: Array(rows.prefix(4)), targets: [rows[1]],
            selection: SelectionState(selected: [rows[1]], focused: rows[1])))
        let result = try #require(snapshot.selection(afterRemoving: [rows[1]], remainingURLs: [rows[4], rows[3], rows[0]]))
        #expect(result.selected == [rows[3]])
        let empty = try #require(snapshot.selection(afterRemoving: [rows[1]], remainingURLs: [rows[4], rows[0]]))
        #expect(empty.selected.isEmpty)
        #expect(empty.focused == nil)
    }

    @Test("A selected parent link does not block the successor or retain a selection at the end",
          arguments: [false, true], 0...2)
    func parentLinkIsNotASurvivor(_ hasNext: Bool, _ successCount: Int) throws {
        let parent = ParentLink.url(for: URL(fileURLWithPath: "/trash-selection"))
        let targets = urls(["a", "b"])
        let next = urls(["c"])[0]
        let rows = [parent] + targets + (hasNext ? [next] : [])
        let snapshot = try #require(makeSnapshot(orderedURLs: rows, targets: Set(targets),
            selection: SelectionState(selected: Set([parent] + targets), focused: parent)))
        let removed = Set(targets.prefix(successCount))
        let result = snapshot.selection(afterRemoving: removed, remainingURLs: rows.filter { !removed.contains($0) })
        if successCount == 0 {
            #expect(result == nil)
        } else {
            let expected = successCount == 1 ? targets[1] : (hasNext ? next : nil)
            #expect(result?.selected == Set(expected.map { [$0] } ?? []))
            #expect(result?.focused == expected)
        }
    }

    @Test("Deleted descendants cannot become successors, and deleting all rows leaves an empty selection")
    func descendantsAndEmptyList() throws {
        let rows = urls(["a", "b/child", "b2", "c"])
        let snapshot = try #require(makeSnapshot(orderedURLs: rows, targets: [rows[0]],
            selection: SelectionState(selected: [rows[0]], focused: rows[0])))
        let result = try #require(snapshot.selection(afterRemoving: [rows[0], urls(["b"])[0]],
            remainingURLs: Array(rows.dropFirst())))
        #expect(result.focused == rows[2])
        let all = try #require(makeSnapshot(orderedURLs: rows, targets: Set(rows),
            selection: SelectionState(selected: Set(rows), focused: rows.last)))
        let empty = try #require(all.selection(afterRemoving: Set(rows), remainingURLs: []))
        #expect(empty.selected.isEmpty)
        #expect(empty.focused == nil)
    }

    @Test("Ten thousand rows and five thousand targets use the same selection rules")
    func largeSelection() throws {
        let rows = urls((0..<10_000).map(String.init))
        let targets = Set(rows.prefix(5_000))
        let originalFiles = files(rows)
        let start = ContinuousClock.now
        let snapshot = try #require(PostTrashSelection(orderedFiles: originalFiles, targets: targets,
            selection: SelectionState(selected: targets, focused: rows[4_999]),
            navigationGeneration: 0, intentGeneration: 0))
        let result = try #require(snapshot.selection(afterRemoving: targets, remainingURLs: Array(rows.suffix(5_000))))
        let elapsed = start.duration(to: .now)
        print("PostTrashSelection 10000 rows / 5000 selected: \(elapsed)")
        #expect(result.selected == [rows[5_000]])
        #expect(result.focused == rows[5_000])
    }
}
