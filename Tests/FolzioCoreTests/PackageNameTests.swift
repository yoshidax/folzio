import Foundation
import Testing
@testable import FolzioCore

@Suite("PackageName")
struct PackageNameTests {
    @Test("True when the extension is a package type", arguments: ["Photos.app", "Docs.rtfd", "X.bundle"])
    func detectsPackageExtensions(name: String) {
        #expect(PackageName.isPackage(name))
    }

    @Test("False for non-package extensions and no extension", arguments: ["2025.01", "Photos", "a.txt", "", ".app"])
    func ignoresOrdinaryNames(name: String) {
        #expect(!PackageName.isPackage(name))
    }

    @Test("True for an uppercase extension (Photos.APP); UTType matching is case-insensitive")
    func uppercaseExtensionIsPackage() {
        #expect(PackageName.isPackage("Photos.APP"))
    }
}
