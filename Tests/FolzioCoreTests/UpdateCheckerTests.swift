import Foundation
import Testing
@testable import FolzioCore

@Suite("Update checker")
struct UpdateCheckerTests {
    private static let current = AppVersion(major: 1, minor: 7, patch: 0)
    private static let apiURL = URL(string: "https://api.github.com/repos/yoshidax/folzio/releases/latest")!

    private struct TransportError: Error {}

    private static func response(status: Int) -> URLResponse {
        HTTPURLResponse(url: apiURL, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    private static func body(tag: String) -> Data {
        Data(#"{"tag_name": "\#(tag)", "draft": false, "prerelease": false}"#.utf8)
    }

    private static func check(_ data: Data, _ response: URLResponse) async -> UpdateCheckResult {
        await UpdateChecker.check(current: current) { _ in (data, response) }
    }

    @Test("Reports a newer release with its release page")
    func newerRelease() async {
        let result = await Self.check(Self.body(tag: "v1.10.0"), Self.response(status: 200))
        let latest = AppVersion(major: 1, minor: 10, patch: 0)
        #expect(result == .updateAvailable(
            latest: latest,
            current: Self.current,
            releasePage: URL(string: "https://github.com/yoshidax/folzio/releases/tag/v1.10.0")!
        ))
    }

    @Test("Reports up to date for the same or an older release", arguments: ["v1.7.0", "v1.6.9", "v0.9.0"])
    func sameOrOlderRelease(tag: String) async {
        let result = await Self.check(Self.body(tag: tag), Self.response(status: 200))
        #expect(result == .upToDate(current: Self.current))
    }

    @Test("Fails when the transport throws")
    func transportFailure() async {
        let result = await UpdateChecker.check(current: Self.current) { _ in throw TransportError() }
        #expect(result == .failed(.transport))
    }

    @Test("Fails on a status other than 200", arguments: [404, 403, 429, 500, 503, 204, 301])
    func statusFailure(status: Int) async {
        let result = await Self.check(Self.body(tag: "v9.0.0"), Self.response(status: status))
        #expect(result == .failed(.httpStatus(status)))
    }

    @Test("Fails when the response is not a web response")
    func nonWebResponse() async {
        let response = URLResponse(url: Self.apiURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let result = await Self.check(Self.body(tag: "v9.0.0"), response)
        #expect(result == .failed(.malformedResponse))
    }

    @Test("Fails when the body is larger than 1 MiB")
    func tooLarge() async {
        var data = Self.body(tag: "v9.0.0")
        data.append(Data(repeating: 0x20, count: UpdateChecker.maximumResponseSize))
        let result = await Self.check(data, Self.response(status: 200))
        #expect(result == .failed(.responseTooLarge))
    }

    @Test("Fails when the body has no string tag", arguments: [
        "", "not json", "[]", "{}", #"{"tag_name": 170}"#, #"{"tag_name": null}"#, #"{"name": "v9.0.0"}"#,
    ])
    func malformed(body: String) async {
        let result = await Self.check(Data(body.utf8), Self.response(status: 200))
        #expect(result == .failed(.malformedResponse))
    }

    @Test("Fails when the tag is not v<major>.<minor>.<patch>", arguments: [
        "1.8.0", "v1.8", "v1.8.0-beta", "vv1.8.0", "V1.8.0", "release-1.8.0", "",
    ])
    func unrecognizedTag(tag: String) async {
        let result = await Self.check(Self.body(tag: tag), Self.response(status: 200))
        #expect(result == .failed(.unrecognizedTag(tag)))
    }

    @Test("Sends one GET to the latest-release API with minimal headers")
    func request() async {
        let recorder = RequestRecorder()
        _ = await UpdateChecker.check(current: Self.current) { request in
            await recorder.record(request)
            return (Self.body(tag: "v1.7.0"), Self.response(status: 200))
        }
        let requests = await recorder.requests
        #expect(requests.count == 1)
        let request = requests[0]
        #expect(request.url == Self.apiURL)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.timeoutInterval == 15)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(!request.httpShouldHandleCookies)
        #expect(request.allHTTPHeaderFields == [
            "User-Agent": "Folzio",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Accept-Language": "en",
        ])
    }

    @Test("Builds the release page from the repository link and the version")
    func releasePage() {
        #expect(
            UpdateSource.releasePageURL(for: AppVersion(major: 2, minor: 0, patch: 1)).absoluteString
                == "https://github.com/yoshidax/folzio/releases/tag/v2.0.1"
        )
    }
}

private actor RequestRecorder {
    private(set) var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }
}
