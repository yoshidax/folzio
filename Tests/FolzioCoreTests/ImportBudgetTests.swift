import Testing
@testable import FolzioCore

@Suite("Import budget")
struct ImportBudgetTests {
    @Test func limits() {
        let budget = ImportBudget(kinds: [.image, .unknown, .video])
        #expect(budget.byteLimit == 4_512_000_000)
        #expect(!budget.exceedsCapacity(4_512_000_000))
        #expect(budget.exceedsCapacity(4_512_000_001))
        #expect(budget.expiredIndices(elapsed: 59.999) == [])
        #expect(budget.expiredIndices(elapsed: 60) == [0, 1])
        #expect(budget.expiredIndices(elapsed: 599.999, completed: [0, 1]) == [])
        #expect(budget.expiredIndices(elapsed: 600, completed: [0, 1]) == [2])
        #expect(budget.expiredIndices(elapsed: 600, completed: [0, 1, 2]) == [])
    }
}
