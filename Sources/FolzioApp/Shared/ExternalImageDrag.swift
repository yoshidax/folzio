import AppKit
import FolzioCore

@MainActor
final class ExternalImageDrag {
    static let registeredTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff, .init("public.jpeg")]
        + NSFilePromiseReceiver.readableDraggedTypes.map { .init($0) }
    private static let cache = ExternalImageDrag()
    private var sequence: Int?
    private var cached: ImportPayload?

    func payload(sequence: Int, read: () -> ImportPayload?) -> ImportPayload? {
        if self.sequence != sequence { self.sequence = sequence; cached = read() }
        return cached
    }

    static func payload(in board: NSPasteboard) -> ImportPayload? {
        let items = board.pasteboardItems ?? []
        let hasFileURLs = items.contains { $0.types.contains(.fileURL) }
        let isPhotosDrag = !items.isEmpty && items.allSatisfy {
            $0.types.contains(.init("com.apple.photos.object-reference.asset"))
        }
        if hasFileURLs && !isPhotosDrag { return .fileURLs }
        let promises = (board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
        return ImportPayloadPolicy.select(hasFileURLs: hasFileURLs, isPhotosDrag: isPhotosDrag,
            promiseDeclaredTypes: promises.map(\.fileTypes),
            imageDataTypes: items.map { $0.types.map(\.rawValue) })
    }

    static func payload(in board: NSPasteboard, sequence: Int) -> ImportPayload? {
        cache.payload(sequence: sequence) { Self.payload(in: board) }
    }

    static func operation(payload: ImportPayload?, mask: NSDragOperation, hasStaging: Bool) -> NSDragOperation {
        guard mask.contains(.copy) else { return [] }
        switch payload {
        case .promises: return hasStaging ? .copy : []
        case .imageData: return .copy
        default: return []
        }
    }

    static func operation(_ info: any NSDraggingInfo) -> NSDragOperation {
        let payload = payload(in: info.draggingPasteboard, sequence: info.draggingSequenceNumber)
        return operation(payload: payload, mask: info.draggingSourceOperationMask, hasStaging: !ImportSessionManager.shared.pool.ready.isEmpty)
    }

    static func images(in board: NSPasteboard) -> [RawImportItem] {
        (board.pasteboardItems ?? []).compactMap { item in
            guard let type = ImportPayloadPolicy.imageDataTypes.first(where: { item.types.contains(.init($0)) }) else { return nil }
            let result: Result<Data, ImportRejection>
            if let data = item.data(forType: .init(type)) {
                result = data.count <= Int(ExpectedKind.image.byteLimit) ? .success(data) : .failure(.tooLarge(limit: ExpectedKind.image.byteLimit))
            } else { result = .failure(.notImageOrVideo) }
            return RawImportItem(data: result, name: item.string(forType: .URL).flatMap(ImportedFileName.nameFromURL))
        }
    }

    static func accept(_ info: any NSDraggingInfo, destination: URL, save: @escaping ImportSessionManager.Save) -> Bool {
        guard info.draggingSourceOperationMask.contains(.copy) else { return false }
        let board = info.draggingPasteboard
        // Re-read receivers during the drop. Never defer the actual request until after the drop returns.
        switch payload(in: board) {
        case .promises:
            let receivers = (board.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver]) ?? []
            let cancellation = ImportCancellation()
            return ImportSessionManager.shared.beginPromises(receivers.map { .live($0, cancellation: cancellation) },
                destination: destination, cancellation: cancellation, save: save) != nil
        case .imageData:
            return ImportSessionManager.shared.beginImages(images(in: board), destination: destination, save: save) != nil
        default: return false
        }
    }
}
