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
    /// Last modified date. Nil when unavailable. For an entry inside a zip, the entry's modification date.
    public var modificationDate: Date?
    public var fileSize: Int64
    /// Nil means a kind name obtained from the OS or the format that the app does not translate.
    public var kindNameSource: KindNameSource?
    /// Identifies the content of a media file. Nil for folders, zip files, `..`, and when unavailable (FR-228).
    /// Not part of `==` or `hash`, which compare only the URL.
    public var contentVersion: FileContentVersion?

    public init(
        url: URL,
        name: String,
        kind: ListItemKind,
        typeDescription: String,
        creationDate: Date?,
        modificationDate: Date? = nil,
        fileSize: Int64,
        kindNameSource: KindNameSource? = nil,
        contentVersion: FileContentVersion? = nil
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.typeDescription = typeDescription
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.kindNameSource = kindNameSource
        self.contentVersion = contentVersion
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
