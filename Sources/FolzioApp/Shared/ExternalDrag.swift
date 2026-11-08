import AppKit
import FolzioCore

/// Drags between this app and other apps (TAK-74). Drags that start and end in this app's views are handled by
/// `InternalDrag` and keep their own rules (FR-020).
@MainActor
enum ExternalDrag {
    /// Operations offered when an item from the tree, the list, or the thumbnails is dropped outside the app. The
    /// destination app (such as Finder) chooses between copy and move, so this app shows no confirmation (FR-344).
    /// `.generic` is included because the system narrows the mask to `.generic` while Command is held.
    /// `.delete` is left out: the Dock Trash leaves the deletion to the drag source, and this app does not delete
    /// items at the end of a drag, so dragging to the Dock Trash is not supported (FR-344).
    /// `.link` is left out because creating aliases is out of scope (A-206).
    static let sourceOperationMaskOutsideApp: NSDragOperation = [.copy, .move, .generic]

    private static let operations = DropOperationCache()

    /// The file URLs of a drag that did not start in this app's views, or nil for drags inside the app and for drags
    /// without file URLs, such as images, links, and text from a web browser (FR-348).
    static func urls(_ info: any NSDraggingInfo) -> [URL]? {
        guard InternalDrag.urls(info) == nil else { return nil }
        let urls = operations.urls(sequence: info.draggingSequenceNumber) {
            PasteboardFileURLs.fileURLs(in: info.draggingPasteboard)
        }
        return urls.isEmpty ? nil : urls
    }

    /// The operation shown while hovering over `destination`: move or copy by the Finder rules (FR-346), or none until
    /// the decision made off the UI thread is ready or when the drop is invalid (EC-16, EC-121, EC-238).
    static func operation(_ info: any NSDraggingInfo, destination: URL) -> NSDragOperation {
        guard let urls = urls(info) else { return [] }
        let context = context(info, urls: urls, destination: destination)
        guard case .accepted(let kind)? = operations.outcome(
            sequence: info.draggingSequenceNumber,
            context: context,
            decide: decide
        ) else { return [] }
        return dragOperation(kind, mask: info.draggingSourceOperationMask)
    }

    /// The operation to perform at the drop. Uses only the decision made while hovering, because a drop must answer at
    /// once and cannot read the file system on the UI thread; without one, the drop is rejected. The coordinator
    /// validates again before it runs (FR-347).
    static func dropOperation(
        _ info: any NSDraggingInfo,
        destination: URL
    ) -> (urls: [URL], kind: InternalDropValidation.Kind)? {
        guard let urls = urls(info) else { return nil }
        let context = context(info, urls: urls, destination: destination)
        guard case .accepted(let kind)? = operations.cachedOutcome(
            sequence: info.draggingSequenceNumber,
            context: context
        ) else { return nil }
        return (urls, kind)
    }

    /// Shows a move as `.move` when the source allows it, otherwise as `.generic` (the Command move).
    static func dragOperation(_ kind: InternalDropValidation.Kind, mask: NSDragOperation) -> NSDragOperation {
        switch kind {
        case .copy: return .copy
        case .move: return mask.contains(.move) ? .move : .generic
        }
    }

    private static func context(
        _ info: any NSDraggingInfo,
        urls: [URL],
        destination: URL
    ) -> DropOperationCache.Context {
        let modifiers = NSEvent.modifierFlags
        return DropOperationCache.Context(
            urls: urls,
            destination: destination,
            option: modifiers.contains(.option),
            command: modifiers.contains(.command),
            mask: info.draggingSourceOperationMask.rawValue
        )
    }

    /// Runs in a detached task, off the UI thread: reads the volumes and validates the whole drop (R3, R4).
    nonisolated private static let decide: DropOperationCache.Decide = { context in
        let mask = NSDragOperation(rawValue: context.mask)
        guard let kind = ExternalDropPolicy.operation(
            option: context.option,
            command: context.command,
            allOnSameVolume: ExternalDropPolicy.allOnSameVolume(context.urls, destination: context.destination),
            allowsMove: mask.contains(.move) || mask.contains(.generic),
            allowsCopy: mask.contains(.copy)
        ) else { return .rejected }
        let result = InternalDropValidation.validate(sources: context.urls, destination: context.destination, kind: kind)
        return result == .valid ? .accepted(kind) : .rejected
    }
}
