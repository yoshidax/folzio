import AppKit
import FolzioLocalization
import Testing
@testable import FolzioApp

/// Root rows and the wildcard note in the search sheet (FR-081, FR-435, FR-441; TAK-104).
@Suite("Search sheet root rows", .serialized)
@MainActor
struct SearchPanelRowsTests {
    private func withSheet(_ body: (NSWindow, SearchPanelController) throws -> Void) rethrows {
        _ = NSApplication.shared
        let controller = SearchPanelController(keyword: "cat", rootPath: "/start") { _, _ in }
        let window = NSWindow(contentViewController: controller)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        try body(window, controller)
    }

    private func type(_ text: String, in field: NSTextField, _ controller: SearchPanelController) {
        field.stringValue = text
        controller.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    /// The field whose editor has the keyboard focus.
    private func focusedField(_ window: NSWindow) -> NSTextField? {
        if let editor = window.firstResponder as? NSTextView {
            return editor.delegate as? NSTextField
        }
        return window.firstResponder as? NSTextField
    }

    @Test("Opens with one row holding the default root; its Remove is disabled and Add Folder is enabled")
    func opensWithOneRow() {
        withSheet { _, controller in
            #expect(controller.rows.count == 1)
            #expect(controller.rows[0].field.stringValue == "/start")
            #expect(!controller.rows[0].removeButton.isEnabled)
            #expect(!controller.rows[0].removeButton.canBecomeKeyView)
            #expect(controller.addRootButton.isEnabled)
            #expect(controller.rows[0].field.accessibilityLabel() == l10n.text(.searchRoot))
        }
    }

    @Test("Add Folder appends an empty row and focuses it; Remove keeps the other rows and focuses the row that moved up")
    func addAndRemoveRows() {
        withSheet { window, controller in
            controller.addRootButton.performClick(nil)
            #expect(controller.rows.count == 2)
            #expect(controller.rows[1].field.stringValue.isEmpty)
            #expect(focusedField(window) === controller.rows[1].field)
            #expect(controller.rows.allSatisfy { $0.removeButton.isEnabled })

            type("/b", in: controller.rows[1].field, controller)
            controller.addRootButton.performClick(nil)
            type("/c", in: controller.rows[2].field, controller)

            controller.rows[1].removeButton.performClick(nil)
            #expect(controller.rows.map(\.field.stringValue) == ["/start", "/c"])
            #expect(focusedField(window) === controller.rows[1].field)

            controller.rows[1].removeButton.performClick(nil)
            #expect(controller.rows.map(\.field.stringValue) == ["/start"])
            #expect(focusedField(window) === controller.rows[0].field)
            #expect(!controller.rows[0].removeButton.isEnabled)
        }
    }

    @Test("Add Folder is disabled at ten rows and is skipped by Tab")
    func tenRowsAtMost() {
        withSheet { _, controller in
            for _ in 0..<12 {
                controller.addRootButton.performClick(nil)
            }
            #expect(controller.rows.count == 10)
            #expect(!controller.addRootButton.isEnabled)
            #expect(!controller.addRootButton.canBecomeKeyView)
        }
    }

    @Test("Tab goes keyword, each row's field, Choose, and Remove, then Add Folder, Cancel, and Search")
    func tabOrder() {
        withSheet { _, controller in
            controller.addRootButton.performClick(nil)
            let rows = controller.rows
            #expect(controller.keywordField.nextKeyView === rows[0].field)
            #expect(rows[0].field.nextKeyView === rows[0].chooseButton)
            #expect(rows[0].chooseButton.nextKeyView === rows[0].removeButton)
            #expect(rows[0].removeButton.nextKeyView === rows[1].field)
            #expect(rows[1].removeButton.nextKeyView === controller.addRootButton)
            #expect(controller.addRootButton.nextKeyView === controller.cancelButton)
        }
    }

    @Test("With several rows, each row's accessibility labels carry its row number")
    func numberedAccessibilityLabels() {
        withSheet { _, controller in
            controller.addRootButton.performClick(nil)
            let second = controller.rows[1]
            #expect(second.field.accessibilityLabel() == l10n.text(.searchRootNumbered, .number(2)))
            #expect(second.chooseButton.accessibilityLabel() == l10n.text(.searchChooseNumbered, .number(2)))
            #expect(second.removeButton.accessibilityLabel() == l10n.text(.searchRemoveRootNumbered, .number(2)))
            #expect(controller.rows[0].field.accessibilityLabel() == l10n.text(.searchRootNumbered, .number(1)))

            second.removeButton.performClick(nil)
            #expect(controller.rows[0].field.accessibilityLabel() == l10n.text(.searchRoot))
        }
    }

    @Test("The wildcard note sits below the keyword field, is not interactive, and follows the description in the keyword help")
    func wildcardNote() {
        withSheet { _, controller in
            let note = controller.wildcardLabel
            #expect(note.stringValue == l10n.text(.searchWildcardHint))
            #expect(!note.isSelectable)
            #expect(!note.isEditable)
            #expect(!note.acceptsFirstResponder)
            #expect(!note.isAccessibilityElement())
            #expect(controller.keywordField.accessibilityHelp()
                == l10n.text(.searchDescription) + " " + l10n.text(.searchWildcardHint))
        }
    }
}
