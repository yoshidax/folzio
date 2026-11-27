import AppKit
import FolzioCore
import FolzioLocalization

/// A dialog of the update check (US96...US98).
enum UpdateDialog: Equatable {
    case updateAvailable(latest: AppVersion, current: AppVersion)
    case upToDate(current: AppVersion)
    case failed
    case consent
}

/// The button the user chose. `first` is the default button (Return); `second` is the one that Esc presses.
enum UpdateDialogResponse: Equatable {
    case first
    case second
}

/// Runs update checks from the menu and at launch, and shows their dialogs (FR-422...FR-433).
///
/// The checks themselves are in `UpdateChecker` and `AutomaticUpdateCheckPolicy`. Dialogs are app-wide alerts, not
/// sheets, so they appear whatever the main window is doing (FR-428, EC-295). Tests replace the closures.
@MainActor
final class UpdateCheckController {
    var presentDialog: @MainActor (UpdateDialog) -> UpdateDialogResponse = { dialog in
        NSApp.activate()
        let response = UpdateCheckController.makeAlert(for: dialog).runModal()
        return response == .alertFirstButtonReturn ? .first : .second
    }

    var openURL: @MainActor (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    var now: @MainActor () -> Date = { Date() }

    /// Whether a dialog would interrupt the user: false while editing text, with a sheet or modal window, in full
    /// screen, or during a slideshow (EC-296).
    var canPresent: @MainActor () -> Bool = { true }

    /// The running version, or `nil` when it is missing or malformed (FR-422, EC-299).
    let currentVersion: AppVersion?

    private let settings: SettingsStore
    private let transport: UpdateTransport

    private(set) var isChecking = false

    /// The running check. Tests await it.
    private(set) var checkTask: Task<Void, Never>?

    init(
        currentVersion: AppVersion?,
        settings: SettingsStore = SettingsStore(),
        transport: @escaping UpdateTransport = LiveUpdateTransport.send
    ) {
        self.currentVersion = currentVersion
        self.settings = settings
        self.transport = transport
    }

    /// Whether "Check for Updates…" is enabled (FR-422, EC-291).
    var canCheck: Bool {
        currentVersion != nil && !isChecking
    }

    /// Runs a check chosen from the menu, and shows its result whatever it is (US96, US97).
    func checkFromMenu() {
        guard let currentVersion, !isChecking else { return }
        start(current: currentVersion, automatic: false)
    }

    /// Asks for consent or runs the automatic check, once the main window is shown at launch (FR-430, FR-431).
    func performLaunchAction() {
        let action = AutomaticUpdateCheckPolicy.launchAction(
            setting: settings.automaticUpdateCheck,
            current: currentVersion,
            lastCheck: settings.lastAutomaticUpdateCheck,
            now: now(),
            canPresent: canPresent()
        )
        switch action {
        case .none:
            return
        case .askConsent:
            askConsent()
        case .check:
            startAutomaticCheck()
        }
    }

    private func askConsent() {
        let agreed = presentDialog(.consent) == .first
        settings.automaticUpdateCheck = agreed ? .enabled : .disabled
        if agreed {
            startAutomaticCheck()
        }
    }

    private func startAutomaticCheck() {
        guard let currentVersion, !isChecking else { return }
        start(current: currentVersion, automatic: true)
    }

    private func start(current: AppVersion, automatic: Bool) {
        isChecking = true
        let transport = transport
        checkTask = Task { [weak self] in
            let result = await UpdateChecker.check(current: current, transport: transport)
            self?.finish(result, automatic: automatic)
        }
    }

    private func finish(_ result: UpdateCheckResult, automatic: Bool) {
        isChecking = false
        if automatic {
            finishAutomatic(result)
        } else {
            finishFromMenu(result)
        }
    }

    private func finishFromMenu(_ result: UpdateCheckResult) {
        switch result {
        case let .updateAvailable(latest, current, releasePage):
            settings.lastNotifiedUpdateVersion = AutomaticUpdateCheckPolicy.notifiedVersion(
                afterAnnouncing: latest, previous: settings.lastNotifiedUpdateVersion
            )
            announce(latest: latest, current: current, releasePage: releasePage)
        case let .upToDate(current):
            _ = presentDialog(.upToDate(current: current))
        case .failed:
            _ = presentDialog(.failed)
        }
    }

    /// Saves what the policy says and shows only a version not announced before; up to date and failures stay
    /// silent (FR-432, FR-433).
    private func finishAutomatic(_ result: UpdateCheckResult) {
        let outcome = AutomaticUpdateCheckPolicy.automaticOutcome(
            result: result,
            lastNotified: settings.lastNotifiedUpdateVersion,
            canPresent: canPresent(),
            now: now()
        )
        if let checkTime = outcome.savesCheckTime {
            settings.lastAutomaticUpdateCheck = checkTime
        }
        if let notified = outcome.savesNotifiedVersion {
            settings.lastNotifiedUpdateVersion = notified
        }
        if outcome.announces != nil, case let .updateAvailable(latest, current, releasePage) = result {
            announce(latest: latest, current: current, releasePage: releasePage)
        }
    }

    private func announce(latest: AppVersion, current: AppVersion, releasePage: URL) {
        if presentDialog(.updateAvailable(latest: latest, current: current)) == .first {
            openURL(releasePage)
        }
    }

    /// Builds the alert for `dialog` in the current display language.
    static func makeAlert(for dialog: UpdateDialog) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .informational
        switch dialog {
        case let .updateAvailable(latest, current):
            alert.messageText = l10n.text(.updateAvailableTitle)
            alert.informativeText = l10n.text(
                .updateAvailableMessage, .text(latest.description), .text(current.description)
            )
            alert.addButton(withTitle: l10n.text(.updateAvailableOpen))
            alert.addButton(withTitle: l10n.text(.updateAvailableClose)).keyEquivalent = "\u{1b}"
        case let .upToDate(current):
            alert.messageText = l10n.text(.updateUpToDateTitle)
            alert.informativeText = l10n.text(.updateUpToDateMessage, .text(current.description))
            alert.addButton(withTitle: l10n.text(.dialogOK))
        case .failed:
            alert.messageText = l10n.text(.updateFailedTitle)
            alert.informativeText = l10n.text(.updateFailedMessage)
            alert.addButton(withTitle: l10n.text(.dialogOK))
        case .consent:
            alert.messageText = l10n.text(.updateConsentTitle)
            alert.informativeText = l10n.text(.updateConsentMessage)
            alert.addButton(withTitle: l10n.text(.updateConsentEnable))
            alert.addButton(withTitle: l10n.text(.updateConsentDecline)).keyEquivalent = "\u{1b}"
        }
        return alert
    }
}
