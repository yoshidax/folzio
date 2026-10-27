import Foundation
import Testing
@testable import FolzioCore

@Suite("SelectionIndex")
struct SelectionIndexTests {
    private func directory(_ index: Int) -> URL {
        URL(fileURLWithPath: "/selection/\(index)", isDirectory: true)
    }

    @Test("Returns an empty IndexSet for an empty selection or listing")
    func emptyInputs() {
        #expect(SelectionIndex.indexes(of: [], in: []) == IndexSet())
        #expect(SelectionIndex.indexes(of: [directory(0)], in: []) == IndexSet())
        #expect(SelectionIndex.indexes(of: [], in: [directory(0)]) == IndexSet())
    }

    @Test("Returns row indexes for selected URLs and ignores URLs not in the listing")
    func mapsSelectedURLs() {
        let urls = (0..<6).map(directory)
        let selected: Set<URL> = [urls[0], urls[2], urls[5], directory(99)]
        #expect(SelectionIndex.indexes(of: selected, in: urls) == IndexSet([0, 2, 5]))
    }

    @Test("Uses the first row when the listing contains duplicate URLs")
    func duplicateURLsUseFirstRow() {
        let first = directory(0)
        let second = directory(1)
        let urls = [first, second, first, second]
        #expect(SelectionIndex.indexes(of: [first, second], in: urls) == IndexSet([0, 1]))
    }
}
