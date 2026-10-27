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
}
