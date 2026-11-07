import Foundation

public enum NameValidation: Sendable, Equatable {
    case ok
    case needsExtensionChangeConfirmation
    case invalid(NameValidationFailure)
}

/// Reason a name cannot be used (a value independent of the display language).
/// `FolzioLocalization` chooses the text.
public enum NameValidationFailure: Error, Sendable, Equatable {
    case empty
    case forbiddenCharacter
    case leadingDot
    case duplicate
    case becomesPackage
}

/// Validates a name against sibling entries supplied in `existingNames`, excluding only the source's exact name.
/// Treats every remaining entry as a conflict, even when it links to the source.
/// When `isDirectory` is true (renaming a folder), does not treat the part after `.` as an extension and does not
/// return `needsExtensionChangeConfirmation` (research.md R32). Rejects names that would make the folder a package
/// (such as `.app`) because the folder would no longer be visible (EC-53, R57).
public func validateNewName(
    _ name: String,
    for file: URL,
    existingNames: Set<String>,
    isDirectory: Bool = false
) -> NameValidation {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .invalid(.empty)
    }
    guard !name.contains("/") && !name.contains(":") else {
        return .invalid(.forbiddenCharacter)
    }
    guard !name.hasPrefix(".") else {
        return .invalid(.leadingDot)
    }
    guard !existingNames.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
        return .invalid(.duplicate)
    }
    guard !(isDirectory && PackageName.isPackage(name)) else {
        return .invalid(.becomesPackage)
    }

    guard !isDirectory else { return .ok }

    let newExtension = (name as NSString).pathExtension
    guard newExtension.caseInsensitiveCompare(file.pathExtension) == .orderedSame else {
        return .needsExtensionChangeConfirmation
    }
    return .ok
}

/// Returns the name for a new folder (FR-209, research.md R2).
/// Returns `baseName` when no entry in `existingNames` matches it, ignoring case.
/// Otherwise numbers it from 2 with `uniqueName(for:existingNames:)`, matching Duplicate (FR-018).
public func newFolderName(baseName: String, existingNames: Set<String>) -> String {
    let isTaken = existingNames.contains { $0.caseInsensitiveCompare(baseName) == .orderedSame }
    return isTaken ? uniqueName(for: baseName, existingNames: existingNames) : baseName
}

public func uniqueName(for name: String, existingNames: Set<String>) -> String {
    let lowercasedNames = Set(existingNames.map { $0.lowercased() })
    let fileExtension = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension

    var base = stem
    var counter = "2"
    if let match = trailingCounter(in: stem) {
        base = match.base
        counter = incrementDecimal(match.number)
    }

    while true {
        let candidate = fileExtension.isEmpty
            ? "\(base) \(counter)"
            : "\(base) \(counter).\(fileExtension)"
        if !lowercasedNames.contains(candidate.lowercased()) {
            return candidate
        }
        counter = incrementDecimal(counter)
    }
}

private func trailingCounter(in stem: String) -> (base: String, number: String)? {
    guard let separator = stem.lastIndex(of: " ") else { return nil }
    let suffix = stem[stem.index(after: separator)...]
    guard !suffix.isEmpty, suffix.utf8.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }) else {
        return nil
    }
    let normalized = suffix.drop(while: { $0 == "0" })
    return (String(stem[..<separator]), normalized.isEmpty ? "0" : String(normalized))
}

private func incrementDecimal(_ number: String) -> String {
    var digits = Array(number.utf8)

    for index in digits.indices.reversed() {
        if digits[index] < UInt8(ascii: "9") {
            digits[index] += 1
            return String(decoding: digits, as: UTF8.self)
        }
        digits[index] = UInt8(ascii: "0")
    }
    digits.insert(UInt8(ascii: "1"), at: 0)
    return String(decoding: digits, as: UTF8.self)
}
