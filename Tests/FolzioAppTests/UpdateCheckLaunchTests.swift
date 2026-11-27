import AppKit
import FolzioCore
import Testing
@testable import FolzioApp

@Suite("Update check at launch", .serialized)
@MainActor
struct UpdateCheckLaunchTests {
    private static let v180 = AppVersion(major: 1, minor: 8, patch: 0)
    private static let v170 = AppVersion(major: 1, minor: 7, patch: 0)
    private static let day: TimeInterval = 24 * 60 * 60

    @Test("Asks once when not answered and sends nothing before the answer")
    func asksConsent() throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.controller.performLaunchAction()
        #expect(fixture.dialogs == [.consent])
        #expect(fixture.stub.callCount == 0)
    }

    @Test("Agreeing saves the answer and checks right away")
    func agree() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.responses = [.first, .second]
        fixture.controller.performLaunchAction()
        #expect(fixture.settings.automaticUpdateCheck == .enabled)
        await fixture.finishCheck()
        #expect(fixture.stub.callCount == 1)
        #expect(fixture.dialogs == [.consent, .updateAvailable(latest: Self.v180, current: Self.v170)])
        #expect(fixture.settings.lastAutomaticUpdateCheck == fixture.now)
        #expect(fixture.settings.lastNotifiedUpdateVersion == Self.v180)
    }

    @Test("Declining saves the answer, sends nothing, and is not asked again")
    func decline() throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.responses = [.second]
        fixture.controller.performLaunchAction()
        #expect(fixture.settings.automaticUpdateCheck == .disabled)
        #expect(fixture.controller.checkTask == nil)
        fixture.controller.performLaunchAction()
        #expect(fixture.dialogs == [.consent])
        #expect(fixture.stub.callCount == 0)
    }

    @Test("Asks again on the next launch when the question could not be shown or was not answered")
    func notAnsweredYet() throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.canPresent = false
        fixture.controller.performLaunchAction()
        #expect(fixture.dialogs.isEmpty)
        #expect(fixture.settings.automaticUpdateCheck == .notAsked)
        fixture.canPresent = true
        fixture.controller.performLaunchAction()
        #expect(fixture.dialogs == [.consent])
        #expect(fixture.stub.callCount == 0)
    }

    @Test("Does nothing at launch without a running version (EC-299)")
    func noVersion() throws {
        let fixture = try UpdateCheckFixture(current: nil, stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.controller.performLaunchAction()
        fixture.settings.automaticUpdateCheck = .enabled
        fixture.controller.performLaunchAction()
        #expect(fixture.dialogs.isEmpty)
        #expect(fixture.stub.callCount == 0)
    }

    @Test("Checks only once 24 hours have passed")
    func interval() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.7.0"))
        defer { fixture.finish() }
        fixture.settings.automaticUpdateCheck = .enabled
        fixture.settings.lastAutomaticUpdateCheck = fixture.now.addingTimeInterval(-Self.day + 60)
        fixture.controller.performLaunchAction()
        #expect(fixture.controller.checkTask == nil)
        #expect(fixture.stub.callCount == 0)

        fixture.now = fixture.now.addingTimeInterval(60)
        fixture.controller.performLaunchAction()
        await fixture.finishCheck()
        #expect(fixture.stub.callCount == 1)
        #expect(fixture.settings.lastAutomaticUpdateCheck == fixture.now)
        #expect(fixture.dialogs.isEmpty)
    }

    @Test("Announces each version once")
    func announcesOnce() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.settings.automaticUpdateCheck = .enabled
        fixture.controller.performLaunchAction()
        await fixture.finishCheck()
        #expect(fixture.dialogs == [.updateAvailable(latest: Self.v180, current: Self.v170)])

        fixture.now = fixture.now.addingTimeInterval(Self.day)
        fixture.controller.performLaunchAction()
        await fixture.finishCheck()
        #expect(fixture.stub.callCount == 2)
        #expect(fixture.dialogs.count == 1)
        #expect(fixture.settings.lastAutomaticUpdateCheck == fixture.now)
    }

    @Test("A version announced from the menu is not announced again automatically")
    func menuAnnouncementCounts() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.controller.checkFromMenu()
        await fixture.finishCheck()
        fixture.settings.automaticUpdateCheck = .enabled
        fixture.controller.performLaunchAction()
        await fixture.finishCheck()
        #expect(fixture.stub.callCount == 2)
        #expect(fixture.dialogs.count == 1)
    }

    @Test("Up to date and failures stay silent; failures do not reset the interval", arguments: [false, true])
    func silentResults(fails: Bool) async throws {
        let stub = fails ? UpdateTransportStub(error: UpdateTransportFailure()) : UpdateTransportStub(tag: "v1.7.0")
        let fixture = try UpdateCheckFixture(stub: stub)
        defer { fixture.finish() }
        fixture.settings.automaticUpdateCheck = .enabled
        fixture.controller.performLaunchAction()
        await fixture.finishCheck()
        #expect(fixture.dialogs.isEmpty)
        #expect(fixture.settings.lastAutomaticUpdateCheck == (fails ? nil : fixture.now))
        #expect(fixture.controller.canCheck)
    }

    @Test("A new version found while the user is busy is not announced or saved (EC-296)")
    func busy() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        fixture.settings.automaticUpdateCheck = .enabled
        fixture.controller.performLaunchAction()
        fixture.canPresent = false
        await fixture.finishCheck()
        #expect(fixture.dialogs.isEmpty)
        #expect(fixture.settings.lastAutomaticUpdateCheck == nil)
        #expect(fixture.settings.lastNotifiedUpdateVersion == nil)
    }

    @Test("The menu item is disabled while the automatic check runs")
    func menuDisabledDuringAutomaticCheck() async throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.7.0"))
        defer { fixture.finish() }
        fixture.settings.automaticUpdateCheck = .enabled
        fixture.controller.performLaunchAction()
        #expect(!fixture.controller.canCheck)
        await fixture.finishCheck()
        #expect(fixture.controller.canCheck)
    }

    @Test("The Settings checkbox follows the transition popup in the key loop and saves both states")
    func settingsCheckbox() throws {
        let fixture = try UpdateCheckFixture(stub: UpdateTransportStub(tag: "v1.8.0"))
        defer { fixture.finish() }
        let controller = SettingsWindowController(store: fixture.settings)
        let window = try #require(controller.window)
        let language = try #require(window.initialFirstResponder as? NSPopUpButton)
        var view: NSView = language
        var checkbox: NSButton?
        for _ in 0..<40 {
            guard let next = view.nextKeyView, next !== language else { break }
            if let button = next as? NSButton, button.action == NSSelectorFromString("toggleAutomaticUpdateCheck:") {
                checkbox = button
                #expect((view as? NSPopUpButton)?.action == NSSelectorFromString("selectTransition:"))
                #expect(button.nextKeyView === language)
                break
            }
            view = next
        }
        let updates = try #require(checkbox)
        #expect(updates.state == .off)
        updates.performClick(nil)
        #expect(SettingsStore(defaults: fixture.defaults).automaticUpdateCheck == .enabled)
        updates.performClick(nil)
        #expect(SettingsStore(defaults: fixture.defaults).automaticUpdateCheck == .disabled)
        #expect(fixture.stub.callCount == 0)
        withExtendedLifetime(controller) {}
    }
}
