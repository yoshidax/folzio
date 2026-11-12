import CoreGraphics
import Testing
@testable import FolzioCore

@Suite("Preview keyboard scrolling")
struct PreviewKeyboardScrollTests {
    @Test("All diagonal combinations keep a 45 degree angle and the single-axis distance")
    func diagonalDirections() {
        for (horizontal, vertical, expectedX, expectedY) in [
            (PreviewKeyboardScroll.Direction.left, PreviewKeyboardScroll.Direction.up, -1.0, 1.0),
            (.right, .up, 1.0, 1.0), (.left, .down, -1.0, -1.0), (.right, .down, 1.0, -1.0),
        ] {
            var state = PreviewKeyboardScroll()
            state.press(horizontal)
            state.press(vertical)
            let movement = state.movement(step: 40)
            #expect(abs(movement.x - expectedX * 40 / sqrt(2)) < 0.0001)
            #expect(abs(movement.y - expectedY * 40 / sqrt(2)) < 0.0001)
            #expect(abs(hypot(movement.x, movement.y) - 40) < 0.0001)
        }
    }

    @Test("Releases and opposing directions update the held state")
    func releaseAndOpposites() {
        var state = PreviewKeyboardScroll()
        state.press(.right)
        #expect(state.movement(step: 40) == CGPoint(x: 40, y: 0))
        state.press(.left)
        state.press(.up)
        #expect(state.movement(step: 40) == CGPoint(x: 0, y: 40))
        state.release(.left)
        #expect(state.movement(step: 40).x > 0)
        state.release(.right)
        #expect(state.movement(step: 40) == CGPoint(x: 0, y: 40))
        state.reset()
        #expect(state.isEmpty)
        #expect(state.movement(step: 40) == .zero)
    }
}
