import AppKit
import FolzioCore
import os

/// Logs how long the main thread could not run, for measuring (TAK-129). Off unless enabled, because it wakes the
/// main thread every 10 ms:
///
///     defaults write local.folzio.Folzio FolzioLogMainThreadStalls -bool YES
///
/// The timer runs in the common run loop modes, so stalls while dragging the scroll bar or holding a key are logged
/// too. Messages go to `PerformanceLog` at the debug level.
@MainActor
final class MainThreadStallMonitor {
    static let defaultsKey = "FolzioLogMainThreadStalls"
    private static let interval: TimeInterval = 0.01
    /// Gaps at or above this are logged.
    private static let threshold: Double = 50

    private var timer: Timer?
    private var last = ContinuousClock.now

    /// Starts the monitor when the user default is set.
    func startIfEnabled(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: Self.defaultsKey), timer == nil else { return }
        last = ContinuousClock.now
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        PerformanceLog.logger.debug("[main] stall monitor started")
    }

    private func tick() {
        let elapsed = PerformanceLog.milliseconds(since: last)
        last = ContinuousClock.now
        // One interval is the expected gap; the rest is time the main thread was busy.
        let stall = elapsed - Self.interval * 1_000
        if stall >= Self.threshold {
            PerformanceLog.logger.debug("[main] stall \(stall, format: .fixed(precision: 1)) ms")
        }
    }
}
