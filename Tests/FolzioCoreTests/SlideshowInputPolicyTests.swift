import Foundation
import Testing
@testable import FolzioCore

@Suite("SlideshowInputPolicy")
struct SlideshowInputPolicyTests {
    @Test("Across 64 combinations of six conditions, accepts Esc and arrows only when all conditions hold")
    func truthTable() {
        for active in [false, true] {
            for restoring in [false, true] {
                for keyWindow in [false, true] {
                    for sheet in [false, true] {
                        for modal in [false, true] {
                            for editing in [false, true] {
                                let policy = SlideshowInputPolicy(
                                    isActive: active,
                                    isRestoring: restoring,
                                    isTargetWindowKey: keyWindow,
                                    hasSheet: sheet,
                                    hasAppModal: modal,
                                    isEditingText: editing
                                )
                                let label = "active=\(active), restoring=\(restoring), key=\(keyWindow), "
                                    + "sheet=\(sheet), modal=\(modal), editing=\(editing)"
                                let expected = active
                                    && !restoring
                                    && keyWindow
                                    && !sheet
                                    && !modal
                                    && !editing

                                #expect(policy.acceptsKeys == expected, "\(label)")
                                #expect(policy.accepts(.escape) == expected, "\(label)")
                                #expect(policy.accepts(.arrow) == expected, "\(label)")
                                #expect(!policy.accepts(.other), "\(label)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Does not accept Esc or arrows while a menu is handling keys")
    func menuOwnsInput() {
        let policy = SlideshowInputPolicy(
            isActive: true,
            isRestoring: false,
            isTargetWindowKey: true,
            hasSheet: false,
            hasAppModal: false,
            isEditingText: false,
            menuOwnsInput: true
        )
        #expect(!policy.acceptsKeys)
        #expect(!policy.accepts(.escape))
        #expect(!policy.accepts(.arrow))
    }

    @Test("Start availability depends on candidates, running state, editing, sheets, and modals; loading and full screen do not prevent it")
    func startTruthTable() {
        for hasCandidate in [false, true] {
            for loading in [false, true] {
                for fullScreen in [false, true] {
                    for active in [false, true] {
                        for restoring in [false, true] {
                            for editing in [false, true] {
                                for sheet in [false, true] {
                                    for modal in [false, true] {
                                        let policy = SlideshowStartPolicy(
                                            hasCandidate: hasCandidate,
                                            isLoading: loading,
                                            isFullScreen: fullScreen,
                                            isSlideshowActive: active,
                                            isRestoring: restoring,
                                            isEditingText: editing,
                                            hasSheet: sheet,
                                            hasAppModal: modal
                                        )
                                        let expected = hasCandidate
                                            && !active
                                            && !restoring
                                            && !editing
                                            && !sheet
                                            && !modal
                                        let label = "candidate=\(hasCandidate), loading=\(loading), "
                                            + "fullScreen=\(fullScreen), active=\(active), "
                                            + "restoring=\(restoring), editing=\(editing), "
                                            + "sheet=\(sheet), modal=\(modal)"
                                        #expect(policy.canStart == expected, "\(label)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("Stops pane switching and history navigation during the slideshow and while restoring")
    func paneCommandsRespectSlideshow() {
        let normal = PaneCommands(layout: .all, isFullScreen: false, isEditingText: false)
        #expect(normal.canChangeLayout)
        #expect(normal.canNavigateHistory)

        let active = PaneCommands(
            layout: .previewOnly,
            isFullScreen: false,
            isEditingText: false,
            isSlideshowActive: true
        )
        #expect(!active.canChangeLayout)
        #expect(!active.canNavigateHistory)

        let restoring = PaneCommands(
            layout: .all,
            isFullScreen: false,
            isEditingText: false,
            isRestoring: true
        )
        #expect(!restoring.canChangeLayout)
        #expect(!restoring.canNavigateHistory)
    }
}
