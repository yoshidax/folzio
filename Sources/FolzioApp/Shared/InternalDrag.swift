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
    private struct ValidationKey: Hashable {
        let sequence: Int
        let urls: [URL]
        let destination: URL
        let copy: Bool
    }
    private static var cache: [ValidationKey: Bool] = [:]
    private static var pending: Set<ValidationKey> = []
    private static var currentSequence: Int?

    static func register(_ view: NSView) {
        sources.removeAll { $0.view == nil }
        sources.append(WeakView(view))
    }

    static func urls(_ info: any NSDraggingInfo) -> [URL]? {
        guard let source = info.draggingSource as? NSView,
              sources.contains(where: { $0.view === source }) else { return nil }
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL])?.map { $0 as URL } ?? []
        return urls.isEmpty ? nil : urls
    }

    static func operation(_ info: any NSDraggingInfo, destination: URL) -> NSDragOperation {
        guard let urls = urls(info) else { return [] }
        let copy = NSEvent.modifierFlags.contains(.option)
        let sequence = info.draggingSequenceNumber
        if currentSequence != sequence {
            currentSequence = sequence
            cache.removeAll()
            pending.removeAll()
        }
        let key = ValidationKey(sequence: sequence, urls: urls, destination: destination, copy: copy)
        if let valid = cache[key] {
            guard valid else { return [] }
            let operation: NSDragOperation = copy ? .copy : .move
            return info.draggingSourceOperationMask.contains(operation) ? operation : []
        }
        if pending.insert(key).inserted {
            Task { @MainActor in
                let valid = await validForExecution(urls, destination: destination, copy: copy)
                guard currentSequence == sequence else { return }
                cache[key] = valid
                pending.remove(key)
            }
        }
        return []
    }

    static func validForExecution(_ urls: [URL], destination: URL, copy: Bool) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            InternalDropValidation.validate(sources: urls, destination: destination, kind: copy ? .copy : .move) == .valid
        }.value
    }
}
