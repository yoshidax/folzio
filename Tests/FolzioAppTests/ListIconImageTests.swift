import AppKit
import FolzioCore
import FolzioLocalization
import Testing
@testable import FolzioApp

@Suite("List icon image", .serialized)
@MainActor
struct ListIconImageTests {
    private func generatedImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        return try #require(context.makeImage())
    }

    @Test(
        "The leading icon keeps the aspect ratio of the generated image within 16 pt (FR-048)",
        arguments: [
            (64, 36, NSSize(width: 16, height: 9)),
            (36, 64, NSSize(width: 9, height: 16)),
            (64, 64, NSSize(width: 16, height: 16)),
            (16, 64, NSSize(width: 4, height: 16)),
            (8, 4, NSSize(width: 16, height: 8)),
        ]
    )
    func keepsAspectRatio(width: Int, height: Int, expected: NSSize) throws {
        let image = try generatedImage(width: width, height: height)
        let icon = ListModeView.listIconImage(from: image, pointSize: 16)
        #expect(icon.size == expected)
    }

    @Test("The badge of a 16:9 frame stays inside the drawn frame of the 16 pt icon (FR-418, EC-286)")
    func badgeStaysInsideWideFrame() throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        // The same settings as the leading icon of the list mode.
        let imageView = VideoBadgeImageView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        imageView.imageScaling = .scaleProportionallyDown
        imageView.badgeMetrics = VideoBadgeLayout.listIcon
        window.contentView?.addSubview(imageView)

        let image = try generatedImage(width: 64, height: 36)
        imageView.image = ListModeView.listIconImage(from: image, pointSize: 16)
        imageView.showsVideoBadge = true
        imageView.layoutSubtreeIfNeeded()

        let badge = imageView.videoBadgeView
        #expect(!badge.isHidden)
        let drawn = NSRect(x: 0, y: 3.5, width: 16, height: 9)
        // Pixel alignment may move each edge by up to half a point.
        let tolerance: CGFloat = 0.5
        #expect(badge.frame.minX >= drawn.minX - tolerance)
        #expect(badge.frame.maxX <= drawn.maxX + tolerance)
        #expect(badge.frame.minY >= drawn.minY - tolerance)
        #expect(badge.frame.maxY <= drawn.maxY + tolerance)
    }

    @Test("A row of the list mode shows the generated 16:9 image as a 16 x 9 pt leading icon (FR-048)")
    func rowIconKeepsAspectRatio() async throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("list-icon-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([0]).write(to: folder.appendingPathComponent("wide.jpg"))

        let suite = "Folzio.ListIconImage.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let model = BrowserModel(kindNames: l10n.kindNames, lister: DirectoryLister(kindNames: l10n.kindNames),
            decoder: ImageDecoder(), cache: DecodedImageCache(), settings: settings)
        model.setNavigationRoots([folder])
        await model.selectFolder(folder)
        let row = try #require(model.listing.files.firstIndex { $0.name == "wide.jpg" })

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let list = ListModeView(model: model, provider: WideThumbnailProvider())
        list.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        window.contentView?.addSubview(list)
        list.layoutSubtreeIfNeeded()

        let table = try #require(findTable(in: list))
        let column = table.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
        let cell = try #require(table.view(atColumn: column, row: row, makeIfNecessary: true) as? NSTableCellView)
        let expected = NSSize(width: 16, height: 9)
        let deadline = ContinuousClock.now + .seconds(3)
        while cell.imageView?.image?.size != expected, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(cell.imageView?.image?.size == expected)
    }

    private func findTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { findTable(in: $0) }.first
    }
}

/// Returns a 64 x 36 px image for every file, like a generated 16:9 thumbnail.
private struct WideThumbnailProvider: ThumbnailProviding {
    func thumbnail(for url: URL, pointSize: Double, scale: Double, version: FileContentVersion?) async -> CGImage? {
        let context = CGContext(
            data: nil,
            width: 64,
            height: 36,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        return context?.makeImage()
    }

    func cancel(for url: URL, pointSize: Double, scale: Double, version: FileContentVersion?) {}
}
