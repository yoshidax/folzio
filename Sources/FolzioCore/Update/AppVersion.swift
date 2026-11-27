import Foundation

/// A release version in the `<major>.<minor>.<patch>` form used by `CFBundleShortVersionString` and the release tags
/// (FR-171, FR-425).
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses exactly three dot-separated decimal numbers.
    ///
    /// Returns `nil` for surrounding whitespace, a leading `v`, a sign, empty or non-ASCII-digit parts, a part count
    /// other than three, and numbers that do not fit in `Int`.
    public init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.unicodeScalars.allSatisfy({ $0.value >= 0x30 && $0.value <= 0x39 }),
                  let number = Int(part) else { return nil }
            numbers.append(number)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// Compares each part as a number, so 1.10.0 is newer than 1.9.0 (EC-293).
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
