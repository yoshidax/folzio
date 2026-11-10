import AppKit

/// Keeps editor cancellation ahead of the receiving command's menu equivalent.
@MainActor
final class MainApplicationMenu: NSMenu {
    var cancellationContext: () -> (window: NSWindow?, hasModal: Bool, hasSheet: Bool) = {
        (NSApp.keyWindow, NSApp.modalWindow != nil,
         NSApp.keyWindow?.attachedSheet != nil || NSApp.mainWindow?.attachedSheet != nil)
    }

    nonisolated override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if event.type == .keyDown, modifiers == [.command], event.charactersIgnoringModifiers == "." {
            // Older SDKs leave this main-thread AppKit callback nonisolated.
            // Keep the non-Sendable menu local to this synchronous, runtime-checked boundary.
            nonisolated(unsafe) let menu = self
            if MainActor.assumeIsolated({ menu.cancelEditingIfPossible() }) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func cancelEditingIfPossible() -> Bool {
        let context = cancellationContext()
        guard !context.hasModal, !context.hasSheet,
              let editor = context.window?.firstResponder as? NSTextView else { return false }
        // Disabling the receiving item does not deliver the standard text cancellation command.
        editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        return true
    }
}
