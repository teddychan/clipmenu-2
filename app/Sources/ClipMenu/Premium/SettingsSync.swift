import Foundation
import os

/// Minimal abstraction over `NSUbiquitousKeyValueStore` so the mirroring logic is
/// unit-testable with a fake.
@MainActor
protocol UbiquitousStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    var snapshot: [String: Any] { get }
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousStore {
    var snapshot: [String: Any] { dictionaryRepresentation }
}

/// Mirrors a whitelist of preference keys between `UserDefaults` and the iCloud
/// key-value store. Without the `com.apple.developer.ubiquity-kvstore-identifier`
/// entitlement the KV store is a harmless local cache, so this degrades silently.
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()

    /// Preference keys that should follow the user across Macs. Excludes machine-local
    /// flags: `loginItem` (per-machine launch state, reconciled with SMAppService),
    /// `suppressAlertForLoginItem`, `didMigrateToSplitStores`, and `iCloudSyncEnabled`.
    static let syncedKeys: [String] = [
        // General
        PreferenceKeys.inputPasteCommand, PreferenceKeys.reorderClipsAfterPasting, PreferenceKeys.maxHistorySize, PreferenceKeys.timeInterval,
        PreferenceKeys.saveHistoryOnQuit, PreferenceKeys.showStatusItem, PreferenceKeys.exportHistoryAsSingleFile,
        PreferenceKeys.tagOfSeparatorForExportHistoryToFile,
        // Menu
        PreferenceKeys.numberOfItemsPlaceInline, PreferenceKeys.numberOfItemsPlaceInsideFolder, PreferenceKeys.maxMenuItemTitleLength,
        PreferenceKeys.menuItemsAreMarkedWithNumbers, PreferenceKeys.addNumericKeyEquivalents, PreferenceKeys.showLabelsInMenu,
        PreferenceKeys.addClearHistoryMenuItem, PreferenceKeys.showAlertBeforeClearHistory, PreferenceKeys.showToolTipOnMenuItem,
        PreferenceKeys.maxLengthOfToolTipKey, PreferenceKeys.changeFontSize, PreferenceKeys.howToChangeFontSize, PreferenceKeys.selectedFontSize,
        PreferenceKeys.showImageInTheMenu, PreferenceKeys.thumbnailWidth, PreferenceKeys.thumbnailHeight, PreferenceKeys.showIconInTheMenu,
        PreferenceKeys.menuIconSize, PreferenceKeys.positionOfSnippets, PreferenceKeys.groupSnippetsInFolder,
        // Type
        PreferenceKeys.storeTypes,
        // Action
        PreferenceKeys.enableAction, PreferenceKeys.invokeActionImmediately, PreferenceKeys.controlClickBehavior, PreferenceKeys.shiftClickBehavior,
        PreferenceKeys.optionClickBehavior, PreferenceKeys.commandClickBehavior,
        // Shortcuts + exclusions
        PreferenceKeys.hotKeys, PreferenceKeys.excludeApps,
    ]

    private static let log = Logger(subsystem: "com.dragonapp.clipmenu-2", category: "settings-sync")

    private let cloud: UbiquitousStore
    private let defaults: UserDefaults
    // nonisolated(unsafe): only mutated on @MainActor; deinit reads it for cleanup.
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []
    private var applyingRemoteChange = false
    private var started = false
    private var pendingPush: Task<Void, Never>?

    init(cloud: UbiquitousStore = NSUbiquitousKeyValueStore.default, defaults: UserDefaults = .standard) {
        self.cloud = cloud
        self.defaults = defaults
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Pure mirroring (tested)

    static func pushToCloud(keys: [String], from defaults: UserDefaults, to cloud: UbiquitousStore) {
        for key in keys {
            if let value = defaults.object(forKey: key) {
                cloud.set(value, forKey: key)
            }
        }
        cloud.synchronize()
    }

    static func pullFromCloud(keys: [String], from cloud: UbiquitousStore, to defaults: UserDefaults) {
        let snapshot = cloud.snapshot
        for key in keys where snapshot[key] != nil {
            defaults.set(snapshot[key], forKey: key)
        }
    }

    // MARK: Lifecycle

    /// Coalesce rapid local changes into one push after a short quiet period, so a
    /// burst of UserDefaults writes doesn't hammer the iCloud key-value store.
    private func schedulePush() {
        pendingPush?.cancel()
        pendingPush = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            Self.pushToCloud(keys: Self.syncedKeys, from: self.defaults, to: self.cloud)
        }
    }

    /// Reconcile once (cloud wins so a fresh Mac inherits settings), seed the cloud
    /// with local values, then observe changes in both directions. Idempotent.
    func start() {
        guard !started else { return }
        started = true
        cloud.synchronize()

        applyingRemoteChange = true
        Self.pullFromCloud(keys: Self.syncedKeys, from: cloud, to: defaults)
        applyingRemoteChange = false
        Self.pushToCloud(keys: Self.syncedKeys, from: defaults, to: cloud)

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud as? NSUbiquitousKeyValueStore, queue: .main) { [weak self] _ in
                // queue: .main delivers on the main thread, so assumeIsolated is safe.
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.applyingRemoteChange = true
                    Self.pullFromCloud(keys: Self.syncedKeys, from: self.cloud, to: self.defaults)
                    self.applyingRemoteChange = false
                    Self.log.info("Applied remote settings change")
                }
            })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults, queue: .main) { [weak self] _ in
                // queue: .main delivers on the main thread, so assumeIsolated is safe.
                MainActor.assumeIsolated {
                    guard let self, !self.applyingRemoteChange else { return }
                    self.schedulePush()
                }
            })
    }

    /// Flush any pending push, then stop observing. Symmetric with start().
    /// The flush matters at quit: without it a setting changed inside the
    /// debounce window is dropped, and the next launch's cloud-wins pull then
    /// silently reverts it to the stale cloud value.
    func stop() {
        if pendingPush != nil {
            Self.pushToCloud(keys: Self.syncedKeys, from: defaults, to: cloud)
        }
        pendingPush?.cancel()
        pendingPush = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        started = false
    }
}
