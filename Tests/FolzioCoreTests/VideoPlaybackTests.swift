import AVFoundation
import Foundation
import Testing
@testable import FixtureKit
@testable import FolzioCore

@Suite("VideoPlayback.seekTarget")
struct VideoPlaybackSeekTargetTests {
    @Test("Clamps ±15 seconds and +5 seconds to [0, duration] for a 5-second video")
    func clampsToDuration() {
        #expect(VideoPlayback.seekTarget(from: 2, by: 15, duration: 5) == 5)
        #expect(VideoPlayback.seekTarget(from: 2, by: -15, duration: 5) == 0)
        #expect(VideoPlayback.seekTarget(from: 2, by: 5, duration: 5) == 5)
        #expect(VideoPlayback.seekTarget(from: 2, by: 1.5, duration: 5) == 3.5)
    }

    @Test("Returns nil when the position or duration is not finite")
    func undefined() {
        #expect(VideoPlayback.seekTarget(from: .nan, by: 5, duration: 5) == nil)
        #expect(VideoPlayback.seekTarget(from: 0, by: 5, duration: .nan) == nil)
        #expect(VideoPlayback.seekTarget(from: 0, by: 5, duration: 0) == nil)
    }
}

/// `VideoFixtures` blocks its thread while writing. Running in parallel can exhaust the cooperative thread pool
/// and hang, so run serially.
@Suite("VideoPlayback", .serialized)
@MainActor
struct VideoPlaybackTests {
    private func makeVideo(seconds: Double) throws -> (directory: URL, video: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoPlaybackTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("clip.mp4")
        try VideoFixtures.mp4(at: video, seconds: seconds)
        return (directory, video)
    }

    private func waitUntilReady(_ player: AVPlayer) async throws {
        for _ in 0..<100 where player.currentItem?.status != .readyToPlay {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(player.currentItem?.status == .readyToPlay)
    }

    /// bug: preview-skip-forward-frame-freeze. Seeking past the end continues playing from the start of the same
    /// item instead of switching to another item.
    @Test("With looping, seeking past the end continues from the start of the same item")
    func loopSeekPastEndKeepsItem() async throws {
        let (directory, video) = try makeVideo(seconds: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        let playback = VideoPlayback()
        playback.load(asset: AVURLAsset(url: video), loop: true)
        defer { playback.unload() }
        let player = playback.player
        let item = try #require(player.currentItem)
        try await waitUntilReady(player)

        player.play()
        try await Task.sleep(for: .milliseconds(300))
        // Seek past the duration without rounding, as AVPlayerView's "Skip Forward 15 Seconds" does.
        await player.seek(to: CMTime(seconds: 17, preferredTimescale: 600))
        try await Task.sleep(for: .milliseconds(700))

        #expect(player.currentItem === item)
        #expect(player.rate != 0)
        let current = player.currentTime().seconds
        #expect(current > 0 && current < 2)
    }

    @Test("With looping, seeking before the start continues with the same item")
    func loopSeekBeforeStartKeepsItem() async throws {
        let (directory, video) = try makeVideo(seconds: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        let playback = VideoPlayback()
        playback.load(asset: AVURLAsset(url: video), loop: true)
        defer { playback.unload() }
        let player = playback.player
        let item = try #require(player.currentItem)
        try await waitUntilReady(player)

        player.play()
        try await Task.sleep(for: .milliseconds(300))
        await player.seek(to: CMTime(seconds: -15, preferredTimescale: 600))
        try await Task.sleep(for: .milliseconds(500))

        #expect(player.currentItem === item)
        #expect(player.rate != 0)
        #expect(player.currentTime().seconds > 0)
    }

    @Test("Without looping, seeking past the end stops at the end")
    func noLoopStopsAtEnd() async throws {
        let (directory, video) = try makeVideo(seconds: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        let playback = VideoPlayback()
        playback.load(asset: AVURLAsset(url: video), loop: false)
        defer { playback.unload() }
        let player = playback.player
        try await waitUntilReady(player)

        player.play()
        try await Task.sleep(for: .milliseconds(300))
        await player.seek(to: CMTime(seconds: 17, preferredTimescale: 600))
        try await Task.sleep(for: .milliseconds(500))

        #expect(player.rate == 0)
        #expect(player.currentTime().seconds > 1.9)
    }

    /// bug: slideshow-video-routing-context-crash. Recreating AVPlayer on every video switch repeatedly creates and
    /// destroys routing contexts during the slideshow, crashing due to a CoreMedia internal race.
    @Test("Keeps using the same AVPlayer instance when replacing videos")
    func reusesPlayerAcrossLoads() async throws {
        let (directory, video) = try makeVideo(seconds: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        let playback = VideoPlayback()
        defer { playback.unload() }
        let player = playback.player

        playback.load(asset: AVURLAsset(url: video), loop: true)
        let first = try #require(player.currentItem)
        playback.unload()
        #expect(player.currentItem == nil)
        playback.load(asset: AVURLAsset(url: video), loop: false)
        let second = try #require(player.currentItem)

        #expect(playback.player === player)
        #expect(second !== first)
    }

    @Test("A replaced item follows the loop setting at that time and is not rewound by the previous item's end notification")
    func reloadFollowsNewLoopSetting() async throws {
        let (directory, video) = try makeVideo(seconds: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        let playback = VideoPlayback()
        defer { playback.unload() }
        let player = playback.player

        playback.load(asset: AVURLAsset(url: video), loop: true)
        #expect(player.actionAtItemEnd == .none)
        let first = try #require(player.currentItem)

        playback.load(asset: AVURLAsset(url: video), loop: false)
        #expect(player.actionAtItemEnd == .pause)
        try await waitUntilReady(player)
        await player.seek(to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)

        // If the previous item's loop observer remains, the new item seeks back to the start here.
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: first)
        try await Task.sleep(for: .milliseconds(300))
        #expect(player.currentTime().seconds > 0.9)

        playback.load(asset: AVURLAsset(url: video), loop: true)
        #expect(player.actionAtItemEnd == .none)
    }

    @Test("unload stops playback and removes the item")
    func unloadStopsAndClearsItem() async throws {
        let (directory, video) = try makeVideo(seconds: 2)
        defer { try? FileManager.default.removeItem(at: directory) }

        let playback = VideoPlayback()
        let player = playback.player
        playback.load(asset: AVURLAsset(url: video), loop: true)
        try await waitUntilReady(player)
        player.play()

        playback.unload()

        #expect(player.rate == 0)
        #expect(player.currentItem == nil)
    }
    @Test("Attaches one frame output per item and removes it on replacement and unload")
    func transitionOutputLifecycle() throws {
        let (directory, video) = try makeVideo(seconds: 1)
        defer { try? FileManager.default.removeItem(at: directory) }
        let playback = VideoPlayback()
        defer { playback.unload() }
        let player = playback.player
        #expect(playback.currentFrame() == nil)
        playback.load(asset: AVURLAsset(url: video), loop: false)
        let first = try #require(player.currentItem)
        #expect(first.outputs.count == 1)
        #expect(first.outputs.first is AVPlayerItemVideoOutput)
        playback.load(asset: AVURLAsset(url: video), loop: true)
        let second = try #require(player.currentItem)
        #expect(first.outputs.isEmpty)
        #expect(second.outputs.count == 1)
        #expect(second.outputs.first is AVPlayerItemVideoOutput)
        #expect(playback.player === player)
        playback.unload()
        #expect(second.outputs.isEmpty)
        #expect(playback.currentFrame() == nil)
    }
}
