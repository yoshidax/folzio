import Testing
@testable import FolzioCore

@Suite("FocusNavigator")
struct FocusNavigatorTests {
    @Test("List mode moves to the previous or next item with up and down")
    func listMovesVertically() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 2,
            fileCount: 5,
            move: .up,
            layout: .list
        ) == 1)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 2,
            fileCount: 5,
            move: .down,
            layout: .list
        ) == 3)
    }

    @Test("Left and right do not move focus in List mode")
    func listIgnoresHorizontalMoves() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 2,
            fileCount: 5,
            move: .left,
            layout: .list
        ) == nil)
        #expect(FocusNavigator.targetIndex(
            currentIndex: nil,
            fileCount: 5,
            move: .right,
            layout: .list
        ) == nil)
    }

    @Test("List mode stops at the ends")
    func listStopsAtEnds() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 0,
            fileCount: 5,
            move: .up,
            layout: .list
        ) == nil)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 4,
            fileCount: 5,
            move: .down,
            layout: .list
        ) == nil)
    }

    @Test("Thumbnails mode moves to the previous or next item with left and right")
    func gridMovesHorizontally() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 4,
            fileCount: 10,
            move: .left,
            layout: .grid(columns: 4)
        ) == 3)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 4,
            fileCount: 10,
            move: .right,
            layout: .grid(columns: 4)
        ) == 5)
    }

    @Test("Thumbnails mode moves by rows with up and down")
    func gridMovesByRow() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 6,
            fileCount: 10,
            move: .up,
            layout: .grid(columns: 4)
        ) == 2)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 2,
            fileCount: 10,
            move: .down,
            layout: .grid(columns: 4)
        ) == 6)
    }

    @Test("Thumbnails mode stops at the ends")
    func gridStopsAtEnds() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 0,
            fileCount: 10,
            move: .left,
            layout: .grid(columns: 4)
        ) == nil)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 9,
            fileCount: 10,
            move: .right,
            layout: .grid(columns: 4)
        ) == nil)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 0,
            fileCount: 10,
            move: .up,
            layout: .grid(columns: 4)
        ) == nil)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 1,
            fileCount: 10,
            move: .up,
            layout: .grid(columns: 4)
        ) == 0)
    }

    @Test("Clamps to the valid range when the last row is shorter")
    func gridClampsShortLastRow() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 8,
            fileCount: 9,
            move: .down,
            layout: .grid(columns: 4)
        ) == nil)
    }

    @Test("Selects the first item when there is no current position")
    func selectsFirstItemWhenNoFocus() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: nil,
            fileCount: 3,
            move: .down,
            layout: .grid(columns: 4)
        ) == 0)
    }

    @Test("An empty list has no destination")
    func emptyListReturnsNil() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: nil,
            fileCount: 0,
            move: .down,
            layout: .list
        ) == nil)
    }

    @Test("Treats nonpositive column counts as one column")
    func invalidColumnCountFallsBackToOne() {
        #expect(FocusNavigator.targetIndex(
            currentIndex: 1,
            fileCount: 5,
            move: .up,
            layout: .grid(columns: 0)
        ) == 0)
        #expect(FocusNavigator.targetIndex(
            currentIndex: 1,
            fileCount: 5,
            move: .down,
            layout: .grid(columns: -2)
        ) == 2)
    }

    // MARK: - With isNavigable (FR-046)

    private func target(
        _ kinds: [ListItemKind],
        from currentIndex: Int?,
        _ move: FocusMove,
        _ layout: FocusLayout
    ) -> Int? {
        FocusNavigator.targetIndex(
            currentIndex: currentIndex,
            fileCount: kinds.count,
            move: move,
            layout: layout,
            isNavigable: { kinds[$0].isMedia }
        )
    }

    @Test("List mode skips non-media rows to reach the next media item")
    func navigableListSkipsNonMedia() {
        let kinds: [ListItemKind] = [.media(.jpeg), .directory, .directory, .media(.png)]
        #expect(target(kinds, from: 0, .down, .list) == 3)
        #expect(target(kinds, from: 3, .up, .list) == 0)
    }

    @Test("Grid navigation returns nil when no eligible row exists above and skips non-media rows horizontally")
    func navigableGrid() {
        let kinds: [ListItemKind] = [.parent, .directory, .media(.jpeg), .media(.png)]
        #expect(target(kinds, from: 2, .up, .grid(columns: 2)) == nil)
        #expect(target(kinds, from: 3, .left, .grid(columns: 2)) == 2)
        #expect(target(kinds, from: 2, .right, .grid(columns: 2)) == 3)
    }

    @Test("Vertical grid navigation repeatedly steps by the column count until reaching media")
    func navigableGridVerticalRepeats() {
        let kinds: [ListItemKind] = [
            .media(.jpeg), .directory,
            .directory, .directory,
            .media(.png), .media(.gif),
        ]
        #expect(target(kinds, from: 0, .down, .grid(columns: 2)) == 4)
        #expect(target(kinds, from: 4, .up, .grid(columns: 2)) == 0)
        // Up from 1 clamps to the start as in the existing function, and stops because 0 is media.
        #expect(target(kinds, from: 5, .up, .grid(columns: 2)) == 0)
    }

    @Test("Returns nil when no media exists in the direction of movement")
    func navigableNoMediaInDirection() {
        let kinds: [ListItemKind] = [.media(.jpeg), .directory, .directory]
        #expect(target(kinds, from: 0, .down, .list) == nil)
        #expect(target(kinds, from: 2, .down, .list) == nil)
    }

    @Test("Also skips folder and .. rows")
    func navigableSkipsFolders() {
        let kinds: [ListItemKind] = [.parent, .folder, .media(.jpeg), .folder, .media(.png)]
        #expect(target(kinds, from: 2, .down, .list) == 4)
        #expect(target(kinds, from: 2, .up, .list) == nil)
    }

    @Test("Returns nil when all rows are non-media")
    func navigableAllNonMedia() {
        let kinds: [ListItemKind] = [.parent, .directory, .archive]
        #expect(target(kinds, from: 0, .down, .list) == nil)
        #expect(target(kinds, from: nil, .down, .list) == nil)
        #expect(target(kinds, from: nil, .right, .grid(columns: 2)) == nil)
    }

    @Test("A nil currentIndex finds the first media item from the start")
    func navigableNilCurrentIndex() {
        let kinds: [ListItemKind] = [.parent, .directory, .media(.jpeg), .media(.png)]
        #expect(target(kinds, from: nil, .down, .list) == 2)
        #expect(target(kinds, from: nil, .up, .list) == 2)
        #expect(target(kinds, from: nil, .right, .grid(columns: 2)) == 2)
        #expect(target(kinds, from: nil, .left, .grid(columns: 2)) == 2)
    }

    @Test("Left and right in List mode and an empty list still return nil")
    func navigableKeepsBaseNilCases() {
        let kinds: [ListItemKind] = [.media(.jpeg), .media(.png)]
        #expect(target(kinds, from: 0, .right, .list) == nil)
        #expect(target(kinds, from: nil, .left, .list) == nil)
        #expect(target([], from: nil, .down, .list) == nil)
    }

    // MARK: - entryIndex（FR-093）

    private func entry(
        _ kinds: [ListItemKind],
        from currentIndex: Int?
    ) -> Int? {
        FocusNavigator.entryIndex(
            currentIndex: currentIndex,
            fileCount: kinds.count,
            isNavigable: { kinds[$0].isMedia }
        )
    }

    @Test("Preserves selection when a media item is focused")
    func entryKeepsMediaFocus() {
        let kinds: [ListItemKind] = [.media(.jpeg), .media(.png)]
        #expect(entry(kinds, from: 0) == 0)
        #expect(entry(kinds, from: 1) == 1)
    }

    @Test("Selects the first following media item when a non-media item is focused")
    func entryFindsNextMedia() {
        let kinds: [ListItemKind] = [.parent, .folder, .media(.jpeg), .archive, .media(.png)]
        #expect(entry(kinds, from: 0) == 2)
        #expect(entry(kinds, from: 1) == 2)
        #expect(entry(kinds, from: 3) == 4)
    }

    @Test("Selects the nearest preceding media item when none follows")
    func entryFallsBackToPreviousMedia() {
        let kinds: [ListItemKind] = [.media(.jpeg), .folder, .media(.png), .folder, .archive]
        #expect(entry(kinds, from: 3) == 2)
        #expect(entry(kinds, from: 4) == 2)
    }

    @Test("Selects the first media item from the start when nothing is selected")
    func entrySelectsFirstMediaWhenUnselected() {
        let kinds: [ListItemKind] = [.parent, .directory, .media(.jpeg), .media(.png)]
        #expect(entry(kinds, from: nil) == 2)
    }

    @Test("Returns nil when no media items exist")
    func entryReturnsNilWithoutMedia() {
        let kinds: [ListItemKind] = [.parent, .folder, .archive, .directory]
        #expect(entry(kinds, from: 0) == nil)
        #expect(entry(kinds, from: nil) == nil)
        #expect(entry([], from: nil) == nil)
    }

    @Test("An out-of-range currentIndex selects the first media item just like no selection")
    func entryTreatsOutOfRangeAsUnselected() {
        let kinds: [ListItemKind] = [.parent, .directory, .media(.jpeg), .media(.png)]
        #expect(entry(kinds, from: -1) == 2)
        #expect(entry(kinds, from: kinds.count) == 2)
        #expect(entry(kinds, from: 10) == 2)
    }

    @Test("Arrow keys select the first media item after selection is cleared in preview-only mode")
    func navigableNilCurrentIndexAfterPreviewOnly() {
        let kinds: [ListItemKind] = [.parent, .folder, .media(.jpeg), .archive, .media(.png)]
        #expect(target(kinds, from: nil, .up, .list) == 2)
        #expect(target(kinds, from: nil, .down, .list) == 2)
        #expect(target(kinds, from: nil, .left, .grid(columns: 2)) == 2)
        #expect(target(kinds, from: nil, .right, .grid(columns: 2)) == 2)
        #expect(target(kinds, from: nil, .up, .grid(columns: 2)) == 2)
        #expect(target(kinds, from: nil, .down, .grid(columns: 2)) == 2)
        #expect(target(kinds, from: nil, .left, .list) == nil)
        #expect(target(kinds, from: nil, .right, .list) == nil)
    }

    @Test("An always-true isNavigable produces the same results as the existing function")
    func navigableAlwaysTrueMatchesBase() {
        let layouts: [FocusLayout] = [.list, .grid(columns: 1), .grid(columns: 3), .grid(columns: 0), .grid(columns: 10)]
        let moves: [FocusMove] = [.left, .right, .up, .down]
        for count in [0, 1, 2, 5, 10] {
            let currents: [Int?] = [nil] + (0..<count).map { Optional($0) }
            for layout in layouts {
                for move in moves {
                    for current in currents {
                        let expected = FocusNavigator.targetIndex(
                            currentIndex: current, fileCount: count, move: move, layout: layout
                        )
                        let actual = FocusNavigator.targetIndex(
                            currentIndex: current, fileCount: count, move: move, layout: layout,
                            isNavigable: { _ in true }
                        )
                        #expect(
                            actual == expected,
                            "count=\(count) current=\(String(describing: current)) move=\(move) layout=\(layout)"
                        )
                    }
                }
            }
        }
    }
}
