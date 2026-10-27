import AppKit
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        launchToListState = performanceSignposter.beginInterval("LaunchToList")

        NSWindow.allowsAutomaticWindowTabbing = false
        MainMenu.install(zoomTarget: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(displayLanguageDidChange), name: .displayLanguageDidChange, object: nil
        )

        let controller = MainWindowController()
        if let splitViewController = controller.window?.contentViewController as? MainSplitViewController {
            splitViewController.onInitialListingDisplayed = { [weak self] in
                self?.endLaunchToListInterval()
            }
        }
        controller.showWindow(nil)
        mainWindowController = controller

        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func displayLanguageDidChange() {
        MainMenu.refreshTitles()
    }

    private func endLaunchToListInterval() {
        guard let state = launchToListState else { return }
        launchToListState = nil
        performanceSignposter.endInterval("LaunchToList", state)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.stopSlideshowImmediately()
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
