import Foundation
import AppKit
import os

/// Runs the once-per-launch automatic snippet backup whenever iCloud sync is active
/// this launch (the same condition under which CloudKit is mirroring). A no-op when
/// the build is running local-only.
@MainActor
enum BackupScheduler {
    private static let log = Logger(subsystem: "com.dragonapp.clipmenu-2", category: "backup")

    /// Whether automatic backup may run this launch. Mirrors the live-sync gate:
    /// CloudKit is actually active, so there's a private database to back up to.
    static var isEligible: Bool {
        AppStore.isCloudKitActive
    }

    /// Build a manager bound to the live container + CloudKit store.
    static func makeManager() -> BackupManager {
        let deviceName = ProcessInfo.processInfo.hostName
        return BackupManager(
            store: CloudKitBackupStore(containerID: AppStore.cloudContainerID),
            context: AppStore.container.mainContext,
            deviceName: deviceName,
            appVersion: AppInfo.version)
    }

    /// Fire-and-forget daily check; safe to call once at startup.
    static func runIfEligible() {
        guard isEligible else { return }
        let manager = makeManager()
        Task {
            // Wait for the first CloudKit import/export this launch so the backup
            // reflects synced data rather than a stale or empty local store (e.g.
            // a new Mac or freshly re-enabled iCloud). Fall back after 30s so an
            // offline launch — which fires no sync events — still backs up.
            await CloudSyncMonitor.shared.waitForFirstSync(timeout: 30)
            let didSync = CloudSyncMonitor.shared.hasSyncedThisLaunch
            do { try await manager.runDailyCheck(didSyncThisLaunch: didSync) }
            catch { log.error("daily backup check failed: \(String(describing: error))") }
        }
    }
}
