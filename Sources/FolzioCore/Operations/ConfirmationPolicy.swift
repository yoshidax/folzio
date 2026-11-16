import Foundation

/// Pane from which an operation was started. The tree's confirmations also show each folder's absolute path
/// (FR-079, FR-103; research.md R58).
public enum OperationOrigin: Sendable, Equatable {
    case fileList
    case tree
}

public enum ConfirmationPolicy {
    /// The setting that decides whether the operation confirms (FR-023, FR-024). Every operation that confirms has
    /// one: moving folders in the tree to the Trash follows the same Trash setting as the file list, because a
    /// context click targets the clicked item in both panes and the Trash can undo it (FR-079, A-232, A-233).
    public static func target(for kind: FileOperation.Kind, origin: OperationOrigin) -> ConfirmationTarget {
        switch kind {
        case .copy:
            return .copy
        case .move:
            return .move
        case .rename:
            return .rename
        case .trash:
            return .trash
        }
    }
}
