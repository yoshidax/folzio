import Foundation
import Testing
import FixtureKit
@testable import FolzioCore

// Add to the existing PerformanceBaseline suite (.serialized), so the measurement does not run in parallel with the
// other performance tests (the same reason as SlideshowPerformanceTests).
extension PerformanceBaselineTests {
    @Test("Filters a listing of 10,000 items by name within 100 ms per typed character (SC-209)")
    @MainActor
    func nameFilterOnHugeFolderWithinBudget() async throws {
        // Create 10,000 files off the MainActor so concurrent tests are not blocked.
        let directory = try await Task.detached(priority: .userInitiated) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("NameFilterPerformance-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FixtureSets.huge(in: directory, count: 10_000)
            return directory
        }.value
        defer { try? FileManager.default.removeItem(at: directory) }
        let huge = directory.appendingPathComponent("huge", isDirectory: true)

        let suite = "NameFilterPerformance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = BrowserModel(
            kindNames: FixtureKit.kindNames,
            lister: DirectoryLister(kindNames: FixtureKit.kindNames),
            decoder: ImageDecoder(),
            cache: DecodedImageCache(),
            settings: SettingsStore(defaults: defaults)
        )
        model.setNavigationRoots([directory])
        await model.selectFolder(huge)
        #expect(model.listing.files.filter { $0.kind != .parent }.count == 10_000)

        // Typing "img_0999" one character at a time, then a wildcard, then clearing the field.
        let steps = ["i", "im", "img", "img_", "img_0", "img_09", "img_099", "img_0999", "*_0999?.jpg", ""]
        var slowest: Duration = .zero
        for text in steps {
            let start = ContinuousClock.now
            model.setNameFilter(text)
            let elapsed = ContinuousClock.now - start
            slowest = max(slowest, elapsed)
            #expect(
                elapsed < .milliseconds(100),
                "Filtering 10,000 items by \"\(text)\" must take at most 100 ms (measured: \(elapsed))"
            )
        }
        print("[perf] BrowserModel.setNameFilter 10,000 (slowest step): \(slowest)")

        model.setNameFilter("img_0999")
        #expect(model.listing.files.filter { $0.kind != .parent }.count == 10)
        model.setNameFilter("")
        #expect(model.listing.files.filter { $0.kind != .parent }.count == 10_000)
    }
}
