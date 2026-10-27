import AppKit
import FolzioCore
import os

/// Normal presentation before starting the slideshow and the state restored after it ends. Kept only in the app.
struct SlideshowRestoreState {
    let normalPaneLayout: PaneLayout
    let normalFocusedPane: Pane?
    let threePaneWidths: [Double]?
}

@MainActor
protocol SlideshowCoordinatorDelegate: AnyObject {
    var slideshowFiles: [MediaFile] { get }
    var slideshowSelectedURLs: Set<URL> { get }
    var slideshowFocusedURL: URL? { get }
    var slideshowListingIsLoading: Bool { get }
    func slideshowPrepareForStart() -> Bool
    func slideshowSynchronizeSelection(to url: URL) -> Bool
    func slideshowMoveFocus(_ move: FocusMove)
    func slideshowFocusPreview()
    func slideshowRestoreAfterStop(completion: @escaping @MainActor () -> Void)
    func slideshowDiscardRestore()
    func slideshowAcceptsKeyEvent(_ event: NSEvent) -> Bool
    func slideshowHasPendingKeyEvent() -> Bool
    func slideshowAvailabilityDidChange()
    func slideshowBeginTransition(to url: URL, current: URL?, effect: SlideshowTransitionEffect)
    func slideshowCancelTransition()
}

/// App-side driver that arbitrates the configured interval deadline, arrow and Esc input, and pending automatic
/// advance. Does not keep a playlist; determines the target on each advance from Core's `SlideshowSequence`
/// and the latest listing.
@MainActor
final class SlideshowCoordinator {
    weak var delegate: SlideshowCoordinatorDelegate?

    private(set) var isActive = false
    private(set) var isRestoring = false

    private let settings: SettingsStore
    private var session = SlideshowSession()
    private var deadlineTask: Task<Void, Never>?
    private let clock = ContinuousClock()
    private let signposter = OSSignposter(
        subsystem: "local.folzio.Folzio",
        category: "Performance"
    )
    private var startInterval: OSSignpostIntervalState?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var canStart: Bool {
        !isActive && !isRestoring && delegate != nil
    }

    func start() {
        guard canStart, let delegate else { return }
        guard let target = SlideshowSequence.startTarget(
            in: delegate.slideshowFiles,
            selected: delegate.slideshowSelectedURLs,
            focused: delegate.slideshowFocusedURL
        ) else {
            return
        }
        guard delegate.slideshowPrepareForStart() else { return }

        isActive = true
        startInterval = signposter.beginInterval("SlideshowStart")
        _ = delegate.slideshowSynchronizeSelection(to: target)
        delegate.slideshowFocusPreview()

        let started = session.start(now: clock.now, interval: settings.slideshow.interval)
        assert(started, "start is only valid from idle")
        guard started else {
            isActive = false
            isRestoring = true
            endStartInterval()
            delegate.slideshowRestoreAfterStop { [weak self] in
                self?.isRestoring = false
                self?.delegate?.slideshowAvailabilityDidChange()
            }
            return
        }

        delegate.slideshowAvailabilityDidChange()
        schedule()
    }

    /// Stops and restores when active. Sets `isRestoring` while restoration waits for full screen to exit.
    func stop() {
        guard isActive else { return }
        delegate?.slideshowCancelTransition()
        isActive = false
        isRestoring = true
        cancelDeadline()
        _ = session.stop()
        endStartInterval()
        signposter.emitEvent("SlideshowStop")
        delegate?.slideshowAvailabilityDidChange()

        guard let delegate else {
            isRestoring = false
            return
        }
        delegate.slideshowRestoreAfterStop { [weak self] in
            guard let self else { return }
            self.isRestoring = false
            self.delegate?.slideshowAvailabilityDidChange()
        }
    }

    /// Discards resources without waiting for the restore display when closing the window or quitting.
    func stopImmediately() {
        guard isActive || isRestoring else { return }
        delegate?.slideshowCancelTransition()
        isActive = false
        isRestoring = false
        cancelDeadline()
        _ = session.stop()
        endStartInterval()
        signposter.emitEvent("SlideshowStop")
        delegate?.slideshowDiscardRestore()
        delegate?.slideshowAvailabilityDidChange()
    }

    /// Immediately before replacing the location (FR-126). Stops advancing synchronously without waiting to fix the
    /// restore target.
    func handleWillReplaceLocation() {
        guard isActive else { return }
        stop()
    }

    /// Processes a key from the local monitor only when the slideshow accepts it.
    /// Esc stops; arrows restart the deadline and navigate the hidden file list. Returns `<`, `>`, and similar keys to
    /// the existing handling.
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard isActive, !isRestoring,
              let delegate,
              delegate.slideshowAcceptsKeyEvent(event) else {
            return false
        }

        if event.keyCode == 53 {
            stop()
            return true
        }

        guard let move = Self.focusMove(for: event) else { return false }
        delegate.slideshowCancelTransition()
        guard session.arrow(now: clock.now, interval: settings.slideshow.interval) else { return false }
        signposter.emitEvent("SlideshowArrow")
        delegate.slideshowMoveFocus(move)
        schedule()
        return true
    }

    /// Called after listing or selection changes. Ends automatically only when there are zero candidates, except while
    /// loading. Does not change the selection just because the current target disappeared; the next deadline selects
    /// from the beginning again.
    func listingDidChange() {
        guard isActive, !isRestoring, let delegate else { return }
        guard !SlideshowSequence.hasMedia(in: delegate.slideshowFiles),
              !delegate.slideshowListingIsLoading else {
            return
        }
        stop()
    }

    private func schedule() {
        cancelDeadline()
        guard isActive, let deadline = session.deadline else { return }

        let generation = session.generation
        let clock = self.clock
        deadlineTask = Task { @MainActor [weak self] in
            // If the deadline is in the past, return immediately and arbitrate pending work and key input in the next
            // run loop.
            try? await clock.sleep(until: deadline, tolerance: .zero)
            guard !Task.isCancelled,
                  let self,
                  self.isActive,
                  !self.isRestoring,
                  self.session.generation == generation else {
                return
            }
            self.handleTimeout(generation: generation)
        }
    }

    private func cancelDeadline() {
        deadlineTask?.cancel()
        deadlineTask = nil
    }

    private func handleTimeout(generation: Int) {
        guard isActive, !isRestoring, session.generation == generation else { return }
        guard session.timeout(now: clock.now) else { return }

        // When deadline expiry and key input are queued in the same run loop, dispatch accepted Esc and arrow keys to
        // AppKit first. Only mark pending work here and commit it in the next run loop.
        RunLoop.main.perform(inModes: [.default, .eventTracking, .modalPanel]) { [weak self] in
            MainActor.assumeIsolated {
                self?.commitPendingDue(generation: generation)
            }
        }
    }

    private func commitPendingDue(generation: Int) {
        guard isActive, !isRestoring,
              let delegate,
              session.generation == generation else {
            return
        }
        // If an accepted key is still unhandled, defer this automatic advance. The key handling restarts the deadline
        // or stops.
        if delegate.slideshowHasPendingKeyEvent() {
            return
        }

        let options = settings.slideshow
        guard session.commit(now: clock.now, interval: options.interval) else { return }
        switch SlideshowSequence.advance(
            in: delegate.slideshowFiles,
            focused: delegate.slideshowFocusedURL,
            repeats: options.repeats
        ) {
        case .target(let target):
            let current = delegate.slideshowFocusedURL
            let effect = options.transition.effective(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            if target != current, effect != .none {
                delegate.slideshowBeginTransition(to: target, current: current, effect: effect)
                signposter.emitEvent("SlideshowTransitionBegin")
            } else {
                delegate.slideshowCancelTransition()
            }
            let changed = delegate.slideshowSynchronizeSelection(to: target)
            if changed {
                signposter.emitEvent("SlideshowAdvance")
            } else {
                delegate.slideshowCancelTransition()
            }
            schedule()
        case .finish, .empty:
            stop()
        }
    }

    private func endStartInterval() {
        guard let startInterval else { return }
        signposter.endInterval("SlideshowStart", startInterval)
        self.startInterval = nil
    }

    private static func focusMove(for event: NSEvent) -> FocusMove? {
        switch event.specialKey {
        case .leftArrow:
            return .left
        case .rightArrow:
            return .right
        case .upArrow:
            return .up
        case .downArrow:
            return .down
        default:
            return nil
        }
    }
}
