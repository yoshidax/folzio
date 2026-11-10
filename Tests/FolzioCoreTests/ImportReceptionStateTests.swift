import Testing
@testable import FolzioCore

@Suite("Import reception state")
struct ImportReceptionStateTests {
    @Test func transitions() {
        var state = ImportReceptionState(hasPromises: true)
        #expect(state.phase == .receiving)
        do { let applied = state.apply(.confirmed); #expect(applied == false) }
        do { let applied = state.apply(.received(id: "one")); #expect(applied == true) }
        do { let applied = state.apply(.received(id: "one")); #expect(applied == false) }
        #expect(state.receivedCount == 1)
        do { let applied = state.apply(.receptionCompleted); #expect(applied == true) }
        do { let applied = state.apply(.checked); #expect(applied == true) }
        do { let applied = state.apply(.confirmed); #expect(applied == true) }
        do { let applied = state.apply(.saved); #expect(applied == true) }
        #expect(state.phase == .finished)
        do { let applied = state.apply(.received(id: "late")); #expect(applied == false) }
        do { let applied = state.apply(.failed); #expect(applied == false) }
        do { let applied = state.apply(.cancelled); #expect(applied == false) }
    }
    @Test func cancellationAndFailure() {
        for event in [ImportReceptionState.Event.failed, .cancelled] {
            var state = ImportReceptionState(hasPromises: true)
            do { let applied = state.apply(event); #expect(applied == true) }
            let phase = state.phase
            do { let applied = state.apply(.received(id: "late")); #expect(applied == false) }
            do { let applied = state.apply(.receptionCompleted); #expect(applied == false) }
            #expect(state.phase == phase)
        }
        var raw = ImportReceptionState(hasPromises: false)
        #expect(raw.phase == .checking)
        do { let applied = raw.apply(.cancelled); #expect(applied == true) }
    }
}
