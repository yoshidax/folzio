import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Thumbnail rename", .serialized)
@MainActor
struct ThumbnailRenameTests {
    @Test("Keeps the original display and accessibility names when a rename is not applied", arguments: [
        "new-name.jpg", "bad/name.jpg", "existing.jpg", "new-extension.png",
    ], [false, true])
    func unappliedRename(newName: String, isFolder: Bool) throws {
        try withItem(isFolder: isFolder) { item, field, file in
            var requests: [(URL, String)] = []
            item.onCommitRename = { url, name in
                // Models rejection or cancellation: no successful model update follows the request.
                requests.append((url, name))
            }

            try finishEditing(item, field: field, name: newName)

            #expect(requests.count == 1)
            #expect(requests.first?.0 == file.url)
            #expect(requests.first?.1 == newName)
            expectName(file.name, item: item, field: field)
            #expect(field.isEditable == false)

            // A subsequent end-editing notification must not submit the rename a second time.
            item.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
            #expect(requests.count == 1)
            expectName(file.name, item: item, field: field)
        }
    }

    @Test("Shows the renamed model only after a successful update", arguments: [false, true])
    func successfulRename(isFolder: Bool) throws {
        try withItem(isFolder: isFolder) { item, field, file in
            let newName = isFolder ? "Renamed Album" : "renamed.jpg"
            var requestedName: String?
            item.onCommitRename = { _, name in requestedName = name }

            try finishEditing(item, field: field, name: newName)
            #expect(requestedName == newName)
            expectName(file.name, item: item, field: field)

            var renamed = file
            renamed.name = newName
            renamed.url = file.url.deletingLastPathComponent().appendingPathComponent(newName)
            item.configure(with: renamed, iconPointSize: 16)

            expectName(newName, item: item, field: field)
            #expect(item.representedURL == renamed.url)
        }
    }

    @Test("Escape restores the name without submitting a rename", arguments: [false, true])
    func escapeCancelsEditing(isFolder: Bool) throws {
        try withItem(isFolder: isFolder) { item, field, file in
            var requested = false
            item.onCommitRename = { _, _ in requested = true }
            #expect(item.beginRenaming())
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.string = "changed.jpg"

            #expect(item.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))

            #expect(requested == false)
            expectName(file.name, item: item, field: field)
            #expect(field.isEditable == false)
        }
    }

    @Test("Empty and unchanged names do not submit a rename", arguments: ["", "   ", "original.jpg"])
    func noOpRename(newName: String) throws {
        try withItem(isFolder: false) { item, field, file in
            var requested = false
            item.onCommitRename = { _, _ in requested = true }

            try finishEditing(item, field: field, name: newName)

            #expect(requested == false)
            expectName(file.name, item: item, field: field)
        }
    }

    /// Ways a rename ends (TAK-37).
    enum EndingPath: CaseIterable {
        case returnKey
        case escapeKey
        case focusLoss
    }

    @Test("Centers the name again after the field editor is detached", arguments: EndingPath.allCases, [false, true])
    func alignmentAfterEditing(path: EndingPath, isFolder: Bool) throws {
        try withItem(isFolder: isFolder) { item, field, file in
            #expect(field.alignment == .center)
            item.onCommitRename = { _, _ in }
            #expect(item.beginRenaming())
            #expect(field.alignment == .left)
            let editor = try #require(field.currentEditor() as? NSTextView)
            editor.string = "changed.jpg"

            switch path {
            case .returnKey:
                #expect(item.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
            case .escapeKey:
                #expect(item.control(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
            case .focusLoss:
                break
            }

            if path != .focusLoss {
                // The rename has ended by now, whether or not the field editor is still attached.
                #expect(field.alignment == .center)
            }

            // Ends the edit the way AppKit does, so the field editor writes its state back to the cell.
            #expect(field.window?.makeFirstResponder(nil) == true)

            #expect(field.currentEditor() == nil)
            #expect(field.alignment == .center)
            expectName(file.name, item: item, field: field)
        }
    }

    private func finishEditing(_ item: ThumbnailItemView, field: NSTextField, name: String) throws {
        #expect(item.beginRenaming())
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = name
        #expect(item.control(field, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }

    private func expectName(_ name: String, item: ThumbnailItemView, field: NSTextField) {
        #expect(field.stringValue == name)
        #expect(field.accessibilityLabel() == name)
        #expect(item.view.accessibilityLabel() == name)
    }

    private func withItem(
        isFolder: Bool,
        body: (ThumbnailItemView, NSTextField, MediaFile) throws -> Void
    ) throws {
        _ = NSApplication.shared
        let file = MediaFile(
            url: URL(fileURLWithPath: isFolder ? "/tmp/Album" : "/tmp/original.jpg"),
            name: isFolder ? "Album" : "original.jpg",
            kind: isFolder ? .folder : .media(.jpeg),
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
        let item = ThumbnailItemView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = item.view
        defer {
            window.makeFirstResponder(nil)
            window.close()
        }
        item.configure(with: file, iconPointSize: 16)
        let field = try #require(item.textField)
        try body(item, field, file)
    }
}
