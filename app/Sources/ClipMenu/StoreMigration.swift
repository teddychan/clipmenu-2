import Foundation
import SwiftData
import os

// One-time migration from the pre-2.3 combined ClipMenu.store into the split
// snippet/history stores (see App.swift `AppStore`). Snippets/history previously
// shared one store; CloudKit mirroring is per-store and each model belongs to one
// configuration, so each now lives in its own file. The combined store is read once
// with its full original schema and left untouched as a backup.

/// Sendable snapshot of a Snippet, decoupled from any ModelContext.
struct SnippetSeed: Sendable {
    var title: String
    var content: String
    var index: Int
}

/// Sendable snapshot of a Folder and its snippets.
struct FolderSeed: Sendable {
    var title: String
    var index: Int
    var snippets: [SnippetSeed]
}

/// Sendable snapshot of a ClipRecord (with the original image bytes inlined).
struct ClipSeed: Sendable {
    var createdDate: Date
    var lastUsedDate: Date
    var typeIdentifiers: [String]
    var stringValue: String?
    var rtfData: Data?
    var pdfData: Data?
    var filenames: [String]?
    var urlString: String?
    var imageData: Data?
    var thumbnailData: Data?
    var contentHash: Int
}

enum StoreMigration {
    static let flagKey = "didMigrateToSplitStores"
    private static let log = Logger(subsystem: "com.dragonapp.clipmenu-2", category: "migration")

    // MARK: Read

    static func extractFolders(from context: ModelContext) throws -> [FolderSeed] {
        let folders = try context.fetch(FetchDescriptor<Folder>(sortBy: [SortDescriptor(\.index)]))
        return folders.map { folder in
            FolderSeed(
                title: folder.title, index: folder.index,
                snippets: (folder.snippets ?? []).sorted { $0.index < $1.index }.map {
                    SnippetSeed(title: $0.title, content: $0.content, index: $0.index)
                })
        }
    }

    // Fix 2: predicate-based fetch to avoid double-fetch + lazy-relationship ambiguity.
    static func extractOrphanSnippets(from context: ModelContext) throws -> [SnippetSeed] {
        let descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.folder == nil },
            sortBy: [SortDescriptor(\.index)])
        return try context.fetch(descriptor)
            .map { SnippetSeed(title: $0.title, content: $0.content, index: $0.index) }
    }

    // Fix 1: sort by createdDate for deterministic order.
    static func extractClips(from context: ModelContext) throws -> [ClipSeed] {
        let clips = try context.fetch(FetchDescriptor<ClipRecord>(sortBy: [SortDescriptor(\.createdDate)]))
        return clips.map { clipSeed(from: $0) }
    }

    // Fix 3: shared helper to convert ClipRecord → ClipSeed (used by extractClips and copyClipsInBatches).
    static func clipSeed(from clip: ClipRecord) -> ClipSeed {
        ClipSeed(
            createdDate: clip.createdDate, lastUsedDate: clip.lastUsedDate,
            typeIdentifiers: clip.typeIdentifiers, stringValue: clip.stringValue,
            rtfData: clip.rtfData, pdfData: clip.pdfData, filenames: clip.filenames,
            urlString: clip.urlString, imageData: clip.image?.data,
            thumbnailData: clip.thumbnailData, contentHash: clip.contentHash)
    }

    // MARK: Write

    static func insert(folders: [FolderSeed], orphanSnippets: [SnippetSeed], into context: ModelContext) {
        for folderSeed in folders {
            let folder = Folder(title: folderSeed.title, index: folderSeed.index)
            context.insert(folder)
            for seed in folderSeed.snippets {
                context.insert(Snippet(title: seed.title, content: seed.content,
                                       index: seed.index, folder: folder))
            }
        }
        for seed in orphanSnippets {
            context.insert(Snippet(title: seed.title, content: seed.content,
                                   index: seed.index, folder: nil))
        }
    }

    static func insert(clips: [ClipSeed], into context: ModelContext) {
        for seed in clips {
            context.insert(ClipRecord(
                createdDate: seed.createdDate, lastUsedDate: seed.lastUsedDate,
                typeIdentifiers: seed.typeIdentifiers, stringValue: seed.stringValue,
                rtfData: seed.rtfData, pdfData: seed.pdfData, filenames: seed.filenames,
                urlString: seed.urlString, image: seed.imageData.map { ClipImage(data: $0) },
                thumbnailData: seed.thumbnailData, contentHash: seed.contentHash))
        }
    }

    // Fix 3: copy clips in bounded batches so image blobs don't all live in memory at once (CLAUDE.md §4).
    // Skips clips whose contentHash already exists in the destination, so a
    // retry after a partial failure doesn't duplicate already-copied batches.
    //
    // Only the newest `limit` clips are carried over (same order `trim()` keeps),
    // so the upgrade never copies the full legacy history — including its old
    // image/PDF blobs — onto disk just to have the first capture trim it away
    // (CLAUDE.md §2/§4). The oldest legacy rows are never even faulted.
    private static func copyClipsInBatches(from legacy: ModelContext,
                                           into context: ModelContext,
                                           limit: Int,
                                           batchSize: Int = 50) throws -> Int {
        guard limit > 0 else { return 0 }
        var existingHashes: Set<Int> = []
        do {
            var existing = FetchDescriptor<ClipRecord>()
            existing.propertiesToFetch = [\.contentHash]
            existingHashes = Set(try context.fetch(existing).map(\.contentHash))
        }

        var offset = 0
        var total = 0
        while offset < limit {
            let pageSize = min(batchSize, limit - offset)
            var descriptor = FetchDescriptor<ClipRecord>(sortBy: [ClipStore.sortDescriptor])
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = pageSize
            let batch = try legacy.fetch(descriptor)
            if batch.isEmpty { break }
            let fresh = batch.map(clipSeed(from:)).filter { !existingHashes.contains($0.contentHash) }
            if !fresh.isEmpty {
                insert(clips: fresh, into: context)
                try context.save()
                existingHashes.formUnion(fresh.map(\.contentHash))
            }
            total += fresh.count
            offset += batch.count
            if batch.count < pageSize { break }
        }
        return total
    }

    // MARK: Backup deletion

    /// Remove the pre-2.3 combined-store backup (and its SQLite sidecars /
    /// external-storage folder). Called from the explicit history-deletion
    /// paths — Clear History and save-history-on-quit OFF — because the backup
    /// holds the full pre-migration clip history in plaintext, and a user who
    /// clears their history expects it gone from disk. Only removed after a
    /// completed migration so an interrupted migration keeps its source.
    static func deleteLegacyBackupIfMigrated(defaults: UserDefaults = .standard, folder: URL) {
        guard defaults.bool(forKey: flagKey) else { return }
        let fm = FileManager.default
        for name in ["ClipMenu.store", "ClipMenu.store-wal", "ClipMenu.store-shm",
                     ".ClipMenu.store_SUPPORT"] {
            try? fm.removeItem(at: folder.appending(path: name))
        }
    }

    // MARK: Orchestrator

    /// Copies the old combined store into `context` (the split-store container's
    /// main context) exactly once. Sets `flagKey` on success or when there is
    /// nothing to migrate; leaves it unset on failure so a transient error retries.
    @MainActor
    static func migrateIfNeeded(defaults: UserDefaults = .standard,
                                oldStoreURL: URL,
                                into context: ModelContext) {
        guard !defaults.bool(forKey: flagKey) else { return }
        guard FileManager.default.fileExists(atPath: oldStoreURL.path) else {
            defaults.set(true, forKey: flagKey)   // fresh install: nothing to migrate
            return
        }
        do {
            let legacyConfig = ModelConfiguration(
                schema: Schema([Folder.self, Snippet.self, ClipRecord.self, ClipImage.self]),
                url: oldStoreURL, cloudKitDatabase: .none)
            let legacy = try ModelContainer(
                for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
                configurations: legacyConfig)
            let legacyContext = ModelContext(legacy)

            let folders = try extractFolders(from: legacyContext)
            let orphans = try extractOrphanSnippets(from: legacyContext)

            // Skip folders/orphans a previous partial run (or CloudKit sync)
            // already put in the destination, keyed by title+index — a retry
            // must not duplicate them. Wiping the destination instead would be
            // wrong: it can already hold CloudKit-synced snippets.
            let existingFolderKeys = Set(try context.fetch(FetchDescriptor<Folder>())
                .map { "\($0.index)|\($0.title)" })
            let existingOrphanKeys = Set(try context.fetch(
                FetchDescriptor<Snippet>(predicate: #Predicate { $0.folder == nil }))
                .map { "\($0.index)|\($0.title)" })
            let freshFolders = folders.filter { !existingFolderKeys.contains("\($0.index)|\($0.title)") }
            let freshOrphans = orphans.filter { !existingOrphanKeys.contains("\($0.index)|\($0.title)") }

            insert(folders: freshFolders, orphanSnippets: freshOrphans, into: context)
            try context.save()

            let clipCount = try copyClipsInBatches(
                from: legacyContext, into: context, limit: ClipStore.maxHistorySize(defaults))

            defaults.set(true, forKey: flagKey)
            log.info("Migrated \(folders.count) folders / \(clipCount) clips to split stores")
        } catch {
            log.error("Store migration failed: \(error.localizedDescription)")
        }
    }
}
