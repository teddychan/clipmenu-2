import Foundation

/// The category of a backup version. `preRestore` snapshots are created
/// automatically right before a destructive restore and live in their own
/// retention quota so they can never evict daily/manual history.
enum BackupKind: String, Codable, Sendable, CaseIterable {
    case auto
    case manual
    case preRestore
}

/// Metadata describing one stored backup version (no payload).
struct BackupVersionMeta: Sendable, Equatable, Identifiable {
    var recordName: String
    var kind: BackupKind
    /// CloudKit server creation date — authoritative for sort/prune.
    var serverDate: Date?
    /// Client-supplied date, for display and as a fallback if `serverDate` is nil.
    var clientDate: Date
    var folderCount: Int
    var snippetCount: Int
    var contentHash: String
    var schemaVersion: Int
    var deviceName: String

    var id: String { recordName }
    /// Date used for ordering: prefer the server clock over the client clock.
    var effectiveDate: Date { serverDate ?? clientDate }
}

/// Fields needed to persist a new backup version.
struct BackupSaveMeta: Sendable {
    var kind: BackupKind
    var clientDate: Date
    var deviceName: String
    var appVersion: String
    var folderCount: Int
    var snippetCount: Int
    var contentHash: String
    var schemaVersion: Int
}

/// Storage boundary for backups. The concrete impl is CloudKit; tests inject a
/// mock so all orchestration logic is verifiable without a network.
protocol BackupStore: Sendable {
    /// Idempotently ensure the backing zone exists.
    func ensureZone() async throws
    /// All versions, in no guaranteed order.
    func list() async throws -> [BackupVersionMeta]
    /// Persist a new version; returns its stored metadata.
    func save(payload: Data, meta: BackupSaveMeta) async throws -> BackupVersionMeta
    /// Download a version's snapshot payload bytes.
    func fetchPayload(recordName: String) async throws -> Data
    /// Delete versions by record name.
    func delete(recordNames: [String]) async throws
}

/// Typed failures surfaced to the restore UI.
enum BackupError: Error, Equatable {
    case unsupportedSchemaVersion(found: Int, supported: Int)
    case validationFailed
    case preRestoreFailed
}

/// Outcome of a backup attempt.
enum BackupResult: Equatable {
    case created(BackupVersionMeta)
    case noChanges
}
