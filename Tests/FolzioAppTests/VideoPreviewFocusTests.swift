import AppKit
import Testing
@testable import FolzioApp

@Suite("Video preview focus", .serialized)
@MainActor
struct VideoPreviewFocusTests {
    @Test("Keyboard focus goes to the inner player view, not the container (FR-033, FR-248; bug: tak-48)")
    func focusTargetIsInnerPlayerView() {
        let view = VideoPreviewView()

        #expect(!view.acceptsFirstResponder)
        #expect(view.focusTargetView !== view)
        #expect(view.focusTargetView.isDescendant(of: view))
    }
}
