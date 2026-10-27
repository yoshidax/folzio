import Foundation

public struct MediaFile: Identifiable, Hashable, Sendable {
    public enum KindNameSource: Sendable {
        case folder
        case zipArchive
    }
    public var url: URL
    public var name: String
    public var kind: ListItemKind
    public var typeDescription: String
    public var creationDate: Date?
    public var fileSize: Int64
    /// Nil means a kind name obtained from the OS or the format that the app does not translate.
    public var kindNameSource: KindNameSource?

    public init(
        url: URL,
        name: String,
        kind: ListItemKind,
        typeDescription: String,
        creationDate: Date?,
        fileSize: Int64,
        kindNameSource: KindNameSource? = nil
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.typeDescription = typeDescription
        self.creationDate = creationDate
        self.fileSize = fileSize
        self.kindNameSource = kindNameSource
    }

    public var id: URL { url }

    public func localizedKindName(using names: KindNames) -> MediaFile {
        var result = self
        switch kindNameSource {
        case .folder: result.typeDescription = names.folder
        case .zipArchive: result.typeDescription = names.zipArchive
        case nil: break
        }
        return result
    }

    public static func == (lhs: MediaFile, rhs: MediaFile) -> Bool {
        lhs.url == rhs.url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}

/// Kind names managed by the app. Injected into Core so sorting by the Kind column uses the displayed names
/// (EC-112).
public struct KindNames: Sendable, Equatable {
    public var folder: String
    public var zipArchive: String

    public init(folder: String, zipArchive: String) {
        self.folder = folder
        self.zipArchive = zipArchive
    }
}
