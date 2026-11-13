import AppKit
import Testing
@testable import FolzioApp

/// Typing in the toolbar name filter field is not renaming (FR-388, TAK-86). Treating it as renaming disabled the
/// field while the user typed in it, which moved the focus to the file list and blocked input methods.
@Suite("Toolbar search field editing", .serialized)
@MainActor
struct ToolbarSearchFieldEditingTests {
    @Test("Editing the toolbar name filter field does not count as renaming")
    func toolbarFieldIsNotRenaming() throws {
        try withWindow(ToolbarSearchField(width: 180)) { window, field in
            #expect(window.makeFirstResponder(field))
            let editor = try #require(window.firstResponder as? NSTextView)
            #expect((editor.delegate as AnyObject?) === field)
            #expect(FileListViewController.isRenaming(firstResponder: editor) == false)
        }
    }

    @Test("Editing another text field, such as a name being renamed, still counts as renaming")
    func otherFieldIsRenaming() throws {
        let rename = NSTextField(string: "original.jpg")
        rename.isEditable = true
        try withWindow(rename) { window, field in
            #expect(window.makeFirstResponder(field))
            let editor = try #require(window.firstResponder as? NSTextView)
            #expect(FileListViewController.isRenaming(firstResponder: editor))
        }
    }

    @Test("No first responder and a non-text responder are not renaming")
    func nonTextResponders() {
        #expect(FileListViewController.isRenaming(firstResponder: nil) == false)
        #expect(FileListViewController.isRenaming(firstResponder: NSView()) == false)
    }

    @Test("A click on the magnifying glass sends showSearch to the find target without editing the text (FR-390)")
    func magnifyingGlassOpensSearch() throws {
        let target = FindTargetSpy()
        try withWindow(ToolbarSearchField(width: 180)) { window, field in
            field.stringValue = "kyoto"
            field.findCommandTarget = target
            window.contentView?.layoutSubtreeIfNeeded()
            let button = field.searchButtonBounds
            try #require(!button.isEmpty)
            #expect(button.maxX <= field.bounds.midX, "The magnifying glass is at the leading edge")

            field.mouseDown(with: try click(at: NSPoint(x: button.midX, y: button.midY), in: field, window: window))
            #expect(target.calls == 1)
            #expect(field.currentEditor() == nil)
            #expect(field.stringValue == "kyoto")

            field.isEnabled = false
            field.mouseDown(with: try click(at: NSPoint(x: button.midX, y: button.midY), in: field, window: window))
            #expect(target.calls == 1, "A disabled field does not open the search sheet (FR-388)")
        }
    }

    @Test("An accessibility action named like the magnifying glass opens the search sheet (FR-390, FR-392)")
    func accessibilityActionOpensSearch() throws {
        let target = FindTargetSpy()
        try withWindow(ToolbarSearchField(width: 180)) { _, field in
            field.findCommandTarget = target
            field.setFindAccessibilityAction(name: "Find… (⌥⌘F)")
            let action = try #require(field.accessibilityCustomActions()?.first)
            #expect(action.name == "Find… (⌥⌘F)")
            #expect(action.handler?() == true)
            #expect(target.calls == 1)

            field.isEnabled = false
            #expect(action.handler?() == false)
            #expect(target.calls == 1, "A disabled field does not open the search sheet (FR-388)")
        }
    }

    private func click(at point: NSPoint, in view: NSView, window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: view.convert(point, to: nil),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func withWindow<Field: NSTextField>(
        _ field: Field,
        body: (NSWindow, Field) throws -> Void
    ) throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 60))
        window.contentView = container
        field.frame = NSRect(x: 10, y: 20, width: 200, height: 22)
        container.addSubview(field)
        defer {
            window.makeFirstResponder(nil)
            window.close()
        }
        try body(window, field)
    }
}

/// Records `showSearch(_:)` calls from the toolbar search field.
@MainActor
private final class FindTargetSpy: NSObject {
    var calls = 0

    @objc func showSearch(_ sender: Any?) {
        calls += 1
    }
}
