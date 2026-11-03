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

        NSApp.activate(ignoringOtherApps: true)
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
