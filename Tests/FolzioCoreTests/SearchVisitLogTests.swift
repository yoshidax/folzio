import Foundation
import Testing
@testable import FolzioCore

@Suite("SearchVisitLog")
struct SearchVisitLogTests {
    @Test("Contains only recorded paths")
    func recordsPaths() {
        let log = SearchVisitLog()
        #expect(!log.contains("/a"))
        log.record("/a")
        #expect(log.contains("/a"))
        #expect(!log.contains("/b"))
        #expect(!log.contains("/a/b"))
    }

    @Test("Keeps all records made concurrently from multiple tasks")
    func concurrentRecords() async {
        let log = SearchVisitLog()
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 1_000 {
                group.addTask { log.record("/p/\(index)") }
            }
        }
        for index in 0 ..< 1_000 {
            #expect(log.contains("/p/\(index)"), "Record is missing: \(index)")
        }
    }
}
