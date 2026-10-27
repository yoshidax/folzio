import Foundation

/// Reason a file operation failed (a value independent of the display language).
/// `FolzioLocalization` chooses the text. Reasons returned by the OS are kept verbatim in `systemReason`
/// and are not re-translated (EC-111).
public enum OperationFailureReason: Error, Sendable, Equatable {
    case noDestination
    case destinationNotFound
    case sourceNotFound
    case intoItself
    case invalidName(NameValidationFailure)
    case sameNameExists
    case sameNameAtDestination
    case trashExistingFailed(systemReason: String)
    /// Reason the OS rejected the copy, move, or rename itself
    case systemFailure(systemReason: String)
}
