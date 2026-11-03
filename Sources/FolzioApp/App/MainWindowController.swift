import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
final class MainWindowController: NSWindowController {
    private let splitViewController: MainSplitViewController
    private let toolbarController: MainToolbarController
    private var shortcutWindowController: ShortcutCheatSheetWindowController?
    private var hasClosed = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let splitViewController = MainSplitViewController()
        self.splitViewController = splitViewController
        let settings = SettingsStore(defaults: .standard)
        let fileList = splitViewController.fileListViewController
        let toolbarController = MainToolbarController(
            fileList: fileList,
            panes: splitViewController,
            settings: settings
        )
        self.toolbarController = toolbarController
        super.init(window: window)

        NotificationCenter.default.addObserver(
            self, selector: #selector(parentWillClose(_:)), name: NSWindow.willCloseNotification, object: window
        )

        window.contentViewController = splitViewController
        window.title = "Folzio"

        let showsToolbar = settings.viewSettings.showsToolbar
        toolbarController.toolbar.isVisible = showsToolbar
        fileList.isToolbarShown = showsToolbar
        window.toolbarStyle = .unified
        window.toolbar = toolbarController.toolbar
        toolbarController.restoreSavedConfiguration()

        let dividerWidth = splitViewController.splitView.dividerThickness
        window.minSize = NSSize(width: 720 + dividerWidth * 2, height: 400)

        let autosaveKey = "NSWindow Frame MainWindow"
        let hasSavedFrame = UserDefaults.standard.object(forKey: autosaveKey) != nil
        window.setFrameAutosaveName("MainWindow")
        if !hasSavedFrame {
            window.center()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Whether the existing parent can present its shortcut reference without disturbing another operation.
    var canShowShortcuts: Bool {
        !hasClosed && splitViewController.canShowShortcuts
    }

    func showShortcuts() {
        guard canShowShortcuts, let window else { return }
        if shortcutWindowController == nil {
            shortcutWindowController = ShortcutCheatSheetWindowController(parent: window)
        }
        shortcutWindowController?.present()
    }

    @objc private func parentWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else { return }
        hasClosed = true
        shortcutWindowController?.close()
        shortcutWindowController = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: closingWindow)
    }

    /// Leaves no slideshow tasks, pending work, or restore state on termination.
    func stopSlideshowImmediately() {
        splitViewController.stopSlideshowImmediately()
    }

    override func cancelOperation(_ sender: Any?) {
        if splitViewController.handleSlideshowEscapeFallback() {
            return
        }
        splitViewController.exitPreviewFullScreenIfNeeded()
        super.cancelOperation(sender)
    }

    // MARK: - Preview Zoom (entry points for AppDelegate menu actions and validation)

    var zoomAvailability: PreviewZoomAvailability {
        splitViewController.zoomAvailability
    }

    @discardableResult
    func zoomIn() -> Bool {
        splitViewController.zoomIn()
    }

    @discardableResult
    func zoomOut() -> Bool {
        splitViewController.zoomOut()
    }

    @discardableResult
    func zoomToFit() -> Bool {
        splitViewController.zoomToFit()
    }

    @objc func toggleMainToolbar(_ sender: Any?) {
        guard let toolbar = window?.toolbar else { return }
        toolbar.isVisible.toggle()
    }
}

extension MainWindowController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleMainToolbar(_:)) {
            let isVisible = window?.toolbar?.isVisible ?? false
            menuItem.title = isVisible ? l10n.text(.menuViewHideToolbar) : l10n.text(.menuViewShowToolbar)
            return window?.toolbar != nil
        }
        return true
    }
}
