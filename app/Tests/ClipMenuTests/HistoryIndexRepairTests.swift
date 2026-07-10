import Testing
import Foundation
import SQLite3
import SwiftData
@testable import ClipMenu

// Verifies HistoryIndexRepair restores the ClipRecord indexes that SwiftData's
// automatic migration leaves off an upgraded store, and that SwiftData can still
// open and write to the repaired store (the repair must not break it).
@Suite struct HistoryIndexRepairTests {

    private func indexNames(at url: URL) -> Set<String> {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db,
            "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='ZCLIPRECORD'",
            -1, &stmt, nil) == SQLITE_OK else { return [] }
        var names = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { names.insert(String(cString: c)) }
        }
        return names
    }

    private func exec(_ sql: String, at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    @Test func repairRestoresMissingIndexesAndStoreStaysUsable() async throws {
        let dir = URL.temporaryDirectory.appending(path: "ClipMenuIdxRepair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "History.store")
        let config = ModelConfiguration(
            "History", schema: Schema([ClipRecord.self, ClipImage.self]), url: url, cloudKitDatabase: .none)

        // Fresh SwiftData store — has the three #Index indexes.
        do {
            let c = try ModelContainer(for: ClipRecord.self, ClipImage.self, configurations: config)
            let ctx = ModelContext(c)
            ctx.insert(ClipRecord(typeIdentifiers: ["String"], stringValue: "seed", contentHash: 1))
            try ctx.save()
        }
        // Force a WAL checkpoint so the dropped-index state is in the main file.
        exec("PRAGMA wal_checkpoint(TRUNCATE)", at: url)

        // Simulate a migrated store: drop the #Index indexes SwiftData would leave off.
        for name in HistoryIndexRepair.indexStatements.compactMap(Self.indexName(fromCreate:)) {
            exec("DROP INDEX IF EXISTS \(name)", at: url)
        }
        let missing = indexNames(at: url).filter { $0.hasPrefix("Z_ClipRecord_SwiftData") }
        #expect(missing.isEmpty, "precondition: indexes dropped")

        // Repair.
        #expect(HistoryIndexRepair.ensureIndexes(at: url))
        let restored = indexNames(at: url).filter { $0.hasPrefix("Z_ClipRecord_SwiftData") }
        #expect(restored.count == 3, "all three indexes restored")

        // SwiftData still opens the repaired store and captures a new clip.
        let reopened = try ModelContainer(for: ClipRecord.self, ClipImage.self, configurations: config)
        let store = ClipStore(modelContainer: reopened)
        await store.capture(PasteboardSnapshot(
            typeNames: ["String"], stringValue: "after repair", rtfData: nil, pdfData: nil,
            filenames: nil, urlString: nil, imageData: nil, contentHash: 2))
        let count = try ModelContext(reopened).fetchCount(FetchDescriptor<ClipRecord>())
        #expect(count == 2, "repaired store still accepts writes")
    }

    @Test func ensureIndexesIsNoOpWhenFileMissing() {
        let url = URL(fileURLWithPath: "/tmp/clipmenu-nope-\(UUID().uuidString)/History.store")
        #expect(!HistoryIndexRepair.ensureIndexes(at: url))
    }

    private static func indexName(fromCreate sql: String) -> String? {
        // "CREATE INDEX IF NOT EXISTS <name> ON ..." -> <name> (skip the 5 keywords)
        sql.split(separator: " ").dropFirst(5).first.map(String.init)
    }
}
