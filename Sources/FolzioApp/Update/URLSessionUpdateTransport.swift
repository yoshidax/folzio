import Foundation
import FolzioCore

/// The only code in the app that sends a network request: the update check (FR-423, FR-431).
///
/// `scripts/check-no-network.sh` allows URLSession only in this file. The session is ephemeral and keeps no
/// cookies, cache, or credentials, so a request carries nothing from earlier requests (FR-424).
enum LiveUpdateTransport {
    static let send: UpdateTransport = { request in
        try await session.data(for: request)
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = UpdateSource.timeout
        configuration.timeoutIntervalForResource = UpdateSource.timeout
        return URLSession(configuration: configuration)
    }()
}
