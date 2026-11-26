import AppKit
import FolzioCore
import FolzioLocalization
import Testing
@testable import FolzioApp

@Suite("Thumbnail video badge", .serialized)
@MainActor
struct ThumbnailVideoBadgeTests {
    private static let video = ListItemKind.media(.mp4)

    private func file(kind: ListItemKind) -> MediaFile {
        let name: String
        switch kind {
        case .media(.mp4): name = "clip.mp4"
        case .media: name = "photo.jpg"
        default: name = "Album"
        }
        return MediaFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
    }

    private func frameImage(width: Int = 160, height: Int = 90) throws -> CGImage {
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

    /// Shows a thumbnail item of the given size in a window.
    private func withItem(
        size: NSSize = NSSize(width: 160, height: 196),
        body: (ThumbnailItemView) throws -> Void
    ) rethrows {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let item = ThumbnailItemView()
        item.view.frame = NSRect(origin: .zero, size: size)
        window.contentView?.addSubview(item.view)
        try body(item)
    }

    @Test("A video gets the badge only after its frame arrives, and loses it on reuse (US95-AS1, US95-AS4)")
    func videoBadgeLifecycle() throws {
        let image = try frameImage()
        withItem { item in
            item.configure(with: file(kind: Self.video), iconPointSize: 16)
            #expect(!item.showsVideoBadge)

            item.setThumbnailImage(image)
            #expect(item.showsVideoBadge)

            item.prepareForReuse()
            #expect(!item.showsVideoBadge)
        }
    }

    @Test(
        "Images, folders, zip files, and the parent row get no badge (US95-AS2, FR-417)",
        arguments: [ListItemKind.media(.jpeg), .media(.png), .folder, .archive, .directory, .parent]
    )
    func noBadge(kind: ListItemKind) throws {
        let image = try frameImage()
        withItem { item in
            item.configure(with: file(kind: kind), iconPointSize: 16)
            item.setThumbnailImage(image)
            #expect(!item.showsVideoBadge)
        }
    }

    @Test("The badge diameter is 10 pt at 48 pt and 40 pt at 512 pt for a 16:9 video (SC-240)")
    func diameterAtThumbnailSizes() throws {
        let image = try frameImage()
        for (width, diameter) in [(CGFloat(48), CGFloat(10)), (512, 40)] {
            try withItem(size: NSSize(width: width, height: width + 36)) { item in
                item.configure(with: file(kind: Self.video), iconPointSize: 16)
                item.setThumbnailImage(image)
                item.view.layoutSubtreeIfNeeded()
                let imageView = try #require(item.imageView as? VideoBadgeImageView)
                let badge = imageView.videoBadgeView
                #expect(!badge.isHidden)
                // Pixel alignment may move each edge by up to half a point.
                #expect(abs(badge.frame.width - diameter) <= 1, "width \(width)")
                #expect(abs(badge.frame.height - diameter) <= 1, "width \(width)")
            }
        }
    }

    @Test("Videos read as video thumbnails and other media as thumbnails (FR-419, US95-AS10)")
    func accessibilityLabels() throws {
        let image = try frameImage()
        withItem { item in
            item.configure(with: file(kind: Self.video), iconPointSize: 16)
            #expect(item.imageView?.accessibilityLabel() == l10n.text(.a11yVideoThumbnail))
            item.setThumbnailImage(image)
            #expect(item.imageView?.accessibilityLabel() == l10n.text(.a11yVideoThumbnail))

            item.prepareForReuse()
            item.configure(with: file(kind: .media(.jpeg)), iconPointSize: 16)
            #expect(item.imageView?.accessibilityLabel() == l10n.text(.a11yThumbnail))
            item.setThumbnailImage(image)
            #expect(item.imageView?.accessibilityLabel() == l10n.text(.a11yThumbnail))
        }
    }
}
