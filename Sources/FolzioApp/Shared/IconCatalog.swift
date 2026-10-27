import AppKit
import FolzioCore

@MainActor
enum IconCatalog {
    static func treeIcon(for kind: FolderNode.Kind) -> NSImage? {
        let name: String
        switch kind {
        case .home:
            name = "house"
        case .volume:
            name = "externaldrive"
        case .folder:
            name = "folder"
        }
        return symbol(named: name, pointSize: 13)
    }

    static func favoritesIcon() -> NSImage? {
        symbol(named: "star.fill", pointSize: 13)
    }

    static func slideshowIcon(pointSize: CGFloat = 16) -> NSImage? {
        symbol(named: "play.rectangle", pointSize: pointSize)
    }

    static func fallbackIcon(for kind: MediaKind) -> NSImage? {
        listItemIcon(for: .media(kind), pointSize: 16)
    }

    static func listItemIcon(for kind: ListItemKind, pointSize: CGFloat) -> NSImage? {
        let name: String
        switch kind {
        case .media(let mediaKind):
            switch mediaKind {
            case .jpeg:
                name = "photo"
            case .png:
                name = "photo.on.rectangle"
            case .gif:
                name = "photo.stack"
            case .webp:
                name = "photo.circle"
            case .mp4:
                name = "film"
            case .mov:
                name = "video"
            }
        case .archive:
            name = "doc.zipper"
        case .folder, .directory:
            name = "folder"
        case .parent:
            name = "arrowshape.turn.up.left"
        }
        return symbol(named: name, pointSize: pointSize)
    }

    private static func symbol(named name: String, pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular
        )
        guard let image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration) else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}
