import Testing
@testable import FolzioCore

@Suite("Import producer completion")
struct ImportPromiseCompletionTests {
    @Test func waitsForEveryFileAndReceiver() {
        var completion = ImportPromiseCompletion()
        #expect(completion.completedReceivers(expectedCounts: [2, 1]).isEmpty)
        let first = completion.record(receiver: 0, identity: "a", failedWithoutNames: false)
        let duplicate = completion.record(receiver: 0, identity: "a", failedWithoutNames: false)
        #expect(first)
        #expect(!duplicate)
        #expect(completion.completedReceivers(expectedCounts: [2, 1]).isEmpty)
        completion.record(receiver: 0, identity: "b", failedWithoutNames: false)
        #expect(completion.completedReceivers(expectedCounts: [2, 1]) == [0])
        completion.record(receiver: 1, identity: "a", failedWithoutNames: false)
        #expect(completion.completedReceivers(expectedCounts: [2, 1]) == [0, 1])
    }

    @Test func unknownNamesWaitUnlessTheProducerFails() {
        var completion = ImportPromiseCompletion()
        completion.record(receiver: 0, identity: "a", failedWithoutNames: false)
        #expect(completion.completedReceivers(expectedCounts: [0]).isEmpty)
        completion.record(receiver: 0, identity: nil, failedWithoutNames: true)
        #expect(completion.completedReceivers(expectedCounts: [0]) == [0])
        #expect(completion.completedReceivers(expectedCounts: [3]).isEmpty)
    }
}
