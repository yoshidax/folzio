import AppKit
import FolzioCore
import FolzioLocalization

/// Displays one parent's shortcut reference without blocking that parent's input.
@MainActor
final class ShortcutCheatSheetWindowController: NSWindowController {
    private let scrollView = NSScrollView()
    private let referenceView = ShortcutDocumentView(frame: .zero)
    private var languageObserver: LanguageChangeObserver?
    private var assignmentObserver: ShortcutAssignmentObserver?

    init(parent: NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.tabbingMode = .disallowed
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        window.contentView = scrollView
        referenceView.autoresizingMask = [.width]
        referenceView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: 1))
        scrollView.documentView = referenceView
        window.initialFirstResponder = referenceView
        refreshLanguage()
        placeInitially(beside: parent)
        languageObserver = LanguageChangeObserver { [weak self] in self?.refreshLanguage() }
        // The keys shown follow the current assignments, so a change refreshes the text and keeps the visible row.
        assignmentObserver = ShortcutAssignmentObserver { [weak self] in self?.refreshLanguage() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(referenceView)
    }

    private func refreshLanguage() {
        let anchor = referenceView.visibleAnchor()
        window?.title = l10n.text(.shortcutsWindow)
        scrollView.setAccessibilityLabel(l10n.text(.shortcutsWindow))
        referenceView.refreshLanguage()
        referenceView.restore(anchor)
    }

    private func placeInitially(beside parent: NSWindow) {
        guard let window, let screen = parent.screen ?? NSScreen.main else { return }
        let available = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, available.width)
        frame.size.height = min(frame.height, available.height)
        let availableContent = window.contentRect(forFrameRect: available).size
        window.contentMinSize = NSSize(
            width: min(480, availableContent.width), height: min(360, availableContent.height)
        )
        let right = parent.frame.maxX + 12
        let left = parent.frame.minX - 12 - frame.width
        let preferredX = right + frame.width <= available.maxX ? right : left
        frame.origin.x = max(available.minX, min(preferredX, available.maxX - frame.width))
        frame.origin.y = max(available.minY, min(parent.frame.maxY - frame.height, available.maxY - frame.height))
        window.setFrame(frame, display: false)
    }
}

/// Lays out fixed reference labels with a flipped origin and keyboard-only vertical scrolling.
@MainActor
private final class ShortcutDocumentView: NSView {
    struct Anchor {
        let id: ShortcutID
        let offset: CGFloat
    }

    private struct Row {
        let entry: ShortcutEntry
        let keys: NSTextField
        let description: NSTextField
        let condition: NSTextField
    }

    private var headings: [ShortcutSection: NSTextField] = [:]
    private var rows: [Row] = []
    private var rowFrames: [ShortcutID: NSRect] = [:]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for section in ShortcutSection.allCases {
            let heading = NSTextField(wrappingLabelWithString: "")
            heading.font = .systemFont(ofSize: 16, weight: .semibold)
            headings[section] = heading
            addSubview(heading)
            for entry in section.entries {
                let keys = NSTextField(wrappingLabelWithString: entry.keys)
                keys.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
                let description = NSTextField(wrappingLabelWithString: "")
                description.font = .systemFont(ofSize: 13)
                let condition = NSTextField(wrappingLabelWithString: "")
                condition.font = .systemFont(ofSize: 12)
                condition.textColor = .secondaryLabelColor
                for label in [keys, description, condition] {
                    label.maximumNumberOfLines = 0
                    addSubview(label)
                }
                // Read each entry as one unit so key glyphs remain associated with their meaning and conditions.
                keys.setAccessibilityElement(false)
                condition.setAccessibilityElement(false)
                rows.append(Row(entry: entry, keys: keys, description: description, condition: condition))
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changesWidth = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if changesWidth { layoutLabels() }
    }

    func refreshLanguage() {
        for section in ShortcutSection.allCases {
            if let heading = headings[section] {
                heading.stringValue = l10n.text(ShortcutText.heading(section))
                heading.setAccessibilityLabel(heading.stringValue)
            }
        }
        let assignments = ShortcutAssignmentStore.shared.assignments
        for row in rows {
            row.keys.stringValue = row.entry.keys(using: assignments, unsetText: l10n.text(.settingsShortcutsUnset))
            row.description.stringValue = l10n.text(ShortcutText.description(row.entry.id))
            let note = ShortcutText.condition(row.entry.id).map { l10n.text($0) } ?? ""
            row.condition.stringValue = note
            row.condition.isHidden = note.isEmpty
            row.description.setAccessibilityLabel(
                [row.keys.stringValue, row.description.stringValue, note].filter { !$0.isEmpty }.joined(separator: ". ")
            )
        }
        layoutLabels()
    }

    private func layoutLabels() {
        let padding: CGFloat = 20
        let gap: CGFloat = 16
        let width = max(1, bounds.width - padding * 2)
        let keyWidth = min(170, width * 0.4)
        let textWidth = max(1, width - keyWidth - gap)
        var y: CGFloat = padding
        rowFrames.removeAll(keepingCapacity: true)
        for section in ShortcutSection.allCases {
            if let heading = headings[section] {
                y += place(heading, x: padding, y: y, width: width) + 14
            }
            for row in rows where row.entry.section == section {
                let start = y
                let keyHeight = place(row.keys, x: padding, y: y, width: keyWidth)
                let x = padding + keyWidth + gap
                var height = place(row.description, x: x, y: y, width: textWidth)
                if !row.condition.isHidden {
                    height += 4
                    height += place(row.condition, x: x, y: y + height, width: textWidth)
                }
                y += max(keyHeight, height) + 14
                rowFrames[row.entry.id] = NSRect(x: padding, y: start, width: width, height: y - start)
            }
            y += 16
        }
        super.setFrameSize(NSSize(width: frame.width, height: max(y, enclosingScrollView?.contentSize.height ?? 0)))
    }

    @discardableResult
    private func place(_ label: NSTextField, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        label.preferredMaxLayoutWidth = width
        let height = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: x, y: y, width: width, height: max(18, height))
        return label.frame.height
    }

    func visibleAnchor() -> Anchor? {
        let top = enclosingScrollView?.contentView.bounds.minY ?? 0
        guard let row = rows.first(where: { (rowFrames[$0.entry.id]?.maxY ?? 0) > top }),
              let frame = rowFrames[row.entry.id] else { return nil }
        return Anchor(id: row.entry.id, offset: top - frame.minY)
    }

    func restore(_ anchor: Anchor?) {
        guard let anchor, let frame = rowFrames[anchor.id] else { return }
        scroll(to: frame.minY + anchor.offset)
    }

    private func scroll(to y: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let limit = max(0, bounds.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: min(max(0, y), limit)))
        scrollView.reflectScrolledClipView(clip)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers.isEmpty, let clip = enclosingScrollView?.contentView else {
            super.keyDown(with: event)
            return
        }
        let page = max(40, clip.bounds.height - 40)
        switch event.specialKey {
        case .upArrow: scroll(to: clip.bounds.minY - 32)
        case .downArrow: scroll(to: clip.bounds.minY + 32)
        case .pageUp: scroll(to: clip.bounds.minY - page)
        case .pageDown: scroll(to: clip.bounds.minY + page)
        case .home: scroll(to: 0)
        case .end: scroll(to: bounds.height)
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc in this reference must never cancel an operation in its parent.
    }
}
