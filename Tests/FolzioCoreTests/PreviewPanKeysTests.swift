import CoreGraphics
import Testing
@testable import FolzioCore

@Suite("Preview pan keys")
struct PreviewPanKeysTests {
    @Test("Two perpendicular keys produce a normalized diagonal and release restores the remaining direction")
    func diagonalAndRelease() {
        var keys = PreviewPanKeys()
        keys.press(.right)
        #expect(keys.direction == CGPoint(x: 1, y: 0))
        keys.press(.up)
        let direction = keys.direction
        #expect(abs(direction.x - direction.y) < 0.0001)
        #expect(abs(direction.x * direction.x + direction.y * direction.y - 1) < 0.0001)
        keys.release(.right)
        #expect(keys.direction == CGPoint(x: 0, y: 1))
        keys.release(.up)
        #expect(keys.direction == .zero)
    }

    @Test("Opposing directions cancel and reset clears every held key")
    func opposingAndReset() {
        var keys = PreviewPanKeys()
        keys.press(.left)
        keys.press(.right)
        keys.press(.down)
        #expect(keys.direction == CGPoint(x: 0, y: -1))
        keys.release(.right)
        #expect(keys.direction.x < 0 && keys.direction.y < 0)
        keys.reset()
        #expect(keys.direction == .zero)
    }
}
