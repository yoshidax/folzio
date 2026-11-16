import Foundation
import Testing
@testable import FolzioCore

@Suite("ConfirmationPolicy")
struct ConfirmationPolicyTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let kind: FileOperation.Kind
        let origin: OperationOrigin
        let target: ConfirmationTarget

        var testDescription: String { "\(kind) / \(origin) → \(target)" }
    }

    static let cases: [Case] = [
        Case(kind: .copy, origin: .fileList, target: .copy),
        Case(kind: .copy, origin: .tree, target: .copy),
        Case(kind: .trash, origin: .fileList, target: .trash),
        Case(kind: .trash, origin: .tree, target: .trash),
        Case(kind: .move, origin: .fileList, target: .move),
        Case(kind: .move, origin: .tree, target: .move),
        Case(kind: .rename(newName: "b"), origin: .fileList, target: .rename),
        Case(kind: .rename(newName: "b"), origin: .tree, target: .rename),
    ]

    @Test("Each operation follows its own setting; Trash from the tree follows the Trash setting (FR-024, FR-079)",
          arguments: cases)
    func target(_ testCase: Case) {
        #expect(ConfirmationPolicy.target(for: testCase.kind, origin: testCase.origin) == testCase.target)
    }
}
