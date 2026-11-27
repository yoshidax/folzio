import AppKit
import FolzioCore
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let performanceSignposter = OSSignposter(
        subsystem: "local.folzio.Folzio",
        category: "Performance"
    )
    private var launchToListState: OSSignpostIntervalState?
    private var mainWindowController: MainWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var aboutWindowController: AboutWindowController?

    /// Checks for updates from the menu and at launch (FR-422...FR-433). Under `swift run` there is no Info.plist, so
    /// there is no version and the check stays off (FR-422, EC-299).
    private(set) lazy var updateCheckController: UpdateCheckController = {
        let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        let controller = UpdateCheckController(
            currentVersion: AboutInfo.displayVersion(from: value).flatMap(AppVersion.init)
        )
        controller.canPresent = { [weak self] in
            self?.mainWindowController?.canShowShortcuts ?? false
        }
        return controller
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchToListState = performanceSignposter.beginInterval("LaunchToList")

        NSWindow.allowsAutomaticWindowTabbing = false
        MainMenu.install(zoomTarget: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )

        let controller = MainWindowController()
        mainWindowController = controller
        if let window = controller.window {
            NotificationCenter.default.addObserver(
                self, selector: #selector(mainWindowWillClose(_:)), name: NSWindow.willCloseNotification,
                object: window
            )
        }
        if let splitViewController = controller.window?.contentViewController as? MainSplitViewController {
            splitViewController.onInitialListingDisplayed = { [weak self] in
                self?.endLaunchToListInterval()
            }
        }
        controller.showWindow(nil)

        ImportSessionManager.shared.start()
        NSApp.activate(ignoringOtherApps: true)

        // Runs on a later turn of the main run loop, after the main window is on screen (FR-430, FR-431).
        Task { @MainActor [weak self] in
            self?.updateCheckController.performLaunchAction()
        }
    }

    @objc private func displayLanguageDidChange() {
        MainMenu.refreshTitles()
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === mainWindowController?.window else { return }
        settingsWindowController?.close()
        aboutWindowController?.close()
    }

    private func endLaunchToListInterval() {
        guard let state = launchToListState else { return }
        launchToListState = nil
        performanceSignposter.endInterval("LaunchToList", state)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private var importShutdownFinished = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if importShutdownFinished { return .terminateNow }
        Task { @MainActor in
            await ImportSessionManager.shared.shutdown()
            importShutdownFinished = true
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.stopSlideshowImmediately()
    }

    /// Opens the About window, or brings the existing one to the front (FR-238, FR-243). It is always available.
    @objc func showAbout(_ sender: Any?) {
        let controller: AboutWindowController
        if let existing = aboutWindowController {
            controller = existing
        } else {
            // Info.plist is absent under `swift run`, which yields no version and so no version line (FR-241).
            let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            controller = AboutWindowController(version: AboutInfo.displayVersion(from: value))
            aboutWindowController = controller
        }
        controller.present()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Checks for updates and shows the result (FR-423). Disabled without a version or while a check runs (FR-422).
    @objc func checkForUpdates(_ sender: Any?) {
        updateCheckController.checkFromMenu()
    }

    @objc func showSettings(_ sender: Any?) {
        let controller: SettingsWindowController
        if let existing = settingsWindowController {
            controller = existing
        } else {
            controller = SettingsWindowController()
            settingsWindowController = controller
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showShortcuts(_ sender: Any?) {
        mainWindowController?.showShortcuts()
    }

    // MARK: - Preview Zoom (FR-135)
    // Set an explicit target so the actions arrive even when a sheet, the Settings window, or a rename is key (A-73).

    @objc func previewZoomIn(_ sender: Any?) {
        mainWindowController?.zoomIn()
    }

    @objc func previewZoomOut(_ sender: Any?) {
        mainWindowController?.zoomOut()
    }

    @objc func previewZoomToFit(_ sender: Any?) {
        mainWindowController?.zoomToFit()
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates(_:)):
            return updateCheckController.canCheck
        case #selector(showShortcuts(_:)):
            return mainWindowController?.canShowShortcuts ?? false
        case #selector(previewZoomIn(_:)):
            return mainWindowController?.zoomAvailability.canZoomIn ?? false
        case #selector(previewZoomOut(_:)):
            return mainWindowController?.zoomAvailability.canZoomOut ?? false
        case #selector(previewZoomToFit(_:)):
            return mainWindowController?.zoomAvailability.canFit ?? false
        default:
            return true
        }
    }
}
