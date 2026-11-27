import Foundation

/// Sends one request and returns the body and response. The app passes the only implementation that uses the
/// network; tests pass fixed responses.
public typealias UpdateTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Why an update check could not decide. The UI shows the same message for all of them (US97-AS2).
public enum UpdateCheckFailure: Equatable, Sendable {
    /// No response: offline, timed out, or cancelled.
    case transport
    /// A status other than 200, such as 404 when there is no release, or 403 and 429 for rate limits (EC-292, EC-294).
    case httpStatus(Int)
    /// The body is larger than `UpdateChecker.maximumResponseSize`.
    case responseTooLarge
    /// The response is not a web response, the body is not a JSON object, or `tag_name` is not a string.
    case malformedResponse
    /// `tag_name` is not `v<major>.<minor>.<patch>` (EC-292).
    case unrecognizedTag(String)
}

/// The outcome of comparing the latest published release with the running app (FR-425).
public enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(latest: AppVersion, current: AppVersion, releasePage: URL)
    case upToDate(current: AppVersion)
    case failed(UpdateCheckFailure)
}

public enum UpdateChecker {
    /// A normal response is a few kilobytes. Larger bodies are not parsed.
    public static let maximumResponseSize = 1_048_576

    /// Asks for the latest published release once and compares it with `current`. Never throws.
    public static func check(current: AppVersion, transport: UpdateTransport) async -> UpdateCheckResult {
        let fetched: (Data, URLResponse)
        do {
            fetched = try await transport(UpdateSource.latestReleaseRequest)
        } catch {
            return .failed(.transport)
        }
        let (data, response) = fetched
        guard let webResponse = response as? HTTPURLResponse else {
            return .failed(.malformedResponse)
        }
        guard webResponse.statusCode == 200 else {
            return .failed(.httpStatus(webResponse.statusCode))
        }
        guard data.count <= maximumResponseSize else {
            return .failed(.responseTooLarge)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else {
            return .failed(.malformedResponse)
        }
        guard tag.hasPrefix("v"), let latest = AppVersion(String(tag.dropFirst())) else {
            return .failed(.unrecognizedTag(tag))
        }
        if latest > current {
            return .updateAvailable(
                latest: latest,
                current: current,
                releasePage: UpdateSource.releasePageURL(for: latest)
            )
        }
        return .upToDate(current: current)
    }
}
