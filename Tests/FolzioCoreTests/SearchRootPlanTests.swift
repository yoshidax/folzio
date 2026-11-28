import Foundation
import Testing
@testable import FolzioCore

@Suite("SearchRootPlan")
struct SearchRootPlanTests {
    private func folder(_ path: String) -> URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }

    @Test("Hands out roots from the top and then nil")
    func nextInOrder() {
        var plan = SearchRootPlan(pending: [folder("/a"), folder("/b")])
        let first = plan.next()
        let second = plan.next()
        let third = plan.next()
        #expect(first == folder("/a"))
        #expect(second == folder("/b"))
        #expect(third == nil)
        #expect(plan.isEmpty)
    }

    @Test("Rebases a waiting root that is renamed or inside a renamed folder, and ignores unrelated renames")
    func rebasesWaitingRoots() {
        var plan = SearchRootPlan(pending: [folder("/v/b"), folder("/w/c/d"), folder("/x")])
        let itself = plan.rebase(RenamedFolder(from: folder("/v/b"), to: folder("/v/b2")))
        let ancestor = plan.rebase(RenamedFolder(from: folder("/w"), to: folder("/w2")))
        let unrelated = plan.rebase(RenamedFolder(from: folder("/x/inner"), to: folder("/x/inner2")))
        #expect(itself)
        #expect(ancestor)
        #expect(!unrelated)
        #expect(plan.pending.map(\.path) == ["/v/b2", "/w2/c/d", "/x"])
    }

    @Test("Reports whether a folder is a waiting root or inside one")
    func containsWaitingRoot() {
        let plan = SearchRootPlan(pending: [folder("/v/b")])
        #expect(plan.contains(folder("/v/b")))
        #expect(plan.contains(folder("/v/b/inner")))
        #expect(!plan.contains(folder("/v/b2")))
        #expect(!plan.contains(folder("/v")))
    }

    @Test("Removing all roots empties the queue")
    func removeAll() {
        var plan = SearchRootPlan(pending: [folder("/a"), folder("/b")])
        plan.removeAll()
        let next = plan.next()
        #expect(next == nil)
    }
}
