public enum ImportRejection: Error, Sendable, Equatable {
    case notImageOrVideo
    case unsupportedImageFormat
    case unsupportedVideoFormat
    case notRegularFile
    case tooLarge(limit: UInt64)
    case tooManyPixels
    case timedOut(seconds: Int)
    case sourceFailed
}
