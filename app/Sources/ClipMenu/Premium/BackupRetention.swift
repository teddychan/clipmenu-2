import Foundation

/// Pure retention & change-detection logic for backups. No I/O, fully testable.
enum BackupRetention {
    static let keepNormal = 20
    static let keepPreRestore = 3
    static let minAutoInterval: TimeInterval = 24 * 60 * 60

    /// Record names to delete so each class stays within its quota. Sorts by the
    /// server clock (`effectiveDate`) so client clock drift can't misorder.
    static func recordsToPrune(
        _ versions: [BackupVersionMeta],
        keepNormal: Int = keepNormal,
        keepPreRestore: Int = keepPreRestore
    ) -> [String] {
        func victims(_ items: [BackupVersionMeta], keep: Int) -> [String] {
            items.sorted { $0.effectiveDate > $1.effectiveDate }
                .dropFirst(keep).map(\.recordName)
        }
        let normal = versions.filter { $0.kind != .preRestore }
        let pre = versions.filter { $0.kind == .preRestore }
        return victims(normal, keep: keepNormal) + victims(pre, keep: keepPreRestore)
    }

    /// True when current content differs from the newest backup (or none exists).
    static func hasChanges(newest: BackupVersionMeta?, currentHash: String) -> Bool {
        guard let newest else { return true }
        return newest.contentHash != currentHash
    }

    /// Auto-backup fires only when content changed AND >= `minInterval` has passed
    /// since the newest backup (or there are no backups yet).
    static func shouldAutoBackUp(
        now: Date,
        newest: BackupVersionMeta?,
        currentHash: String,
        minInterval: TimeInterval = minAutoInterval
    ) -> Bool {
        guard hasChanges(newest: newest, currentHash: currentHash) else { return false }
        guard let newest else { return true }
        return now.timeIntervalSince(newest.effectiveDate) >= minInterval
    }

    /// The newest non-`preRestore` version (used as the change-detection baseline).
    static func newestNormal(_ versions: [BackupVersionMeta]) -> BackupVersionMeta? {
        versions.filter { $0.kind != .preRestore }
            .max { $0.effectiveDate < $1.effectiveDate }
    }
}
