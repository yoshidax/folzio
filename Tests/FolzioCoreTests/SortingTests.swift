import Foundation
import Testing
@testable import FolzioCore

@Suite("Sorting")
struct SortingTests {
    @Test("Compares names in natural order")
    func sortsNamesNaturally() {
        let files = [file("img10.jpg"), file("img2.jpg"), file("img1.jpg")]
        let result = sorted(files, by: SortOrder(column: .name, ascending: true))
        #expect(result.map(\.name) == ["img1.jpg", "img2.jpg", "img10.jpg"])

        let descending = sorted(files, by: SortOrder(column: .name, ascending: false))
        #expect(descending.map(\.name) == ["img10.jpg", "img2.jpg", "img1.jpg"])
    }

    @Test("Nil creation dates sort last in both ascending and descending order")
    func placesMissingCreationDateLast() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let files = [file("none.jpg", created: nil), file("old.jpg", created: old), file("new.jpg", created: new)]

        let ascending = sorted(files, by: SortOrder(column: .creationDate, ascending: true))
        #expect(ascending.map(\.name) == ["old.jpg", "new.jpg", "none.jpg"])

        let descending = sorted(files, by: SortOrder(column: .creationDate, ascending: false))
        #expect(descending.map(\.name) == ["new.jpg", "old.jpg", "none.jpg"])
    }

    @Test("Nil modification dates sort last in both ascending and descending order")
    func placesMissingModificationDateLast() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let files = [file("none.jpg"), file("new.jpg", modified: new), file("old.jpg", modified: old)]

        let ascending = sorted(files, by: SortOrder(column: .modificationDate, ascending: true))
        #expect(ascending.map(\.name) == ["old.jpg", "new.jpg", "none.jpg"])

        let descending = sorted(files, by: SortOrder(column: .modificationDate, ascending: false))
        #expect(descending.map(\.name) == ["new.jpg", "old.jpg", "none.jpg"])
    }

    @Test("Folders and files are ordered together by modification date")
    func mixesFoldersAndFilesByModificationDate() {
        let files = [
            file("late.jpg", modified: Date(timeIntervalSince1970: 300)),
            folder("early", modified: Date(timeIntervalSince1970: 100)),
            file("middle.jpg", modified: Date(timeIntervalSince1970: 200)),
        ]

        let ascending = sorted(files, by: SortOrder(column: .modificationDate, ascending: true))
        #expect(ascending.map(\.name) == ["early", "middle.jpg", "late.jpg"])

        let descending = sorted(files, by: SortOrder(column: .modificationDate, ascending: false))
        #expect(descending.map(\.name) == ["late.jpg", "middle.jpg", "early"])
    }

    @Test("Folders count as 0 bytes when sorting by size: first when ascending, last when descending")
    func sortsFoldersAsZeroBytes() {
        let files = [
            file("big.jpg", size: 2_000), folder("b", fileSize: 99_999), file("small.jpg", size: 1_000), folder("a"),
        ]

        let ascending = sorted(files, by: SortOrder(column: .size, ascending: true))
        #expect(ascending.map(\.name) == ["a", "b", "small.jpg", "big.jpg"])

        let descending = sorted(files, by: SortOrder(column: .size, ascending: false))
        #expect(descending.map(\.name) == ["big.jpg", "small.jpg", "a", "b"])
    }

    @Test("Equal sizes use natural name order as the secondary key")
    func breaksSizeTiesByName() {
        let files = [file("b.jpg", size: 5), file("a10.jpg", size: 5), file("a2.jpg", size: 5)]
        let result = sorted(files, by: SortOrder(column: .size, ascending: false))
        #expect(result.map(\.name) == ["a2.jpg", "a10.jpg", "b.jpg"])
    }

    @Test("Only files and zip files have a size to show")
    func hasFileSizeByKind() {
        #expect(file("a.jpg").hasFileSize)
        #expect(!folder("a").hasFileSize)
        let kinds: [ListItemKind] = [.archive, .directory, .parent]
        #expect(kinds.map { kind in
            MediaFile(url: URL(fileURLWithPath: "/tmp/x"), name: "x", kind: kind, typeDescription: "", creationDate: nil, fileSize: 1).hasFileSize
        } == [true, false, false])
    }

    @Test("Equal values use natural name order as the secondary key")
    func breaksTiesByName() {
        let sameDate = Date(timeIntervalSince1970: 100)
        let files = [file("b.jpg", created: sameDate), file("a10.jpg", created: sameDate), file("a2.jpg", created: sameDate)]
        let result = sorted(files, by: SortOrder(column: .creationDate, ascending: true))
        #expect(result.map(\.name) == ["a2.jpg", "a10.jpg", "b.jpg"])
    }

    @Test("Sorts kinds by display name")
    func sortsByKindDescription() {
        let files = [
            file("c.mp4", typeDescription: "MPEG-4 ムービー"),
            file("b.jpg", typeDescription: "JPEG イメージ"),
            file("a.png", typeDescription: "PNG イメージ"),
        ]
        let result = sorted(files, by: SortOrder(column: .kind, ascending: true))
        #expect(result.map(\.name) == ["b.jpg", "c.mp4", "a.png"])
    }

    @Test("The .. row always sorts first regardless of column or direction")
    func keepsParentRowFirst() {
        let created = Date(timeIntervalSince1970: 100)
        let files = [
            item("c.png", .media(.png), created: created),
            item("..", .parent, created: nil),
            item("a.jpg", .media(.jpeg), created: created),
            item("b", .directory, created: created),
        ]
        for column in [SortColumn.name, .creationDate, .kind] {
            for ascending in [true, false] {
                let result = sorted(files, by: SortOrder(column: column, ascending: ascending))
                #expect(result.first?.name == "..", "column=\(column) ascending=\(ascending)")
                #expect(result.count == files.count)
            }
        }
    }

    @Test("Name sort groups zip directories before media in both directions (FR-288)")
    func groupsDirectoriesBeforeMediaByName() {
        let files = [
            item("c.png", .media(.png)),
            item("..", .parent),
            item("b", .directory),
            item("a.jpg", .media(.jpeg)),
            item("d", .directory),
        ]
        let ascending = sorted(files, by: SortOrder(column: .name, ascending: true))
        #expect(ascending.map(\.name) == ["..", "b", "d", "a.jpg", "c.png"])

        let descending = sorted(files, by: SortOrder(column: .name, ascending: false))
        #expect(descending.map(\.name) == ["..", "d", "b", "c.png", "a.jpg"])
    }

    @Test("Name sort puts folders first and keeps zip files with the files (FR-288)")
    func groupsFoldersFirstByName() {
        let files = [
            item("c.png", .media(.png)),
            item("e.zip", .archive),
            item("b", .folder),
            item("a.jpg", .media(.jpeg)),
            item("d", .folder),
        ]
        let ascending = sorted(files, by: SortOrder(column: .name, ascending: true))
        #expect(ascending.map(\.name) == ["b", "d", "a.jpg", "c.png", "e.zip"])

        let descending = sorted(files, by: SortOrder(column: .name, ascending: false))
        #expect(descending.map(\.name) == ["d", "b", "e.zip", "c.png", "a.jpg"])
    }

    @Test("Other columns still mix folders and files")
    func otherColumnsStillMixFolders() {
        let modified = { (seconds: Double) in Date(timeIntervalSince1970: seconds) }
        let files = [
            file("late.jpg", modified: modified(300)),
            folder("early", modified: modified(100)),
            file("middle.jpg", modified: modified(200)),
        ]
        #expect(
            sorted(files, by: SortOrder(column: .modificationDate, ascending: true)).map(\.name)
                == ["early", "middle.jpg", "late.jpg"]
        )
    }

    @Test("Folders and files sort with folders first and .. always comes first")
    func mixesFoldersWithFiles() {
        let created = Date(timeIntervalSince1970: 100)
        let files = [
            item("c.png", .media(.png), created: created),
            item("d.zip", .archive, created: created),
            item("..", .parent, created: nil),
            item("b", .folder, created: created),
            item("a.jpg", .media(.jpeg), created: created),
        ]
        let ascending = sorted(files, by: SortOrder(column: .name, ascending: true))
        #expect(ascending.map(\.name) == ["..", "b", "a.jpg", "c.png", "d.zip"])
        let descending = sorted(files, by: SortOrder(column: .name, ascending: false))
        #expect(descending.map(\.name) == ["..", "b", "d.zip", "c.png", "a.jpg"])

        for column in [SortColumn.name, .creationDate, .kind] {
            for ascending in [true, false] {
                let result = sorted(files, by: SortOrder(column: column, ascending: ascending))
                #expect(result.first?.name == "..", "column=\(column) ascending=\(ascending)")
                #expect(result.count == files.count)
            }
        }
    }

    // MARK: - Location and sortedMerge (FR-084, 085)

    @Test("Locations sort by natural parent-folder path order, then by natural name order within the same location")
    func sortsByLocation() {
        let files = ["/r/b/x.jpg", "/r/a/z.jpg", "/r/a/y.jpg", "/r/a10/w.jpg", "/r/a2/v.jpg"].map(located)
        let ascending = sorted(files, by: SortOrder(column: .location, ascending: true))
        #expect(ascending.map(\.url.path) == ["/r/a/y.jpg", "/r/a/z.jpg", "/r/a2/v.jpg", "/r/a10/w.jpg", "/r/b/x.jpg"])

        let descending = sorted(files, by: SortOrder(column: .location, ascending: false))
        #expect(descending.map(\.url.path) == ["/r/b/x.jpg", "/r/a10/w.jpg", "/r/a2/v.jpg", "/r/a/y.jpg", "/r/a/z.jpg"])
    }

    @Test("sortedMerge matches sorted(a + b) with rows from a first on ties")
    func sortedMergeMatchesSorted() {
        var generator = SeededGenerator(seed: 0x5EA2C4)
        let dates: [Date?] = [nil, Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200), Date(timeIntervalSince1970: 300)]
        let names = ["a.jpg", "b.png", "c 2.jpg", "img10.mp4", "img2.jpg", "Cat.mov", "z.webp"]
        let folders = ["/r/a", "/r/a2", "/r/a10", "/r/b"]
        let types = ["JPEG イメージ", "PNG イメージ", "ムービー"]
        var serial = 0
        func randomFiles() -> [MediaFile] {
            let count = Int.random(in: 0...50, using: &generator)
            return (0..<count).map { _ in
                serial += 1
                let name = names.randomElement(using: &generator)!
                let folder = folders.randomElement(using: &generator)!
                return MediaFile(
                    // Also create rows with the same name and location (ties), distinguished by a fileSize sequence
                    // number.
                    url: URL(fileURLWithPath: "\(folder)/\(name)"),
                    name: name,
                    // Roughly one row in four is a folder so the name sort's folder grouping (FR-288) is exercised.
                    kind: Int.random(in: 0..<4, using: &generator) == 0
                        ? .folder
                        : .media(MediaKind(fileExtension: (name as NSString).pathExtension) ?? .jpeg),
                    typeDescription: types.randomElement(using: &generator)!,
                    creationDate: dates.randomElement(using: &generator)!,
                    fileSize: Int64(serial)
                )
            }
        }

        for column in [SortColumn.name, .creationDate, .kind, .location] {
            for ascending in [true, false] {
                let order = SortOrder(column: column, ascending: ascending)
                for _ in 0..<100 {
                    let a = sorted(randomFiles(), by: order)
                    let b = sorted(randomFiles(), by: order)
                    let merged = sortedMerge(a, b, by: order)
                    let expected = sorted(a + b, by: order)
                    #expect(merged.map(\.fileSize) == expected.map(\.fileSize), "column=\(column) ascending=\(ascending)")
                }
            }
        }
    }

    @Test("resortRow matches sorted after one row's key changes, including ties")
    func resortRowMatchesSorted() {
        var generator = SeededGenerator(seed: 0x2E50_47ED)
        let dates: [Date?] = [nil, Date(timeIntervalSince1970: 100), Date(timeIntervalSince1970: 200)]
        // Few distinct names, sizes, and types so the changed row often ties with other rows on every column.
        let names = ["a.jpg", "b.png", "img10.mp4", "img2.jpg", "Cat.mov"]
        let sizes: [Int64] = [0, 10, 20]
        let folders = ["/r/a", "/r/a2", "/r/b"]
        let types = ["JPEG イメージ", "PNG イメージ", "ムービー"]
        var serial = 0
        func randomFile() -> MediaFile {
            serial += 1
            let name = names.randomElement(using: &generator)!
            return MediaFile(
                // The sequence number in the path identifies each row; no column compares it.
                url: URL(fileURLWithPath: "\(folders.randomElement(using: &generator)!)/\(serial)/\(name)"),
                name: name,
                kind: Int.random(in: 0..<4, using: &generator) == 0
                    ? .folder
                    : .media(MediaKind(fileExtension: (name as NSString).pathExtension) ?? .jpeg),
                typeDescription: types.randomElement(using: &generator)!,
                creationDate: dates.randomElement(using: &generator)!,
                fileSize: sizes.randomElement(using: &generator)!
            )
        }

        for column in SortColumn.allCases where column != .location {
            for ascending in [true, false] {
                let order = SortOrder(column: column, ascending: ascending)
                for _ in 0..<100 {
                    var files = sorted((0..<Int.random(in: 1...40, using: &generator)).map { _ in randomFile() }, by: order)
                    let index = Int.random(in: 0..<files.count, using: &generator)
                    files[index].name = names.randomElement(using: &generator)!
                    files[index].fileSize = sizes.randomElement(using: &generator)!
                    let expected = sorted(files, by: order)
                    resortRow(in: &files, at: index, by: order)
                    #expect(files.map(\.url.path) == expected.map(\.url.path), "column=\(column) ascending=\(ascending)")
                }
            }
        }
    }

    @Test("resortRow falls back to a full sort for a .. row and keeps it first")
    func resortRowWithParentRow() {
        let order = SortOrder(column: .name, ascending: true)
        var files = [file("b.jpg"), item("..", .parent), file("a.jpg")]
        let expected = sorted(files, by: order)
        resortRow(in: &files, at: 1, by: order)
        #expect(files.map(\.name) == expected.map(\.name))
        #expect(files.map(\.name) == ["..", "a.jpg", "b.jpg"])
    }

    @Test("sortedMerge also matches when either input is empty")
    func sortedMergeWithEmptySide() {
        let order = SortOrder(column: .name, ascending: true)
        let files = sorted([file("b.jpg"), file("a.jpg")], by: order)
        #expect(sortedMerge(files, [], by: order).map(\.name) == ["a.jpg", "b.jpg"])
        #expect(sortedMerge([], files, by: order).map(\.name) == ["a.jpg", "b.jpg"])
        #expect(sortedMerge([], [], by: order).isEmpty)
    }

    private func located(_ path: String) -> MediaFile {
        let url = URL(fileURLWithPath: path)
        return MediaFile(
            url: url,
            name: url.lastPathComponent,
            kind: .media(.jpeg),
            typeDescription: "JPEG イメージ",
            creationDate: nil,
            fileSize: 0
        )
    }

    private func item(_ name: String, _ kind: ListItemKind, created: Date? = nil) -> MediaFile {
        MediaFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: kind,
            typeDescription: "",
            creationDate: created,
            fileSize: 0
        )
    }

    private func file(
        _ name: String,
        created: Date? = nil,
        modified: Date? = nil,
        size: Int64 = 0,
        typeDescription: String = "JPEG イメージ"
    ) -> MediaFile {
        MediaFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: .media(MediaKind(fileExtension: (name as NSString).pathExtension) ?? .jpeg),
            typeDescription: typeDescription,
            creationDate: created,
            modificationDate: modified,
            fileSize: size
        )
    }

    private func folder(_ name: String, modified: Date? = nil, fileSize: Int64 = 0) -> MediaFile {
        MediaFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            kind: .folder,
            typeDescription: "Folder",
            creationDate: nil,
            modificationDate: modified,
            fileSize: fileSize
        )
    }
}

/// Fixed-seed random number generator (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
