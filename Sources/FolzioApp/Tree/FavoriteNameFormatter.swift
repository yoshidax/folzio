import AppKit
import FolzioCore

/// Attached to the favorite name field. Prevents newlines and characters after the 256th, including pasted text
/// (FR-100, R50). The rules live in `FavoriteName` and are not repeated here. This formatter is stateless, and its
/// `Formatter` overrides are nonisolated, so it has no isolation annotation.
final class FavoriteNameFormatter: Formatter {
    override init() {
        super.init()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func string(for obj: Any?) -> String? {
        obj as? String
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let partial = partialStringPtr.pointee as String
        let sanitized = FavoriteName.sanitizedForEditing(partial)
        if sanitized == partial { return true }

        let result = sanitized as NSString
        partialStringPtr.pointee = result
        if let range = proposedSelRangePtr {
            // Clamp to the post-formatting length.
            let location = min(range.pointee.location, result.length)
            range.pointee = NSRange(location: location, length: 0)
        }
        return false
    }
}
