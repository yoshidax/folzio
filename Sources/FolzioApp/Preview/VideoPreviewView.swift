import AVFoundation
import AVKit
import AppKit
import FolzioCore
import os

@MainActor
final class VideoPreviewView: NSView {
    private let playerView = AVPlayerView()
    private let performanceSignposter = OSSignposter(
        subsystem: "local.folzio.Folzio",
        category: "Performance"
    )
    private let playback = VideoPlayback()
    /// Returns the player only while a video is loaded.
    private var player: AVPlayer? { playback.player.currentItem == nil ? nil : playback.player }
    private var timeControlObservation: NSKeyValueObservation?
    private var playbackIntervalState: OSSignpostIntervalState?
    private var playbackIntervalStarted = false
    private var playbackGeneration = 0
    var onReadyForTransition: (() -> Void)?
    private var displayObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var tracksTask: Task<Void, Never>?
    private var hasVideoTrack: Bool?
    private var didNotifyTransitionReady = false

    init() {
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    var isPlaying: Bool {
        guard let player else { return false }
        return player.rate != 0
    }

    func configure(url: URL, autoplay: Bool, loop: Bool, fileName: String) {
        configure(asset: AVURLAsset(url: url), autoplay: autoplay, loop: loop, fileName: fileName)
    }

    func configure(asset: AVAsset, autoplay: Bool, loop: Bool, fileName: String) {
        stop()

        playback.load(asset: asset, loop: loop)
        let player = playback.player
        setAccessibilityLabel(fileName)

        let generation = playbackGeneration
        displayObservation = playerView.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.notifyTransitionReady(generation: generation) }
        }
        itemStatusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.notifyTransitionReady(generation: generation) }
        }
        tracksTask = Task { [weak self] in
            let tracks = try? await asset.loadTracks(withMediaType: .video)
            guard !Task.isCancelled, let self, self.playbackGeneration == generation else { return }
            self.hasVideoTrack = tracks.map { !$0.isEmpty }
            self.notifyTransitionReady(generation: generation)
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.handleTimeControlStatusChange(generation: generation)
            }
        }

        if autoplay {
            beginPlaybackIntervalIfNeeded()
            player.play()
        } else {
            player.pause()
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    func stop() {
        playbackGeneration &+= 1
        displayObservation?.invalidate()
        displayObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        tracksTask?.cancel()
        tracksTask = nil
        hasVideoTrack = nil
        didNotifyTransitionReady = false
        endPlaybackInterval()
        playbackIntervalStarted = false

        timeControlObservation?.invalidate()
        timeControlObservation = nil

        // Remove only the item and do not discard AVPlayer (bug: slideshow-video-routing-context-crash).
        playback.unload()
        setAccessibilityLabel("")
    }

    func freezeForTransition() -> (image: CGImage?, videoRect: CGRect) {
        player?.pause()
        let image = playback.currentFrame()
        let rect = image.map {
            AVMakeRect(aspectRatio: CGSize(width: $0.width, height: $0.height), insideRect: playerView.bounds)
        } ?? .zero
        return (image, playerView.convert(rect, to: self))
    }

    private func notifyTransitionReady(generation: Int) {
        guard generation == playbackGeneration, !didNotifyTransitionReady,
              let item = player?.currentItem else { return }
        let ready = item.status == .failed || (item.status == .readyToPlay &&
            (playerView.isReadyForDisplay || hasVideoTrack == false))
        guard ready else { return }
        didNotifyTransitionReady = true
        onReadyForTransition?()
    }

    func togglePlayPause() {
        guard let player else { return }
        if player.rate != 0 {
            player.pause()
        } else {
            beginPlaybackIntervalIfNeeded()
            player.play()
        }
    }

    func seek(by seconds: Double) {
        guard let player,
              let duration = player.currentItem?.duration.seconds,
              let target = VideoPlayback.seekTarget(
                  from: player.currentTime().seconds, by: seconds, duration: duration
              ) else {
            return
        }
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func beginPlaybackIntervalIfNeeded() {
        guard !playbackIntervalStarted else { return }
        playbackIntervalStarted = true
        playbackIntervalState = performanceSignposter.beginInterval("VideoPlaybackStart")
    }

    private func endPlaybackInterval() {
        guard let state = playbackIntervalState else { return }
        playbackIntervalState = nil
        performanceSignposter.endInterval("VideoPlaybackStart", state)
    }

    private func handleTimeControlStatusChange(generation: Int) {
        guard generation == playbackGeneration,
              let player,
              player.timeControlStatus == .playing else {
            return
        }
        endPlaybackInterval()
    }

    private func setup() {
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        playerView.player = playback.player
        addSubview(playerView)

        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }
}
