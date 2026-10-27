import Foundation
import Testing
@testable import FolzioCore

@Suite("NavigationHistory")
struct NavigationHistoryTests {
    private func folder(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/n/\(name)", isDirectory: true)
    }

    private func location(_ name: String) -> HistoryLocation {
        HistoryLocation(folder: folder(name))
    }

    private func state(
        displayMode: DisplayMode = .list,
        thumbnailSize: Double = 128,
        paneLayout: PaneLayout = .all,
        filter: MediaTypeFilter = MediaTypeFilter(),
        showsZipFiles: Bool = false
    ) -> HistoryViewState {
        HistoryViewState(
            presentation: HistoryPresentation(
                displayMode: displayMode,
                thumbnailSize: thumbnailSize,
                paneLayout: paneLayout
            ),
            mediaTypeFilter: filter,
            showsZipFiles: showsZipFiles
        )
    }

    private func entry(
        _ name: String,
        displayMode: DisplayMode = .list,
        thumbnailSize: Double = 128,
        filter: MediaTypeFilter = MediaTypeFilter(),
        showsZipFiles: Bool = false,
        focused: String? = nil
    ) -> HistoryEntry {
        HistoryEntry(
            location: location(name),
            viewState: state(
                displayMode: displayMode,
                thumbnailSize: thumbnailSize,
                filter: filter,
                showsZipFiles: showsZipFiles
            ),
            focusedItem: focused.map(folder)
        )
    }

    @discardableResult
    private func record(
        _ history: inout NavigationHistory,
        _ name: String,
        kind: HistoryRecordKind = .navigation,
        leavingFocus: String? = nil,
        displayMode: DisplayMode = .list,
        thumbnailSize: Double = 128
    ) -> Bool {
        history.record(
            location: location(name),
            viewState: state(displayMode: displayMode, thumbnailSize: thumbnailSize),
            kind: kind,
            leavingFocus: leavingFocus.map(folder)
        )
    }

    private func name(_ history: NavigationHistory) -> String? {
        history.current?.location.folder.lastPathComponent
    }

    @Test("Initially has no current entry and cannot go back or forward")
    func emptyHistory() {
        let history = NavigationHistory()
        #expect(history.current == nil)
        #expect(history.count == 0)
        #expect(history.canGoBack == false)
        #expect(history.canGoForward == false)
        #expect(history.backEntries.isEmpty)
        #expect(history.forwardEntries.isEmpty)
    }

    @Test("The first record creates no back history and leaves Back and Forward unavailable after launch")
    func firstRecord() {
        var history = NavigationHistory()
        #expect(record(&history, "A"))
        #expect(history.backEntries.isEmpty)
        #expect(name(history) == "A")
        #expect(history.canGoBack == false)
        #expect(history.canGoForward == false)
    }

    @Test("Recording A, B, and C creates chronological back history and a current entry; identical state is not recorded")
    func recordsInOrder() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "C")
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A", "B"])
        #expect(name(history) == "C")
        #expect(history.count == 3)

        let version = history.version
        let recorded = history.record(
            location: location("C"),
            viewState: state(),
            kind: .navigation,
            leavingFocus: folder("C/1.jpg")
        )
        #expect(recorded == false)
        #expect(history.version == version)
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A", "B"])
        #expect(history.forwardEntries.isEmpty)
    }

    @Test("leavingFocus is stored in the departing back-history entry and the new entry has nil focus")
    func leavingFocusIsRecorded() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B", leavingFocus: "A/2.jpg")
        #expect(history.backEntries.first?.focusedItem == folder("A/2.jpg"))
        #expect(history.current?.focusedItem == nil)
    }

    @Test("Candidates are the last back entry and the first forward entry")
    func candidates() {
        var history = NavigationHistory()
        #expect(history.candidate(.back) == nil)
        #expect(history.candidate(.forward) == nil)

        record(&history, "A")
        record(&history, "B")
        record(&history, "C")
        #expect(history.candidate(.back)?.location == location("B"))
        #expect(history.candidate(.forward) == nil)

        history.move(.back, leavingFocus: nil)
        #expect(history.candidate(.back)?.location == location("A"))
        #expect(history.candidate(.forward)?.location == location("C"))
    }

    @Test("move stores focus in the departing entry and moves it to the opposite history")
    func movesBothWays() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B", leavingFocus: "A/1.jpg")
        record(&history, "C", leavingFocus: "B/1.jpg")

        let moved = history.move(.back, leavingFocus: folder("C/1.jpg"))
        #expect(moved?.location == location("B"))
        #expect(name(history) == "B")
        #expect(history.forwardEntries.map(\.location.folder.lastPathComponent) == ["C"])
        #expect(history.forwardEntries.first?.focusedItem == folder("C/1.jpg"))
        #expect(history.candidate(.forward)?.focusedItem == folder("C/1.jpg"))

        _ = history.move(.back, leavingFocus: folder("B/2.jpg"))
        #expect(name(history) == "A")
        #expect(history.forwardEntries.map(\.location.folder.lastPathComponent) == ["B", "C"])
        #expect(history.forwardEntries.first?.focusedItem == folder("B/2.jpg"))

        #expect(history.move(.forward, leavingFocus: folder("A/3.jpg"))?.location == location("B"))
        #expect(history.backEntries.last?.focusedItem == folder("A/3.jpg"))
    }

    @Test("move in a direction without a candidate changes nothing")
    func moveWithoutCandidateDoesNothing() {
        var history = NavigationHistory()
        record(&history, "A")
        let version = history.version
        #expect(history.move(.back, leavingFocus: nil) == nil)
        #expect(history.move(.forward, leavingFocus: nil) == nil)
        #expect(history.version == version)
    }

    @Test("Recording a new entry after Back removes forward history to create a branch")
    func branchClearsForward() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "C")
        _ = history.move(.back, leavingFocus: nil)
        _ = history.move(.back, leavingFocus: nil)
        #expect(history.forwardEntries.count == 2)

        record(&history, "E")
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(name(history) == "E")
        #expect(history.forwardEntries.isEmpty)
    }

    @Test("Recording 150 entries retains 100 and allows 99 Back steps (FR-110, SC-031)")
    func capacityKeepsNewestHundred() {
        var history = NavigationHistory()
        for index in 0..<150 {
            record(&history, "F\(index)")
        }
        #expect(history.count == 100)
        #expect(history.backEntries.first?.location.folder.lastPathComponent == "F50")
        #expect(name(history) == "F149")

        var backCount = 0
        while history.move(.back, leavingFocus: nil) != nil {
            backCount += 1
        }
        #expect(backCount == 99)
        #expect(name(history) == "F50")
    }

    @Test("Recording with forward history still retains at most 100 entries")
    func capacityWithForward() {
        var history = NavigationHistory()
        for index in 0..<100 {
            record(&history, "F\(index)")
        }
        for _ in 0..<50 {
            _ = history.move(.back, leavingFocus: nil)
        }
        record(&history, "New")
        #expect(history.count <= NavigationHistory.capacity)
        #expect(history.forwardEntries.isEmpty)
        #expect(name(history) == "New")
    }

    @Test("version increments on changes and stays unchanged for no-ops")
    func versionChanges() {
        var history = NavigationHistory()
        let emptyVersion = history.version
        record(&history, "A")
        #expect(history.version > emptyVersion)
        let version = history.version
        record(&history, "A")
        #expect(history.version == version)
        history.dropCandidate(.back)
        #expect(history.version == version)
        history.removeEntries(within: [], keepingCurrent: true)
        #expect(history.version == version)
    }

    @Test("allEntries orders back history, current entry, and forward history")
    func allEntriesOrder() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "C")
        _ = history.move(.back, leavingFocus: nil)
        #expect(history.allEntries.map(\.location.folder.lastPathComponent) == ["A", "B", "C"])
    }

    @Test("dropCandidate removes a missing candidate and coalesces adjacent identical entries")
    func dropCandidateConsolidates() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "A")
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A", "B"])

        history.dropCandidate(.back)
        #expect(history.backEntries.isEmpty)
        #expect(name(history) == "A")

        for _ in 0..<3 {
            history.dropCandidate(.back)
        }
        #expect(history.backEntries.isEmpty)
        #expect(name(history) == "A")
    }

    @Test("Identical-state pairs not containing the current entry retain the newer entry")
    func consolidationKeepsNewerOutsideCurrent() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "A")
        record(&history, "C")
        history.removeEntries(within: [folder("B")], keepingCurrent: true)
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(name(history) == "C")
    }

    @Test("removeEntries removes descendants and zip contents but preserves siblings sharing a path prefix")
    func removeEntriesWithin() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "B/x")
        history.record(
            location: HistoryLocation(
                folder: folder("B"),
                archive: ArchiveLocation(archive: URL(fileURLWithPath: "/tmp/n/B/t.zip"), directory: "d/")
            ),
            viewState: state(),
            kind: .navigation,
            leavingFocus: nil
        )
        record(&history, "B2")
        record(&history, "C")

        history.removeEntries(within: [folder("B")], keepingCurrent: true)
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A", "B2"])
        #expect(name(history) == "C")
    }

    @Test("keepingCurrent set to false also removes the current entry")
    func removeEntriesRemovesCurrent() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")

        history.removeEntries(within: [folder("B")], keepingCurrent: false)
        #expect(history.current == nil)
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])

        var keeping = NavigationHistory()
        record(&keeping, "A")
        record(&keeping, "B")
        keeping.removeEntries(within: [folder("B")], keepingCurrent: true)
        #expect(name(keeping) == "B")
    }

    @Test("removeEntries(at:) removes by allEntries index and ignores out-of-range indices")
    func removeEntriesAtPositions() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "C")

        history.removeEntries(at: [1])
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(name(history) == "C")

        history.removeEntries(at: [99])
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(name(history) == "C")

        history.removeEntries(at: [1])
        #expect(name(history) == nil)
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
    }

    @Test("renameFolder replaces the current location and removes other affected entries")
    func renameFolderReplacesCurrent() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")

        history.renameFolder(RenamedFolder(from: folder("B"), to: folder("B2")))
        #expect(history.current?.location == location("B2"))
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
    }

    @Test("renameFolder removes old locations from back and forward history and remaps current descendants")
    func renameFolderRemovesOthers() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "C")
        history.renameFolder(RenamedFolder(from: folder("B"), to: folder("B2")))
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(name(history) == "C")

        var below = NavigationHistory()
        record(&below, "B")
        record(&below, "B/x")
        below.renameFolder(RenamedFolder(from: folder("B"), to: folder("B2")))
        #expect(below.current?.location == location("B2/x"))
        #expect(below.backEntries.isEmpty)

        var forward = NavigationHistory()
        record(&forward, "A")
        record(&forward, "B")
        record(&forward, "C")
        _ = forward.move(.back, leavingFocus: nil)
        _ = forward.move(.back, leavingFocus: nil)
        forward.renameFolder(RenamedFolder(from: folder("B"), to: folder("B2")))
        #expect(forward.forwardEntries.map(\.location.folder.lastPathComponent) == ["C"])
        #expect(name(forward) == "A")
    }

    @Test("An unrelated rename also leaves version unchanged")
    func unrelatedRenameDoesNothing() {
        var history = NavigationHistory()
        record(&history, "A")
        let version = history.version
        history.renameFolder(RenamedFolder(from: folder("B"), to: folder("B2")))
        #expect(history.version == version)
        #expect(history.current?.location == location("A"))
    }

    @Test("replaceCurrentLocation changes only the location, preserves forward history, and coalesces neighbors")
    func replaceCurrentLocation() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "C")
        _ = history.move(.back, leavingFocus: nil)
        #expect(history.forwardEntries.count == 1)

        history.replaceCurrentLocation(location("A"))
        #expect(history.current?.location == location("A"))
        #expect(history.backEntries.isEmpty)
        #expect(history.forwardEntries.map(\.location.folder.lastPathComponent) == ["C"])
    }

    @Test("detachCurrent moves the current entry to back history; removeCurrent removes it")
    func detachAndRemoveCurrent() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        history.detachCurrent()
        #expect(history.current == nil)
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A", "B"])
        #expect(history.forwardEntries.isEmpty)

        var removed = NavigationHistory()
        record(&removed, "A")
        record(&removed, "B")
        removed.removeCurrent()
        #expect(removed.current == nil)
        #expect(removed.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
    }

    @Test("Without a current entry, navigation still reaches candidates; recording sets current and clears forward history")
    func movesAndRecordsWithoutCurrent() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "B")
        record(&history, "C")
        _ = history.move(.back, leavingFocus: nil)
        _ = history.move(.back, leavingFocus: nil)
        history.detachCurrent()
        #expect(history.current == nil)
        #expect(history.candidate(.forward)?.location == location("B"))

        #expect(history.move(.forward, leavingFocus: nil)?.location == location("B"))
        #expect(name(history) == "B")
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(history.forwardEntries.map(\.location.folder.lastPathComponent) == ["C"])

        history.detachCurrent()
        record(&history, "E")
        #expect(name(history) == "E")
        #expect(history.forwardEntries.isEmpty)
    }

    @Test("updateCurrentViewState updates only the current entry and coalesces it with an identical previous entry")
    func updateCurrentViewState() {
        var history = NavigationHistory()
        record(&history, "A")
        history.record(
            location: location("A"),
            viewState: state(displayMode: .thumbnails),
            kind: .navigation,
            leavingFocus: nil
        )
        #expect(history.backEntries.count == 1)
        #expect(history.current?.viewState.presentation.displayMode == .thumbnails)

        history.updateCurrentViewState(state(displayMode: .list))
        #expect(history.backEntries.isEmpty)
        #expect(history.count == 1)
        #expect(history.current?.viewState.presentation.displayMode == .list)
    }

    @Test("Consecutive thumbnail size changes coalesce into one entry (US8-AS2)")
    func thumbnailSizeChangesMerge() {
        var history = NavigationHistory()
        record(&history, "A")
        for size in [144.0, 160, 176, 192, 208] {
            record(&history, "A", kind: .thumbnailSize, thumbnailSize: size)
        }
        #expect(history.count == 2)
        #expect(history.backEntries.first?.viewState.presentation.thumbnailSize == 128)
        #expect(history.current?.viewState.presentation.thumbnailSize == 208)
        _ = history.move(.back, leavingFocus: nil)
        #expect(history.current?.viewState.presentation.thumbnailSize == 128)
    }

    @Test("An intervening record separates thumbnail size changes into distinct entries")
    func thumbnailSizeMergeStops() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "A", kind: .thumbnailSize, thumbnailSize: 160)
        history.record(
            location: location("A"),
            viewState: state(displayMode: .thumbnails, thumbnailSize: 160),
            kind: .viewChange,
            leavingFocus: nil
        )
        record(&history, "A", kind: .thumbnailSize, displayMode: .thumbnails, thumbnailSize: 192)
        #expect(history.count == 4)
        #expect(history.current?.viewState.presentation.thumbnailSize == 192)
    }

    @Test("A size change immediately after Back or Forward creates a new entry and clears forward history (US8-AS7)")
    func thumbnailSizeAfterMoveIsNew() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "A", kind: .thumbnailSize, thumbnailSize: 160)
        _ = history.move(.back, leavingFocus: nil)
        #expect(history.current?.viewState.presentation.thumbnailSize == 128)
        #expect(history.canGoForward)

        record(&history, "A", kind: .thumbnailSize, thumbnailSize: 176)
        #expect(history.canGoForward == false)
        #expect(history.backEntries.count == 1)
        #expect(history.current?.viewState.presentation.thumbnailSize == 176)
    }

    @Test("Returning to the original size coalesces changes into one entry; subsequent changes create a new entry")
    func thumbnailSizeReturningToOriginalMerges() {
        var history = NavigationHistory()
        record(&history, "A")
        record(&history, "A", kind: .thumbnailSize, thumbnailSize: 160)
        record(&history, "A", kind: .thumbnailSize, thumbnailSize: 128)
        #expect(history.count == 1)
        #expect(history.current?.viewState.presentation.thumbnailSize == 128)

        record(&history, "A", kind: .thumbnailSize, thumbnailSize: 176)
        #expect(history.count == 2)
        #expect(history.backEntries.first?.viewState.presentation.thumbnailSize == 128)
        #expect(history.current?.viewState.presentation.thumbnailSize == 176)
    }

    @Test("A size change after removing the current entry creates a new entry")
    func thumbnailSizeWithoutCurrent() {
        var history = NavigationHistory()
        record(&history, "A")
        history.removeCurrent()
        record(&history, "A", kind: .thumbnailSize, thumbnailSize: 160)
        #expect(history.count == 1)
        #expect(history.backEntries.isEmpty)
        #expect(history.current?.viewState.presentation.thumbnailSize == 160)
    }

    @Test("Reproduces the documented sequence of state transitions")
    func documentedTransitions() {
        var history = NavigationHistory()
        #expect(history.current == nil)

        record(&history, "A")
        #expect(history.allEntries.map(\.location.folder.lastPathComponent) == ["A"])

        record(&history, "B")
        record(&history, "C")
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A", "B"])
        #expect(name(history) == "C")

        _ = history.move(.back, leavingFocus: nil)
        _ = history.move(.back, leavingFocus: nil)
        #expect(history.backEntries.isEmpty)
        #expect(name(history) == "A")
        #expect(history.forwardEntries.map(\.location.folder.lastPathComponent) == ["B", "C"])

        record(&history, "E")
        #expect(history.backEntries.map(\.location.folder.lastPathComponent) == ["A"])
        #expect(name(history) == "E")
        #expect(history.forwardEntries.isEmpty)
    }
}
