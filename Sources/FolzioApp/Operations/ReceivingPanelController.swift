import AppKit
import FolzioCore
import FolzioLocalization

@MainActor
final class ReceivingPanelController: NSObject {
    let panel: NSPanel
    private let stack = NSStackView()
    private let cancel: (UUID) -> Void
    private var rows: [ImportProgressRow] = []
    private var rowViews: [UUID: RowViews] = [:]

    @MainActor
    private struct RowViews {
        let title = NSTextField(labelWithString: "")
        let detail = NSTextField(labelWithString: "")
        let stage = NSTextField(labelWithString: "")
        let button: NSButton
        let line: NSStackView

        init(id: UUID, target: ReceivingPanelController) {
            title.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
            button = NSButton(title: "", target: target, action: #selector(cancelClicked(_:)))
            button.identifier = .init(id.uuidString)
            let text = NSStackView(views: [title, detail, stage])
            text.orientation = .vertical
            text.alignment = .leading
            line = NSStackView(views: [text, button])
            line.spacing = 16
        }

        func update(_ row: ImportProgressRow) {
            title.stringValue = row.destination
            let size = ByteCountFormatter.string(fromByteCount: Int64(clamping: row.bytes), countStyle: .file)
            detail.stringValue = l10n.receivingProgressText(total: row.total, completed: row.completed, size: size)
            stage.stringValue = l10n.receivingStageText(isChecking: row.checking)
            button.title = l10n.receivingCancelTitle
            button.setAccessibilityLabel(l10n.receivingCancelTitle + " " + row.destination)
        }
    }
    private var languageObserver: LanguageChangeObserver?

    init(cancel: @escaping (UUID) -> Void) {
        self.cancel = cancel
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 120),
            styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        panel.contentView = stack
        panel.center()
        languageObserver = LanguageChangeObserver { [weak self] in
            guard let self else { return }
            self.update(self.rows)
        }
    }

    func update(_ rows: [ImportProgressRow]) {
        self.rows = rows
        panel.title = l10n.receivingStageText(isChecking: false)
        let activeIDs = Set(rows.map(\.id))
        for id in Set(rowViews.keys).subtracting(activeIDs) {
            if let views = rowViews.removeValue(forKey: id) {
                stack.removeArrangedSubview(views.line)
                views.line.removeFromSuperview()
            }
        }
        for (index, row) in rows.enumerated() {
            let views = rowViews[row.id] ?? RowViews(id: row.id, target: self)
            rowViews[row.id] = views
            views.update(row)
            if stack.arrangedSubviews.indices.contains(index), stack.arrangedSubviews[index] === views.line {
                continue
            }
            if views.line.superview != nil {
                stack.removeArrangedSubview(views.line)
                views.line.removeFromSuperview()
            }
            stack.insertArrangedSubview(views.line, at: index)
        }
        if rows.isEmpty { panel.orderOut(nil) }
        else {
            panel.setContentSize(NSSize(width: 460, height: max(120, rows.count * 90 + 32)))
            panel.orderFront(nil)
        }
    }

    @objc private func cancelClicked(_ sender: NSButton) {
        if let text = sender.identifier?.rawValue, let id = UUID(uuidString: text) { cancel(id) }
    }
}
