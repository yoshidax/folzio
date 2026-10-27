import AVFoundation
import CoreVideo
import Foundation

public enum VideoFixtures {
    /// - Parameters:
    ///   - fastStart: When true, places the playback metadata (moov) at the start of the file.
    ///   - averageBitRate: Sets the average bit rate (bps) when provided.
    ///   - noisyFrames: When true, uses a noise pattern that changes every frame (to create a large file).
    public static func mp4(
        at url: URL, width: Int = 640, height: Int = 360, seconds: Double = 1.5,
        fastStart: Bool = false, averageBitRate: Int? = nil, noisyFrames: Bool = false
    ) throws {
        try write(
            at: url, fileType: .mp4, width: width, height: height, seconds: seconds,
            fastStart: fastStart, averageBitRate: averageBitRate, noisyFrames: noisyFrames
        )
    }

    public static func mov(
        at url: URL, width: Int = 640, height: Int = 360, seconds: Double = 1.5,
        fastStart: Bool = false, averageBitRate: Int? = nil, noisyFrames: Bool = false
    ) throws {
        try write(
            at: url, fileType: .mov, width: width, height: height, seconds: seconds,
            fastStart: fastStart, averageBitRate: averageBitRate, noisyFrames: noisyFrames
        )
    }

    private static func write(
        at url: URL, fileType: AVFileType, width: Int, height: Int, seconds: Double,
        fastStart: Bool, averageBitRate: Int?, noisyFrames: Bool
    ) throws {
        try? FileManager.default.removeItem(at: url)

        let writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        writer.shouldOptimizeForNetworkUse = fastStart
        var outputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        if let averageBitRate {
            outputSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: averageBitRate,
            ]
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )

        guard writer.canAdd(input) else {
            throw FixtureError.videoWriterFailed("cannot add video input")
        }
        writer.add(input)

        guard writer.startWriting() else {
            throw FixtureError.videoWriterFailed(writer.error?.localizedDescription ?? "startWriting")
        }
        writer.startSession(atSourceTime: .zero)

        let noiseTable = noisyFrames ? makeNoiseTable(width: width, height: height) : []
        let framesPerSecond: Int32 = 30
        let frameCount = max(1, Int(seconds * Double(framesPerSecond)))

        for index in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }

            var pixelBuffer: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            }
            guard let buffer = pixelBuffer else {
                throw FixtureError.cannotCreatePixelBuffer
            }

            if noisyFrames {
                fillNoise(buffer, frame: index, table: noiseTable)
            } else {
                fill(buffer, frame: index, frameCount: frameCount)
            }

            let time = CMTime(value: CMTimeValue(index), timescale: framesPerSecond)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw FixtureError.videoWriterFailed(writer.error?.localizedDescription ?? "append")
            }
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            semaphore.signal()
        }
        semaphore.wait()

        guard writer.status == .completed else {
            throw FixtureError.videoWriterFailed(writer.error?.localizedDescription ?? "finishWriting")
        }
    }

    private static func fill(_ buffer: CVPixelBuffer, frame: Int, frameCount: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let width = CVPixelBufferGetWidth(buffer)

        let barX = (frame * width / max(1, frameCount)) % max(1, width)
        let barWidth = max(8, width / 8)

        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                let distance = abs(x - barX)
                let inBar = distance < barWidth / 2
                row[offset] = inBar ? 230 : 60
                row[offset + 1] = inBar ? 120 : 40
                row[offset + 2] = inBar ? 40 : 30
                row[offset + 3] = 255
            }
        }
    }

    /// Pseudo-random sequence (xorshift64) twice the length of one frame. Reads from a different position each
    /// frame.
    private static func makeNoiseTable(width: Int, height: Int) -> [UInt8] {
        let count = width * height * 4 * 2
        var table = [UInt8](repeating: 0, count: count)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        table.withUnsafeMutableBytes { raw in
            let words = raw.bindMemory(to: UInt64.self)
            for index in 0..<words.count {
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                words[index] = state
            }
        }
        return table
    }

    /// Fills the buffer by copying the noise table from a different position each frame (fast even in debug builds;
    /// hard to compress and reaches a high bit rate).
    private static func fillNoise(_ buffer: CVPixelBuffer, frame: Int, table: [UInt8]) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetWidth(buffer) * 4
        let slack = table.count - rowBytes * height
        let start = (frame &* 104_729) % max(1, slack)
        table.withUnsafeBytes { source in
            for y in 0..<height {
                memcpy(base + y * bytesPerRow, source.baseAddress! + start + y * rowBytes, rowBytes)
            }
        }
    }
}
