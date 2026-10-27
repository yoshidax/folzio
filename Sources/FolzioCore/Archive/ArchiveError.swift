import Foundation

public enum ArchiveError: Error, Sendable, Equatable {
    case notFound
    case accessDenied
    /// The end record cannot be found or the structure is damaged
    case notAZip
    /// Multi-disk zip
    case multiDisk
    case entryEncrypted
    case unsupportedMethod(UInt16)
    /// Image size limit of 512 MB (research.md R24)
    case tooLarge
    case corrupted(ArchiveCorruption)
}

/// Reason the contents of a zip are damaged (a value independent of the display language).
/// `FolzioLocalization` chooses the text.
public enum ArchiveCorruption: Error, Sendable, Equatable {
    case cannotStartInflate
    case compressedDataDamaged
    case dataTruncated
    case compressedDataTruncated
    case headerDamaged
    case invalidOffset
    case centralDirectoryTooLarge
    case invalidLocation
    case entryNotFound
    case sizeMismatch
    case dataOutsideFile
    case readCancelled
    case readFailed
    case unreadable
}
