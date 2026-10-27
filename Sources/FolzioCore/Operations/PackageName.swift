import Foundation
import UniformTypeIdentifiers

/// Determines from the name alone whether a folder with that name would be treated as a package (EC-53,
/// research.md R57). Does not inspect disk state (the bundle bit), so it can be used before renaming.
public enum PackageName {
    /// True when the extension is a package type (such as .app, .bundle, or .rtfd); false when there is no extension.
    public static func isPackage(_ name: String) -> Bool {
        let fileExtension = (name as NSString).pathExtension
        guard !fileExtension.isEmpty else { return false }
        return UTType(filenameExtension: fileExtension, conformingTo: .directory)?.conforms(to: .package) == true
    }
}
