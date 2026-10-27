import Foundation

public enum FocusMove: Sendable {
    case left
    case right
    case up
    case down
}

public enum FocusLayout: Sendable {
    case list
    case grid(columns: Int)
}

public struct FocusNavigator {
    public static func targetIndex(
        currentIndex: Int?,
        fileCount: Int,
        move: FocusMove,
        layout: FocusLayout
    ) -> Int? {
        guard fileCount > 0 else { return nil }

        let delta: Int
        switch layout {
        case .list:
            switch move {
            case .up:
                delta = -1
            case .down:
                delta = 1
            case .left, .right:
                return nil
            }
        case let .grid(columns):
            let columns = max(1, columns)
            switch move {
            case .left:
                delta = -1
            case .right:
                delta = 1
            case .up:
                delta = -columns
            case .down:
                delta = columns
            }
        }

        guard let currentIndex else { return 0 }

        let target = min(fileCount - 1, max(0, currentIndex + delta))
        return target == currentIndex ? nil : target
    }

    /// For full screen (FR-046). When the destination has `isNavigable(index) == false`, repeats the move in the
    /// same direction with the same rules. Returns nil when it reaches an edge without finding a navigable row.
    /// When `currentIndex` is nil, returns the first navigable row from the start.
    public static func targetIndex(
        currentIndex: Int?,
        fileCount: Int,
        move: FocusMove,
        layout: FocusLayout,
        isNavigable: (Int) -> Bool
    ) -> Int? {
        // Empty lists and left/right in list layout return nil, as in the existing function.
        guard targetIndex(
            currentIndex: nil, fileCount: fileCount, move: move, layout: layout
        ) != nil else { return nil }

        guard var current = currentIndex else {
            return (0..<fileCount).first(where: isNavigable)
        }

        for _ in 0..<fileCount {
            guard let next = targetIndex(
                currentIndex: current, fileCount: fileCount, move: move, layout: layout
            ) else { return nil }
            if isNavigable(next) { return next }
            current = next
        }
        return nil
    }

    /// First file when switching to preview-only (FR-093). Uses the row at `currentIndex` when it is `isNavigable`.
    /// Otherwise uses the first `isNavigable` row after it, or the nearest row before it when none follows. When
    /// `currentIndex` is nil (out-of-range values are treated the same), uses the first row from the start. Returns
    /// nil when no row is `isNavigable`.
    public static func entryIndex(
        currentIndex: Int?,
        fileCount: Int,
        isNavigable: (Int) -> Bool
    ) -> Int? {
        guard fileCount > 0 else { return nil }

        guard let currentIndex, (0..<fileCount).contains(currentIndex) else {
            return (0..<fileCount).first(where: isNavigable)
        }

        if isNavigable(currentIndex) { return currentIndex }

        if let after = (currentIndex + 1..<fileCount).first(where: isNavigable) {
            return after
        }
        return stride(from: currentIndex - 1, through: 0, by: -1).first(where: isNavigable)
    }
}
