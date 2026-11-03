import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("About window", .serialized)
@MainActor
struct AboutWindowTests {
    /// Collects every button in the view tree, so the test notices any control added besides the link.
    private func buttons(in view: NSView) -> [NSButton] {
        var found: [NSButton] = []
        if let button = view as? NSButton { found.append(button) }
        for subview in view.subviews { found += buttons(in: subview) }
        return found
    }

    @Test("Has only a close button in the title bar and a non-empty accessibility name (FR-239)")
    func windowAppearance() throws {
        let controller = AboutWindowController(version: "1.0.0", openURL: { _ in true })
        let window = try #require(controller.window)

        #expect(window.styleMask.contains(.closable))
        #expect(!window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
        #expect(window.titleVisibility == .hidden)
        #expect(!window.title.isEmpty)
        #expect(!window.isReleasedWhenClosed)
    }

    @Test("Shows the version line only when a version is given (FR-241, EC-168)")
    func versionLine() {
        let withVersion = AboutWindowController(version: "1.0.0", openURL: { _ in true })
        let text = withVersion.versionText
        #expect(text?.contains("1.0.0") == true)

        let withoutVersion = AboutWindowController(version: nil, openURL: { _ in true })
        #expect(withoutVersion.versionText == nil)
    }

    @Test("The link is the only button and is reachable with Tab (FR-242)")
    func linkIsTheOnlyControl() throws {
        let controller = AboutWindowController(version: "1.0.0", openURL: { _ in true })
        let content = try #require(controller.window?.contentView)
        let all = buttons(in: content)

        #expect(all.count == 1)
        #expect(all.first === controller.linkButton)
        #expect(controller.linkButton.canBecomeKeyView)
        #expect(controller.linkButton.attributedTitle.string == "https://github.com/yoshidax/folzio")
    }

    @Test("The link does not show a focus ring when it gets the initial focus without a key event (FR-242)")
    func noFocusRingOnInitialFocus() throws {
        let controller = AboutWindowController(version: "1.0.0", openURL: { _ in true })
        let window = try #require(controller.window)

        #expect(controller.linkButton.showsFocusRing == false)
        #expect(controller.linkButton.focusRingType == .none)

        // Giving the link the focus without a key event (as when the window opens) keeps the ring hidden.
        window.makeFirstResponder(controller.linkButton)
        #expect(controller.linkButton.showsFocusRing == false)
        #expect(controller.linkButton.focusRingType == .none)

        window.makeFirstResponder(nil)
        #expect(controller.linkButton.showsFocusRing == false)
    }

    @Test("Pressing the link opens the repository once and ignores failure (US46-AS2, EC-166)", arguments: [true, false])
    func linkOpensRepository(succeeds: Bool) throws {
        var opened: [URL] = []
        let controller = AboutWindowController(version: "1.0.0", openURL: { url in
            opened.append(url)
            return succeeds
        })

        controller.linkButton.performClick(nil)

        #expect(opened == [AboutInfo.repositoryURL])
        #expect(opened.first?.absoluteString == "https://github.com/yoshidax/folzio")
        // The window is not closed or replaced by a failure.
        #expect(controller.window != nil)
    }
}
