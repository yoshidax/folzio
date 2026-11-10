import Foundation
import UniformTypeIdentifiers

public enum ImportedFileName {
    public static func isAcceptable(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
            && name.utf8.count <= 200
            && !name.unicodeScalars.contains { [.control, .format].contains($0.properties.generalCategory) }
    }

    public static func nameFromURL(_ text: String) -> String? {
        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), components.host?.isEmpty == false,
              ["http", "https"].contains(scheme),
              let encoded = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).last,
              let name = String(encoded).removingPercentEncoding, isAcceptable(name) else { return nil }
        let result = (name as NSString).deletingPathExtension + ".png"
        return isAcceptable(result) ? result : nil
    }

    public static func datedName(
        prefix: String, date: Date, extension suffix: String,
        timeZone: TimeZone = .current, locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stem = "\(prefix) \(formatter.string(from: date))"
        return suffix.isEmpty ? stem : stem + "." + suffix
    }

    public static func corrected(
        name: String, contentType: UTType, prefix: String = "Image", date: Date = Date()
    ) -> String {
        let suffix = contentType == .jpeg ? "jpg" : (contentType.preferredFilenameExtension ?? "png")
        guard isAcceptable(name) else { return datedName(prefix: prefix, date: date, extension: suffix) }
        let original = (name as NSString).pathExtension
        let sameType = UTType(filenameExtension: original) == contentType
        let supportedAlias = MediaKind(fileExtension: original) != nil
        let keep = original.caseInsensitiveCompare(suffix) == .orderedSame || (sameType && supportedAlias)
        let result = keep ? name : (name as NSString).deletingPathExtension + "." + suffix
        return isAcceptable(result) ? result : datedName(prefix: prefix, date: date, extension: suffix)
    }

    public static func uniqueNames(_ names: [String]) -> [String] {
        var used = Set<String>()
        return names.map { name in
            let result = used.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
                ? uniqueName(for: name, existingNames: used) : name
            used.insert(result)
            return result
        }
    }
}
