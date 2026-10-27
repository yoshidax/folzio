import Foundation

/// Parses the input string for the slideshow interval (seconds) in the Settings window.
/// Accepts only ASCII or full-width digits after trimming whitespace. Rejects signs, decimal points, and grouping
/// separators.
public enum SlideshowIntervalInput {
    /// Returns a valid interval in seconds, or nil when outside `SlideshowOptions.intervalRange` or invalid.
    public static func parse(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var ascii = String.UnicodeScalarView()
        for scalar in trimmed.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                ascii.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0x30...0x39:
                ascii.append(scalar)
            default:
                return nil
            }
        }
        guard !ascii.isEmpty,
              let value = Int(String(ascii)),
              SlideshowOptions.intervalRange.contains(value)
        else { return nil }
        return value
    }
}
