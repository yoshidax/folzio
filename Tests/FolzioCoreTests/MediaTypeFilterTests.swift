import Foundation
import Testing
@testable import FolzioCore

@Suite("MediaTypeFilter")
struct MediaTypeFilterTests {
    private static let combinations: [(imagesOnly: Bool, videosOnly: Bool)] = [
        (false, false), (true, false), (false, true), (true, true),
    ]

    @Test("Both options default to off")
    func defaultsAreOff() {
        let filter = MediaTypeFilter()
        #expect(filter.imagesOnly == false)
        #expect(filter.videosOnly == false)
    }

    @Test("includes handles all six kinds correctly for all four combinations")
    func includesForAllCombinations() {
        for combo in Self.combinations {
            let filter = MediaTypeFilter(imagesOnly: combo.imagesOnly, videosOnly: combo.videosOnly)
            for kind in MediaKind.allCases {
                let expected: Bool
                switch (combo.imagesOnly, combo.videosOnly) {
                case (true, false): expected = !kind.isVideo
                case (false, true): expected = kind.isVideo
                default: expected = true
                }
                #expect(
                    filter.includes(kind) == expected,
                    "imagesOnly=\(combo.imagesOnly) videosOnly=\(combo.videosOnly) kind=\(kind)"
                )
            }
        }
    }

    @Test("isFiltering is true only when exactly one option is enabled")
    func isFilteringOnlyWhenExactlyOneIsOn() {
        #expect(MediaTypeFilter(imagesOnly: false, videosOnly: false).isFiltering == false)
        #expect(MediaTypeFilter(imagesOnly: true, videosOnly: false).isFiltering == true)
        #expect(MediaTypeFilter(imagesOnly: false, videosOnly: true).isFiltering == true)
        #expect(MediaTypeFilter(imagesOnly: true, videosOnly: true).isFiltering == false)
    }

    @Test("apply filters while preserving order")
    func applyKeepsOrder() {
        let folder = URL(fileURLWithPath: "/tmp/filter", isDirectory: true)
        let files = ["b.mov", "a.jpg", "c.mp4", "d.png"].map { file($0, in: folder) }

        #expect(MediaTypeFilter(imagesOnly: true).apply(to: files).map(\.name) == ["a.jpg", "d.png"])
        #expect(MediaTypeFilter(videosOnly: true).apply(to: files).map(\.name) == ["b.mov", "c.mp4"])
        #expect(MediaTypeFilter().apply(to: files).map(\.name) == files.map(\.name))
        #expect(
            MediaTypeFilter(imagesOnly: true, videosOnly: true).apply(to: files).map(\.name)
                == files.map(\.name)
        )
    }

    @Test("apply always preserves non-media rows including zip, directories, and ... in their original order")
    func applyKeepsNonMediaRows() {
        let folder = URL(fileURLWithPath: "/tmp/filter", isDirectory: true)
        let files = [
            item("..", .parent, in: folder),
            item("sub", .directory, in: folder),
            item("a.jpg", .media(.jpeg), in: folder),
            item("pack.zip", .archive, in: folder),
            item("b.mov", .media(.mov), in: folder),
            item("c.png", .media(.png), in: folder),
        ]

        #expect(
            MediaTypeFilter(imagesOnly: true).apply(to: files).map(\.name)
                == ["..", "sub", "a.jpg", "pack.zip", "c.png"]
        )
        #expect(
            MediaTypeFilter(videosOnly: true).apply(to: files).map(\.name)
                == ["..", "sub", "pack.zip", "b.mov"]
        )
        #expect(MediaTypeFilter().apply(to: files).map(\.name) == files.map(\.name))
    }

    @Test("Non-media rows remain while filtering even when there are no media rows")
    func applyKeepsOnlyNonMediaRows() {
        let folder = URL(fileURLWithPath: "/tmp/filter", isDirectory: true)
        let files = [item("..", .parent, in: folder), item("sub", .directory, in: folder)]
        #expect(MediaTypeFilter(imagesOnly: true).apply(to: files).map(\.name) == ["..", "sub"])
        #expect(MediaTypeFilter(videosOnly: true).apply(to: files).map(\.name) == ["..", "sub"])
    }

    @Test("apply preserves folder rows and their order")
    func applyKeepsFolderRows() {
        let folder = URL(fileURLWithPath: "/tmp/filter", isDirectory: true)
        let files = [
            item("..", .parent, in: folder),
            item("a.jpg", .media(.jpeg), in: folder),
            item("album", .folder, in: folder),
            item("b.mov", .media(.mov), in: folder),
        ]
        #expect(MediaTypeFilter(imagesOnly: true).apply(to: files).map(\.name) == ["..", "a.jpg", "album"])
        #expect(MediaTypeFilter(videosOnly: true).apply(to: files).map(\.name) == ["..", "album", "b.mov"])
    }

    @Test("apply returns an empty array for an empty array")
    func applyToEmpty() {
        for combo in Self.combinations {
            let filter = MediaTypeFilter(imagesOnly: combo.imagesOnly, videosOnly: combo.videosOnly)
            #expect(filter.apply(to: []).isEmpty)
        }
    }

    @Test("emptyState returns a kind-specific value only while filtering")
    func emptyState() {
        #expect(MediaTypeFilter(imagesOnly: true).emptyState == .imagesOnly)
        #expect(MediaTypeFilter(videosOnly: true).emptyState == .videosOnly)
        #expect(MediaTypeFilter().emptyState == nil)
        #expect(MediaTypeFilter(imagesOnly: true, videosOnly: true).emptyState == nil)
    }

    // MARK: - SelectionState.restricted(toVisible:)

    @Test("If focus remains visible, selection retains only visible items and focus is preserved")
    func restrictedKeepsVisibleFocus() {
        let (a, b, v) = (url("a.jpg"), url("b.png"), url("v.mov"))
        let state = SelectionState(selected: [a, v], focused: a)
        let result = state.restricted(toVisible: [a, b])
        #expect(result.selected == [a])
        #expect(result.focused == a)
    }

    @Test("If focus is hidden but selection remains, the last selected item in display order becomes focused")
    func restrictedMovesFocusToLastVisibleSelected() {
        let (a, b, c, v) = (url("a.jpg"), url("b.png"), url("c.gif"), url("v.mov"))
        let state = SelectionState(selected: [a, c, v], focused: v)

        let first = state.restricted(toVisible: [c, b, a])
        #expect(first.selected == [a, c])
        #expect(first.focused == a)

        let second = state.restricted(toVisible: [a, b, c])
        #expect(second.selected == [a, c])
        #expect(second.focused == c)
    }

    @Test("No remaining selection clears selection and sets focus to nil")
    func restrictedClearsWhenNothingRemains() {
        let (a, b, v) = (url("a.jpg"), url("b.png"), url("v.mov"))
        let result = SelectionState(selected: [v], focused: v).restricted(toVisible: [a, b])
        #expect(result.selected.isEmpty)
        #expect(result.focused == nil)
    }

    @Test("Absent focus remains nil")
    func restrictedKeepsNilFocus() {
        let a = url("a.jpg")
        let result = SelectionState(selected: [a], focused: nil).restricted(toVisible: [a])
        #expect(result.selected == [a])
        #expect(result.focused == nil)
    }

    @Test("An empty display clears selection and sets focus to nil")
    func restrictedToEmptyVisible() {
        let (a, v) = (url("a.jpg"), url("v.mov"))
        let result = SelectionState(selected: [a, v], focused: a).restricted(toVisible: [])
        #expect(result.selected.isEmpty)
        #expect(result.focused == nil)
    }

    // MARK: - Helpers

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/filter", isDirectory: true).appendingPathComponent(name)
    }

    private func item(_ name: String, _ kind: ListItemKind, in folder: URL) -> MediaFile {
        MediaFile(
            url: folder.appendingPathComponent(name),
            name: name,
            kind: kind,
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
    }

    private func file(_ name: String, in folder: URL) -> MediaFile {
        MediaFile(
            url: folder.appendingPathComponent(name),
            name: name,
            kind: .media(MediaKind(fileExtension: (name as NSString).pathExtension) ?? .jpeg),
            typeDescription: "JPEG イメージ",
            creationDate: nil,
            fileSize: 0
        )
    }
}
