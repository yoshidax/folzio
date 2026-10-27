import CoreGraphics
import Foundation
import Testing
@testable import FolzioCore
import FixtureKit

@Suite("BrowserModelVideo")
struct BrowserModelVideoTests {
    @Test("Selecting a video enters the video state with the configured playback options")
    @MainActor
    func exposesPlaybackOptions() async {
        let folder = URL(fileURLWithPath: "/tmp/video-\(UUID().uuidString)", isDirectory: true)
        let video = file("clip.mp4", in: folder)
        let lister = VideoFakeLister(responses: [folder: [video]])

        let suite = "BrowserModelVideoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "playback.autoplay")
        defaults.set(true, forKey: "playback.loop")

        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: lister,
            decoder: VideoFakeDecoder(),
            cache: DecodedImageCache(costLimitBytes: 1_000_000),
            settings: SettingsStore(defaults: defaults)
        )

        await model.selectFolder(folder)
        model.select([video.url], focused: video.url)

        guard case let .video(url) = model.preview else {
            Issue.record("preview is not video")
            return
        }
        #expect(url == video.url)
        #expect(model.playbackRequest == PlaybackOptions(autoplay: false, loop: true))
    }

    @Test("Moving from a video to an image increments the stop signal first")
    @MainActor
    func emitsStopSignal() async {
        let folder = URL(fileURLWithPath: "/tmp/video-\(UUID().uuidString)", isDirectory: true)
        let video = file("clip.mov", in: folder)
        let image = file("photo.jpg", in: folder)
        let lister = VideoFakeLister(responses: [folder: [video, image]])

        let suite = "BrowserModelVideoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: lister,
            decoder: VideoFakeDecoder(),
            cache: DecodedImageCache(costLimitBytes: 1_000_000),
            settings: SettingsStore(defaults: defaults)
        )

        await model.selectFolder(folder)
        model.select([video.url], focused: video.url)
        let baseline = model.stopPlaybackSignal
        model.select([image.url], focused: image.url)

        #expect(model.stopPlaybackSignal == baseline + 1)

        let isImage = await waitUntil {
            if case .image = model.preview { return true }
            return false
        }
        #expect(isImage)
    }

    @Test("Hiding the playing video with the media type filter increments the stop signal and clears the preview")
    @MainActor
    func filterHidingPlayingVideoStopsPlayback() async {
        let folder = URL(fileURLWithPath: "/tmp/video-\(UUID().uuidString)", isDirectory: true)
        let video = file("clip.mov", in: folder)
        let image = file("photo.jpg", in: folder)
        let lister = VideoFakeLister(responses: [folder: [video, image]])

        let suite = "BrowserModelVideoTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: lister,
            decoder: VideoFakeDecoder(),
            cache: DecodedImageCache(costLimitBytes: 1_000_000),
            settings: SettingsStore(defaults: defaults)
        )

        await model.selectFolder(folder)
        model.select([video.url], focused: video.url)
        let baseline = model.stopPlaybackSignal
        model.setMediaTypeFilter(MediaTypeFilter(imagesOnly: true))

        #expect(model.stopPlaybackSignal == baseline + 1)
        if case .empty = model.preview {
        } else {
            Issue.record("preview is not empty")
        }
        #expect(model.selection.focused == nil)
        #expect(model.listing.files.map(\.name) == ["photo.jpg"])
        #expect(model.selection.selected.isEmpty)
    }

    @MainActor
    private func file(_ name: String, in folder: URL) -> MediaFile {
        MediaFile(
            url: folder.appendingPathComponent(name),
            name: name,
            kind: .media(MediaKind(fileExtension: (name as NSString).pathExtension) ?? .jpeg),
            typeDescription: name,
            creationDate: nil,
            fileSize: 0
        )
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private actor VideoFakeLister: DirectoryListing {
    private let responses: [URL: [MediaFile]]

    init(responses: [URL: [MediaFile]]) {
        self.responses = responses
    }

    func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] {
        guard let files = responses[folder] else { throw ListingError.notFound }
        return files
    }

    func subfolders(of folder: URL) async throws(ListingError) -> [URL] {
        []
    }
}

private struct VideoFakeDecoder: ImageDecoding {
    func decode(_ url: URL, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return DecodedImage(
            cgImage: context.makeImage()!,
            pixelSize: CGSize(width: 2, height: 2),
            originalPixelSize: CGSize(width: 2, height: 2),
            byteCost: 16
        )
    }

    func isAnimated(_ url: URL) -> Bool { false }

    func decode(data: Data, maxPixelSize: Int) async throws(DecodeError) -> DecodedImage {
        try await decode(URL(fileURLWithPath: "/"), maxPixelSize: maxPixelSize)
    }

    func isAnimated(data: Data) -> Bool { false }
}
