import Foundation
import Testing
@testable import FolzioCore

@Suite("FolderDisclosure")
struct FolderDisclosureTests {
    private func makeNode() -> FolderNode {
        FolderNode(url: URL(fileURLWithPath: "/tmp/folder"), name: "folder", kind: .folder)
    }

    @Test("Defaults to unknown subfolder presence and cannot expand or collapse")
    func defaultsToUnknown() {
        let node = makeNode()
        #expect(node.subfolderState == .unknown)
        #expect(!node.isExpandable)
    }

    @Test(
        "Allows disclosure only if access is not denied and the subfolder state is either present or failed",
        arguments: [FolderNode.AccessState.unknown, .accessible, .denied, .unavailable]
    )
    func expandability(access: FolderNode.AccessState) {
        let states: [FolderNode.SubfolderState] = [.unknown, .present, .absent, .failed]
        for state in states {
            var node = makeNode()
            node.accessState = access
            node.subfolderState = state
            let expected = access != .denied && (state == .present || state == .failed)
            #expect(node.isExpandable == expected, "access: \(access), subfolders: \(state)")
        }
    }

    @Test("A probe finding subfolders sets present")
    func probeFindsSubfolders() {
        var node = makeNode()
        node.applySubfolderProbe(.success(true))
        #expect(node.subfolderState == .present)
        #expect(node.accessState == .accessible)
        #expect(node.isExpandable)
    }

    @Test("A probe finding no subfolders sets absent")
    func probeFindsNoSubfolders() {
        var node = makeNode()
        node.applySubfolderProbe(.success(false))
        #expect(node.subfolderState == .absent)
        #expect(node.accessState == .accessible)
        #expect(!node.isExpandable)
    }

    @Test("An access-denied probe sets denied and disables disclosure")
    func probeDenied() {
        var node = makeNode()
        node.applySubfolderProbe(.failure(.accessDenied))
        #expect(node.accessState == .denied)
        #expect(!node.isExpandable)
    }

    @Test("A probe failing for another reason sets failed and allows disclosure", arguments: [
        ListingError.notFound,
        .other("x"),
    ])
    func probeFailed(error: ListingError) {
        var node = makeNode()
        node.applySubfolderProbe(.failure(error))
        #expect(node.subfolderState == .failed)
        #expect(node.isExpandable)
    }

    @Test("A repeated probe overwrites the state with its result")
    func reprobeOverridesState() {
        var node = makeNode()
        node.applySubfolderProbe(.success(true))
        node.applySubfolderProbe(.success(false))
        #expect(node.subfolderState == .absent)

        var denied = makeNode()
        denied.applySubfolderProbe(.failure(.accessDenied))
        denied.applySubfolderProbe(.success(true))
        #expect(denied.subfolderState == .present)
        #expect(denied.accessState == .accessible)
        #expect(denied.isExpandable)
    }

    @Test("Expanding with at least one child sets present")
    func listingWithChildren() {
        var node = makeNode()
        node.subfolderState = .failed
        node.applySubfolderListing(.success(3))
        #expect(node.subfolderState == .present)
        #expect(node.accessState == .accessible)
    }

    @Test("Expanding with no children sets absent and disables disclosure")
    func listingWithoutChildren() {
        var node = makeNode()
        node.subfolderState = .present
        node.applySubfolderListing(.success(0))
        #expect(node.subfolderState == .absent)
        #expect(!node.isExpandable)
    }

    @Test("An access-denied load during expansion sets denied and clears children")
    func listingDenied() {
        var node = makeNode()
        node.subfolderState = .present
        node.applySubfolderListing(.failure(.accessDenied))
        #expect(node.accessState == .denied)
        #expect(node.children == [])
        #expect(!node.isExpandable)
    }

    @Test("A load failing for another reason during expansion sets unavailable and allows another expansion", arguments: [
        ListingError.notFound,
        .other("x"),
    ])
    func listingUnavailable(error: ListingError) {
        var node = makeNode()
        node.subfolderState = .present
        node.children = []
        node.applySubfolderListing(.failure(error))
        #expect(node.accessState == .unavailable)
        #expect(node.subfolderState == .failed)
        #expect(node.children == nil)
        #expect(node.isExpandable)
    }

    @Test("A successful reload restores accessible even for a previously unreadable folder")
    func listingRecovers() {
        var node = makeNode()
        node.applySubfolderListing(.failure(.other("x")))
        node.applySubfolderListing(.success(2))
        #expect(node.subfolderState == .present)
        #expect(node.accessState == .accessible)
    }

    @Test("Double-click collapses expanded folders, expands expandable folders, and otherwise does nothing")
    func doubleClickToggle() {
        #expect(FolderDisclosure.doubleClickToggle(isExpandable: true, isExpanded: false) == .expand)
        #expect(FolderDisclosure.doubleClickToggle(isExpandable: true, isExpanded: true) == .collapse)
        #expect(FolderDisclosure.doubleClickToggle(isExpandable: false, isExpanded: true) == .collapse)
        #expect(FolderDisclosure.doubleClickToggle(isExpandable: false, isExpanded: false) == .none)
    }
}
