import Foundation

public protocol VolumeProviding: Sendable {
    func rootNodes() -> [FolderNode]
    var changes: AsyncStream<[FolderNode]> { get }
}

public struct VolumeProvider: VolumeProviding {
    private let changeStream: AsyncStream<[FolderNode]>

    public init(changes: AsyncStream<[FolderNode]>) {
        self.changeStream = changes
    }

    public var changes: AsyncStream<[FolderNode]> {
        changeStream
    }

    public func rootNodes() -> [FolderNode] {
        Self.computeRootNodes()
    }

    public static func computeRootNodes() -> [FolderNode] {
        let fileManager = FileManager.default
        var nodes: [FolderNode] = []

        let home = fileManager.homeDirectoryForCurrentUser
        let homeName = fileManager.displayName(atPath: home.path)
        nodes.append(FolderNode(url: home, name: homeName, kind: .home))

        let volumes = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeLocalizedNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        for volume in volumes {
            let name = (try? volume.resourceValues(forKeys: [.volumeLocalizedNameKey]))?.volumeLocalizedName
                ?? volume.lastPathComponent
            nodes.append(FolderNode(url: volume, name: name, kind: .volume))
        }

        return nodes
    }
}
