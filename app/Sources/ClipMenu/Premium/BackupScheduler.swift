import Foundation
import AppKit
import os

/// Runs the once-per-launch automatic snippet backup into the user-chosen backup
/// folder. A no-op until the user has picked a folder in the Sync/Backup pane.
@MainActor
enum BackupScheduler {
    private static let log = Logger(subsystem: "com.dragonapp.clipmenu-2", category: "backup")

    /// Whether automatic backup may run: the user has chosen a backup folder.
    static var isEligible: Bool {
        BackupFolder.isConfigured()
    }

    /// Build a manager bound to the live container + the user's backup folder, or
    /// nil when no folder is configured.
    static func makeManager() -> BackupManager? {
        guard let folder = BackupFolder.resolvedURL() else { return nil }
        return BackupManager(
            store: FolderBackupStore(folder: folder),
            context: AppStore.container.mainContext,
            deviceName: ProcessInfo.processInfo.hostName,
            appVersion: AppInfo.version)
    }

    /// Fire-and-forget daily check; safe to call once at startup.
    static func runIfEligible() {
        guard let manager = makeManager() else { return }
        Task {
            // The local store is authoritative (no CloudKit import to wait for), so the
            // snapshot always reflects real data.
            do { try await manager.runDailyCheck(didSyncThisLaunch: true) }
            catch { log.error("daily backup check failed: \(String(describing: error))") }
        }
    }
}
