import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

/// Records calls to a fake transport; the tests never reach the network.
final class UpdateTransportStub: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private let result: Result<(Data, URLResponse), Error>

    init(tag: String, status: Int = 200) {
        let url = URL(string: "https://api.github.com/repos/yoshidax/folzio/releases/latest")!
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        result = .success((Data(#"{"tag_name": "\#(tag)"}"#.utf8), response))
    }

    init(error: Error) {
        result = .failure(error)
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    var transport: UpdateTransport {
        { [self] _ in
            lock.withLock { calls += 1 }
            return try result.get()
        }
    }
}

struct UpdateTransportFailure: Error {}

/// Builds a controller with an isolated settings domain and records its dialogs and opened URLs.
@MainActor
final class UpdateCheckFixture {
    let suiteName = "UpdateCheckTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let settings: SettingsStore
    let stub: UpdateTransportStub
    let controller: UpdateCheckController
    var dialogs: [UpdateDialog] = []
    var openedURLs: [URL] = []
    var responses: [UpdateDialogResponse] = []
    var canPresent = true
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Whether the menu item was enabled while each dialog was shown.
    var canCheckDuringDialogs: [Bool] = []

    init(current: String? = "1.7.0", stub: UpdateTransportStub) throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        settings = SettingsStore(defaults: defaults)
        self.stub = stub
        controller = UpdateCheckController(
            currentVersion: current.flatMap(AppVersion.init),
            settings: settings,
            transport: stub.transport
        )
        controller.presentDialog = { [unowned self] dialog in
            self.dialogs.append(dialog)
            self.canCheckDuringDialogs.append(self.controller.canCheck)
            return self.responses.isEmpty ? .second : self.responses.removeFirst()
        }
        controller.openURL = { [unowned self] url in self.openedURLs.append(url) }
        controller.canPresent = { [unowned self] in self.canPresent }
        controller.now = { [unowned self] in self.now }
    }

    func finishCheck() async {
        await controller.checkTask?.value
    }

    func finish() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@Suite("Update check menu", .serialized)
@MainActor
struct UpdateCheckMenuTests {
    private static let v180 = AppVersion(major: 1, minor: 8, patch: 0)
    private static let v170 = AppVersion(major: 1, minor: 7, patch: 0)

    @Test("Check for Updates follows About, before the separator, with no shortcut")
    func menuItem() throws {
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        MainMenu.install(zoomTarget: AppDelegate())
        defer { NSApp.mainMenu = previousMenu }
        let appMenu = try #require(NSApp.mainMenu?.items.first?.submenu)
        let items = appMenu.items
        #expect(items[0].action == #selector(AppDelegate.showAbout(_:)))
        #expect(items[1].action == #selector(AppDelegate.checkForUpdates(_:)))
        #expect(items[1].keyEquivalent.isEmpty)
        #expect(items[1].target == nil)
        #expect(items[2].isSeparatorItem)
        #expect(items[3].action == #selector(AppDelegate.showSettings(_:)))
    }

    @Test("The item is disabled without a usable version", arguments: [nil, "1.0", "v1.7.0", "dev"] as [String?])
    func disabledWithoutVersion(current: String?) throws {
        let fixture = try UpdateCheckFixture(current: current, stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        #expect(!fixture.controller.canCheck)
        fixture.controller.checkFromMenu()
        #expect(fixture.controller.checkTask == nil)
        #expect(fixture.stub.callCount == 0)
    }

    @Test("Creating the controller and installing the menu send nothing (SC-244)")
    func noTrafficUntilChosen() throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        _ = NSApplication.shared
        let previousMenu = NSApp.mainMenu
        MainMenu.install(zoomTarget: AppDelegate())
        defer { NSApp.mainMenu = previousMenu }
        #expect(fixture.controller.canCheck)
        #expect(fixture.stub.callCount == 0)
        #expect(fixture.dialogs.isEmpty)
    }

    @Test("A newer release opens its page from the default button and is saved as announced")
    func newVersionOpensPage() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.responses = [.first]
        fixture.controller.checkFromMenu()
        #expect(!fixture.controller.canCheck)
        await fixture.finishCheck()
        #expect(fixture.stub.callCount == 1)
        #expect(fixture.dialogs == [.updateAvailable(latest: Self.v180, current: Self.v170)])
        #expect(fixture.openedURLs == [URL(string: "https://github.com/yoshidax/folzio/releases/tag/v1.8.0")!])
        #expect(fixture.settings.lastNotifiedUpdateVersion == Self.v180)
        #expect(fixture.canCheckDuringDialogs == [true])
        #expect(fixture.controller.canCheck)
    }

    @Test("Close or Esc opens nothing")
    func newVersionClosed() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.responses = [.second]
        fixture.controller.checkFromMenu()
        await fixture.finishCheck()
        #expect(fixture.dialogs.count == 1)
        #expect(fixture.openedURLs.isEmpty)
    }

    @Test("A second choice while checking starts no second request (EC-291)")
    func noSecondCheck() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.7.0"))
        defer { fixture.finish() }
        fixture.controller.checkFromMenu()
        let task = fixture.controller.checkTask
        fixture.controller.checkFromMenu()
        #expect(fixture.controller.checkTask == task)
        await fixture.finishCheck()
        #expect(fixture.stub.callCount == 1)
        #expect(fixture.dialogs.count == 1)
    }

    @Test("Up to date shows the running version with OK only and opens nothing", arguments: ["v1.7.0", "v1.6.0"])
    func upToDate(tag: String) async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: tag))
        defer { fixture.finish() }
        fixture.responses = [.first]
        fixture.controller.checkFromMenu()
        await fixture.finishCheck()
        #expect(fixture.dialogs == [.upToDate(current: Self.v170)])
        #expect(fixture.openedURLs.isEmpty)
        #expect(fixture.settings.lastNotifiedUpdateVersion == nil)
        #expect(fixture.controller.canCheck)
    }

    @Test("A failure shows the failure dialog and enables the item again")
    func failure() async throws {
        for stub in [UpdateTransportStub(error: UpdateTransportFailure()), UpdateTransportStub(tag: "v1.8.0", status: 403)] {
            let fixture = try UpdateCheckFixture(stub: stub)
            defer { fixture.finish() }
            fixture.responses = [.first]
            fixture.controller.checkFromMenu()
            await fixture.finishCheck()
            #expect(fixture.dialogs == [.failed])
            #expect(fixture.openedURLs.isEmpty)
            #expect(fixture.controller.canCheck)
        }
    }

    @Test("The menu check is not limited by the automatic check's interval or announced version")
    func menuIgnoresAutomaticState() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.settings.automaticUpdateCheck = .disabled
        fixture.settings.lastAutomaticUpdateCheck = fixture.now
        fixture.settings.lastNotifiedUpdateVersion = Self.v180
        fixture.controller.checkFromMenu()
        await fixture.finishCheck()
        #expect(fixture.dialogs == [.updateAvailable(latest: Self.v180, current: Self.v170)])
        #expect(fixture.settings.lastAutomaticUpdateCheck == fixture.now)
    }

    @Test("Alerts have the expected buttons, and Esc presses the second one")
    func alerts() {
        let available = UpdateCheckController.makeAlert(for: .updateAvailable(latest: Self.v180, current: Self.v170))
        #expect(available.buttons.count == 2)
        #expect(available.buttons[1].keyEquivalent == "\u{1b}")
        #expect(available.informativeText.contains("1.8.0"))
        #expect(available.informativeText.contains("1.7.0"))
        let consent = UpdateCheckController.makeAlert(for: .consent)
        #expect(consent.buttons.count == 2)
        #expect(consent.buttons[1].keyEquivalent == "\u{1b}")
        #expect(UpdateCheckController.makeAlert(for: .upToDate(current: Self.v170)).buttons.count == 1)
        #expect(UpdateCheckController.makeAlert(for: .upToDate(current: Self.v170)).informativeText.contains("1.7.0"))
        #expect(UpdateCheckController.makeAlert(for: .failed).buttons.count == 1)
    }
}
