import Foundation

/// Chooses between move and copy for file URLs dropped from another app, with the same rules as Finder (FR-346).
public enum ExternalDropPolicy {
    public typealias Operation = InternalDropValidation.Kind

    /// - Parameters:
    ///   - option: Option is held at the drop. Prefers copy, and wins over Command.
    ///   - command: Command is held at the drop. Prefers move.
    ///   - allOnSameVolume: Every item is on the destination's volume (`allOnSameVolume(_:destination:)`).
    ///     Without modifiers, prefers move only in this case (EC-237).
    ///   - allowsMove: The drag source allows move (`.move` or `.generic` in its mask).
    ///   - allowsCopy: The drag source allows copy.
    /// - Returns: The preferred operation, the other one when only that is allowed, or nil when neither is allowed
    ///   (EC-238).
    public static func operation(
        option: Bool,
        command: Bool,
        allOnSameVolume: Bool,
        allowsMove: Bool,
        allowsCopy: Bool
    ) -> Operation? {
        let preferred: Operation
        if option {
            preferred = .copy
        } else if command || allOnSameVolume {
            preferred = .move
        } else {
            preferred = .copy
        }
        switch preferred {
        case .move:
            if allowsMove { return .move }
            return allowsCopy ? .copy : nil
        case .copy:
            if allowsCopy { return .copy }
            return allowsMove ? .move : nil
        }
    }

    /// Whether every item is on the same volume as `destination`. Returns false when any volume cannot be read, so that
    /// the drop copies instead of removing the originals (EC-237). Reads the file system; do not call on the UI thread.
    public static func allOnSameVolume(_ sources: [URL], destination: URL) -> Bool {
        guard !sources.isEmpty, let destinationVolume = volumeIdentifier(of: destination) else { return false }
        return sources.allSatisfy { source in
            guard let volume = volumeIdentifier(of: source) else { return false }
            return volume.isEqual(destinationVolume)
        }
    }

    private static func volumeIdentifier(of url: URL) -> NSObject? {
        // Resource values are cached per URL instance, so read from a fresh URL.
        let fresh = URL(fileURLWithPath: url.path)
        return (try? fresh.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }
}
