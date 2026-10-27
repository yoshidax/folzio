import Foundation

public struct FolderNode: Identifiable, Hashable, Sendable {
    public enum Kind: Sendable {
        case home
        case volume
        case folder
    }

    public enum AccessState: Sendable {
        case unknown
        case accessible
        case denied
        case unavailable
    }

    public enum SubfolderState: Sendable {
        case unknown
        case present
        case absent
        case failed
    }

    public var url: URL
    public var name: String
    public var kind: Kind
    public var children: [FolderNode]?
    public var accessState: AccessState
    public var subfolderState: SubfolderState

    public init(
        url: URL,
        name: String,
        kind: Kind,
        children: [FolderNode]? = nil,
        accessState: AccessState = .unknown,
        subfolderState: SubfolderState = .unknown
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.children = children
        self.accessState = accessState
        self.subfolderState = subfolderState
    }

    public var id: URL { url }

    public var isExpandable: Bool {
        accessState != .denied && (subfolderState == .present || subfolderState == .failed)
    }

    public mutating func applySubfolderProbe(_ result: Result<Bool, ListingError>) {
        switch result {
        case .success(let hasSubfolders):
            subfolderState = hasSubfolders ? .present : .absent
            accessState = .accessible
        case .failure(.accessDenied):
            accessState = .denied
        case .failure:
            subfolderState = .failed
        }
    }

    public mutating func applySubfolderListing(_ result: Result<Int, ListingError>) {
        switch result {
        case .success(let count):
            subfolderState = count > 0 ? .present : .absent
            accessState = .accessible
        case .failure(.accessDenied):
            accessState = .denied
            children = []
        case .failure:
            accessState = .unavailable
            subfolderState = .failed
            children = nil
        }
    }

    public static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.url == rhs.url
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
