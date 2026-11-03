import Foundation
import Testing
@testable import FolzioCore

@Suite("TreeBatchTargets")
struct TreeBatchTargetsTests {
    private let roots = [URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/Users/me")]
    private let a = URL(fileURLWithPath: "/Users/me/a")
    private let b = URL(fileURLWithPath: "/Users/me/b")
    private let c = URL(fileURLWithPath: "/Volumes/Ext/c")
    private let home = URL(fileURLWithPath: "/Users/me")

    // MARK: Targets (FR-217)

    @Test("Keyboard and menu bar commands act on the whole selection (FR-217 (1))")
    func keyboardUsesSelection() {
        let targets = TreeBatchTargets(selection: [.folder(a), .folder(b)])
        #expect(targets.targets == [.folder(a), .folder(b)])
        #expect(targets.isMultiple)
        #expect(!targets.isSingle)
        #expect(targets.singleTarget == nil)
    }

    @Test("A right-click or drag on a selected row acts on the whole selection (FR-217 (2), (3))")
    func selectedOriginUsesSelection() {
        let targets = TreeBatchTargets(selection: [.folder(a), .folder(b)], origin: .folder(b), originIsSelected: true)
        #expect(targets.targets == [.folder(a), .folder(b)])
    }

    @Test("A right-click or drag on an unselected row acts on that row only (FR-217 (2), (3), A-21)")
    func unselectedOriginUsesOriginOnly() {
        let targets = TreeBatchTargets(selection: [.folder(a), .folder(b)], origin: .folder(c), originIsSelected: false)
        #expect(targets.targets == [.folder(c)])
        #expect(targets.isSingle)
        #expect(targets.singleTarget == .folder(c))
    }

    @Test("No selection and no origin has no targets")
    func emptySelection() {
        let targets = TreeBatchTargets(selection: [])
        #expect(targets.targets.isEmpty)
        #expect(!targets.isSingle)
        #expect(!targets.isMultiple)
        #expect(targets.trashTargets(roots: roots) == .unavailable)
        #expect(targets.dragURLs(roots: roots) == nil)
        #expect(targets.contextMenu(roots: roots).isEmpty)
    }

    // MARK: Availability (FR-218)

    @Test("Multiple regular folders can be moved to the Trash and dragged (FR-218 (1))")
    func regularFoldersAreAvailable() {
        let targets = TreeBatchTargets(selection: [.folder(a), .folder(b), .folder(c)])
        #expect(targets.trashTargets(roots: roots) == .folders([a, b, c]))
        #expect(targets.dragURLs(roots: roots) == [a, b, c])
    }

    @Test(
        "Any root, favorite, or heading among multiple targets makes Trash and drag unavailable (FR-218 (1))",
        arguments: [
            TreeItemRole.folder(URL(fileURLWithPath: "/Users/me")),
            .folder(URL(fileURLWithPath: "/")),
            .favorite(URL(fileURLWithPath: "/Users/me/fav")),
            .favoritesHeader,
        ]
    )
    func mixedTargetsAreUnavailable(other: TreeItemRole) {
        let targets = TreeBatchTargets(selection: [.folder(a), other])
        #expect(targets.trashTargets(roots: roots) == .unavailable)
        #expect(targets.dragURLs(roots: roots) == nil)
    }

    @Test(
        "A single target matches FavoriteCommands for Trash, removal, and rename",
        arguments: [
            TreeItemRole.folder(URL(fileURLWithPath: "/Users/me/a")),
            .folder(URL(fileURLWithPath: "/Users/me")),
            .favorite(URL(fileURLWithPath: "/Users/me/fav")),
            .favoritesHeader,
        ]
    )
    func singleTargetMatchesFavoriteCommands(role: TreeItemRole) {
        let targets = TreeBatchTargets(selection: [role])
        let expectedTrash: TreeBatchTargets.TrashTargets =
            FavoriteCommands.trashTarget(role, roots: roots).map { .folders([$0]) } ?? .unavailable
        #expect(targets.trashTargets(roots: roots) == expectedTrash)
        #expect(targets.dragURLs(roots: roots) == FavoriteCommands.trashTarget(role, roots: roots).map { [$0] })
        #expect(FavoriteCommands.removalTarget(targets.singleTarget) == FavoriteCommands.removalTarget(role))
        #expect(FavoriteCommands.renameTarget(targets.singleTarget, roots: roots) == FavoriteCommands.renameTarget(role, roots: roots))
        #expect(targets.contextMenu(roots: roots) == FavoriteCommands.contextMenu(for: role, roots: roots))
    }

    @Test("Multiple targets use the regular folder menu regardless of their roles (FR-218 (3))")
    func multipleTargetsUseFolderMenu() {
        let folderMenu = FavoriteCommands.contextMenu(for: .folder(a), roots: roots)
        #expect(TreeBatchTargets(selection: [.folder(a), .folder(b)]).contextMenu(roots: roots) == folderMenu)
        #expect(TreeBatchTargets(selection: [.favorite(a), .favoritesHeader]).contextMenu(roots: roots) == folderMenu)
        #expect(TreeBatchTargets(selection: [.folder(home), .folder(a)]).contextMenu(roots: roots) == folderMenu)
    }

    @Test("The multiple-target menu starts with New Folder like a regular folder menu, which the UI disables (FR-218)")
    func multipleTargetMenuStartsWithNewFolder() {
        let menu = TreeBatchTargets(selection: [.folder(a), .folder(b)]).contextMenu(roots: roots)
        #expect(Array(menu.prefix(2)) == [.newFolder, .separator])
        #expect(menu.contains(.moveToTrash))
    }

    // MARK: Overlap (EC-146)

    @Test("A folder and its child or grandchild are rejected as a whole (EC-146)")
    func parentAndDescendantOverlap() {
        let child = a.appendingPathComponent("child")
        let grandchild = child.appendingPathComponent("grandchild")
        #expect(TreeBatchTargets(selection: [.folder(a), .folder(child)]).trashTargets(roots: roots) == .overlapping)
        #expect(TreeBatchTargets(selection: [.folder(grandchild), .folder(a)]).trashTargets(roots: roots) == .overlapping)
        #expect(TreeBatchTargets(selection: [.folder(b), .folder(grandchild), .folder(a)]).trashTargets(roots: roots) == .overlapping)
    }

    @Test("Siblings and names that share a prefix do not overlap (EC-146)")
    func siblingsDoNotOverlap() {
        let ab = URL(fileURLWithPath: "/Users/me/ab")
        #expect(TreeBatchTargets(selection: [.folder(a), .folder(ab)]).trashTargets(roots: roots) == .folders([a, ab]))
        #expect(!TreeBatchTargets.containsOverlap([a, b, ab]))
    }

    @Test("Overlap compares standardized paths")
    func overlapUsesStandardizedPaths() {
        let child = URL(fileURLWithPath: "/Users/me/b/../a/child")
        #expect(TreeBatchTargets.containsOverlap([a, child]))
        #expect(TreeBatchTargets.containsOverlap([a, URL(fileURLWithPath: "/Users/me/a/")]))
    }

    @Test("Overlapping folders can still start a drag; the drop validation rejects them (EC-121)")
    func overlappingFoldersCanBeDragged() {
        let child = a.appendingPathComponent("child")
        #expect(TreeBatchTargets(selection: [.folder(a), .folder(child)]).dragURLs(roots: roots) == [a, child])
    }
}
