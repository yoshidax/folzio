import AVFoundation
import CoreGraphics
import CoreVideo
import VideoToolbox

/// `AVPlayer` for preview video playback and loop handling (FR-031, FR-033).
/// Creates a single `AVPlayer` and switches videos by replacing the item.
/// Recreating `AVPlayer` on every switch repeatedly creates and destroys routing contexts during the slideshow,
/// which crashes due to a CoreMedia internal race (bug: slideshow-video-routing-context-crash).
/// Looping does not use `AVPlayerLooper`; it seeks one item back to the start at the end.
/// `AVPlayerLooper` duplicates and switches items, so skipping past the end with AVPlayerView's 15-second skip
/// stops the video (bug: preview-skip-forward-frame-freeze).
@MainActor
public final class VideoPlayback {
    public let player = AVPlayer()
    private var endObserver: NSObjectProtocol?
    private var videoOutput: AVPlayerItemVideoOutput?

    public init() {}

    /// Removes the previous item and installs the item for `asset`. The caller decides when to play or pause.
    public func load(asset: AVAsset, loop: Bool) {
        unload()
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        videoOutput = output
        player.replaceCurrentItem(with: item)

        guard loop else {
            player.actionAtItemEnd = .pause
            return
        }
        // Return to the start instead of stopping at the end. The rate is unchanged, so playback continues when
        // playing and stays paused at the start when paused.
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak player] _ in
            MainActor.assumeIsolated {
                player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }

    /// Stops observing the end, stops playback, and removes the item. `AVPlayer` is reused by the next `load`.
    public func unload() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        player.pause()
        if let videoOutput, let item = player.currentItem {
            item.remove(videoOutput)
        }
        videoOutput = nil
        player.replaceCurrentItem(with: nil)
    }

    /// Captures one frame at the current position regardless of whether a new frame is available.
    public func currentFrame() -> CGImage? {
        guard let videoOutput,
              let buffer = videoOutput.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil)
        else { return nil }
        var image: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image) == 0 else { return nil }
        return image
    }

    /// Returns the position moved by `seconds` from the current position, clamped to `[0, duration]`. Returns nil
    /// when the position or duration is not finite.
    public nonisolated static func seekTarget(from current: Double, by seconds: Double, duration: Double) -> Double? {
        guard duration.isFinite, duration > 0, current.isFinite else { return nil }
        return min(max(0, current + seconds), duration)
    }
}
