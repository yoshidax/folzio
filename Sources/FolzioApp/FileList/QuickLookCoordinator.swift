import AppKit
import FolzioCore
import Quartz

/// Drives the Quick Look panel for the file list (TAK-18; FR-247–250, FR-253, FR-254; research.md R1–R3, R8).
///
/// The panel is the standard `QLPreviewPanel`. It takes control through the responder chain: the file list views
/// answer `acceptsPreviewPanelControl(_:)` and call `attach(to:)` / `detach(from:)`, so the panel only opens while the
/// file list has the focus (EC-170). The coordinator supplies the items, the on-screen frame each item zooms from and
/// back to, and forwards arrow keys to the file list so that the list selection follows (FR-254).
@MainActor
final class QuickLookCoordinator: NSObject, @preconcurrency QLPreviewPanelDataSource,
    @preconcurrency QLPreviewPanelDelegate {
    private let model: BrowserModel
    private var items: [URL] = []
    private var isControlling = false
    private weak var panel: QLPreviewPanel?

    /// Whether Space must not open the panel (full screen, slideshow). Name editing never reaches the list view.
    var isBlocked: () -> Bool = { false }
    /// Called before the panel opens, for example to scroll the focused row into view (EC-173).
    var prepareToOpen: () -> Void = {}
    /// Returns the on-screen frame of the row or thumbnail for a URL, or `.zero` when it is not visible.
    var sourceFrame: (URL) -> NSRect = { _ in .zero }
    /// Passes an arrow key event to the file list as if it had the key focus (FR-254).
    var forwardKey: (NSEvent) -> Void = { _ in }
    /// Called when the panel starts or stops showing the file list's items (EC-175).
    var onActiveChange: (Bool) -> Void = { _ in }

    init(model: BrowserModel) {
        self.model = model
        super.init()
    }

    // MARK: - Opening and closing

    /// Handles Space typed in the file list. Returns whether the key was consumed.
    func handleSpace(_ event: NSEvent) -> Bool {
        let disallowed: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(disallowed).isEmpty, !isBlocked() else { return false }
        toggle()
        return true
    }

    /// Opens the panel for the selected media, or closes it when it is already shown. Does nothing when the selection
    /// has no media (EC-171).
    func toggle() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
        let targets = currentTargets()
        guard !targets.isEmpty else { return }
        items = targets
        prepareToOpen()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the panel if it is shown (a double-click opens the file in its default app; US3-AS34).
    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private func currentTargets() -> [URL] {
        QuickLookTargets.urls(
            files: model.listing.files,
            selected: model.selection.selected,
            isBrowsingArchive: model.listing.archive != nil
        )
    }

    // MARK: - Panel control (called from the file list views' responder overrides)

    func attach(to panel: QLPreviewPanel) {
        self.panel = panel
        panel.dataSource = self
        panel.delegate = self
        if items.isEmpty {
            items = currentTargets()
        }
        guard !isControlling else { return }
        isControlling = true
        onActiveChange(true)
        observeModel()
    }

    func detach(from panel: QLPreviewPanel) {
        if panel.dataSource === self { panel.dataSource = nil }
        if panel.delegate === self { panel.delegate = nil }
        guard isControlling else { return }
        isControlling = false
        items = []
        onActiveChange(false)
    }

    /// Follows the file list while the panel is shown: a different selection or listing updates or closes the panel
    /// (FR-254, EC-172).
    private func observeModel() {
        guard isControlling else { return }
        withObservationTracking {
            _ = model.listing.files
            _ = model.selection.selected
            _ = model.listing.archive
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isControlling else { return }
                self.refresh()
                self.observeModel()
            }
        }
    }

    private func refresh() {
        guard let panel, panel.isVisible else { return }
        let targets = currentTargets()
        guard !targets.isEmpty else {
            panel.orderOut(nil)
            return
        }
        guard targets != items else { return }
        items = targets
        panel.reloadData()
        if let focused = model.selection.focused, let index = items.firstIndex(of: focused) {
            panel.currentPreviewItemIndex = index
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        items.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard items.indices.contains(index) else { return nil }
        return items[index] as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown,
              let key = event.specialKey,
              [.leftArrow, .rightArrow, .upArrow, .downArrow].contains(key),
              event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
            return false
        }
        forwardKey(event)
        return true
    }

    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
        guard let url = item as? NSURL else { return .zero }
        return sourceFrame(url as URL)
    }
}
