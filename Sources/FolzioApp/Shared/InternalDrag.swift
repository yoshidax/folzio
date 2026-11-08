import AppKit
import FolzioCore

/// Recognizes only views owned by this app. No filesystem work is done during hover.
@MainActor
enum InternalDrag {
    private final class WeakView {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }
    private static var sources: [WeakView] = []
    private static let operations = DropOperationCache()
    private static var acceptedSequence: Int?

    static func register(_ view: NSView) {
        sources.removeAll { $0.view == nil }
        sources.append(WeakView(view))
    }

    /// Records that one of this app's views accepted the drop of the drag session `sequence` and started an operation.
    /// A drag that ends without this mark was dropped outside the app (TAK-74).
    static func markAccepted(_ sequence: Int) {
        acceptedSequence = sequence
    }

    /// Whether one of this app's views accepted the drop of the drag session `sequence`.
    static func wasAccepted(_ sequence: Int) -> Bool {
        acceptedSequence == sequence
    }

    static func urls(_ info: any NSDraggingInfo) -> [URL]? {
        guard let source = info.draggingSource as? NSView,
              sources.contains(where: { $0.view === source }) else { return nil }
        let urls = operations.urls(sequence: info.draggingSequenceNumber) {
            PasteboardFileURLs.fileURLs(in: info.draggingPasteboard)
        }
        return urls.isEmpty ? nil : urls
    }

    /// Move by default and copy while Option is held (FR-020). Only Option is part of the key, so pressing other
    /// modifiers does not start a new decision.
    static func operation(_ info: any NSDraggingInfo, destination: URL) -> NSDragOperation {
        guard let urls = urls(info) else { return [] }
        let context = DropOperationCache.Context(
            urls: urls,
            destination: destination,
            option: NSEvent.modifierFlags.contains(.option),
            command: false,
            mask: 0
        )
        guard case .accepted(let kind)? = operations.outcome(
            sequence: info.draggingSequenceNumber,
            context: context,
            decide: decide
        ) else { return [] }
        let operation: NSDragOperation = kind == .copy ? .copy : .move
        return info.draggingSourceOperationMask.contains(operation) ? operation : []
    }

    /// Runs in a detached task, off the UI thread.
    nonisolated private static let decide: DropOperationCache.Decide = { context in
        let kind: InternalDropValidation.Kind = context.option ? .copy : .move
        let result = InternalDropValidation.validate(sources: context.urls, destination: context.destination, kind: kind)
        return result == .valid ? .accepted(kind) : .rejected
    }
}
