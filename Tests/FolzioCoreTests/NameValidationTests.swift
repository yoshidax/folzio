import Foundation
import Testing
@testable import FolzioCore

@Suite("NameValidation")
struct NameValidationTests {
    private let file = URL(fileURLWithPath: "/tmp/a.jpg")
    private let existingNames: Set<String> = ["a.jpg", "photo.png"]

    @Test("Rejects invalid names and collisions with supplied sibling names", arguments: [
        "",
        "   ",
        "a/b.jpg",
        "a:b.jpg",
        ".hidden.jpg",
        "A.JPG",
    ])
    func rejectsInvalidNames(name: String) {
        guard case .invalid = validateNewName(name, for: file, existingNames: existingNames) else {
            Issue.record("\(String(reflecting: name)) was accepted")
            return
        }
    }

    @Test("Accepts case-only changes when only the source entry is excluded", arguments: ["A.JPG", "a.JPG"])
    func acceptsCaseOnlySourceRename(name: String) {
        #expect(validateNewName(name, for: file, existingNames: ["photo.png"]) == .ok)
        #expect(validateNewName(name, for: file, existingNames: ["A.jpg"]) == .invalid(.duplicate))
    }

    @Test("Requests confirmation when the extension changes")
    func asksForExtensionChange() {
        #expect(
            validateNewName("a.png", for: file, existingNames: existingNames)
                == .needsExtensionChangeConfirmation
        )
        #expect(
            validateNewName("a", for: file, existingNames: existingNames)
                == .needsExtensionChangeConfirmation
        )
    }

    @Test("Accepts names with the same extension")
    func acceptsValidName() {
        #expect(validateNewName("b.jpg", for: file, existingNames: existingNames) == .ok)
        #expect(validateNewName("B.JPG", for: file, existingNames: existingNames) == .ok)
    }

    @Test("Rejects a name present in the supplied sibling set")
    func rejectsSameName() {
        #expect(validateNewName("a.jpg", for: file, existingNames: existingNames) == .invalid(.duplicate))
    }

    @Test("Accepts a folder's case-only change but rejects another sibling")
    func validatesCaseOnlyFolderRename() {
        let folder = URL(fileURLWithPath: "/tmp/Album", isDirectory: true)
        #expect(validateNewName("album", for: folder, existingNames: [], isDirectory: true) == .ok)
        #expect(validateNewName("album", for: folder, existingNames: ["ALBUM"], isDirectory: true)
            == .invalid(.duplicate))
    }

    @Test("Folder renaming does not request extension confirmation")
    func folderSkipsExtensionConfirmation() {
        let folder = URL(fileURLWithPath: "/tmp/album", isDirectory: true)
        #expect(validateNewName("album.2024", for: folder, existingNames: [], isDirectory: true) == .ok)
        let dotted = URL(fileURLWithPath: "/tmp/photos.old", isDirectory: true)
        #expect(validateNewName("photos", for: dotted, existingNames: [], isDirectory: true) == .ok)
        // Files that omit isDirectory behave as before.
        #expect(validateNewName("a.png", for: file, existingNames: existingNames) == .needsExtensionChangeConfirmation)
    }

    @Test("Also rejects empty names, invalid characters, leading dots, and duplicate names for folders", arguments: ["", "a/b", ".x", "ALBUM 2"])
    func folderRejectsInvalidNames(name: String) {
        let folder = URL(fileURLWithPath: "/tmp/album", isDirectory: true)
        guard case .invalid = validateNewName(name, for: folder, existingNames: ["album 2"], isDirectory: true) else {
            Issue.record("\(String(reflecting: name)) was accepted")
            return
        }
    }

    // MARK: Names That Become Packages (EC-53, EC-14)

    @Test("Rejects renaming a folder to a name that makes it a package")
    func folderRejectsPackageName() {
        let folder = URL(fileURLWithPath: "/tmp/a/Photos", isDirectory: true)
        #expect(
            validateNewName("Photos.app", for: folder, existingNames: [], isDirectory: true)
                == .invalid(.becomesPackage)
        )
        #expect(validateNewName("2025.01", for: folder, existingNames: [], isDirectory: true) == .ok)
    }

    @Test("Does not apply package checks to files")
    func fileIgnoresPackageName() {
        let png = URL(fileURLWithPath: "/tmp/a/Photos.png")
        #expect(
            validateNewName("Photos.app", for: png, existingNames: [], isDirectory: false)
                == .needsExtensionChangeConfirmation
        )
    }

    @Test("Existing validation runs before package checks")
    func existingChecksComeFirst() {
        let folder = URL(fileURLWithPath: "/tmp/a/Photos", isDirectory: true)
        #expect(
            validateNewName(".app", for: folder, existingNames: [], isDirectory: true)
                == .invalid(.leadingDot)
        )
        #expect(
            validateNewName("a/b.app", for: folder, existingNames: [], isDirectory: true)
                == .invalid(.forbiddenCharacter)
        )
        #expect(
            validateNewName("photos.app", for: folder, existingNames: ["Photos.app"], isDirectory: true)
                == .invalid(.duplicate)
        )
    }

    @Test("uniqueName starts numbering at 2")
    func numbersUniqueNames() {
        #expect(uniqueName(for: "a.jpg", existingNames: []) == "a 2.jpg")
        #expect(uniqueName(for: "a.jpg", existingNames: ["a.jpg"]) == "a 2.jpg")
        #expect(uniqueName(for: "a.jpg", existingNames: ["a.jpg", "a 2.jpg"]) == "a 3.jpg")
    }

    @Test("Continues numbering after existing numbered names")
    func continuesExistingCounter() {
        #expect(uniqueName(for: "c 2.jpg", existingNames: ["c 2.jpg"]) == "c 3.jpg")
        #expect(uniqueName(for: "c 2.jpg", existingNames: ["c 2.jpg", "c 3.jpg"]) == "c 4.jpg")
    }

    @Test("Detects conflicts without case sensitivity")
    func detectsCaseInsensitiveCollisions() {
        #expect(uniqueName(for: "a.jpg", existingNames: ["A.JPG"]) == "a 2.jpg")
        #expect(uniqueName(for: "a.jpg", existingNames: ["A.JPG", "A 2.JPG"]) == "a 3.jpg")
    }

    @Test("Also numbers names without extensions")
    func handlesNameWithoutExtension() {
        #expect(uniqueName(for: "notes", existingNames: ["notes"]) == "notes 2")
        #expect(uniqueName(for: "notes", existingNames: ["NOTES", "notes 2"]) == "notes 3")
    }
    @Test("newFolderName keeps the base name when it is free")
    func keepsFreeNewFolderName() {
        #expect(newFolderName(baseName: "untitled folder", existingNames: []) == "untitled folder")
        #expect(newFolderName(baseName: "untitled folder", existingNames: ["a.jpg", "Album"]) == "untitled folder")
    }

    @Test("newFolderName numbers from 2 when the base name is taken by any entry")
    func numbersTakenNewFolderName() {
        #expect(newFolderName(baseName: "untitled folder", existingNames: ["untitled folder"]) == "untitled folder 2")
        // A file, a hidden-looking name, and a case-only match all count as taken (FR-209).
        #expect(newFolderName(baseName: "untitled folder", existingNames: ["Untitled Folder"]) == "untitled folder 2")
        #expect(
            newFolderName(
                baseName: "untitled folder",
                existingNames: ["untitled folder", "untitled folder 2", ".hidden"]
            ) == "untitled folder 3"
        )
        #expect(newFolderName(baseName: "名称未設定フォルダ", existingNames: ["名称未設定フォルダ"]) == "名称未設定フォルダ 2")
    }

    @Test("newFolderName does not change uniqueName")
    func leavesUniqueNameUnchanged() {
        #expect(uniqueName(for: "untitled folder", existingNames: []) == "untitled folder 2")
    }
}
