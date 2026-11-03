import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Icon catalog tint colors")
@MainActor
struct IconCatalogTintTests {
    private func brightness(of color: NSColor) -> CGFloat {
        (color.usingColorSpace(.sRGB) ?? color).brightnessComponent
    }

    @Test("Folders and directories use the fixed blue (FR-269)", arguments: [ListItemKind.folder, .directory])
    func folderColor(kind: ListItemKind) {
        #expect(IconCatalog.tintColor(for: kind) == IconCatalog.folderBlue)
    }

    @Test("Zip files use the fixed yellow (FR-270)")
    func archiveColor() {
        #expect(IconCatalog.tintColor(for: .archive) == IconCatalog.archiveYellow)
    }

    @Test("The parent row and media keep the secondary label color (FR-271)")
    func secondaryColor() {
        #expect(IconCatalog.tintColor(for: .parent) == .secondaryLabelColor)
        #expect(IconCatalog.tintColor(for: .media(.jpeg)) == .secondaryLabelColor)
    }

    @Test("Blue and yellow have close HSB brightness (FR-270)")
    func brightnessIsClose() {
        let difference = abs(brightness(of: IconCatalog.folderBlue) - brightness(of: IconCatalog.archiveYellow))
        #expect(difference <= 0.1)
    }

    @Test("Fixed colors do not depend on the appearance (FR-269)", arguments: [NSAppearance.Name.aqua, .darkAqua])
    func appearanceIndependent(name: NSAppearance.Name) throws {
        let appearance = try #require(NSAppearance(named: name))
        var resolved: [NSColor] = []
        appearance.performAsCurrentDrawingAppearance {
            resolved = [IconCatalog.folderBlue, IconCatalog.archiveYellow].map {
                $0.usingColorSpace(.sRGB) ?? $0
            }
        }
        #expect(resolved[0] == (IconCatalog.folderBlue.usingColorSpace(.sRGB) ?? IconCatalog.folderBlue))
        #expect(resolved[1] == (IconCatalog.archiveYellow.usingColorSpace(.sRGB) ?? IconCatalog.archiveYellow))
    }
}
