import AppKit
import FolzioLocalization

/// Button that accepts Tab focus regardless of the system Keyboard Navigation setting while it is enabled (R39).
/// A disabled button is skipped by Tab (FR-081).
final class SearchKeyViewButton: NSButton {
    override var canBecomeKeyView: Bool { isEnabled }
}

/// One search root row in the search sheet: the root field, "Choose…", and "Remove" (FR-081, FR-435).
@MainActor
final class SearchRootRowView: NSStackView {
    let field = NSTextField()
    let chooseButton = SearchKeyViewButton()
    let removeButton = SearchKeyViewButton()

    init(text: String) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8

        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byTruncatingHead
        field.stringValue = text
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chooseButton.bezelStyle = .push
        chooseButton.setContentHuggingPriority(.required, for: .horizontal)
        removeButton.bezelStyle = .push
        removeButton.setContentHuggingPriority(.required, for: .horizontal)

        addArrangedSubview(field)
        addArrangedSubview(chooseButton)
        addArrangedSubview(removeButton)
        updateText(number: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Sets titles and accessibility text in the current language. `number` is the 1-based row number when the sheet
    /// has several rows, or nil for a single row, which keeps the unnumbered labels (FR-435).
    func updateText(number: Int?) {
        chooseButton.title = l10n.text(.searchChoose)
        chooseButton.setAccessibilityHelp(l10n.text(.searchChooseHelp))
        removeButton.title = l10n.text(.searchRemoveRoot)
        if let number {
            field.setAccessibilityLabel(l10n.text(.searchRootNumbered, .number(number)))
            chooseButton.setAccessibilityLabel(l10n.text(.searchChooseNumbered, .number(number)))
            removeButton.setAccessibilityLabel(l10n.text(.searchRemoveRootNumbered, .number(number)))
        } else {
            field.setAccessibilityLabel(l10n.text(.searchRoot))
            chooseButton.setAccessibilityLabel(l10n.text(.searchChoose))
            removeButton.setAccessibilityLabel(l10n.text(.searchRemoveRoot))
        }
    }
}
