import Foundation
import FolzioCore

/// Converts Core values (which do not depend on the display language) into localized text (research.md R8).
extension Localizer {
    public func text(for error: SearchRootError) -> String {
        switch error {
        case .empty: return text(.errorSearchRootEmpty)
        case .notAbsolute: return text(.errorSearchRootNotAbsolute)
        case .notFound: return text(.errorSearchRootNotFound)
        case .notAFolder: return text(.errorSearchRootNotAFolder)
        case .accessDenied: return text(.errorSearchRootAccessDenied)
        }
    }

    public func text(for error: SearchFolderInitialLocationError) -> String {
        switch error {
        case .noUsableFolder: return text(.errorSearchRootNoUsableFolder)
        }
    }

    public func text(for error: ArchiveError) -> String {
        switch error {
        case .notFound:
            return text(.errorZipCannotOpen, .text(text(.errorZipNotFound)))
        case .accessDenied:
            return text(.errorZipCannotOpen, .text(text(.errorZipAccessDenied)))
        case .notAZip:
            return text(.errorZipCannotOpen, .text(text(.errorZipNotAZip)))
        case .multiDisk:
            return text(.errorZipCannotOpen, .text(text(.errorZipMultiDisk)))
        case .entryEncrypted:
            return text(.errorZipEntryEncrypted)
        case .unsupportedMethod:
            return text(.errorZipUnsupportedMethod)
        case .tooLarge:
            return text(.errorZipTooLarge)
        case let .corrupted(corruption):
            return text(.errorZipCannotOpen, .text(text(for: corruption)))
        }
    }

    public func text(for corruption: ArchiveCorruption) -> String {
        switch corruption {
        case .cannotStartInflate: return text(.errorZipCorruptedCannotStartInflate)
        case .compressedDataDamaged: return text(.errorZipCorruptedCompressedDataDamaged)
        case .dataTruncated: return text(.errorZipCorruptedDataTruncated)
        case .compressedDataTruncated: return text(.errorZipCorruptedCompressedDataTruncated)
        case .headerDamaged: return text(.errorZipCorruptedHeaderDamaged)
        case .invalidOffset: return text(.errorZipCorruptedInvalidOffset)
        case .centralDirectoryTooLarge: return text(.errorZipCorruptedCentralDirectoryTooLarge)
        case .invalidLocation: return text(.errorZipCorruptedInvalidLocation)
        case .entryNotFound: return text(.errorZipCorruptedEntryNotFound)
        case .sizeMismatch: return text(.errorZipCorruptedSizeMismatch)
        case .dataOutsideFile: return text(.errorZipCorruptedDataOutsideFile)
        case .readCancelled: return text(.errorZipCorruptedReadCancelled)
        case .readFailed: return text(.errorZipCorruptedReadFailed)
        case .unreadable: return text(.errorZipCorruptedUnreadable)
        }
    }

    public func text(for failure: NameValidationFailure) -> String {
        switch failure {
        case .empty: return text(.errorNameEmpty)
        case .forbiddenCharacter: return text(.errorNameForbiddenCharacter)
        case .leadingDot: return text(.errorNameLeadingDot)
        case .duplicate: return text(.errorNameDuplicate)
        case .becomesPackage: return text(.errorNameBecomesPackage)
        }
    }

    public func text(for reason: OperationFailureReason) -> String {
        switch reason {
        case .noDestination: return text(.errorOperationNoDestination)
        case .destinationNotFound: return text(.errorOperationDestinationNotFound)
        case .sourceNotFound: return text(.errorOperationSourceNotFound)
        case .intoItself: return text(.errorOperationIntoItself)
        case let .invalidName(failure): return text(for: failure)
        case .sameNameExists: return text(.errorOperationSameNameExists)
        case .sameNameAtDestination: return text(.errorOperationSameNameAtDestination)
        case let .trashExistingFailed(systemReason):
            return text(.errorOperationTrashExistingFailed, .text(systemReason))
        case let .systemFailure(systemReason):
            return text(.errorOperationSystemFailure, .text(systemReason))
        }
    }

    public func text(for failure: ListingFailure) -> String {
        switch failure {
        case .folderNotFound: return text(.emptyFolderNotFound)
        // Do not re-translate reasons returned by the OS (EC-111).
        case let .systemFailure(systemReason): return systemReason
        case let .archive(error): return text(for: error)
        }
    }

    public func text(for failure: PreviewFailure) -> String {
        switch failure {
        case .unreadable: return text(.previewFailureUnreadable)
        case .unsupportedFormat: return text(.previewFailureUnsupportedFormat)
        case .corrupted: return text(.previewFailureCorrupted)
        case let .archive(error): return text(for: error)
        }
    }
}
