import AppKit
import FolzioCore

/// Classifies the clipboard without requesting deferred contents. Clipboard promises are never received (FR-354).
@MainActor
enum PasteboardImport {
    enum Availability: Equatable {
        case none, fileURLs, imageData

        func allowsPaste(move: Bool) -> Bool {
            self == .fileURLs || (!move && self == .imageData)
        }
    }

    static func availability(in board: NSPasteboard = .general) -> Availability {
        let types = (board.pasteboardItems ?? []).map { $0.types.map(\.rawValue) }
        let payload = ImportPayloadPolicy.select(hasFileURLs: types.contains { $0.contains(NSPasteboard.PasteboardType.fileURL.rawValue) },
            promiseDeclaredTypes: [], imageDataTypes: types)
        switch payload {
        case .fileURLs: return .fileURLs
        case .imageData: return .imageData
        default: return .none
        }
    }
}
