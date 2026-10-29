import Testing
@testable import FolzioCore

@Suite("ListItemCommands")
struct ListItemCommandsTests {
    private static let allKinds: [ListItemKind] = [.media(.jpeg), .media(.mp4), .archive, .folder, .directory, .parent]

    // MARK: - Regular Folders (Outside a Zip)

    @Test("Media outside a zip supports operations but cannot be entered or navigated up from")
    func mediaOutsideArchive() {
        let commands = ListItemCommands(kind: .media(.jpeg), isBrowsingArchive: false)
        #expect(commands.canOpenContainer == false)
        #expect(commands.canGoUp == false)
        #expect(commands.allowsFileOperations == true)
        #expect(commands.allowsPaste == true)
    }

    @Test("Videos outside a zip behave the same as images")
    func videoOutsideArchive() {
        let commands = ListItemCommands(kind: .media(.mov), isBrowsingArchive: false)
        #expect(commands.canOpenContainer == false)
        #expect(commands.canGoUp == false)
        #expect(commands.allowsFileOperations == true)
        #expect(commands.allowsPaste == true)
    }

    @Test("Zip files outside a zip can be entered and support all operations")
    func archiveOutsideArchive() {
        let commands = ListItemCommands(kind: .archive, isBrowsingArchive: false)
        #expect(commands.canOpenContainer == true)
        #expect(commands.canGoUp == false)
        #expect(commands.allowsFileOperations == true)
        #expect(commands.allowsPaste == true)
    }

    @Test("Without a selected row outside a zip, file operations and paste are enabled but entry is disabled")
    func noFocusOutsideArchive() {
        let commands = ListItemCommands(kind: nil, isBrowsingArchive: false)
        #expect(commands.canOpenContainer == false)
        #expect(commands.canGoUp == false)
        #expect(commands.allowsFileOperations == true)
        #expect(commands.allowsPaste == true)
    }

    @Test("canGoUp is false for every row kind outside a zip")
    func canGoUpIsFalseOutsideArchive() {
        for kind in Self.allKinds {
            #expect(ListItemCommands(kind: kind, isBrowsingArchive: false).canGoUp == false, "kind=\(kind)")
        }
    }

    @Test("Folder rows in regular folders can be entered and support all operations")
    func folderOutsideArchive() {
        let commands = ListItemCommands(kind: .folder, isBrowsingArchive: false)
        #expect(commands.canOpenContainer == true)
        #expect(commands.allowsFileOperations == true)
        #expect(commands.allowsPaste == true)
    }

    @Test("The .. row in a regular folder opens but cannot be operated on; paste targets the current folder")
    func parentOutsideArchive() {
        let commands = ListItemCommands(kind: .parent, isBrowsingArchive: false, hasEnclosingLevel: true)
        #expect(commands.canOpenContainer == true)
        #expect(commands.canGoUp == true)
        #expect(commands.allowsFileOperations == false)
        #expect(commands.allowsPaste == true)
    }

    @Test("Omitting hasEnclosingLevel makes canGoUp equal isBrowsingArchive")
    func hasEnclosingLevelDefaultsToBrowsingArchive() {
        let kinds: [ListItemKind?] = Self.allKinds + [nil]
        for kind in kinds {
            #expect(ListItemCommands(kind: kind, isBrowsingArchive: false).hasEnclosingLevel == false)
            #expect(ListItemCommands(kind: kind, isBrowsingArchive: true).hasEnclosingLevel == true)
        }
    }

    @Test("Outside a zip, canGoUp follows parent availability for every row kind")
    func canGoUpFollowsEnclosingLevel() {
        let kinds: [ListItemKind?] = Self.allKinds + [nil]
        for kind in kinds {
            let label = "kind=\(String(describing: kind))"
            #expect(ListItemCommands(kind: kind, isBrowsingArchive: false, hasEnclosingLevel: true).canGoUp == true, Comment(rawValue: label))
            #expect(ListItemCommands(kind: kind, isBrowsingArchive: false, hasEnclosingLevel: false).canGoUp == false, Comment(rawValue: label))
        }
    }

    // MARK: - Inside a Zip

    @Test("Media inside a zip cannot be entered, allows going up, and disables file operations and paste")
    func mediaInsideArchive() {
        for kind in [ListItemKind.media(.png), .media(.mp4)] {
            let commands = ListItemCommands(kind: kind, isBrowsingArchive: true)
            #expect(commands.canOpenContainer == false, "kind=\(kind)")
            #expect(commands.canGoUp == true, "kind=\(kind)")
            #expect(commands.allowsFileOperations == false, "kind=\(kind)")
            #expect(commands.allowsPaste == false, "kind=\(kind)")
        }
    }

    @Test("Directories inside a zip can be entered")
    func directoryInsideArchive() {
        let commands = ListItemCommands(kind: .directory, isBrowsingArchive: true)
        #expect(commands.canOpenContainer == true)
        #expect(commands.canGoUp == true)
        #expect(commands.allowsFileOperations == false)
        #expect(commands.allowsPaste == false)
    }

    @Test("The .. row inside a zip allows going up")
    func parentInsideArchive() {
        let commands = ListItemCommands(kind: .parent, isBrowsingArchive: true)
        #expect(commands.canOpenContainer == true)
        #expect(commands.canGoUp == true)
        #expect(commands.allowsFileOperations == false)
        #expect(commands.allowsPaste == false)
    }

    @Test("Without a selected row inside a zip, going up is enabled but entry and operations are disabled")
    func noFocusInsideArchive() {
        let commands = ListItemCommands(kind: nil, isBrowsingArchive: true)
        #expect(commands.canOpenContainer == false)
        #expect(commands.canGoUp == true)
        #expect(commands.allowsFileOperations == false)
        #expect(commands.allowsPaste == false)
    }

    @Test("Every row kind inside a zip is read-only and allows going up")
    func insideArchiveIsReadOnlyForEveryKind() {
        let kinds: [ListItemKind?] = Self.allKinds + [nil]
        for kind in kinds {
            let commands = ListItemCommands(kind: kind, isBrowsingArchive: true)
            #expect(commands.allowsFileOperations == false, "kind=\(String(describing: kind))")
            #expect(commands.allowsPaste == false, "kind=\(String(describing: kind))")
            #expect(commands.canGoUp == true, "kind=\(String(describing: kind))")
        }
    }

    // MARK: - Search Results (FR-087)

    @Test("Search results disable paste and going up; other file operations match regular folders")
    func searchResults() {
        let commands = ListItemCommands(
            kind: .media(.jpeg),
            isBrowsingArchive: false,
            hasEnclosingLevel: true,
            isShowingSearchResults: true
        )
        #expect(commands.allowsPaste == false)
        #expect(commands.canGoUp == false)
        #expect(commands.allowsFileOperations == true)
        #expect(commands.canOpenContainer == false)

        let noFocus = ListItemCommands(kind: nil, isBrowsingArchive: false, isShowingSearchResults: true)
        #expect(noFocus.allowsPaste == false)
    }

    @Test("Omitting isShowingSearchResults preserves existing results")
    func searchFlagDefaultsToFalse() {
        let kinds: [ListItemKind?] = Self.allKinds + [nil]
        for kind in kinds {
            for archive in [false, true] {
                for enclosing in [false, true] {
                    let omitted = ListItemCommands(kind: kind, isBrowsingArchive: archive, hasEnclosingLevel: enclosing)
                    let explicit = ListItemCommands(
                        kind: kind,
                        isBrowsingArchive: archive,
                        hasEnclosingLevel: enclosing,
                        isShowingSearchResults: false
                    )
                    #expect(omitted == explicit)
                    #expect(omitted.canGoUp == enclosing)
                    #expect(omitted.allowsPaste == !archive)
                }
            }
        }
    }

    // MARK: - Copy as Pathname (FR-181, FR-183)

    @Test("Copy as Pathname needs exactly one selected non-parent row outside a zip")
    func copyPathnameOutsideArchive() {
        for kind in [ListItemKind.media(.jpeg), .media(.mp4), .archive, .folder] {
            let commands = ListItemCommands(kind: kind, isBrowsingArchive: false)
            #expect(commands.allowsCopyPathname(selectionCount: 1) == true, "kind=\(kind)")
            #expect(commands.allowsCopyPathname(selectionCount: 0) == false, "kind=\(kind)")
            #expect(commands.allowsCopyPathname(selectionCount: 2) == false, "kind=\(kind)")
        }
    }

    @Test("Copy as Pathname is available for search results")
    func copyPathnameInSearchResults() {
        let commands = ListItemCommands(kind: .folder, isBrowsingArchive: false, isShowingSearchResults: true)
        #expect(commands.allowsCopyPathname(selectionCount: 1) == true)
    }

    @Test("Copy as Pathname is unavailable for the .. row and for everything inside a zip")
    func copyPathnameUnavailable() {
        #expect(
            ListItemCommands(kind: .parent, isBrowsingArchive: false, hasEnclosingLevel: true)
                .allowsCopyPathname(selectionCount: 1) == false
        )
        for kind in Self.allKinds {
            #expect(
                ListItemCommands(kind: kind, isBrowsingArchive: true).allowsCopyPathname(selectionCount: 1) == false,
                "kind=\(kind)"
            )
        }
    }
}
