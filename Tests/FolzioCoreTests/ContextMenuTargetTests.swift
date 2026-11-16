import FolzioCore
import Testing

@Suite("Context menu target")
struct ContextMenuTargetTests {
    @Test("A context click on an unselected item targets only that item (FR-397)",
          arguments: [Set<Int>(), [0], [0, 2, 3]])
    func unselectedItemIsTheTarget(_ selected: Set<Int>) {
        #expect(ContextMenuTarget.resolve(clicked: 1, selected: selected, itemCount: 5) == .item(1))
    }

    @Test("A context click on a selected item targets the whole selection (SC-220)",
          arguments: [Set<Int>([1]), [0, 1, 2]])
    func selectedItemTargetsTheSelection(_ selected: Set<Int>) {
        #expect(ContextMenuTarget.resolve(clicked: 1, selected: selected, itemCount: 5) == .selection)
    }

    @Test("A context click on the background targets the displayed folder (FR-213)")
    func backgroundTargetsTheDisplayedFolder() {
        #expect(ContextMenuTarget.resolve(clicked: nil, selected: [0], itemCount: 5) == .background)
        #expect(ContextMenuTarget.resolve(clicked: nil, selected: [], itemCount: 5) == .background)
    }

    @Test("An index outside the listing counts as the background", arguments: [-1, 5, 9])
    func outOfRangeIsTheBackground(_ clicked: Int) {
        #expect(ContextMenuTarget.resolve(clicked: clicked, selected: [0], itemCount: 5) == .background)
    }
}
