import Foundation
import SQLite3
import os

// SwiftData builds ClipRecord's `#Index` indexes on a FRESH store, but its
// automatic lightweight migration does NOT add them to a store created before the
// index was declared (v2.17.7). So new installs get the indexes; anyone who
// upgraded keeps a store whose only index is the auto image-relationship one, and
// the capture-time dedup lookup / history sort fall back to full scans.
//
// This recreates exactly those indexes on an existing store, matching SwiftData's
// own names and definitions (verified against a fresh store), so a repaired store
// is byte-for-byte equivalent to one SwiftData would have built itself. It MUST
// run before SwiftData opens the store (a plain SQLite connection, no concurrent
// access). Pure optimization: every step is best-effort and any failure just
// leaves the store as-is, exactly as before this repair existed.
enum HistoryIndexRepair {
    private static let log = Logger(subsystem: "com.dragonapp.clipmenu-2", category: "HistoryIndexRepair")

    /// `CREATE INDEX IF NOT EXISTS` statements copied verbatim from a fresh
    /// SwiftData store's schema (same names, columns, and BINARY collation), so
    /// they are no-ops where SwiftData already created them and identical to what
    /// it would create where it didn't.
    static let indexStatements = [
        "CREATE INDEX IF NOT EXISTS Z_ClipRecord_SwiftDataIndexOnBinarycontentHash ON ZCLIPRECORD (ZCONTENTHASH COLLATE BINARY ASC)",
        "CREATE INDEX IF NOT EXISTS Z_ClipRecord_SwiftDataIndexOnBinarylastUsedDate ON ZCLIPRECORD (ZLASTUSEDDATE COLLATE BINARY ASC)",
        "CREATE INDEX IF NOT EXISTS Z_ClipRecord_SwiftDataIndexOnBinarycreatedDate ON ZCLIPRECORD (ZCREATEDDATE COLLATE BINARY ASC)",
    ]

    /// Ensure the ClipRecord indexes exist on the history store at `storeURL`.
    /// No-op when the file doesn't exist yet (fresh install — SwiftData builds
    /// them) or when the `ZCLIPRECORD` table isn't present. Returns true if the
    /// statements ran without error (used by tests).
    @discardableResult
    static func ensureIndexes(at storeURL: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            log.error("open failed: \(String(cString: sqlite3_errmsg(db)))")
            sqlite3_close(db)
            return false
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)

        // Skip cleanly if the entity table isn't there (e.g. a store SwiftData will
        // create fresh anyway) — CREATE INDEX would otherwise fail with no-such-table.
        guard tableExists("ZCLIPRECORD", db: db) else { return false }

        for sql in indexStatements where sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            log.error("index create failed: \(String(cString: sqlite3_errmsg(db)))")
            return false
        }
        log.info("history indexes ensured")
        return true
    }

    private static func tableExists(_ name: String, db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        // SQLITE_TRANSIENT: tell SQLite to copy the string; the default (STATIC)
        // would let it read freed memory after this scope.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, name, -1, transient)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
}
