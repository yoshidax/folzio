import Foundation

/// Where the update check asks for the latest published release, and what the request carries (FR-423, FR-424).
///
/// `scripts/check-no-network.sh` allows the API URL literal only in this file. The request sends no cookies and no
/// information about the user, the computer, or their files.
public enum UpdateSource {
    /// Returns the most recent published release; drafts and prereleases are excluded by GitHub.
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/yoshidax/folzio/releases/latest")!

    /// Seconds without a response after which the check counts as failed (FR-427).
    public static let timeout: TimeInterval = 15

    /// The single GET request of an update check.
    public static var latestReleaseRequest: URLRequest {
        var request = URLRequest(
            url: latestReleaseURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        // GitHub requires a User-Agent. It names the app only, without its version or the OS.
        request.setValue("Folzio", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // Replaces the default, which would reveal the user's preferred languages.
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        return request
    }

    /// The release page of `version` in the public repository (FR-426).
    ///
    /// Built from the checked version number, never from a URL in the response.
    public static func releasePageURL(for version: AppVersion) -> URL {
        AboutInfo.repositoryURL
            .appendingPathComponent("releases")
            .appendingPathComponent("tag")
            .appendingPathComponent("v\(version)")
    }
}
