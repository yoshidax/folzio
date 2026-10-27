import Foundation
import Testing
@testable import FolzioCore

@Suite("ConfirmationPolicy")
struct ConfirmationPolicyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let kind: FileOperation.Kind
        let origin: OperationOrigin
        let isSkippable: Bool

        var testDescription: String { "\(kind) / \(origin) → \(isSkippable)" }
    }

    static let cases: [Case] = [
        Case(kind: .copy, origin: .fileList, isSkippable: true),
        Case(kind: .copy, origin: .tree, isSkippable: true),
        Case(kind: .trash, origin: .fileList, isSkippable: true),
        Case(kind: .trash, origin: .tree, isSkippable: false),
        Case(kind: .move, origin: .fileList, isSkippable: false),
        Case(kind: .move, origin: .tree, isSkippable: false),
        Case(kind: .rename(newName: "b"), origin: .fileList, isSkippable: false),
        Case(kind: .rename(newName: "b"), origin: .tree, isSkippable: false),
    ]

    @Test("Only copy and Trash from the file list can skip confirmation (FR-024, FR-079)", arguments: cases)
    func isSkippable(_ testCase: Case) {
        #expect(ConfirmationPolicy.isSkippable(testCase.kind, origin: testCase.origin) == testCase.isSkippable)
    }
}
