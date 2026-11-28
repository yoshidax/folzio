import Foundation

/// How often search results are added to the listing while a search is running (FR-085, research.md R3).
public enum SearchReflection {
    /// Longest delay between finding a result and showing it (FR-085).
    public static let maximumInterval: Duration = .seconds(1)

    /// Interval before the next addition, given the number of results already listed. Few results are shown quickly;
    /// as the listing grows, additions are grouped so updating the views stays cheap.
    public static func interval(forListedCount count: Int) -> Duration {
        switch count {
        case ..<1_000: return .milliseconds(100)
        case ..<10_000: return .milliseconds(250)
        case ..<30_000: return .milliseconds(500)
        default: return maximumInterval
        }
    }
}
