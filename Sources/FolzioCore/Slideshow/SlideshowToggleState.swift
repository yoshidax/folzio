import Foundation

/// State of the toolbar Slideshow button, which starts the slideshow when stopped and stops it while running
/// (FR-350 to FR-352). The menu item and the shortcut only start the slideshow, so they keep using
/// `SlideshowStartPolicy`.
public struct SlideshowToggleState: Sendable, Equatable {
    /// What pressing the button does.
    public enum Action: Sendable, Equatable {
        case start
        case stop
    }

    /// Start condition of FR-114 (`SlideshowStartPolicy.canStart`).
    public let canStart: Bool
    public let isActive: Bool
    /// Whether the app is restoring the presentation after the slideshow ends, such as while waiting for full screen
    /// to exit.
    public let isRestoring: Bool
    public let hasSheet: Bool
    public let hasAppModal: Bool
    public let isEditingText: Bool

    public init(
        canStart: Bool,
        isActive: Bool,
        isRestoring: Bool,
        hasSheet: Bool,
        hasAppModal: Bool,
        isEditingText: Bool
    ) {
        self.canStart = canStart
        self.isActive = isActive
        self.isRestoring = isRestoring
        self.hasSheet = hasSheet
        self.hasAppModal = hasAppModal
        self.isEditingText = isEditingText
    }

    /// The button is on only while running. It is off while restoring (FR-350).
    public var isOn: Bool {
        isActive && !isRestoring
    }

    public var action: Action {
        isOn ? .stop : .start
    }

    /// While running, uses the conditions for accepting Esc, except that the target window does not have to be the
    /// key window, because the button is clicked (FR-352, A-209). When stopped, uses the start condition, and is
    /// always unavailable while restoring (FR-352, EC-239).
    public var isEnabled: Bool {
        guard isOn else { return canStart && !isRestoring }
        return SlideshowInputPolicy(
            isActive: isActive,
            isRestoring: isRestoring,
            isTargetWindowKey: true,
            hasSheet: hasSheet,
            hasAppModal: hasAppModal,
            isEditingText: isEditingText,
            menuOwnsInput: false
        ).acceptsKeys
    }
}
