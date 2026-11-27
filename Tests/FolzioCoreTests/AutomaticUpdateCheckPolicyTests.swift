import Foundation
import Testing
import FolzioCore

@Suite("Automatic update check policy")
struct AutomaticUpdateCheckPolicyTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let day: TimeInterval = 24 * 60 * 60
    private static let current = AppVersion(major: 1, minor: 7, patch: 0)
    private static let v180 = AppVersion(major: 1, minor: 8, patch: 0)
    private static let v190 = AppVersion(major: 1, minor: 9, patch: 0)

    private static func available(_ latest: AppVersion) -> UpdateCheckResult {
        .updateAvailable(latest: latest, current: current, releasePage: UpdateSource.releasePageURL(for: latest))
    }

    // MARK: - Launch

    @Test("Does nothing at launch without a running version", arguments: [
        AutomaticUpdateCheckSetting.notAsked, .enabled, .disabled,
    ])
    func noVersion(setting: AutomaticUpdateCheckSetting) {
        let action = AutomaticUpdateCheckPolicy.launchAction(
            setting: setting, current: nil, lastCheck: nil, now: Self.now, canPresent: true
        )
        #expect(action == .none)
    }

    @Test("Asks for consent only when the main window can show a dialog")
    func notAsked() {
        #expect(AutomaticUpdateCheckPolicy.launchAction(
            setting: .notAsked, current: Self.current, lastCheck: nil, now: Self.now, canPresent: true
        ) == .askConsent)
        #expect(AutomaticUpdateCheckPolicy.launchAction(
            setting: .notAsked, current: Self.current, lastCheck: nil, now: Self.now, canPresent: false
        ) == .none)
    }

    @Test("Never checks when the user declined", arguments: [nil, Date.distantPast])
    func disabled(lastCheck: Date?) {
        #expect(AutomaticUpdateCheckPolicy.launchAction(
            setting: .disabled, current: Self.current, lastCheck: lastCheck, now: Self.now, canPresent: true
        ) == .none)
    }

    @Test("Checks when enabled and due, whether or not a dialog can be shown now", arguments: [true, false])
    func enabledAndDue(canPresent: Bool) {
        #expect(AutomaticUpdateCheckPolicy.launchAction(
            setting: .enabled, current: Self.current, lastCheck: nil, now: Self.now, canPresent: canPresent
        ) == .check)
        #expect(AutomaticUpdateCheckPolicy.launchAction(
            setting: .enabled, current: Self.current, lastCheck: Self.now.addingTimeInterval(-Self.day),
            now: Self.now, canPresent: canPresent
        ) == .check)
    }

    @Test("Skips the check within 24 hours of the last one")
    func enabledNotDue() {
        #expect(AutomaticUpdateCheckPolicy.launchAction(
            setting: .enabled, current: Self.current, lastCheck: Self.now.addingTimeInterval(-Self.day + 1),
            now: Self.now, canPresent: true
        ) == .none)
    }

    @Test("Is due after exactly 24 hours, before any check, and when the last check is in the future")
    func isDue() {
        #expect(AutomaticUpdateCheckPolicy.isDue(lastCheck: nil, now: Self.now))
        #expect(AutomaticUpdateCheckPolicy.isDue(lastCheck: Self.now.addingTimeInterval(-Self.day), now: Self.now))
        #expect(!AutomaticUpdateCheckPolicy.isDue(lastCheck: Self.now.addingTimeInterval(-Self.day + 1), now: Self.now))
        #expect(!AutomaticUpdateCheckPolicy.isDue(lastCheck: Self.now, now: Self.now))
        #expect(AutomaticUpdateCheckPolicy.isDue(lastCheck: Self.now.addingTimeInterval(1), now: Self.now))
    }

    // MARK: - Automatic Outcome

    @Test("Announces a version not announced before and saves it", arguments: [nil, AppVersion(major: 1, minor: 8, patch: 0)])
    func announcesNewVersion(lastNotified: AppVersion?) {
        let outcome = AutomaticUpdateCheckPolicy.automaticOutcome(
            result: Self.available(Self.v190), lastNotified: lastNotified, canPresent: true, now: Self.now
        )
        #expect(outcome == .init(announces: Self.v190, savesCheckTime: Self.now, savesNotifiedVersion: Self.v190))
    }

    @Test("Does not announce a version already announced or an older one", arguments: [
        AppVersion(major: 1, minor: 8, patch: 0), AppVersion(major: 1, minor: 9, patch: 0),
    ])
    func alreadyAnnounced(lastNotified: AppVersion) {
        let outcome = AutomaticUpdateCheckPolicy.automaticOutcome(
            result: Self.available(Self.v180), lastNotified: lastNotified, canPresent: true, now: Self.now
        )
        #expect(outcome == .init(savesCheckTime: Self.now))
    }

    @Test("Shows and saves nothing when a new version arrives while the user is busy")
    func busy() {
        let outcome = AutomaticUpdateCheckPolicy.automaticOutcome(
            result: Self.available(Self.v190), lastNotified: Self.v180, canPresent: false, now: Self.now
        )
        #expect(outcome == .init())
    }

    @Test("Saves only the check time when up to date", arguments: [true, false])
    func upToDate(canPresent: Bool) {
        let outcome = AutomaticUpdateCheckPolicy.automaticOutcome(
            result: .upToDate(current: Self.current), lastNotified: nil, canPresent: canPresent, now: Self.now
        )
        #expect(outcome == .init(savesCheckTime: Self.now))
    }

    @Test("Shows and saves nothing when the check fails", arguments: [
        UpdateCheckFailure.transport, .httpStatus(403), .httpStatus(404), .responseTooLarge, .malformedResponse,
        .unrecognizedTag("1.8"),
    ])
    func failed(failure: UpdateCheckFailure) {
        let outcome = AutomaticUpdateCheckPolicy.automaticOutcome(
            result: .failed(failure), lastNotified: nil, canPresent: true, now: Self.now
        )
        #expect(outcome == .init())
    }

    @Test("Checks at most once a day across repeated launches that get a result")
    func onceADay() {
        var lastCheck: Date?
        var checks = 0
        for hour in stride(from: 0, to: 72, by: 1) {
            let now = Self.now.addingTimeInterval(TimeInterval(hour) * 3600)
            let action = AutomaticUpdateCheckPolicy.launchAction(
                setting: .enabled, current: Self.current, lastCheck: lastCheck, now: now, canPresent: true
            )
            guard action == .check else { continue }
            checks += 1
            let outcome = AutomaticUpdateCheckPolicy.automaticOutcome(
                result: .upToDate(current: Self.current), lastNotified: nil, canPresent: true, now: now
            )
            lastCheck = outcome.savesCheckTime ?? lastCheck
        }
        #expect(checks == 3)
    }

    @Test("The saved notified version never moves back")
    func notifiedVersion() {
        #expect(AutomaticUpdateCheckPolicy.notifiedVersion(afterAnnouncing: Self.v180, previous: nil) == Self.v180)
        #expect(AutomaticUpdateCheckPolicy.notifiedVersion(afterAnnouncing: Self.v190, previous: Self.v180) == Self.v190)
        #expect(AutomaticUpdateCheckPolicy.notifiedVersion(afterAnnouncing: Self.v180, previous: Self.v190) == Self.v190)
    }
}
