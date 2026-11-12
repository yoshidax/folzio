import AppKit
import FixtureKit
import FolzioCore
import ImageIO
import Testing
@testable import FolzioApp

@Suite("Image preview interaction", .serialized)
@MainActor
struct ImagePreviewInteractionTests {
    private func makeView() throws -> ImagePreviewView {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try ImageFixtures.png(at: url, width: 200, height: 200)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let view = ImagePreviewView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        view.showImage(DecodedImage(cgImage: image, pixelSize: CGSize(width: 200, height: 200),
                                    originalPixelSize: CGSize(width: 200, height: 200), byteCost: 160_000), fileName: "test.png")
        view.applyZoom(try #require(PreviewZoom(percentage: 200)), announce: false)
        return view
    }

    @Test("A precise wheel event without a gesture phase changes zoom")
    func preciseWheel() throws {
        let view = try makeView()
        var factor: CGFloat?
        var receivedAnchor: CGPoint?
        view.onScale = { value, _, anchor in factor = value; receivedAnchor = anchor }
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 10, wheel2: 0, wheel3: 0))
        let event = try #require(NSEvent(cgEvent: cgEvent))
        #expect(event.hasPreciseScrollingDeltas)
        #expect(event.phase.isEmpty && event.momentumPhase.isEmpty)
        view.scrollWheel(with: event)
        #expect(abs((factor ?? 0) - 1.05) < 0.001)
        #expect(receivedAnchor == view.convert(event.locationInWindow, from: nil))
    }

    @Test("Trackpad scroll gestures move the image instead of zooming")
    func trackpadScroll() throws {
        let view = try makeView()
        var changedZoom = false
        view.onScale = { _, _, _ in changedZoom = true }
        let before = view.transitionSnapshot().frame
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 20, wheel2: 0, wheel3: 0))
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        let event = try #require(NSEvent(cgEvent: cgEvent))
        #expect(event.phase.contains(.changed))
        view.scrollWheel(with: event)
        #expect(!changedZoom)
        #expect(view.transitionSnapshot().frame != before)
    }

    @Test("Pointer anchored zoom preserves the image point beneath the pointer")
    func anchoredZoom() throws {
        let view = try makeView()
        let anchor = CGPoint(x: 65, y: 140)
        let before = view.transitionSnapshot().frame
        view.applyZoom(try #require(PreviewZoom(percentage: 250)), announce: false, anchor: anchor)
        let after = view.transitionSnapshot().frame
        #expect(abs((anchor.x - before.minX) / before.width - (anchor.x - after.minX) / after.width) < 0.0001)
        #expect(abs((anchor.y - before.minY) / before.height - (anchor.y - after.minY) / after.height) < 0.0001)
    }

    @Test("Option and two arrow keys pan diagonally in both modes")
    func diagonalKeyboardPan() throws {
        func event(_ type: NSEvent.EventType, key: Int, code: UInt16, repeats: Bool = false) throws -> NSEvent {
            let character = String(try #require(UnicodeScalar(key)))
            return try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: 0,
                context: nil, characters: character, charactersIgnoringModifiers: character,
                isARepeat: repeats, keyCode: code
            ))
        }
        for mode in [PreviewInteractionMode.traditional, .wheelZoom] {
            let view = try makeView()
            view.interactionMode = mode
            let right = try event(.keyDown, key: NSRightArrowFunctionKey, code: 124)
            let up = try event(.keyDown, key: NSUpArrowFunctionKey, code: 126)
            view.keyDown(with: right)
            let beforeDiagonal = view.transitionSnapshot().frame
            view.keyDown(with: up)
            let diagonal = view.transitionSnapshot().frame
            #expect(abs((beforeDiagonal.minX - diagonal.minX) - (beforeDiagonal.minY - diagonal.minY)) < 0.001)
            #expect(diagonal.minX < beforeDiagonal.minX && diagonal.minY < beforeDiagonal.minY)
            view.keyUp(with: try event(.keyUp, key: NSUpArrowFunctionKey, code: 126))
            view.keyDown(with: try event(.keyDown, key: NSRightArrowFunctionKey, code: 124, repeats: true))
            let afterRelease = view.transitionSnapshot().frame
            #expect(afterRelease.minX < diagonal.minX)
            #expect(afterRelease.minY == diagonal.minY)
            let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
            view.keyDown(with: up)
            let afterWindowChange = view.transitionSnapshot().frame
            #expect(afterWindowChange.minX == afterRelease.minX)
            #expect(afterWindowChange.minY < afterRelease.minY)
            window.contentView = nil
        }
    }

    @Test("Wheel zoom animates while direct zoom and movement do not")
    func wheelZoomAnimation() throws {
        let view = try makeView()
        let imageLayer = try #require(view.layer?.sublayers?.first)
        let target = try #require(PreviewZoom(percentage: 225))
        view.applyZoom(target, announce: false, animateWheel: true)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(imageLayer.animation(forKey: "wheelZoom") != nil)
        }
        view.applyZoom(try #require(PreviewZoom(percentage: 250)), announce: false)
        #expect(imageLayer.animation(forKey: "wheelZoom") == nil)
        view.applyZoom(target, announce: false, animateWheel: true)
        view.interactionMode = .traditional
        let event = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 10, wheel2: 0, wheel3: 0))
        view.scrollWheel(with: try #require(NSEvent(cgEvent: event)))
        #expect(imageLayer.animation(forKey: "wheelZoom") == nil)
    }

    @Test("Moving the preview does not animate its image layer")
    func movementDoesNotAnimate() throws {
        let view = try makeView()
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        let imageLayer = try #require(view.layer?.sublayers?.first)
        let before = imageLayer.frame
        let cgEvent = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 10, wheel2: 0, wheel3: 0))
        view.interactionMode = .traditional
        view.scrollWheel(with: try #require(NSEvent(cgEvent: cgEvent)))
        #expect(imageLayer.frame != before)
        #expect(imageLayer.animationKeys()?.isEmpty != false)
    }
}
