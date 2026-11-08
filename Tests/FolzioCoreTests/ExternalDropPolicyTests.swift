import Foundation
import Testing
@testable import FolzioCore

@Suite("External drop policy")
struct ExternalDropPolicyTests {
    /// The preferred operation for every combination of modifiers and volume, with both operations allowed (FR-346).
    /// The same tuple form as `PreviewDoubleClickTests`.
    @Test("chooses the operation like Finder", arguments: [
        // (option, command, allOnSameVolume, expected)
        (false, false, true, ExternalDropPolicy.Operation.move),
        (false, false, false, ExternalDropPolicy.Operation.copy),
        (true, false, true, ExternalDropPolicy.Operation.copy),
        (true, false, false, ExternalDropPolicy.Operation.copy),
        (false, true, true, ExternalDropPolicy.Operation.move),
        (false, true, false, ExternalDropPolicy.Operation.move),
        // Option wins when both are held; the system decides what remains allowed.
        (true, true, true, ExternalDropPolicy.Operation.copy),
        (true, true, false, ExternalDropPolicy.Operation.copy),
    ])
    func preferredOperation(
        option: Bool,
        command: Bool,
        allOnSameVolume: Bool,
        expected: ExternalDropPolicy.Operation
    ) {
        let operation = ExternalDropPolicy.operation(
            option: option, command: command, allOnSameVolume: allOnSameVolume, allowsMove: true, allowsCopy: true
        )
        #expect(operation == expected)
    }

    @Test("switches to the other operation when the drag source does not allow the preferred one (EC-238)")
    func fallsBackToTheAllowedOperation() {
        // Without modifiers on the same volume the preference is move; the source only allows copy.
        #expect(ExternalDropPolicy.operation(
            option: false, command: false, allOnSameVolume: true, allowsMove: false, allowsCopy: true
        ) == .copy)
        // On another volume the preference is copy; the source only allows move.
        #expect(ExternalDropPolicy.operation(
            option: false, command: false, allOnSameVolume: false, allowsMove: true, allowsCopy: false
        ) == .move)
    }

    @Test("rejects the drop when the drag source allows neither operation (EC-238, FR-346)")
    func rejectsWhenNothingIsAllowed() {
        // Option and Command together narrow the mask to an alias (link) only in some sources (A-206).
        #expect(ExternalDropPolicy.operation(
            option: true, command: true, allOnSameVolume: true, allowsMove: false, allowsCopy: false
        ) == nil)
        #expect(ExternalDropPolicy.operation(
            option: false, command: false, allOnSameVolume: false, allowsMove: false, allowsCopy: false
        ) == nil)
    }

    @Test("treats items on the destination's volume as the same volume, and unreadable items as another volume (EC-237)")
    func sameVolume() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        let folder = root.appendingPathComponent("folder", isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("image.jpg")
        try Data("image".utf8).write(to: file)

        #expect(ExternalDropPolicy.allOnSameVolume([file, folder], destination: destination))
        // A missing item has no volume, so the whole drop counts as another volume and copies.
        #expect(!ExternalDropPolicy.allOnSameVolume([file, root.appendingPathComponent("missing")], destination: destination))
        #expect(!ExternalDropPolicy.allOnSameVolume([file], destination: root.appendingPathComponent("missing")))
        #expect(!ExternalDropPolicy.allOnSameVolume([], destination: destination))
    }
}
