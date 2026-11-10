import AppKit
import Testing
@testable import FolzioApp

@Suite("Receiving panel", .serialized)
@MainActor
struct ReceivingPanelControllerTests {
    @Test func progressUpdatesPreserveCancelTargets() throws {
        _ = NSApplication.shared
        var cancelled: [UUID] = []
        let controller = ReceivingPanelController { cancelled.append($0) }
        defer { controller.update([]); controller.panel.close() }
        let a = UUID(), b = UUID()
        func row(_ id: UUID, bytes: UInt64 = 0) -> ImportProgressRow {
            ImportProgressRow(id: id, destination: id == a ? "A" : "B", total: 2,
                completed: bytes == 0 ? 0 : 1, bytes: bytes, checking: bytes > 0)
        }
        func buttons(in view: NSView) -> [NSButton] {
            view.subviews.flatMap { child in
                if let button = child as? NSButton { return [button] }
                return buttons(in: child)
            }
        }
        controller.update([row(a), row(b)])
        let content = try #require(controller.panel.contentView)
        let first = buttons(in: content)
        #expect(first.count == 2)
        let aButton = try #require(first.first { $0.identifier?.rawValue == a.uuidString })
        let bButton = try #require(first.first { $0.identifier?.rawValue == b.uuidString })

        controller.update([row(a, bytes: 42), row(b, bytes: 84)])
        #expect(buttons(in: content).contains { $0 === aButton })
        #expect(buttons(in: content).contains { $0 === bButton })
        controller.update([row(b, bytes: 128)])
        let remaining = buttons(in: content)
        #expect(remaining.count == 1)
        #expect(remaining.first === bButton)
        remaining.first?.performClick(nil)
        #expect(cancelled == [b])
        controller.update([])
        #expect(buttons(in: content).isEmpty)
        #expect(!controller.panel.isVisible)
    }
}
