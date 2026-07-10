import Testing
import Foundation
@testable import ClipMenu

// Characterization of BackupScheduler's eligibility + manager-building dispatch
// (the once-per-launch automatic backup gate). Driven by toggling the backup
// folder bookmark in UserDefaults.standard. The fire-and-forget Task in
// runIfEligible() (manager.runDailyCheck) is only exercised on the no-op path;
// the eligible branch spawns an async backup write, which is left uncovered to
// keep the suite deterministic (BackupManager itself is covered by its own tests).
//
// Serialized + save/restore of the two UserDefaults keys BackupFolder writes.
@Suite(.serialized) @MainActor
struct BackupSchedulerCoverageTests {

    private func withCleanBackupDefaults(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let prevBookmark = defaults.data(forKey: PreferenceKeys.backupFolderBookmark)
        let prevPath = defaults.string(forKey: PreferenceKeys.backupFolderPath)
        defer {
            if let prevBookmark { defaults.set(prevBookmark, forKey: PreferenceKeys.backupFolderBookmark) }
            else { defaults.removeObject(forKey: PreferenceKeys.backupFolderBookmark) }
            if let prevPath { defaults.set(prevPath, forKey: PreferenceKeys.backupFolderPath) }
            else { defaults.removeObject(forKey: PreferenceKeys.backupFolderPath) }
        }
        try body()
    }

    @Test func notEligibleAndNoManagerWhenNoFolderConfigured() throws {
        try withCleanBackupDefaults {
            UserDefaults.standard.removeObject(forKey: PreferenceKeys.backupFolderBookmark)
            UserDefaults.standard.removeObject(forKey: PreferenceKeys.backupFolderPath)

            #expect(BackupScheduler.isEligible == false)
            #expect(BackupScheduler.makeManager() == nil)
            // No manager ⇒ runIfEligible returns immediately (no Task spawned).
            BackupScheduler.runIfEligible()
        }
    }

    @Test func eligibleAndManagerBuiltWhenFolderConfigured() throws {
        try withCleanBackupDefaults {
            let dir = URL.temporaryDirectory.appending(path: "ClipMenuBackupSched-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }

            #expect(BackupFolder.set(dir))
            #expect(BackupScheduler.isEligible)
            // makeManager binds the live container + resolved folder into a real
            // BackupManager (no I/O runs until runDailyCheck is invoked).
            #expect(BackupScheduler.makeManager() != nil)
        }
    }
}
