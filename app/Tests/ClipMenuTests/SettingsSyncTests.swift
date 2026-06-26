import Testing
import Foundation
@testable import ClipMenu

@MainActor
final class FakeUbiquitousStore: UbiquitousStore {
    var storage: [String: Any] = [:]
    func object(forKey key: String) -> Any? { storage[key] }
    func set(_ value: Any?, forKey key: String) { storage[key] = value }
    var snapshot: [String: Any] { storage }
    @discardableResult func synchronize() -> Bool { true }
}

@Suite @MainActor
struct SettingsSyncTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "SettingsSyncTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func pushCopiesOnlyWhitelistedKeys() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "inputPasteCommand")
        defaults.set("secret", forKey: "someUnsyncedKey")
        let cloud = FakeUbiquitousStore()

        SettingsSync.pushToCloud(keys: ["inputPasteCommand"], from: defaults, to: cloud)

        #expect(cloud.object(forKey: "inputPasteCommand") as? Bool == true)
        #expect(cloud.object(forKey: "someUnsyncedKey") == nil)
    }

    @Test func pullWritesCloudValuesIntoDefaults() {
        let defaults = freshDefaults()
        let cloud = FakeUbiquitousStore()
        cloud.set(25, forKey: "maxHistorySize")
        cloud.set("ignored", forKey: "someUnsyncedKey")

        SettingsSync.pullFromCloud(keys: ["maxHistorySize"], from: cloud, to: defaults)

        #expect(defaults.integer(forKey: "maxHistorySize") == 25)
        #expect(defaults.object(forKey: "someUnsyncedKey") == nil)
    }

    @Test func roundTripPreservesValues() {
        let deviceA = freshDefaults()
        deviceA.set(15, forKey: "maxHistorySize")
        deviceA.set(false, forKey: "saveHistoryOnQuit")
        let cloud = FakeUbiquitousStore()
        SettingsSync.pushToCloud(keys: SettingsSync.syncedKeys, from: deviceA, to: cloud)

        let deviceB = freshDefaults()
        SettingsSync.pullFromCloud(keys: SettingsSync.syncedKeys, from: cloud, to: deviceB)

        #expect(deviceB.integer(forKey: "maxHistorySize") == 15)
        #expect(deviceB.object(forKey: "saveHistoryOnQuit") as? Bool == false)
    }

    // Local edits reach the cloud only via a 500ms debounced push. stop() runs
    // at app termination; cancelling the pending push there silently drops a
    // setting changed just before quit (the next launch's cloud-wins pull then
    // reverts it). stop() must flush before tearing down.
    @Test func stopFlushesPendingDebouncedPush() {
        let defaults = freshDefaults()
        let cloud = FakeUbiquitousStore()
        let sync = SettingsSync(cloud: cloud, defaults: defaults)
        sync.start()

        // A local change within the debounce window, then immediate quit.
        defaults.set(99, forKey: "maxHistorySize")
        sync.stop()

        #expect(cloud.object(forKey: "maxHistorySize") as? Int == 99)
    }

    @Test func machineLocalKeysAreNotSynced() {
        #expect(!SettingsSync.syncedKeys.contains("loginItem"))
        #expect(!SettingsSync.syncedKeys.contains("iCloudSyncEnabled"))
        #expect(!SettingsSync.syncedKeys.contains("didMigrateToSplitStores"))
        #expect(!SettingsSync.syncedKeys.contains("suppressAlertForLoginItem"))
    }
}
