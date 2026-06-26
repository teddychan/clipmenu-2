import Foundation
import CoreData
import os

/// Tracks when the snippets store last finished syncing with iCloud.
///
/// SwiftData mirrors the CloudKit-backed store through `NSPersistentCloudKitContainer`
/// under the hood, which posts `eventChangedNotification` for every setup/import/export
/// event. There is no higher-level "last synced" signal, so we observe that notification
/// and remember the end date of the most recent *finished, successful* import or export.
/// The Backup pane reads `lastSyncDate` to show "Last synced …". Only meaningful when
/// CloudKit is active this launch (`AppStore.isCloudKitActive`); otherwise no events fire
/// and `lastSyncDate` stays at whatever was last persisted.
@MainActor
final class CloudSyncMonitor: ObservableObject {
    static let shared = CloudSyncMonitor()

    /// End date of the last successful CloudKit import/export, or `nil` before the first
    /// sync. Persisted across launches so the pane shows a real time immediately at launch.
    @Published private(set) var lastSyncDate: Date?

    /// Whether a successful import/export has completed *this launch* — distinct
    /// from `lastSyncDate`, which is restored from a previous launch. The backup
    /// scheduler waits on this so it never snapshots a pre-sync local store.
    private var syncedThisLaunch = false

    /// Read-only view of `syncedThisLaunch` for the backup scheduler, so an
    /// auto-backup can tell a genuine empty store from one whose import is still
    /// pending (`waitForFirstSync` may have timed out rather than observed a sync).
    var hasSyncedThisLaunch: Bool { syncedThisLaunch }

    private var observer: NSObjectProtocol?
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "com.dragonapp.clipmenu-2", category: "cloud-sync")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastSyncDate = defaults.object(forKey: PreferenceKeys.lastCloudSyncDate) as? Date
    }

    /// Begin observing CloudKit sync events. Idempotent.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: .main) { [weak self] note in
                // Parse the (non-Sendable) Notification here, off the main actor, and only
                // hand the Sendable end date across the boundary. Count a finished,
                // successful import or export — not setup, nor the "started" half (endDate nil).
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      event.succeeded, let endDate = event.endDate,
                      event.type == .import || event.type == .export else { return }
                // queue: .main delivers on the main thread, so assumeIsolated is safe.
                MainActor.assumeIsolated { self?.record(endDate) }
            }
    }

    private func record(_ endDate: Date) {
        syncedThisLaunch = true
        guard endDate != lastSyncDate else { return }
        lastSyncDate = endDate
        defaults.set(endDate, forKey: PreferenceKeys.lastCloudSyncDate)
        Self.log.info("CloudKit sync finished")
    }

    /// Suspend until the first successful CloudKit import/export completes this
    /// launch, or `timeout` seconds elapse — whichever comes first. Returns at
    /// once if a sync already finished this launch. Polls because there is no
    /// awaitable CloudKit "settled" signal; this runs once at startup only.
    func waitForFirstSync(timeout: TimeInterval) async {
        guard !syncedThisLaunch else { return }
        let steps = max(1, Int(timeout / 0.2))
        for _ in 0..<steps {
            try? await Task.sleep(for: .milliseconds(200))
            if syncedThisLaunch { return }
        }
    }
}
