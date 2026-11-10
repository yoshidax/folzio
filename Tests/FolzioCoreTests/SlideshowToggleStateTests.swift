import Foundation
import Testing
@testable import FolzioCore

@Suite("SlideshowToggleState")
struct SlideshowToggleStateTests {
    @Test("Across 64 combinations of six inputs, decides on/off, the action, and availability of the toolbar button")
    func truthTable() {
        for canStart in [false, true] {
            for active in [false, true] {
                for restoring in [false, true] {
                    for sheet in [false, true] {
                        for modal in [false, true] {
                            for editing in [false, true] {
                                let state = SlideshowToggleState(
                                    canStart: canStart,
                                    isActive: active,
                                    isRestoring: restoring,
                                    hasSheet: sheet,
                                    hasAppModal: modal,
                                    isEditingText: editing
                                )
                                let label = "canStart=\(canStart), active=\(active), restoring=\(restoring), "
                                    + "sheet=\(sheet), modal=\(modal), editing=\(editing)"
                                let isOn = active && !restoring
                                let isEnabled = isOn
                                    ? !sheet && !modal && !editing
                                    : canStart && !restoring

                                #expect(state.isOn == isOn, "\(label)")
                                #expect(state.action == (isOn ? .stop : .start), "\(label)")
                                #expect(state.isEnabled == isEnabled, "\(label)")
                            }
                        }
                    }
                }
            }
        }
    }

    @Test("While running, availability matches the Esc acceptance conditions without the key window condition")
    func runningAvailabilityMatchesEscConditions() {
        for canStart in [false, true] {
            for sheet in [false, true] {
                for modal in [false, true] {
                    for editing in [false, true] {
                        let state = SlideshowToggleState(
                            canStart: canStart,
                            isActive: true,
                            isRestoring: false,
                            hasSheet: sheet,
                            hasAppModal: modal,
                            isEditingText: editing
                        )
                        let escape = SlideshowInputPolicy(
                            isActive: true,
                            isRestoring: false,
                            isTargetWindowKey: true,
                            hasSheet: sheet,
                            hasAppModal: modal,
                            isEditingText: editing
                        )
                        let label = "canStart=\(canStart), sheet=\(sheet), modal=\(modal), editing=\(editing)"
                        #expect(state.isEnabled == escape.accepts(.escape), "\(label)")
                    }
                }
            }
        }
    }

    @Test("Is off and unavailable while restoring, even if the start condition is reported as met")
    func restoringIsOffAndUnavailable() {
        for active in [false, true] {
            let state = SlideshowToggleState(
                canStart: true,
                isActive: active,
                isRestoring: true,
                hasSheet: false,
                hasAppModal: false,
                isEditingText: false
            )
            #expect(!state.isOn, "active=\(active)")
            #expect(state.action == .start, "active=\(active)")
            #expect(!state.isEnabled, "active=\(active)")
        }
    }
}
