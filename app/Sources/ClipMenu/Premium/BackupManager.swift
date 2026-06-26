import Foundation
import SwiftData

/// Coordinates snippet backups against a `BackupStore`. `@MainActor` because it
/// reads/writes the `ModelContext`; CloudKit work happens on the store's actor.
@MainActor
final class BackupManager {
    private let store: BackupStore
    private let context: ModelContext
    private let deviceName: String
    private let appVersion: String

    /// True while a restore is replacing data. Shared across every
    /// `BackupManager` instance (the scheduler and the restore sheet each build
    /// their own) so the scheduler's auto-backup can never run mid-restore.
    /// Main-actor-isolated, so all access is serialized.
    private static var isRestoring = false

    init(store: BackupStore, context: ModelContext, deviceName: String, appVersion: String) {
        self.store = store
        self.context = context
        self.deviceName = deviceName
        self.appVersion = appVersion
    }

    // MARK: Backup

    /// Create a version of the current snippets/folders. With `force` (used for
    /// pre-restore safety snapshots) it always saves; otherwise it skips when the
    /// content is unchanged since the newest backup.
    @discardableResult
    func backUpNow(kind: BackupKind, force: Bool = false, now: Date = Date()) async throws -> BackupResult {
        try await store.ensureZone()
        let snapshot = try SnippetSnapshot.capture(from: context)
        // Encode + hash once, off the main actor (snapshot is Sendable). The bytes
        // and hash are reused for change detection, the saved metadata, and the
        // uploaded payload — so a large snippet set is serialized only once.
        let (payload, hash) = await Task.detached { snapshot.canonicalPayloadAndHash() }.value

        if !force {
            let newest = BackupRetention.newestNormal(try await store.list())
            guard BackupRetention.hasChanges(newest: newest, currentHash: hash) else {
                return .noChanges
            }
        }

        let meta = BackupSaveMeta(
            kind: kind, clientDate: now, deviceName: deviceName, appVersion: appVersion,
            folderCount: snapshot.folderCount, snippetCount: snapshot.snippetCount,
            contentHash: hash, schemaVersion: snapshot.schemaVersion)
        let created = try await store.save(payload: payload, meta: meta)

        let pruneTargets = BackupRetention.recordsToPrune(try await store.list())
        if !pruneTargets.isEmpty { try? await store.delete(recordNames: pruneTargets) }
        cacheBaseline(date: now, hash: hash)
        return .created(created)
    }

    /// On-launch daily check: back up only if changed AND >=24h since the newest.
    /// `didSyncThisLaunch` reports whether a CloudKit import/export actually
    /// completed this launch (vs. the scheduler's timeout fallback).
    func runDailyCheck(now: Date = Date(), didSyncThisLaunch: Bool) async throws {
        guard !Self.isRestoring else { return }
        try await store.ensureZone()
        let snapshot = try SnippetSnapshot.capture(from: context)
        // Never snapshot an empty local store that hasn't synced yet this launch:
        // on a fresh or slow-syncing device the CloudKit import may still be
        // pending, and uploading that empty state would make it the newest
        // account-wide version. Backing up a genuinely-empty store is pointless
        // anyway, so the only case skipped is the dangerous "empty because import
        // is pending" one.
        if snapshot.folderCount == 0, snapshot.snippetCount == 0, !didSyncThisLaunch { return }
        let newest = BackupRetention.newestNormal(try await store.list())
        guard BackupRetention.shouldAutoBackUp(
            now: now, newest: newest, currentHash: snapshot.contentHash) else { return }
        try await backUpNow(kind: .auto, now: now)
    }

    /// Versions newest-first for the restore UI.
    func listForUI() async throws -> [BackupVersionMeta] {
        try await store.list().sorted { $0.effectiveDate > $1.effectiveDate }
    }

    // MARK: Restore (two-phase, rollback-safe)

    func restore(_ version: BackupVersionMeta) async throws {
        guard version.schemaVersion <= SnippetSnapshot.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(
                found: version.schemaVersion, supported: SnippetSnapshot.currentSchemaVersion)
        }
        Self.isRestoring = true
        defer { Self.isRestoring = false }

        // Phase A — validate target (no mutation yet).
        let payload = try await store.fetchPayload(recordName: version.recordName)
        let snapshot: SnippetSnapshot
        do { snapshot = try SnippetSnapshot.decode(payload) }
        catch { throw BackupError.validationFailed }
        guard snapshot.schemaVersion <= SnippetSnapshot.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(
                found: snapshot.schemaVersion, supported: SnippetSnapshot.currentSchemaVersion)
        }

        // Phase B — snapshot current state and confirm it persisted.
        do { try await backUpNow(kind: .preRestore, force: true) }
        catch { throw BackupError.preRestoreFailed }

        // Phase C — replace, rolling back if the save fails.
        try BackupManager.applyWithRollback(snapshot, to: context) { try self.context.save() }
    }

    /// Apply a snapshot then run `save`; on failure, roll the context back so the
    /// app is left exactly as it was. Static + injectable `save` for testability.
    static func applyWithRollback(
        _ snapshot: SnippetSnapshot, to context: ModelContext, save: () throws -> Void
    ) throws {
        try SnippetSnapshot.apply(snapshot, to: context)
        do { try save() }
        catch { context.rollback(); throw error }
    }

    // MARK: Local cache (offline fallback only — CloudKit is the source of truth)

    private func cacheBaseline(date: Date, hash: String) {
        UserDefaults.standard.set(date, forKey: PreferenceKeys.lastSnippetBackupDate)
        UserDefaults.standard.set(hash, forKey: PreferenceKeys.lastSnippetBackupHash)
    }
}
