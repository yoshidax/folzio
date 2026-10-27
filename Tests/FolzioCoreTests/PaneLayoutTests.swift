import Foundation
import Testing
@testable import FolzioCore

@Suite("PaneLayout")
struct PaneLayoutTests {
    private let layouts: [PaneLayout] = [.all, .fileListOnly, .previewOnly]

    @Test("init(soloPane:) maps nil, file list, and preview to the three states")
    func initializesFromSoloPane() {
        let cases: [(SoloPane?, PaneLayout)] = [
            (nil, .all),
            (.fileList, .fileListOnly),
            (.preview, .previewOnly),
        ]
        #expect(cases.count == 3)

        for (soloPane, expected) in cases {
            let actual = PaneLayout(soloPane: soloPane)
            #expect(actual == expected, "soloPane=\(String(describing: soloPane))")
        }
    }

    @Test("soloPane reverses init and is nil only for .all")
    func exposesSoloPane() {
        let cases: [(PaneLayout, SoloPane?)] = [
            (.all, nil),
            (.fileListOnly, .fileList),
            (.previewOnly, .preview),
        ]
        #expect(cases.count == 3)

        for (layout, expected) in cases {
            #expect(layout.soloPane == expected, "layout=\(layout)")
        }
    }

    @Test("All 3x2 toggling combinations match the transition table")
    func togglesAccordingToTransitionTable() {
        let cases: [(PaneLayout, SoloPane, PaneLayout)] = [
            (.all, .fileList, .fileListOnly),
            (.all, .preview, .previewOnly),
            (.fileListOnly, .fileList, .all),
            (.fileListOnly, .preview, .previewOnly),
            (.previewOnly, .fileList, .fileListOnly),
            (.previewOnly, .preview, .all),
        ]
        #expect(cases.count == 6)

        for (layout, pane, expected) in cases {
            let actual = layout.toggling(pane)
            #expect(actual == expected, "layout=\(layout), toggling(\(pane))")
        }
    }

    @Test("All 3x4 applyingToolbarSelection combinations match the table without writing back both buttons as pressed")
    func appliesToolbarSelection() {
        let cases: [(PaneLayout, Bool, Bool, PaneLayout)] = [
            (.all, false, false, .all),
            (.all, true, false, .fileListOnly),
            (.all, false, true, .previewOnly),
            (.all, true, true, .all),
            (.fileListOnly, false, false, .all),
            (.fileListOnly, true, false, .fileListOnly),
            (.fileListOnly, false, true, .previewOnly),
            (.fileListOnly, true, true, .previewOnly),
            (.previewOnly, false, false, .all),
            (.previewOnly, true, false, .fileListOnly),
            (.previewOnly, false, true, .previewOnly),
            (.previewOnly, true, true, .fileListOnly),
        ]
        #expect(cases.count == 12)

        for (layout, fileListSelected, previewSelected, expected) in cases {
            let actual = layout.applyingToolbarSelection(
                fileListSelected: fileListSelected,
                previewSelected: previewSelected
            )
            #expect(
                actual == expected,
                "layout=\(layout), fileList=\(fileListSelected), preview=\(previewSelected)"
            )

            let fileListPushed = actual.soloPane == .fileList
            let previewPushed = actual.soloPane == .preview
            #expect(!(fileListPushed && previewPushed), "Returned both sides pressed: \(actual)")
        }
    }

    @Test("isVisible is true only for panes displayed in each state")
    func reportsVisiblePanes() {
        let cases: [(PaneLayout, [Pane])] = [
            (.all, [.tree, .fileList, .preview]),
            (.fileListOnly, [.fileList]),
            (.previewOnly, [.preview]),
        ]
        #expect(cases.count == 3)

        for (layout, visible) in cases {
            for pane in Pane.allCases {
                #expect(layout.isVisible(pane) == visible.contains(pane), "layout=\(layout), pane=\(pane)")
            }
        }
    }

    @Test("All three target states and four focus values match the focusTarget table")
    func computesFocusTarget() {
        let cases: [(PaneLayout, Pane?, Pane?)] = [
            (.all, .tree, nil),
            (.all, .fileList, nil),
            (.all, .preview, nil),
            (.all, nil, nil),
            (.fileListOnly, .tree, .fileList),
            (.fileListOnly, .fileList, nil),
            (.fileListOnly, .preview, .fileList),
            (.fileListOnly, nil, .fileList),
            (.previewOnly, .tree, .preview),
            (.previewOnly, .fileList, .preview),
            (.previewOnly, .preview, nil),
            (.previewOnly, nil, .preview),
        ]
        #expect(cases.count == 12)

        for (layout, focused, expected) in cases {
            let actual = layout.focusTarget(afterSwitchingFrom: focused)
            #expect(actual == expected, "layout=\(layout), focused=\(String(describing: focused))")
        }
    }

    @Test("showsNoMediaMessage is always false for .all and .fileListOnly")
    func noMediaMessageIsFalseOutsidePreviewOnly() {
        let folder = makeFolder()
        let states: [FolderListing.State] = [.loading, .loaded, .empty, .noMatches, .denied, .failed(.systemFailure(systemReason: "x"))]
        let fileSets: [[MediaFile]] = [
            [],
            [file("sub", kind: .folder, in: folder)],
            [file("a.jpg", kind: .media(.jpeg), in: folder)],
        ]

        for layout in [PaneLayout.all, .fileListOnly] {
            for state in states {
                for files in fileSets {
                    let listing = FolderListing(folder: folder, files: files, state: state)
                    #expect(
                        !layout.showsNoMediaMessage(in: listing),
                        "layout=\(layout), state=\(state), files=\(files.map(\.name))"
                    )
                }
            }
        }
    }

    @Test("showsNoMediaMessage is false for loaded previewOnly with media rows")
    func noMediaMessageIsFalseForLoadedWithMedia() {
        let folder = makeFolder()
        let media = file("a.jpg", kind: .media(.jpeg), in: folder)
        let nonMedia = file("sub", kind: .folder, in: folder)

        let onlyMedia = FolderListing(folder: folder, files: [media], state: .loaded)
        #expect(!PaneLayout.previewOnly.showsNoMediaMessage(in: onlyMedia))

        let mixed = FolderListing(folder: folder, files: [nonMedia, media], state: .loaded)
        #expect(!PaneLayout.previewOnly.showsNoMediaMessage(in: mixed))

        let unselected = FolderListing(folder: folder, files: [media], state: .loaded)
        #expect(!PaneLayout.previewOnly.showsNoMediaMessage(in: unselected))
    }

    @Test("showsNoMediaMessage is true for loaded previewOnly with only non-media rows")
    func noMediaMessageIsTrueForLoadedNonMediaRows() {
        let folder = makeFolder()
        let kinds: [ListItemKind] = [.folder, .archive, .directory, .parent]

        for (index, kind) in kinds.enumerated() {
            let rows = [file("row-\(index)", kind: kind, in: folder)]
            let listing = FolderListing(folder: folder, files: rows, state: .loaded)
            #expect(
                PaneLayout.previewOnly.showsNoMediaMessage(in: listing),
                "kind=\(kind)"
            )
        }

        let allRows = [
            file("sub", kind: .folder, in: folder),
            file("a.zip", kind: .archive, in: folder),
            file("dir", kind: .directory, in: folder),
            file("..", kind: .parent, in: folder),
        ]
        let listing = FolderListing(folder: folder, files: allRows, state: .loaded)
        #expect(PaneLayout.previewOnly.showsNoMediaMessage(in: listing))
    }

    @Test("showsNoMediaMessage is true for previewOnly with empty rows while not loading")
    func noMediaMessageIsTrueForEmptyStates() {
        let folder = makeFolder()
        let states: [FolderListing.State] = [.empty, .noMatches, .denied, .failed(.systemFailure(systemReason: "x"))]

        for state in states {
            let listing = FolderListing(folder: folder, files: [], state: state)
            #expect(
                PaneLayout.previewOnly.showsNoMediaMessage(in: listing),
                "state=\(state)"
            )
        }
    }

    @Test("showsNoMediaMessage is false while loading even in previewOnly")
    func noMediaMessageIsFalseWhileLoading() {
        let folder = makeFolder()
        let emptyListing = FolderListing(folder: folder, files: [], state: .loading)
        #expect(!PaneLayout.previewOnly.showsNoMediaMessage(in: emptyListing))

        let nonMediaListing = FolderListing(
            folder: folder,
            files: [file("sub", kind: .folder, in: folder)],
            state: .loading
        )
        #expect(!PaneLayout.previewOnly.showsNoMediaMessage(in: nonMediaListing))
    }

    @Test("shouldAutoSelectEntry is false only while loading and true in all other states")
    func shouldAutoSelectEntryOnlyWhileNotLoading() {
        let folder = makeFolder()

        #expect(!PaneLayout.shouldAutoSelectEntry(
            in: FolderListing(folder: folder, state: .loading)
        ))
        for state in [FolderListing.State.loaded, .empty, .noMatches, .denied, .failed(.systemFailure(systemReason: "x"))] {
            #expect(
                PaneLayout.shouldAutoSelectEntry(in: FolderListing(folder: folder, state: state)),
                "state=\(state)"
            )
        }
    }

    @Test("Three PanePresentation states combined with full screen determine visible panes in six cases")
    func presentationResolvesVisiblePanes() {
        let cases: [(PaneLayout, Bool, [Pane])] = [
            (.all, false, [.tree, .fileList, .preview]),
            (.all, true, [.preview]),
            (.fileListOnly, false, [.fileList]),
            (.fileListOnly, true, [.preview]),
            (.previewOnly, false, [.preview]),
            (.previewOnly, true, [.preview]),
        ]
        #expect(cases.count == 6)

        for (layout, isFullScreen, expectedPanes) in cases {
            let presentation = PanePresentation(layout: layout, isFullScreen: isFullScreen)
            #expect(
                presentation.visiblePanes == expectedPanes,
                "layout=\(layout), isFullScreen=\(isFullScreen)"
            )

            for pane in Pane.allCases {
                #expect(
                    presentation.isVisible(pane) == expectedPanes.contains(pane),
                    "layout=\(layout), isFullScreen=\(isFullScreen), pane=\(pane)"
                )
            }

            #expect(
                presentation.showsAllPanes == (!isFullScreen && layout == .all),
                "layout=\(layout), isFullScreen=\(isFullScreen)"
            )

            let expectedNavigates = isFullScreen || layout == .previewOnly
            #expect(
                presentation.navigatesHiddenFileList == expectedNavigates,
                "layout=\(layout), isFullScreen=\(isFullScreen)"
            )
        }
    }

    @Test("All 3x2x2 PaneCommands combinations match the five rules")
    func commandsFollowRules() {
        var cases = 0

        for layout in layouts {
            for isFullScreen in [false, true] {
                for isEditingText in [false, true] {
                    cases += 1
                    let commands = PaneCommands(
                        layout: layout,
                        isFullScreen: isFullScreen,
                        isEditingText: isEditingText
                    )
                    let label = "layout=\(layout), isFullScreen=\(isFullScreen), isEditingText=\(isEditingText)"

                    #expect(commands.canChangeLayout == (!isFullScreen && !isEditingText), "\(label)")

                    for pane in Pane.allCases {
                        #expect(commands.canFocus(pane) == layout.isVisible(pane), "\(label), pane=\(pane)")
                    }

                    #expect(
                        commands.canGoToFavorites == (!isFullScreen && !isEditingText && layout == .all),
                        "\(label)"
                    )
                    #expect(commands.allowsAddingFavorite == (!isEditingText && layout == .all), "\(label)")
                    #expect(
                        commands.canSearch == (!isFullScreen && !isEditingText && layout.isVisible(.fileList)),
                        "\(label)"
                    )
                    #expect(
                        commands.canNavigateHistory == (!isFullScreen && !isEditingText),
                        "\(label)"
                    )
                }
            }
        }

        #expect(cases == 12)
    }

    @Test("canNavigateHistory is false only during full screen or renaming, regardless of pane visibility")
    func canNavigateHistoryIgnoresLayout() {
        for layout in layouts {
            for isFullScreen in [false, true] {
                for isEditingText in [false, true] {
                    let commands = PaneCommands(
                        layout: layout,
                        isFullScreen: isFullScreen,
                        isEditingText: isEditingText
                    )
                    #expect(
                        commands.canNavigateHistory == (!isFullScreen && !isEditingText),
                        "layout=\(layout), isFullScreen=\(isFullScreen), isEditingText=\(isEditingText)"
                    )
                }
            }
        }
    }

    @Test("fileListOnly enables search and disables Favorites")
    func fileListOnlyCommands() {
        let commands = PaneCommands(layout: .fileListOnly, isFullScreen: false, isEditingText: false)
        #expect(commands.canSearch)
        #expect(!commands.canGoToFavorites)
        #expect(!commands.allowsAddingFavorite)
    }

    @Test("previewOnly disables search, Favorites, and Add to Favorites")
    func previewOnlyCommands() {
        let commands = PaneCommands(layout: .previewOnly, isFullScreen: false, isEditingText: false)
        #expect(!commands.canSearch)
        #expect(!commands.canGoToFavorites)
        #expect(!commands.allowsAddingFavorite)
    }

    @Test("Full screen with .all enables only Add to Favorites")
    func allPanesFullScreenCommands() {
        let commands = PaneCommands(layout: .all, isFullScreen: true, isEditingText: false)
        #expect(!commands.canChangeLayout)
        #expect(!commands.canGoToFavorites)
        #expect(!commands.canSearch)
        #expect(commands.allowsAddingFavorite)
    }

    @Test("Renaming disables all four actions")
    func editingTextDisablesCommands() {
        for layout in layouts {
            for isFullScreen in [false, true] {
                let commands = PaneCommands(
                    layout: layout,
                    isFullScreen: isFullScreen,
                    isEditingText: true
                )
                let label = "layout=\(layout), isFullScreen=\(isFullScreen)"
                #expect(!commands.canChangeLayout, "\(label)")
                #expect(!commands.canGoToFavorites, "\(label)")
                #expect(!commands.allowsAddingFavorite, "\(label)")
                #expect(!commands.canSearch, "\(label)")
            }
        }
    }

    @Test("canFocus is independent of full screen and editing")
    func canFocusIgnoresFullScreenAndEditing() {
        for layout in layouts {
            for pane in Pane.allCases {
                for isFullScreen in [false, true] {
                    for isEditingText in [false, true] {
                        let commands = PaneCommands(
                            layout: layout,
                            isFullScreen: isFullScreen,
                            isEditingText: isEditingText
                        )
                        #expect(
                            commands.canFocus(pane) == layout.isVisible(pane),
                            "layout=\(layout), pane=\(pane), isFullScreen=\(isFullScreen), isEditingText=\(isEditingText)"
                        )
                    }
                }
            }
        }
    }

    @Test("dividerPositions preserves saved widths and gives extra width to the preview")
    func dividerPositionsPreserveSavedWidths() {
        let minimums: [Double] = [160, 240, 320]
        let saved: [Double] = [220, 360, 600]

        #expect(dividerPositions(saved: saved, total: 1182, minimums: minimums) == [220, 581])
        #expect(dividerPositions(saved: saved, total: 1382, minimums: minimums) == [220, 581])
    }

    @Test("Shrinks the file list if the preview is below its minimum width")
    func dividerPositionsShrinkFileList() {
        let positions = dividerPositions(saved: [220, 360, 600], total: 850, minimums: [160, 240, 320])
        #expect(positions == [220, 529])
    }

    @Test("Shrinks the tree if the file list reaches its minimum and the preview still needs space")
    func dividerPositionsShrinkTree() {
        let positions = dividerPositions(saved: [220, 360, 600], total: 730, minimums: [160, 240, 320])
        #expect(positions == [168, 409])
    }

    @Test("Sets the tree and file list to their minimum widths when total width is below the sum of minimums")
    func dividerPositionsUseMinimumsWhenTooNarrow() {
        let positions = dividerPositions(saved: [220, 360, 600], total: 700, minimums: [160, 240, 320])
        #expect(positions == [160, 401])
    }

    @Test("Invalid saved widths use first-launch defaults for a total width of 1182")
    func dividerPositionsFallBackToDefaults() {
        let minimums: [Double] = [160, 240, 320]
        let savedCases: [(String, [Double])] = [
            ("empty", []),
            ("two", [220, 360]),
            ("nan", [220, 360, .nan]),
            ("infinity", [220, 360, .infinity]),
        ]

        for (label, saved) in savedCases {
            let positions = dividerPositions(saved: saved, total: 1182, minimums: minimums)
            #expect(positions == [220, 581], "saved=\(label)")
        }
    }

    private func dividerPositions(saved: [Double], total: Double, minimums: [Double]) -> [Double] {
        PaneWidths.dividerPositions(
            savedWidths: saved,
            totalWidth: total,
            dividerThickness: 1,
            minimumWidths: minimums
        )
    }

    private func makeFolder() -> URL {
        URL(fileURLWithPath: "/tmp/pane-layout-\(UUID().uuidString)", isDirectory: true)
    }

    private func file(_ name: String, kind: ListItemKind, in folder: URL) -> MediaFile {
        MediaFile(
            url: folder.appendingPathComponent(name),
            name: name,
            kind: kind,
            typeDescription: "",
            creationDate: nil,
            fileSize: 0
        )
    }
}
