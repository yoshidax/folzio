import Foundation

/// Pane from which an operation was started. Used to decide whether the confirmation modal can be skipped
/// (FR-024, FR-079; research.md R58).
public enum OperationOrigin: Sendable, Equatable {
    case fileList
    case tree
}

public enum ConfirmationPolicy {
    /// Whether confirmation may be skipped when the skip setting (FR-023) is on.
    /// Copy can always skip, and Trash can skip only from the file list. Rename and move always confirm.
    public static func isSkippable(_ kind: FileOperation.Kind, origin: OperationOrigin) -> Bool {
        switch kind {
        case .copy:
            return true
        case .trash:
            // In the tree, a row that is not selected can be right-clicked and deleted, so keep confirmation to
            // prevent mistakes (A-33).
            return origin == .fileList
        case .move, .rename:
            return false
        }
    }
}
