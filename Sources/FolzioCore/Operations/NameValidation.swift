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

public func uniqueName(for name: String, existingNames: Set<String>) -> String {
    let lowercasedNames = Set(existingNames.map { $0.lowercased() })
    let fileExtension = (name as NSString).pathExtension
    let stem = (name as NSString).deletingPathExtension

    var base = stem
    var counter = 2
    if let match = trailingCounter(in: stem) {
        base = match.base
        counter = match.number + 1
    }

    while true {
        let candidate = fileExtension.isEmpty
            ? "\(base) \(counter)"
            : "\(base) \(counter).\(fileExtension)"
        if !lowercasedNames.contains(candidate.lowercased()) {
            return candidate
        }
        counter += 1
    }
}

private func trailingCounter(in stem: String) -> (base: String, number: Int)? {
    guard let separator = stem.lastIndex(of: " ") else { return nil }
    let suffix = stem[stem.index(after: separator)...]
    guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber), let number = Int(suffix) else {
        return nil
    }
    return (String(stem[..<separator]), number)
}
