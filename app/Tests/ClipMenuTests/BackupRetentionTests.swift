import Testing
import Foundation
@testable import ClipMenu

@Suite struct BackupRetentionTests {

    private func meta(_ name: String, _ kind: BackupKind, daysAgo: Int, hash: String = "h")
    -> BackupVersionMeta {
        let date = Date(timeIntervalSince1970: 1_000_000_000 - Double(daysAgo) * 86_400)
        return BackupVersionMeta(
            recordName: name, kind: kind, serverDate: date, clientDate: date,
            folderCount: 1, snippetCount: 1, contentHash: hash, schemaVersion: 1, deviceName: "Mac")
    }

    @Test func prunesOldestNormalBeyond20() {
        let versions = (0..<22).map { meta("a\($0)", .auto, daysAgo: $0) }
        let pruned = Set(BackupRetention.recordsToPrune(versions))
        #expect(pruned.count == 2)
        #expect(pruned.contains("a21"))
        #expect(pruned.contains("a20"))
        #expect(!pruned.contains("a0"))
    }

    @Test func preRestoreHasOwnQuotaAndNeverEvictsNormal() {
        let normal = (0..<20).map { meta("n\($0)", .auto, daysAgo: $0) }
        let pre = (0..<5).map { meta("p\($0)", .preRestore, daysAgo: $0) }
        let pruned = Set(BackupRetention.recordsToPrune(normal + pre))
        #expect(pruned == ["p3", "p4"])
    }

    @Test func hasChangesTrueWhenNoBackups() {
        #expect(BackupRetention.hasChanges(newest: nil, currentHash: "x"))
    }

    @Test func hasChangesComparesHash() {
        let m = meta("a", .auto, daysAgo: 0, hash: "same")
        #expect(!BackupRetention.hasChanges(newest: m, currentHash: "same"))
        #expect(BackupRetention.hasChanges(newest: m, currentHash: "different"))
    }

    @Test func autoBackupRequiresChangeAndInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let recent = meta("a", .auto, daysAgo: 0, hash: "old")
        let old = meta("b", .auto, daysAgo: 2, hash: "old")
        #expect(!BackupRetention.shouldAutoBackUp(now: now, newest: recent, currentHash: "new"))
        #expect(BackupRetention.shouldAutoBackUp(now: now, newest: old, currentHash: "new"))
        #expect(!BackupRetention.shouldAutoBackUp(now: now, newest: old, currentHash: "old"))
        #expect(BackupRetention.shouldAutoBackUp(now: now, newest: nil, currentHash: "new"))
    }
}
