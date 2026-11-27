import Foundation

/// The user's answer to the automatic update check question (FR-430, FR-434).
public enum AutomaticUpdateCheckSetting: Equatable, Sendable {
    case notAsked
    case enabled
    case disabled
}

/// Decides what the app does about updates at launch and after an automatic check (FR-430...FR-433).
///
/// Holds no state. The caller passes the current time and whether the main window can show a dialog without
/// interrupting the user (the same condition as opening the keyboard shortcut list: not editing text, no sheet or
/// modal window, not full screen, and no slideshow; EC-296).
public enum AutomaticUpdateCheckPolicy {
    /// The minimum time between automatic checks (FR-431).
    public static let interval: TimeInterval = 24 * 60 * 60

    public enum LaunchAction: Equatable, Sendable {
        case none
        case askConsent
        case check
    }

    /// What to show and save after an automatic check.
    public struct AutomaticOutcome: Equatable, Sendable {
        /// The version to announce with the new-version dialog, or `nil` to show nothing (FR-432, FR-433).
        public var announces: AppVersion?
        /// The time to save as the last automatic check, or `nil` to keep the saved value.
        public var savesCheckTime: Date?
        /// The version to save as the last announced one, or `nil` to keep the saved value.
        public var savesNotifiedVersion: AppVersion?

        public init(announces: AppVersion? = nil, savesCheckTime: Date? = nil, savesNotifiedVersion: AppVersion? = nil) {
            self.announces = announces
            self.savesCheckTime = savesCheckTime
            self.savesNotifiedVersion = savesNotifiedVersion
        }
    }

    /// What to do once the main window is shown at launch.
    ///
    /// - Parameter current: The running version, or `nil` when it is missing or malformed (EC-299).
    public static func launchAction(
        setting: AutomaticUpdateCheckSetting,
        current: AppVersion?,
        lastCheck: Date?,
        now: Date,
        canPresent: Bool
    ) -> LaunchAction {
        guard current != nil else { return .none }
        switch setting {
        case .notAsked:
            return canPresent ? .askConsent : .none
        case .disabled:
            return .none
        case .enabled:
            return isDue(lastCheck: lastCheck, now: now) ? .check : .none
        }
    }

    /// Whether at least `interval` has passed since `lastCheck`. A check time in the future counts as due, so a clock
    /// that was set back does not stop the checks (EC-297).
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        if lastCheck > now { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// What to show and save once an automatic check finishes.
    ///
    /// - A version newer than `lastNotified` is announced when `canPresent`; otherwise nothing is saved, so the next
    ///   launch checks again (EC-296).
    /// - A version already announced, or up to date, saves only the check time and shows nothing.
    /// - A failure saves nothing and shows nothing (FR-433, EC-298).
    public static func automaticOutcome(
        result: UpdateCheckResult,
        lastNotified: AppVersion?,
        canPresent: Bool,
        now: Date
    ) -> AutomaticOutcome {
        switch result {
        case let .updateAvailable(latest, _, _):
            if let lastNotified, latest <= lastNotified {
                return AutomaticOutcome(savesCheckTime: now)
            }
            guard canPresent else { return AutomaticOutcome() }
            return AutomaticOutcome(announces: latest, savesCheckTime: now, savesNotifiedVersion: latest)
        case .upToDate:
            return AutomaticOutcome(savesCheckTime: now)
        case .failed:
            return AutomaticOutcome()
        }
    }

    /// The version to save after the new-version dialog announced `latest`, from either the menu or an automatic
    /// check (FR-432). Never moves back to an older version.
    public static func notifiedVersion(afterAnnouncing latest: AppVersion, previous: AppVersion?) -> AppVersion {
        guard let previous else { return latest }
        return max(latest, previous)
    }
}
