/// Pane kind (FR-088–094, research.md R40). The order of `Pane.allCases` is the Tab cycle order
/// (tree → file list → preview).
public enum Pane: Sendable, Equatable, CaseIterable {
    case tree, fileList, preview
}

/// Target of the toolbar buttons and menu items (FR-088, FR-089). Not persisted. The state is owned only by
/// `MainSplitViewController`.
public enum SoloPane: Sendable, Equatable {
    case fileList, preview
}

/// Pane layout (FR-088–093, research.md R40). Keeps only three values; there is no state that hides only the tree.
/// Not persisted. The state is owned only by `MainSplitViewController`. Starts as `.all` on every launch.
public enum PaneLayout: Sendable, Equatable {
    /// Three-pane layout (default)
    case all
    /// Hides the tree and preview
    case fileListOnly
    /// Hides the tree and file list
    case previewOnly

    /// `nil` maps to `.all`; otherwise shows only that side (FR-088)
    public init(soloPane: SoloPane?) {
        switch soloPane {
        case .none:
            self = .all
        case .fileList:
            self = .fileListOnly
        case .preview:
            self = .previewOnly
        }
    }

    /// Target of the toolbar selection and menu checkmark. `.all` maps to `nil` (FR-089)
    public var soloPane: SoloPane? {
        switch self {
        case .all:
            return nil
        case .fileListOnly:
            return .fileList
        case .previewOnly:
            return .preview
        }
    }

    /// Menu and keyboard shortcut. Returns `.all` when that side is currently shown alone; otherwise shows only
    /// that side (FR-089, FR-090)
    public func toggling(_ pane: SoloPane) -> PaneLayout {
        switch (self, pane) {
        case (.fileListOnly, .fileList), (.previewOnly, .preview):
            return .all
        case (_, .fileList):
            return .fileListOnly
        case (_, .preview):
            return .previewOnly
        }
    }

    /// Determines the next layout from the selection reported by the toolbar button group (`selectAny`) (FR-089).
    /// When both are true, keeps only the side that was not pressed previously (leaves `.all` unchanged when it was
    /// already `.all`).
    public func applyingToolbarSelection(fileListSelected: Bool, previewSelected: Bool) -> PaneLayout {
        switch (fileListSelected, previewSelected) {
        case (false, false):
            return .all
        case (true, false):
            return .fileListOnly
        case (false, true):
            return .previewOnly
        case (true, true):
            switch self {
            case .fileListOnly:
                return .previewOnly
            case .previewOnly:
                return .fileListOnly
            case .all:
                return .all
            }
        }
    }

    /// Whether this layout shows the given pane (FR-088, FR-092)
    public func isVisible(_ pane: Pane) -> Bool {
        switch self {
        case .all:
            return true
        case .fileListOnly:
            return pane == .fileList
        case .previewOnly:
            return pane == .preview
        }
    }

    /// Focus target after switching. `nil` leaves focus unchanged (FR-091)
    public func focusTarget(afterSwitchingFrom focused: Pane?) -> Pane? {
        switch self {
        case .all:
            return nil
        case .fileListOnly:
            return focused == .fileList ? nil : .fileList
        case .previewOnly:
            return focused == .preview ? nil : .preview
        }
    }

    /// Whether the first file may be auto-selected when switching to preview-only (FR-093).
    /// Does not auto-select during `.loading` for normal loading or search, and does not retry after loading completes.
    public static func shouldAutoSelectEntry(in listing: FolderListing) -> Bool {
        listing.state != .loading
    }

    /// True in preview-only when not loading and the current listing has no media items (FR-093).
    /// Shows "No media file to display" in the preview.
    public func showsNoMediaMessage(in listing: FolderListing) -> Bool {
        self == .previewOnly
            && listing.state != .loading
            && !listing.files.contains { $0.kind.isMedia }
    }
}

/// Pure computation that determines the panes actually shown from the layout and full-screen state
/// (FR-094, research.md R41, R44). Not persisted. The state is owned only by `MainSplitViewController`.
public struct PanePresentation: Sendable, Equatable {
    public let layout: PaneLayout
    public let isFullScreen: Bool

    public init(layout: PaneLayout, isFullScreen: Bool) {
        self.layout = layout
        self.isFullScreen = isFullScreen
    }

    /// Returns `[.preview]` in full screen; otherwise the panes shown by `layout` (tree → file list → preview).
    public var visiblePanes: [Pane] {
        if isFullScreen {
            return [.preview]
        }
        return Pane.allCases.filter { layout.isVisible($0) }
    }

    public func isVisible(_ pane: Pane) -> Bool {
        visiblePanes.contains(pane)
    }

    /// Whether all three panes are shown (used to preserve and restore pane widths and resume autosave; FR-094)
    public var showsAllPanes: Bool {
        !isFullScreen && layout == .all
    }

    /// Whether the file list is hidden while the preview is visible (arrow keys move the hidden file list's
    /// selection; FR-046, FR-093)
    public var navigatesHiddenFileList: Bool {
        !isVisible(.fileList) && isVisible(.preview)
    }
}

/// Availability of commands related to hidden panes (FR-062, 065, 080, 090, 092, 094; research.md R42).
/// Not persisted. The state is owned only by `MainSplitViewController`.
public struct PaneCommands: Sendable, Equatable {
    public let layout: PaneLayout
    public let isFullScreen: Bool
    public let isEditingText: Bool
    /// Whether the slideshow is active. Stops pane switching and history navigation, including during start and end
    /// transitions.
    public let isSlideshowActive: Bool
    /// Whether the app is restoring state after the slideshow ends. Stops restarting and switching.
    public let isRestoring: Bool

    public init(
        layout: PaneLayout,
        isFullScreen: Bool,
        isEditingText: Bool,
        isSlideshowActive: Bool = false,
        isRestoring: Bool = false
    ) {
        self.layout = layout
        self.isFullScreen = isFullScreen
        self.isEditingText = isEditingText
        self.isSlideshowActive = isSlideshowActive
        self.isRestoring = isRestoring
    }

    /// ⌃⌘2, ⌃⌘3, and toolbar buttons (FR-090, FR-094)
    public var canChangeLayout: Bool {
        !isFullScreen && !isEditingText && !isSlideshowActive && !isRestoring
    }

    /// ⌥⌘1–3 (FR-092)
    public func canFocus(_ pane: Pane) -> Bool {
        layout.isVisible(pane)
    }

    /// ⇧⌘F (FR-065, FR-092)
    public var canGoToFavorites: Bool {
        !isFullScreen && !isEditingText && layout.isVisible(.tree)
    }

    /// ⌃⌘T. Combined with the tree-side check using AND (FR-062, FR-092)
    public var allowsAddingFavorite: Bool {
        !isEditingText && layout.isVisible(.tree)
    }

    /// ⌘F (FR-080, FR-092)
    public var canSearch: Bool {
        !isFullScreen && !isEditingText && layout.isVisible(.fileList)
    }

    /// ⌘[, ⌘], the Go menu, and the toolbar Back/Forward buttons (FR-112).
    /// Combined with the history availability using AND in `HistoryNavigator`.
    public var canNavigateHistory: Bool {
        !isFullScreen && !isEditingText && !isSlideshowActive && !isRestoring
    }
}

/// Kinds of keys the slideshow may intercept (FR-123).
public enum SlideshowKey: Sendable, Equatable {
    case escape
    case arrow
    case other
}

/// Conditions for accepting Esc and arrow keys. While a modal, sheet, name editing, or restore is active,
/// input is left to AppKit's responder (FR-105, FR-123).
public struct SlideshowInputPolicy: Sendable, Equatable {
    public let isActive: Bool
    public let isRestoring: Bool
    public let isTargetWindowKey: Bool
    public let hasSheet: Bool
    public let hasAppModal: Bool
    public let isEditingText: Bool
    /// Whether AppKit is handling keys, such as during menu tracking. Normally false from the app.
    public let menuOwnsInput: Bool

    public init(
        isActive: Bool,
        isRestoring: Bool,
        isTargetWindowKey: Bool,
        hasSheet: Bool,
        hasAppModal: Bool,
        isEditingText: Bool,
        menuOwnsInput: Bool = false
    ) {
        self.isActive = isActive
        self.isRestoring = isRestoring
        self.isTargetWindowKey = isTargetWindowKey
        self.hasSheet = hasSheet
        self.hasAppModal = hasAppModal
        self.isEditingText = isEditingText
        self.menuOwnsInput = menuOwnsInput
    }

    public var acceptsKeys: Bool {
        isActive
            && !isRestoring
            && isTargetWindowKey
            && !hasSheet
            && !hasAppModal
            && !isEditingText
            && !menuOwnsInput
    }

    public func accepts(_ key: SlideshowKey) -> Bool {
        guard acceptsKeys else { return false }
        switch key {
        case .escape, .arrow:
            return true
        case .other:
            return false
        }
    }
}

/// Shared decision for whether the slideshow can start (FR-114, FR-115). It can start while loading if a candidate
/// is visible, and it can start from full screen. It cannot start while editing, with a sheet or app modal,
/// while active, or while restoring.
public struct SlideshowStartPolicy: Sendable, Equatable {
    public let hasCandidate: Bool
    public let isLoading: Bool
    public let isFullScreen: Bool
    public let isSlideshowActive: Bool
    public let isRestoring: Bool
    public let isEditingText: Bool
    public let hasSheet: Bool
    public let hasAppModal: Bool

    public init(
        hasCandidate: Bool,
        isLoading: Bool,
        isFullScreen: Bool,
        isSlideshowActive: Bool,
        isRestoring: Bool,
        isEditingText: Bool,
        hasSheet: Bool,
        hasAppModal: Bool
    ) {
        self.hasCandidate = hasCandidate
        self.isLoading = isLoading
        self.isFullScreen = isFullScreen
        self.isSlideshowActive = isSlideshowActive
        self.isRestoring = isRestoring
        self.isEditingText = isEditingText
        self.hasSheet = hasSheet
        self.hasAppModal = hasAppModal
    }

    public var canStart: Bool {
        hasCandidate
            && !isSlideshowActive
            && !isRestoring
            && !isEditingText
            && !hasSheet
            && !hasAppModal
    }
}


/// Divider positions when returning to the three-pane layout (FR-088, research.md R41). Not persisted.
/// The state is owned only by `MainSplitViewController`.
public enum PaneWidths {
    /// Positions of the two dividers when returning to the three-pane layout (FR-088). `savedWidths` and
    /// `minimumWidths` contain three elements: tree, file list, and preview.
    /// If the preview is below its minimum width, shrinks the file list and then the tree down to their minimums.
    /// Uses the initial defaults (220 / 360 / remainder) for invalid input.
    public static func dividerPositions(
        savedWidths: [Double],
        totalWidth: Double,
        dividerThickness: Double,
        minimumWidths: [Double]
    ) -> [Double] {
        let minimums = minimumWidths.count == 3 && minimumWidths.allSatisfy({ $0.isFinite })
            ? minimumWidths
            : [160, 240, 320]

        var tree: Double
        var list: Double
        if savedWidths.count == 3 && savedWidths.allSatisfy({ $0.isFinite }) {
            tree = savedWidths[0]
            list = savedWidths[1]
        } else {
            tree = 220
            list = 360
        }

        let thickness = dividerThickness.isFinite && dividerThickness >= 0 ? dividerThickness : 0
        let preview = totalWidth - tree - list - 2 * thickness
        let previewMinimum = minimums[2]

        if preview < previewMinimum {
            var deficit = previewMinimum - preview
            let listReduction = min(deficit, max(0, list - minimums[1]))
            list -= listReduction
            deficit -= listReduction
            if deficit > 0 {
                let treeReduction = min(deficit, max(0, tree - minimums[0]))
                tree -= treeReduction
            }
        }

        return [tree, tree + thickness + list]
    }
}
