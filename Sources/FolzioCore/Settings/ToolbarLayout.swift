import Foundation

/// Describes the main toolbar's item order and validates an order that was saved by the app.
///
/// The identifiers are persisted, so their strings must not change. The standard space items use the identifier
/// strings that AppKit defines for them.
public enum ToolbarLayout {
    /// The identifiers of the button sets, in the default order. Each set is one toolbar item and cannot be split.
    public static let setIdentifiers: [String] = [
        "history",
        "paneLayout",
        "slideshow",
        "previewZoom",
        "mediaTypeFilter",
        "zipVisibility",
        "viewMode",
        "thumbnailSize",
        "nameFilter",
    ]

    /// The identifier of the standard fixed space item.
    public static let spaceIdentifier = "NSToolbarSpaceItem"

    /// The identifier of the standard flexible space item.
    public static let flexibleSpaceIdentifier = "NSToolbarFlexibleSpaceItem"

    /// The identifier of the search field that filters the file list by name (FR-380).
    public static let nameFilterIdentifier = "nameFilter"

    /// The order that is used for a first launch, after the user resets the toolbar, and when a saved order is invalid.
    /// The flexible space comes before the name filter field, so the field sits at the right end (FR-233, FR-380).
    public static let defaultOrder: [String] = [
        "history",
        "paneLayout",
        "slideshow",
        "previewZoom",
        "mediaTypeFilter",
        "zipVisibility",
        "viewMode",
        "thumbnailSize",
        flexibleSpaceIdentifier,
        nameFilterIdentifier,
    ]

    /// Every identifier that may appear in a saved order.
    public static let allowed: Set<String> = Set(setIdentifiers + [spaceIdentifier, flexibleSpaceIdentifier])

    /// Returns a valid order for a value read from the saved settings.
    ///
    /// A value that is not an array of strings, or an array with an identifier that is not allowed, is treated as
    /// broken and gives `defaultOrder` (FR-005). Space items may repeat, and repeated button sets keep only their
    /// first occurrence. A set that is missing from a saved order stays missing, and an empty array stays empty,
    /// because the user may remove every set. A saved order from before the name filter field existed is restored
    /// without the field, so the field is not added automatically (FR-393).
    ///
    /// - Parameter saved: The raw value that was stored, such as `UserDefaults.object(forKey:)`.
    public static func normalized(saved: Any?) -> [String] {
        guard let identifiers = saved as? [String] else { return defaultOrder }
        if identifiers.isEmpty { return [] }
        var seenSets = Set<String>()
        var result: [String] = []
        for identifier in identifiers {
            guard allowed.contains(identifier) else { return defaultOrder }
            if setIdentifiers.contains(identifier) {
                guard seenSets.insert(identifier).inserted else { continue }
            }
            result.append(identifier)
        }
        return result
    }
}
