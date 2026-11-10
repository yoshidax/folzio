import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Main menu cancellation", .serialized)
@MainActor
struct MainMenuCancellationTests {
    @Test("Command-period cancels the field editor without cancelling reception", arguments: [false, true])
    func commandPeriodCancelsRename(hasReception: Bool) throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        MainMenu.install(zoomTarget: AppDelegate())
        defer { NSApp.mainMenu = previousMenu }
        let menu = try #require(NSApp.mainMenu as? MainApplicationMenu)
        let receivingItem = try #require(menu.items.compactMap(\.submenu).flatMap(\.items).first {
            $0.action == #selector(ImportSessionManager.cancelReceiving(_:))
        })
        let target = CancellationTarget(enabled: hasReception)
        receivingItem.target = target
        receivingItem.action = #selector(CancellationTarget.cancel(_:))

        let item = ThumbnailItemView()
        let file = MediaFile(url: URL(fileURLWithPath: "/tmp/original.jpg"), name: "original.jpg",
            kind: .media(.jpeg), typeDescription: "", creationDate: nil, fileSize: 0)
        item.configure(with: file, iconPointSize: 16)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = item.view
        defer { window.makeFirstResponder(nil); window.close() }
        menu.cancellationContext = { (window, false, false) }
        target.window = window
        #expect(item.beginRenaming())
        let field = try #require(item.textField)
        let editor = try #require(field.currentEditor() as? NSTextView)
        editor.string = "changed.jpg"
        var committed = false
        item.onCommitRename = { _, _ in committed = true }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: ".",
            charactersIgnoringModifiers: ".", isARepeat: false, keyCode: 47))

        _ = menu.performKeyEquivalent(with: event)

        #expect(!field.isEditable)
        #expect(!committed)
        #expect(field.stringValue == "original.jpg")
        #expect(target.calls == 0)
    }

    @Test("Nonediting Command-period keeps the receiving menu action")
    func commandPeriodWithoutEditor() throws {
        _ = NSApplication.shared
        let menu = MainApplicationMenu()
        let target = CancellationTarget(enabled: true)
        let item = NSMenuItem(title: "Cancel Receiving", action: #selector(CancellationTarget.cancel(_:)), keyEquivalent: ".")
        item.keyEquivalentModifierMask = [.command]
        item.target = target
        menu.addItem(item)
        menu.cancellationContext = { (nil, false, false) }

        let event = try keyEvent()
        #expect(menu.performKeyEquivalent(with: event))
        #expect(target.calls == 1)
    }

    @Test("Other keys and modifier combinations stay with AppKit", arguments: [
        NSEvent.ModifierFlags(), [.command, .control], [.command, .option], [.command, .shift],
    ])
    func otherModifiers(flags: NSEvent.ModifierFlags) throws {
        try withEditor { menu, editor in
            let event = try keyEvent(flags: flags)
        #expect(!menu.performKeyEquivalent(with: event))
            #expect(editor.commands.isEmpty)
        }
    }

    @Test("Another Command shortcut stays with AppKit")
    func otherKey() throws {
        try withEditor { menu, editor in
            let event = try keyEvent(characters: "x")
        #expect(!menu.performKeyEquivalent(with: event))
            #expect(editor.commands.isEmpty)
        }
    }

    @Test("Sheet and modal cancellation stay with AppKit", arguments: [false, true])
    func modalCancellation(hasSheet: Bool) throws {
        try withEditor { menu, editor in
            let window = editor.window
            menu.cancellationContext = { (window, !hasSheet, hasSheet) }
            let event = try keyEvent()
        #expect(!menu.performKeyEquivalent(with: event))
            #expect(editor.commands.isEmpty)
        }
    }

    @Test("Caps Lock does not block standard editor cancellation")
    func capsLock() throws {
        try withEditor { menu, editor in
            let event = try keyEvent(flags: [.command, .capsLock])
        #expect(menu.performKeyEquivalent(with: event))
            #expect(editor.commands == [#selector(NSResponder.cancelOperation(_:))])
        }
    }

    private func keyEvent(flags: NSEvent.ModifierFlags = [.command], characters: String = ".") throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 47))
    }

    private func withEditor(_ body: (MainApplicationMenu, CancellationEditor) throws -> Void) throws {
        _ = NSApplication.shared
        let menu = MainApplicationMenu()
        let editor = CancellationEditor()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        defer { window.makeFirstResponder(nil); window.close() }
        #expect(window.makeFirstResponder(editor))
        menu.cancellationContext = { (window, false, false) }
        try body(menu, editor)
    }

}

@MainActor
private final class CancellationTarget: NSObject, NSMenuItemValidation {
    let enabled: Bool
    var window: NSWindow?
    var calls = 0
    init(enabled: Bool) { self.enabled = enabled }
    @objc func cancel(_ sender: Any?) { calls += 1 }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { enabled && !(window?.firstResponder is NSText) }
}

@MainActor
private final class CancellationEditor: NSTextView {
    var commands: [Selector] = []
    override func doCommand(by selector: Selector) { commands.append(selector) }
}
