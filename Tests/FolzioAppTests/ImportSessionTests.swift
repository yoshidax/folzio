import AppKit
import FolzioCore
import ImageIO
import Testing
@testable import FolzioApp

@MainActor
private final class FakeImportPromise {
    let names: [String]
    var destination: URL?
    var stage: ImportStaging?
    var report: (@MainActor @Sendable (Result<ImportSnapshot, ImportRejection>) -> Void)?
    var delivery: (@MainActor @Sendable (ImportPromiseDelivery) -> Void)?
    init(_ names: [String]) { self.names = names }
    func source(_ type: String = "public.png") -> ImportPromise {
        ImportPromise(declaredTypes: [type], names: { self.names }, request: { stage, _, report in
            self.stage = stage
            self.destination = stage.receptionFolder
            self.delivery = report
            self.report = { result in report(ImportPromiseDelivery(result: result)) }
        })
    }
    func send(_ name: String) async throws {
        let stage = try #require(stage)
        let result = await Task.detached {
            let url = stage.receptionFolder.appendingPathComponent(name)
            do {
                try Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!.write(to: url)
                return ImportInspector.snapshot(url, receptionFolder: stage.receptionFolder, inspectionFolder: stage.inspectionFolder)
            } catch { return .failure(ImportRejection.sourceFailed) }
        }.value
        report?(result)
    }
}

@Suite("Import sessions", .serialized)
@MainActor
struct ImportSessionTests {
    private func eventually(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { await Task.yield() }
        try #require(condition())
    }
    private func withManager(_ body: (ImportSessionManager, URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "Folzio.Import.Session.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ImportCleanupStore(defaults: defaults)
        let pool = ImportStagingPool(factory: {
            #expect(!Thread.isMainThread)
            return try ImportStaging.create(store: store, temporaryDirectory: root)
        })
        let manager = ImportSessionManager(pool: pool, automaticTicks: false, showsPanel: false)
        await pool.prepare()
        #expect(pool.ready.count == 2)
        try await body(manager, root)
        await manager.shutdown()
        #expect(store.records().isEmpty)
    }
    private var save: ImportSessionManager.Save {
        { _, control in control.willConfirm(); control.didConfirm(); return .finished }
    }

    @Test func commonDestinationAndMultipleFiles() async throws {
        try await withManager { manager, root in
            let one = FakeImportPromise(["a.png", "b.png"])
            let two = FakeImportPromise(["c.png"])
            var saved: [URL] = []
            let sessionValue = manager.beginPromises([one.source(), two.source()], destination: root, save: { request, control in
                control.willConfirm(); control.didConfirm(); saved = request.files; return .finished
            })
            let session = try #require(sessionValue)
            #expect(one.destination != nil && one.destination == two.destination)
            try await one.send("a.png")
            #expect(saved.isEmpty)
            try await one.send("a.png")
            #expect(session.state.receivedCount == 1)
            try await one.send("b.png")
            #expect(saved.isEmpty)
            try await two.send("c.png")
            try await eventually { session.state.phase == .finished }
            #expect(saved.map(\.lastPathComponent) == ["a.png", "b.png", "c.png"])
            try await eventually { manager.sessions.isEmpty }
        }
    }

    @Test func rejectsSamePathAcrossReceivers() async throws {
        try await withManager { manager, root in
            let one = FakeImportPromise(["same.png"])
            let two = FakeImportPromise(["same.png"])
            var saved: [URL] = []
            let sessionValue = manager.beginPromises([one.source(), two.source()], destination: root, save: { request, control in
                control.willConfirm(); saved = request.files; return .cancelled
            })
            let session = try #require(sessionValue)
            try await one.send("same.png")
            try await two.send("same.png")
            try await eventually { session.state.phase == .failed }
            #expect(saved.isEmpty)
        }
    }

    @Test func manualTimeoutCapacityAndCancellation() async throws {
        try await withManager { manager, root in
            var time = 0.0
            manager.now = { time }
            let image = FakeImportPromise(["image.png"])
            let video = FakeImportPromise(["video.mov"])
            let firstValue = manager.beginPromises([image.source()], destination: root, save: save)
            let first = try #require(firstValue)
            let secondValue = manager.beginPromises([video.source("com.apple.quicktime-movie")], destination: root, save: save)
            let second = try #require(secondValue)
            time = 60
            await manager.tick()
            #expect(first.state.phase == .failed)
            #expect(second.state.phase == .receiving)
            #expect(manager.rows.map(\.id) == [second.id])
            time = 600
            await manager.tick()
            #expect(second.state.phase == .failed)
            await manager.pool.prepare()
            let huge = FakeImportPromise(["huge.png"])
            time = 0
            let thirdValue = manager.beginPromises([huge.source()], destination: root, save: save)
            let third = try #require(thirdValue)
            let output = try #require(huge.destination).appendingPathComponent("growing")
            try await Task.detached {
                FileManager.default.createFile(atPath: output.path, contents: nil)
                let handle = try FileHandle(forWritingTo: output)
                try handle.truncate(atOffset: 256_000_001)
                try handle.close()
            }.value
            await manager.tick()
            #expect(third.state.phase == .failed)
            await manager.pool.prepare()
            let cancel = FakeImportPromise(["late.png"])
            let fourthValue = manager.beginPromises([cancel.source()], destination: root, save: save)
            let fourth = try #require(fourthValue)
            manager.cancelLatest()
            #expect(fourth.state.phase == .cancelled)
            try await cancel.send("late.png")
            #expect(fourth.state.phase == .cancelled)
        }
    }

    @Test func serialConfirmationQueue() async {
        let gate = ImportConfirmationQueue()
        var order: [Int] = []
        var resume: CheckedContinuation<Void, Never>?
        let first = Task { await gate.perform { order.append(1); await withCheckedContinuation { resume = $0 }; order.append(2) } }
        while resume == nil { await Task.yield() }
        let second = Task { await gate.perform { order.append(3) } }
        await Task.yield()
        #expect(order == [1])
        resume?.resume()
        await first.value; await second.value
        #expect(order == [1, 2, 3])
    }

    @Test func commandAvailability() {
        #expect(ImportSessionManager.canCancel(hasSessions: true, hasSheet: false, hasModal: false, editingText: false))
        #expect(!ImportSessionManager.canCancel(hasSessions: true, hasSheet: true, hasModal: false, editingText: false))
        #expect(!ImportSessionManager.canCancel(hasSessions: true, hasSheet: false, hasModal: true, editingText: false))
        #expect(!ImportSessionManager.canCancel(hasSessions: true, hasSheet: false, hasModal: false, editingText: true))
    }
}


extension ImportSessionTests {
    @Test func unpreparedPoolRejectsWithoutStartingARequest() async throws {
        let pool = ImportStagingPool()
        let manager = ImportSessionManager(pool: pool, automaticTicks: false, showsPanel: false)
        let promise = FakeImportPromise(["a.png"])
        #expect(manager.beginPromises([promise.source()], destination: URL(fileURLWithPath: "/tmp"), save: save) == nil)
        #expect(promise.destination == nil)
        await manager.shutdown()
    }

    @Test func readerClonesBeforeReturningAndIgnoresErrorURLs() async throws {
        try await withManager { manager, _ in
            let stage = try #require(manager.pool.take())
            let cancellation = ImportCancellation()
            var result: Result<ImportSnapshot, ImportRejection>?
            let reader = makeImportPromiseReader(staging: stage, cancellation: cancellation) { result = $0.result }
            let original = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
            let cloneCount = try await Task.detached {
                let url = stage.receptionFolder.appendingPathComponent("a.png")
                try original.write(to: url)
                reader(url, nil)
                let count = try FileManager.default.contentsOfDirectory(atPath: stage.inspectionFolder.path).count
                try Data("changed".utf8).write(to: url)
                return count
            }.value
            #expect(cloneCount == 1)
            try await eventually { result != nil }
            let snapshot = try #require(result).get()
            #expect(try Data(contentsOf: snapshot.url) == original)
            result = nil
            await Task.detached { reader(URL(fileURLWithPath: "/outside/untrusted"), CocoaError(.fileReadUnknown)) }.value
            try await eventually { result != nil }
            if case .failure(.sourceFailed) = result {} else { Issue.record("The error URL must be ignored") }
            await ImportStagingPool.remove(stage)
        }
    }

    @Test func rawNamesPartialFailureAndCancellationWhileChecking() async throws {
        try await withManager { manager, root in
            let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
            var saved: ImportSaveRequest?
            let sessionValue = manager.beginImages([
                RawImportItem(data: .success(data), name: "cat.png"),
                RawImportItem(data: .success(data), name: "cat.png"),
                RawImportItem(data: .failure(.notImageOrVideo), name: "bad.png")
            ], destination: root, save: { request, control in
                saved = request; control.willConfirm(); control.didConfirm(); return .finished
            })
            let session = try #require(sessionValue)
            try await eventually { session.state.phase == .finished }
            let request = try #require(saved)
            #expect(Set(request.files.map(\.lastPathComponent)).count == 2)
            #expect(request.failures.count == 1)
            var resume: CheckedContinuation<Void, Never>?
            var confirmed = false
            let checkingValue = manager.beginImages([RawImportItem(data: .success(data), name: nil)],
                destination: root, save: { _, control in
                    await withCheckedContinuation { resume = $0 }
                    guard control.isActive() else { return .cancelled }
                    confirmed = true; control.willConfirm(); control.didConfirm(); return .finished
                })
            let checking = try #require(checkingValue)
            try await eventually { resume != nil }
            #expect(checking.state.phase == .checking)
            manager.cancel(checking.id)
            resume?.resume()
            await checking.task?.value
            #expect(!confirmed)
            #expect(checking.state.phase == .cancelled)
        }
    }

    @Test func independentRowsAndLatestCancellation() async throws {
        try await withManager { manager, root in
            var time = 0.0
            manager.now = { time }
            let first = FakeImportPromise(["one.png"])
            let second = FakeImportPromise(["two.png"])
            let oneValue = manager.beginPromises([first.source()], destination: root.appendingPathComponent("one"), save: save)
            let one = try #require(oneValue)
            let twoValue = manager.beginPromises([second.source()], destination: root, save: save)
            let two = try #require(twoValue)
            #expect(first.destination != second.destination)
            time = 1.9
            #expect(manager.rows.isEmpty)
            time = 2
            #expect(manager.rows.map(\.id) == [one.id, two.id])
            manager.cancelLatest()
            #expect(two.state.phase == .cancelled && one.state.phase == .receiving)
            #expect(manager.rows.map(\.id) == [one.id])
            manager.cancel(one.id)
            #expect(manager.rows.isEmpty)
            try await first.send("one.png")
            try await second.send("two.png")
        }
    }
}


extension ImportSessionTests {
    @Test func failedReceiverWithoutNamesStillAllowsOtherFiles() async throws {
        try await withManager { manager, root in
            let good = FakeImportPromise(["good.png"])
            let failed = FakeImportPromise([])
            var saved: ImportSaveRequest?
            let pending = manager.beginPromises([good.source(), failed.source()], destination: root, save: { request, control in
                saved = request; control.willConfirm(); control.didConfirm(); return .finished
            })
            let session = try #require(pending)
            failed.report?(.failure(.sourceFailed))
            try await good.send("good.png")
            try await eventually { session.state.phase == .finished }
            #expect(saved?.files.map(\.lastPathComponent) == ["good.png"])
            #expect(saved?.failures.count == 1)
            await manager.pool.prepare()
            #expect(manager.pool.ready.count == 2)
        }
    }

    @Test func lateArrivalsAfterCancellationNeverSaveOrLeaveStaging() async throws {
        try await withManager { manager, root in
            let promise = FakeImportPromise(["late.png"])
            var saves = 0
            let pending = manager.beginPromises([promise.source()], destination: root, save: { _, _ in saves += 1; return .failed })
            let session = try #require(pending)
            let stage = try #require(promise.stage)
            manager.cancel(session.id)
            let report = try #require(promise.delivery)
            let reader = makeImportPromiseReader(staging: stage, cancellation: session.cancellation, report: report)
            try await Task.detached {
                let url = stage.receptionFolder.appendingPathComponent("late.png")
                try Data([1]).write(to: url)
                reader(url, nil)
            }.value
            try await eventually { !FileManager.default.fileExists(atPath: stage.root.path) }
            #expect(saves == 0)
        }
    }

}

extension ImportSessionTests {
    @Test(arguments: 0..<4) func destinationChangesFailAndCleanUp(scenario: Int) async throws {
        try await withManager { manager, root in
            let destination = root.appendingPathComponent("destination")
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.path) }
            let duringConfirmation = scenario & 1 != 0
            let readOnly = scenario & 2 != 0
            let change = {
                if readOnly { try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: destination.path) }
                else { try? FileManager.default.removeItem(at: destination) }
            }
            let promise = FakeImportPromise(["a.png"])
            var reported = false
            let pending = manager.beginPromises([promise.source()], destination: destination, save: { request, control in
                let (result, outcome) = await FileOperationCoordinator.transferReceived(request, service: FileOperationService(),
                    confirm: { _ in
                        #expect(duringConfirmation)
                        change()
                        return true
                    }, resolveConflict: { _, _, _ in .init(resolution: .abort, applyToAll: false) }, control: control)
                #expect(outcome == .failed && result.failed.count == 1)
                if !readOnly { #expect(result.failed.first?.reason == .destinationNotFound) }
                reported = true
                return outcome
            })
            let session = try #require(pending)
            if !duringConfirmation { change() }
            try await promise.send("a.png")
            try await eventually { reported && session.state.phase == .failed }
            let stage = try #require(session.staging)
            try await eventually { !FileManager.default.fileExists(atPath: stage.root.path) }
        }
    }
}


extension ImportSessionTests {
    @Test func shutdownCleansWithoutWaitingForAConfirmationResponse() async throws {
        try await withManager { manager, root in
            let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==")!
            var response: CheckedContinuation<Void, Never>?
            defer { response?.resume() }
            let pending = manager.beginImages([RawImportItem(data: .success(data), name: "a.png")],
                destination: root, save: { _, control in
                    control.willConfirm()
                    await withCheckedContinuation { response = $0 }
                    return .cancelled
                })
            let session = try #require(pending)
            try await eventually { response != nil }
            #expect(session.state.phase == .confirming)
            var done = false
            let shutdown = Task { await manager.shutdown(); done = true }
            try await eventually { done }
            #expect(session.state.phase == .cancelled)
            response?.resume(); response = nil
            await session.task?.value
            await shutdown.value
        }
    }
}


extension ImportSessionTests {
    @Test func failedVideoPromiseDoesNotSaveAnImageRepresentation() async throws {
        try await withManager { manager, root in
            let video = FakeImportPromise(["video.mov"])
            var called = false
            let pending = manager.beginPromises([video.source("com.apple.quicktime-movie")], destination: root,
                save: { request, control in
                    called = true
                    #expect(request.files.isEmpty)
                    #expect(request.failures.count == 1)
                    control.willConfirm()
                    return .failed
                })
            let session = try #require(pending)
            video.report?(.failure(.sourceFailed))
            try await eventually { called && session.state.phase == .failed }
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["Folzio-Import"])
        }
    }
}


extension ImportSessionTests {
    @Test func cancelledProducerKeepsDestinationUntilItsCallback() async throws {
        try await withManager { manager, root in
            let source = FakeImportPromise(["late.png"])
            var saves = 0
            let pending = manager.beginPromises([source.source()], destination: root, save: { _, _ in saves += 1; return .failed })
            let session = try #require(pending)
            let stage = try #require(source.stage)
            manager.cancel(session.id)
            // Flush already-scheduled cleanup without ending the simulated producer.
            await manager.shutdown()
            try #require(FileManager.default.fileExists(atPath: stage.receptionFolder.path))
            try await source.send("late.png")
            try await eventually { !FileManager.default.fileExists(atPath: stage.root.path) }
            #expect(saves == 0)
            #expect(session.state.phase == .cancelled)
        }
    }

    @Test func cancelledReaderStillAcknowledgesCompletionWithoutCloning() async throws {
        try await withManager { manager, _ in
            let stage = try #require(manager.pool.take())
            let token = ImportCancellation()
            token.cancel()
            var acknowledged = false
            let reader = makeImportPromiseReader(staging: stage, cancellation: token) { _ in acknowledged = true }
            try await Task.detached {
                let url = stage.receptionFolder.appendingPathComponent("late.png")
                try Data([1, 2, 3]).write(to: url)
                reader(url, nil)
            }.value
            try #require(FileManager.default.fileExists(atPath: stage.receptionFolder.path))
            try await eventually { acknowledged }
            #expect(try FileManager.default.contentsOfDirectory(atPath: stage.inspectionFolder.path).isEmpty)
            await ImportStagingPool.remove(stage)
        }
    }
}


extension ImportSessionTests {
    @Test func cancellationWaitsForAllReceiversAndDeduplicatesTheirFiles() async throws {
        try await withManager { manager, root in
            let first = FakeImportPromise(["one.png", "two.png"])
            let second = FakeImportPromise(["three.png"])
            var saves = 0
            let pending = manager.beginPromises([first.source(), second.source()], destination: root,
                save: { _, _ in saves += 1; return .failed })
            let session = try #require(pending)
            let stage = try #require(first.stage)
            manager.cancel(session.id)
            await manager.shutdown()
            #expect(manager.retiringSessions[session.id] != nil)
            try await first.send("one.png")
            try await first.send("one.png")
            try await first.send("two.png")
            #expect(FileManager.default.fileExists(atPath: stage.root.path))
            #expect(manager.retiringSessions[session.id] != nil)
            try await second.send("three.png")
            try await eventually { !FileManager.default.fileExists(atPath: stage.root.path) }
            #expect(manager.retiringSessions.isEmpty)
            #expect(saves == 0)
        }
    }

    @Test func retiringReceiversKeepCapacityAndDeadlineLimits() async throws {
        try await withManager { manager, root in
            var time = 0.0
            manager.now = { time }
            let image = FakeImportPromise(["image.png"])
            let video = FakeImportPromise(["video.mov"])
            var saves = 0
            let pending = manager.beginPromises([image.source(), video.source("com.apple.quicktime-movie")], destination: root,
                save: { _, _ in saves += 1; return .failed })
            let session = try #require(pending)
            let stage = try #require(image.stage)
            manager.cancel(session.id)
            time = 60
            await manager.tick()
            #expect(FileManager.default.fileExists(atPath: stage.root.path))
            time = 600
            await manager.tick()
            try await eventually { !FileManager.default.fileExists(atPath: stage.root.path) }
            #expect(manager.retiringSessions.isEmpty)
            await manager.pool.prepare()
            time = 0
            let huge = FakeImportPromise(["huge.png"])
            let pendingHuge = manager.beginPromises([huge.source()], destination: root,
                save: { _, _ in saves += 1; return .failed })
            let hugeSession = try #require(pendingHuge)
            let hugeStage = try #require(huge.stage)
            manager.cancel(hugeSession.id)
            try await Task.detached {
                let url = hugeStage.receptionFolder.appendingPathComponent("growing")
                FileManager.default.createFile(atPath: url.path, contents: nil)
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 256_000_001)
                try handle.close()
            }.value
            await manager.tick()
            try await eventually { !FileManager.default.fileExists(atPath: hugeStage.root.path) }
            #expect(manager.retiringSessions.isEmpty)
            #expect(saves == 0)
        }
    }

    @Test func cancelledSessionRetainsItsProducerUntilCompletion() async throws {
        try await withManager { manager, root in
            weak var producer: FakeImportPromise?
            var report: (@MainActor @Sendable (Result<ImportSnapshot, ImportRejection>) -> Void)?
            @MainActor func start() throws -> ImportSession {
                let source = FakeImportPromise(["late.png"])
                producer = source
                let pending = manager.beginPromises([source.source()], destination: root, save: save)
                report = source.report
                return try #require(pending)
            }
            var session: ImportSession? = try start()
            let id = try #require(session?.id)
            manager.cancel(id)
            await manager.shutdown()
            #expect(producer != nil)
            report?(.failure(.sourceFailed))
            session = nil
            try await eventually { producer == nil }
            #expect(manager.retiringSessions.isEmpty)
        }
    }

    @Test func timingSeparatesReceptionCheckingAndSaving() async throws {
        try await withManager { manager, root in
            var time = 0.0
            manager.now = { time }
            var events: [ImportTiming] = []
            manager.onTiming = { events.append($0) }
            let source = FakeImportPromise(["one.png"])
            let pending = manager.beginPromises([source.source()], destination: root, save: { _, control in
                control.willConfirm()
                time = 26
                control.didConfirm()
                time = 27
                return .finished
            })
            let session = try #require(pending)
            time = 23
            try await source.send("one.png")
            try await eventually { session.state.phase == .finished }
            #expect(events.first?.stage == .requested)
            #expect(events.first(where: { $0.stage == .reader })?.elapsed == 23)
            #expect(events.contains(where: { $0.stage == .checking }))
            #expect(events.contains(where: { $0.stage == .confirming }))
            #expect(events.first(where: { $0.stage == .saving })?.elapsed == 26)
            #expect(events.first(where: { $0.stage == .finished })?.duration == 1)
            #expect(events.allSatisfy { $0.sessionID == session.id })
        }
    }
}


extension ImportSessionTests {
    @Test func lateProducerAfterDeadlineIsSweptWithoutSaving() async throws {
        try await withManager { manager, root in
            var time = 0.0
            manager.now = { time }
            let source = FakeImportPromise(["late.png"])
            var saves = 0
            let pending = manager.beginPromises([source.source()], destination: root,
                save: { _, _ in saves += 1; return .failed })
            let session = try #require(pending)
            let stage = try #require(source.stage)
            manager.cancel(session.id)
            time = 60
            await manager.tick()
            try await eventually { !FileManager.default.fileExists(atPath: stage.root.path) }
            let report = try #require(source.delivery)
            let reader = makeImportPromiseReader(staging: stage, cancellation: session.cancellation, report: report)
            try await Task.detached {
                try FileManager.default.createDirectory(at: stage.receptionFolder, withIntermediateDirectories: true)
                let url = stage.receptionFolder.appendingPathComponent("late.png")
                try Data([1]).write(to: url)
                reader(url, nil)
            }.value
            try await eventually { !FileManager.default.fileExists(atPath: stage.root.path) }
            #expect(manager.retiringSessions.isEmpty)
            #expect(saves == 0)
        }
    }

    @Test func capacityFailureDoesNotRetireAgainAfterItsAlertEnds() async throws {
        try await withManager { manager, root in
            let source = FakeImportPromise(["huge.png"])
            var response: CheckedContinuation<Void, Never>?
            defer { response?.resume() }
            let pending = manager.beginPromises([source.source()], destination: root, save: { _, _ in
                await withCheckedContinuation { response = $0 }
                return .failed
            })
            let session = try #require(pending)
            let stage = try #require(source.stage)
            try await Task.detached {
                let url = stage.receptionFolder.appendingPathComponent("growing")
                FileManager.default.createFile(atPath: url.path, contents: nil)
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 256_000_001)
                try handle.close()
            }.value
            await manager.tick()
            try await eventually { response != nil && !FileManager.default.fileExists(atPath: stage.root.path) }
            response?.resume(); response = nil
            for _ in 0..<20 { await Task.yield() }
            #expect(session.state.phase == .failed)
            #expect(manager.retiringSessions.isEmpty)
        }
    }
}
