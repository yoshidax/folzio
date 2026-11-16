import Foundation
import Testing
@testable import FolzioCore

@Suite("Confirmation settings")
struct ConfirmationSettingsTests {
    private static let legacyKey = "fileOps.confirmBeforeExecuting"

    private static func key(_ target: ConfirmationTarget) -> String { "fileOps.confirm.\(target.rawValue)" }

    @Test("Every operation confirms by default (FR-023)")
    func defaultsToConfirmingEverything() {
        withDefaults { defaults in
            let options = SettingsStore(defaults: defaults).confirmation
            for target in ConfirmationTarget.allCases {
                #expect(options.isEnabled(target), "\(target)")
            }
        }
    }

    @Test("Turning off one operation leaves the other four on (FR-023)", arguments: ConfirmationTarget.allCases)
    func savesEachOperationIndependently(_ target: ConfirmationTarget) {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            var options = ConfirmationOptions()
            options.setEnabled(false, for: target)
            store.confirmation = options

            let reloaded = SettingsStore(defaults: defaults).confirmation
            for other in ConfirmationTarget.allCases {
                #expect(reloaded.isEnabled(other) == (other != target), "\(target) off → \(other)")
            }
            #expect(defaults.object(forKey: Self.key(target)) as? Bool == false)
        }
    }

    @Test("The Settings window order is copy, move, rename, removing from Favorites, Trash (FR-223)")
    func targetOrder() {
        #expect(ConfirmationTarget.allCases == [.copy, .move, .rename, .removeFavorite, .trash])
    }

    @Test(
        "A turned-off earlier setting is taken over by copy, Favorites, and Trash; move and rename start on (FR-396, US85-AS8)"
    )
    func takesOverTurnedOffLegacySetting() {
        withDefaults { defaults in
            defaults.set(false, forKey: Self.legacyKey)
            let options = SettingsStore(defaults: defaults).confirmation
            #expect(!options.copy)
            #expect(!options.removeFavorite)
            #expect(!options.trash)
            #expect(options.move)
            #expect(options.rename)
        }
    }

    @Test("A turned-on earlier setting turns every operation on (FR-396, US85-AS9)")
    func takesOverTurnedOnLegacySetting() {
        withDefaults { defaults in
            defaults.set(true, forKey: Self.legacyKey)
            #expect(SettingsStore(defaults: defaults).confirmation == ConfirmationOptions())
        }
    }

    @Test("An earlier setting of the wrong type is ignored (FR-396)")
    func ignoresInvalidLegacySetting() {
        withDefaults { defaults in
            for invalid in ["no", 0.5, [false]] as [Any] {
                defaults.set(invalid, forKey: Self.legacyKey)
                #expect(SettingsStore(defaults: defaults).confirmation == ConfirmationOptions(), "\(invalid)")
            }
        }
    }

    @Test("A saved per-operation value wins over the earlier setting (FR-396)")
    func savedValueWinsOverLegacySetting() {
        withDefaults { defaults in
            defaults.set(false, forKey: Self.legacyKey)
            defaults.set(true, forKey: Self.key(.copy))
            defaults.set(false, forKey: Self.key(.move))
            let options = SettingsStore(defaults: defaults).confirmation
            #expect(options.copy)
            #expect(!options.move)
            #expect(!options.trash)
        }
    }

    @Test("Saving never writes or removes the earlier setting (A-234)")
    func keepsLegacySetting() {
        withDefaults { defaults in
            defaults.set(false, forKey: Self.legacyKey)
            let store = SettingsStore(defaults: defaults)
            store.confirmation = ConfirmationOptions()
            #expect(defaults.object(forKey: Self.legacyKey) as? Bool == false)
            #expect(store.confirmation == ConfirmationOptions())
        }
        withDefaults { defaults in
            SettingsStore(defaults: defaults).confirmation = ConfirmationOptions(copy: false)
            #expect(defaults.object(forKey: Self.legacyKey) == nil)
        }
    }

    @Test("Saving posts confirmationOptionsDidChange (EC-261)")
    func postsChange() {
        withDefaults { defaults in
            let store = SettingsStore(defaults: defaults)
            // The observer block is `@Sendable`, so Swift 6.0 on CI rejects mutating a captured `var` in it.
            let count = NotificationCounter()
            let observer = NotificationCenter.default.addObserver(
                forName: .confirmationOptionsDidChange, object: defaults, queue: nil
            ) { _ in count.increment() }
            defer { NotificationCenter.default.removeObserver(observer) }
            store.confirmation = ConfirmationOptions(move: false)
            #expect(count.value == 1)
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "ConfirmationSettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("could not create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}

/// A thread-safe counter for a notification observer block.
private final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
