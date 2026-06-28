import Foundation
import CloudKit

/// CloudKit-backed `BackupStore`. Stores one `SnippetBackup` record per version
/// in a dedicated `Backups` zone of the app's private database. The snapshot
/// bytes ride as a `CKAsset` (no 1 MB field limit); sensitive metadata uses
/// `encryptedValues` so it is end-to-end encrypted under Advanced Data Protection.
///
/// Only constructed in the App Store build behind the same gate as live sync; the
/// Developer ID build never references it.
actor CloudKitBackupStore: BackupStore {
    static let recordType = "SnippetBackup"

    /// The record keys `meta(from:)` reads — everything except the `payload`
    /// CKAsset. `list()` is metadata-only (UI, daily/dup checks, pruning), so it
    /// fetches just these and never downloads the snapshot assets. `creationDate`
    /// is intrinsic record metadata and is always returned regardless.
    private static let metadataKeys: [CKRecord.FieldKey] = [
        "kind", "clientDate", "folderCount", "snippetCount",
        "schemaVersion", "contentHash", "deviceName"]

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var zoneEnsured = false
    /// App-private directory for the short-lived CKAsset staging file. Never the
    /// shared system temp dir, so a crash can't leave plaintext snippets where
    /// other processes might read them. Swept on each save.
    private let stagingDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipMenuBackupStaging", isDirectory: true)

    init(containerID: String) {
        let container = CKContainer(identifier: containerID)
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: "Backups", ownerName: CKCurrentUserDefaultName)
    }

    func ensureZone() async throws {
        guard !zoneEnsured else { return }
        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
            zoneEnsured = true
        } catch let error as CKError where error.code == .serverRecordChanged {
            zoneEnsured = true   // already exists
        }
    }

    func list() async throws -> [BackupVersionMeta] {
        try await ensureZone()
        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        do {
            // Follow the query cursor across pages — CloudKit caps a single response,
            // and retention/multi-device churn can push the record count past one page.
            var metas: [BackupVersionMeta] = []
            var response = try await database.records(
                matching: query, inZoneWith: zoneID, desiredKeys: Self.metadataKeys)
            while true {
                for (_, result) in response.matchResults {
                    if let record = try? result.get(), let meta = Self.meta(from: record) {
                        metas.append(meta)
                    }
                }
                guard let cursor = response.queryCursor else { break }
                // The continuation overload does NOT inherit the original query's
                // desiredKeys (it defaults to nil = all keys), so pass them again
                // or pages 2+ would download every record's payload CKAsset.
                response = try await database.records(
                    continuingMatchFrom: cursor, desiredKeys: Self.metadataKeys)
            }
            return metas
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            zoneEnsured = false
            try await ensureZone()
            return []
        }
    }

    func save(payload: Data, meta: BackupSaveMeta) async throws -> BackupVersionMeta {
        try await ensureZone()
        // Stage the payload in an app-private, 0600 file for the CKAsset; keep it
        // alive until the save completes, then remove it. Never log its path or
        // contents. A crash before removal can't leak plaintext snippets to other
        // processes (private dir, owner-only perms, swept on the next save).
        let tempURL = try prepareStagingFile()
        try payload.write(to: tempURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["kind"] = meta.kind.rawValue as CKRecordValue
        record["clientDate"] = meta.clientDate as CKRecordValue
        record["folderCount"] = meta.folderCount as CKRecordValue
        record["snippetCount"] = meta.snippetCount as CKRecordValue
        record["schemaVersion"] = meta.schemaVersion as CKRecordValue
        // Sensitive -> E2E-encrypted under ADP.
        record.encryptedValues["contentHash"] = meta.contentHash
        record.encryptedValues["deviceName"] = meta.deviceName
        record.encryptedValues["appVersion"] = meta.appVersion
        record["payload"] = CKAsset(fileURL: tempURL)

        let saved = try await database.save(record)
        guard let result = Self.meta(from: saved) else {
            throw BackupError.validationFailed
        }
        return result
    }

    /// Prepare a fresh, owner-only staging path under our private directory.
    /// Creates the dir (0700) and sweeps any files a prior crash left behind —
    /// saves are serialized on this actor, so it is normally already empty.
    private func prepareStagingFile() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(
            at: stagingDir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        if let leftovers = try? fm.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil) {
            for url in leftovers { try? fm.removeItem(at: url) }
        }
        return stagingDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }

    func fetchPayload(recordName: String) async throws -> Data {
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = try await database.record(for: recordID)
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
            throw BackupError.validationFailed
        }
        return try Data(contentsOf: url)
    }

    func delete(recordNames: [String]) async throws {
        let ids = recordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }
        _ = try await database.modifyRecords(saving: [], deleting: ids)
    }

    // MARK: Mapping

    private static func meta(from record: CKRecord) -> BackupVersionMeta? {
        guard
            let kindRaw = record["kind"] as? String, let kind = BackupKind(rawValue: kindRaw),
            let clientDate = record["clientDate"] as? Date,
            let folderCount = record["folderCount"] as? Int,
            let snippetCount = record["snippetCount"] as? Int,
            let schemaVersion = record["schemaVersion"] as? Int
        else { return nil }
        return BackupVersionMeta(
            recordName: record.recordID.recordName,
            kind: kind,
            serverDate: record.creationDate,
            clientDate: clientDate,
            folderCount: folderCount,
            snippetCount: snippetCount,
            contentHash: record.encryptedValues["contentHash"] as? String ?? "",
            schemaVersion: schemaVersion,
            deviceName: record.encryptedValues["deviceName"] as? String ?? "")
    }
}
