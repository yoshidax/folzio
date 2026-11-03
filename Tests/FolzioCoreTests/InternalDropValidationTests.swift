import Foundation
import Testing
@testable import FolzioCore

@Suite("Internal drop validation")
struct InternalDropValidationTests {
    @Test("validates the entire selection, same parent and self or descendant")
    func selectionAndDirectories() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let source = root.appendingPathComponent("source", isDirectory: true)
        let child = source.appendingPathComponent("child", isDirectory: true)
        let other = root.appendingPathComponent("other", isDirectory: true)
        try fm.createDirectory(at: child, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("image.jpg")
        try Data("image".utf8).write(to: file)
        #expect(InternalDropValidation.validate(sources: [file], destination: other, kind: .move) == .valid)
        #expect(InternalDropValidation.validate(sources: [file], destination: source, kind: .move) == .sameParent)
        #expect(InternalDropValidation.validate(sources: [file], destination: source, kind: .copy) == .valid)
        #expect(InternalDropValidation.validate(sources: [file, source], destination: child, kind: .copy) == .intoItself)
        #expect(InternalDropValidation.validate(sources: [source], destination: source, kind: .move) == .intoItself)
        #expect(InternalDropValidation.validate(sources: [], destination: other, kind: .copy) == .empty)
        #expect(InternalDropValidation.validate(sources: [root.appendingPathComponent("missing")], destination: other, kind: .move) == .missingSource)
        #expect(InternalDropValidation.validate(sources: [file], destination: file, kind: .move) == .invalidDestination)
        #expect(InternalDropValidation.validate(sources: [source, file], destination: other, kind: .move) == .overlappingSources)
        #expect(InternalDropValidation.validate(sources: [child, source], destination: other, kind: .copy) == .overlappingSources)
        #expect(InternalDropValidation.validate(sources: [file, file], destination: other, kind: .copy) == .overlappingSources)
        let alias = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: alias, withDestinationURL: child)
        #expect(InternalDropValidation.validate(sources: [source], destination: alias, kind: .copy) == .intoItself)
        #expect(InternalDropValidation.validate(sources: [alias, source], destination: other, kind: .copy) == .overlappingSources)
    }

    @Test("validates multiple tree folders from different parents as one selection (FR-020, EC-16, EC-121)")
    func multipleTreeFolders() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let first = root.appendingPathComponent("p1/a", isDirectory: true)
        let second = root.appendingPathComponent("p1/b", isDirectory: true)
        let third = root.appendingPathComponent("p2/c", isDirectory: true)
        let inner = first.appendingPathComponent("inner", isDirectory: true)
        let destination = root.appendingPathComponent("d", isDirectory: true)
        for folder in [second, third, inner, destination] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let sources = [first, second, third]
        #expect(InternalDropValidation.validate(sources: sources, destination: destination, kind: .move) == .valid)
        #expect(InternalDropValidation.validate(sources: sources, destination: destination, kind: .copy) == .valid)
        // A destination that is the parent of one of the folders rejects the whole move, but not a copy (EC-121).
        let firstParent = root.appendingPathComponent("p1", isDirectory: true)
        #expect(InternalDropValidation.validate(sources: sources, destination: firstParent, kind: .move) == .sameParent)
        #expect(InternalDropValidation.validate(sources: sources, destination: firstParent, kind: .copy) == .valid)
        // A destination inside one of the folders rejects the whole operation (EC-16).
        #expect(InternalDropValidation.validate(sources: sources, destination: inner, kind: .move) == .intoItself)
        #expect(InternalDropValidation.validate(sources: sources, destination: inner, kind: .copy) == .intoItself)
        // A folder selected with its own descendant is rejected for both kinds (EC-121).
        #expect(InternalDropValidation.validate(sources: [first, inner], destination: destination, kind: .move) == .overlappingSources)
        #expect(InternalDropValidation.validate(sources: [inner, third, first], destination: destination, kind: .copy) == .overlappingSources)
    }
}
