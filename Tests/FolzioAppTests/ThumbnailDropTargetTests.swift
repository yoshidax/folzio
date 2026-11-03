import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Thumbnail drop target", .serialized)
@MainActor
struct ThumbnailDropTargetTests {
    @Test("The thumbnail image does not take drops meant for the collection view", arguments: [false, true])
    func thumbnailImageIgnoresDrops(isFolder: Bool) throws {
        try withItem(isFolder: isFolder) { item in
            // Drops on the thumbnail must reach the collection view so that folder items can be drop targets
            // (FR-163, bug: tak-44).
            let imageView = try #require(item.imageView)
            #expect(imageView.registeredDraggedTypes.isEmpty)
        }
    }

    @Test("A drop target is filled while targeted and returns to its normal appearance afterwards",
          arguments: [false, true])
    func dropTargetHighlight(wasSelected: Bool) throws {
        try withItem(isFolder: true) { item in
            item.isSelected = wasSelected
            let layer = try #require(item.view.layer)
            let field = try #require(item.textField)
            let normalBackground = layer.backgroundColor
            let normalBorder = layer.borderWidth

            item.highlightState = .asDropTarget
            #expect(layer.backgroundColor == NSColor.selectedContentBackgroundColor.cgColor)
            #expect(layer.borderWidth == 0)
            #expect(field.textColor == .alternateSelectedControlTextColor)

            item.highlightState = .none
            #expect(layer.backgroundColor == normalBackground)
            #expect(layer.borderWidth == normalBorder)
            #expect(field.textColor == .labelColor)
        }
    }

    private func withItem(isFolder: Bool, body: (ThumbnailItemView) throws -> Void) throws {
        _ = NSApplication.shared
        let file = MediaFile(
            url: URL(fileURLWithPath: isFolder ? "/tmp/Album" : "/tmp/original.jpg"),
            name: isFolder ? "Album" : "original.jpg",
            kind: isFolder ? .folder : .media(.jpeg),
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
        let item = ThumbnailItemView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = item.view
        defer { window.close() }
        item.configure(with: file, iconPointSize: 16)
        try body(item)
    }
}
