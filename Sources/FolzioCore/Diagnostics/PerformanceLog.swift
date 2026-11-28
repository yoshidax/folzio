import Foundation
import os

/// Debug messages for measuring thumbnails, previews, and main-thread work (TAK-129). They use the debug level, so
/// the system does not store them and they cost little unless someone streams them:
///
///     log stream --level debug --style compact \
///         --predicate 'subsystem == "local.folzio.Folzio" AND category == "Performance"'
///
/// File names are logged as hashes, so the same file can be followed across messages without showing its name.
public enum PerformanceLog {
    public static let subsystem = "local.folzio.Folzio"

    public static var logger: Logger {
        Logger(subsystem: subsystem, category: "Performance")
    }

    /// Milliseconds since `start`.
    public static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
}
