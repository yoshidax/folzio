import Foundation
import Testing
@testable import FolzioCore

@Suite("SubfolderProbe")
struct SubfolderProbeTests {
    private func makeURLs(_ count: Int) -> [URL] {
        (0..<count).map { URL(fileURLWithPath: "/tmp/probe/\($0)", isDirectory: true) }
    }

    private func collect(_ stream: AsyncStream<SubfolderProbeResult>) async -> [SubfolderProbeResult] {
        var results: [SubfolderProbeResult] = []
        for await result in stream {
            results.append(result)
        }
        return results
    }

    @Test("Emits each URL result once and keeps concurrency within the limit")
    func yieldsEveryURLOnceWithinLimit() async {
        let urls = makeURLs(10)
        let lister = ProbeFakeLister()

        let results = await collect(SubfolderProbe.results(for: urls, lister: lister, maxConcurrent: 3))

        #expect(results.count == 10)
        #expect(Set(results.map(\.url)) == Set(urls))
        #expect(await lister.maxInFlight <= 3)
    }

    @Test("A failure for one URL does not affect other URLs")
    func isolatesFailures() async {
        let urls = makeURLs(5)
        let failing = urls[2]
        let lister = ProbeFakeLister(failing: [failing: .other("boom")])

        let results = await collect(SubfolderProbe.results(for: urls, lister: lister, maxConcurrent: 2))

        #expect(results.count == 5)
        for result in results {
            switch result.result {
            case .success(let value):
                #expect(result.url != failing)
                #expect(value)
            case .failure(let error):
                #expect(result.url == failing)
                #expect(error == .other("boom"))
            }
        }
    }

    @Test("Finishes immediately for empty input")
    func finishesForEmptyInput() async {
        let lister = ProbeFakeLister()
        let results = await collect(SubfolderProbe.results(for: [], lister: lister))
        #expect(results.isEmpty)
        #expect(await lister.started == 0)
    }

    @Test("Treats a limit of 0 or less as 1")
    func treatsNonPositiveLimitAsOne() async {
        let urls = makeURLs(10)
        let lister = ProbeFakeLister()

        let results = await collect(SubfolderProbe.results(for: urls, lister: lister, maxConcurrent: 0))

        #expect(results.count == 10)
        #expect(await lister.maxInFlight == 1)
    }

    @Test("Does not start pending checks after leaving the stream")
    func stopsAfterTermination() async throws {
        let urls = makeURLs(20)
        let lister = ProbeFakeLister()

        for await _ in SubfolderProbe.results(for: urls, lister: lister, maxConcurrent: 2) {
            break
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(await lister.started < 20)
    }
}

private actor ProbeFakeLister: DirectoryListing {
    private let failing: [URL: ListingError]
    private(set) var started = 0
    private(set) var maxInFlight = 0
    private var inFlight = 0

    init(failing: [URL: ListingError] = [:]) {
        self.failing = failing
    }

    func mediaFiles(in folder: URL) async throws(ListingError) -> [MediaFile] {
        []
    }

    func subfolders(of folder: URL) async throws(ListingError) -> [URL] {
        []
    }

    func hasSubfolders(in folder: URL) async throws(ListingError) -> Bool {
        started += 1
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        defer { inFlight -= 1 }

        try? await Task.sleep(for: .milliseconds(20))
        if let error = failing[folder] {
            throw error
        }
        return true
    }
}
