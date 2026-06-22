import Testing
import Foundation
import SwiftData
@testable import ClipMenu

@Suite @MainActor
struct StoreMigrationTests {
    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func foldersAndSnippetsRoundTrip() throws {
        let source = try inMemoryContext()
        let folder = Folder(title: "Greetings", index: 0)
        source.insert(folder)
        source.insert(Snippet(title: "Hi", content: "Hello", index: 0, folder: folder))
        source.insert(Snippet(title: "Bye", content: "Goodbye", index: 1, folder: folder))
        try source.save()

        let folders = try StoreMigration.extractFolders(from: source)
        let orphans = try StoreMigration.extractOrphanSnippets(from: source)

        let dest = try inMemoryContext()
        StoreMigration.insert(folders: folders, orphanSnippets: orphans, into: dest)
        try dest.save()

        let copied = try dest.fetch(FetchDescriptor<Folder>())
        #expect(copied.count == 1)
        #expect(copied[0].title == "Greetings")
        #expect((copied[0].snippets ?? []).count == 2)
        #expect(Set((copied[0].snippets ?? []).map(\.content)) == ["Hello", "Goodbye"])
    }

    @Test func orphanSnippetsRoundTrip() throws {
        let source = try inMemoryContext()
        source.insert(Snippet(title: "Loose", content: "no folder", index: 0, folder: nil))
        try source.save()

        let orphans = try StoreMigration.extractOrphanSnippets(from: source)
        #expect(orphans.count == 1)

        let dest = try inMemoryContext()
        StoreMigration.insert(folders: [], orphanSnippets: orphans, into: dest)
        try dest.save()

        let copied = try dest.fetch(FetchDescriptor<Snippet>())
        #expect(copied.count == 1)
        #expect(copied[0].content == "no folder")
        #expect(copied[0].folder == nil)
    }

    @Test func clipsRoundTripIncludingImage() throws {
        let source = try inMemoryContext()
        let imageBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        source.insert(ClipRecord(typeIdentifiers: ["public.utf8-plain-text"], stringValue: "copied text", contentHash: 42))
        source.insert(ClipRecord(typeIdentifiers: ["public.tiff"], image: ClipImage(data: imageBytes),
                                 thumbnailData: Data([0x01]), contentHash: 7))
        try source.save()

        let clips = try StoreMigration.extractClips(from: source)
        let dest = try inMemoryContext()
        StoreMigration.insert(clips: clips, into: dest)
        try dest.save()

        let copied = try dest.fetch(FetchDescriptor<ClipRecord>())
        #expect(copied.count == 2)
        let withImage = copied.first { $0.contentHash == 7 }
        #expect(withImage?.image?.data == imageBytes)
        #expect(withImage?.thumbnailData == Data([0x01]))
        let textClip = copied.first { $0.contentHash == 42 }
        #expect(textClip?.stringValue == "copied text")
    }

    // Fix 4: orchestrator end-to-end test with flag semantics.
    @Test func migrateIfNeededCopiesAndIsIdempotent() throws {
        let tempDir = URL.temporaryDirectory.appending(path: "StoreMigrationTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let oldStoreURL = tempDir.appending(path: "ClipMenu.store")

        // Build a legacy combined store on disk.
        do {
            let legacy = try ModelContainer(
                for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
                configurations: ModelConfiguration(schema: Schema([Folder.self, Snippet.self, ClipRecord.self, ClipImage.self]),
                                                   url: oldStoreURL, cloudKitDatabase: .none))
            let ctx = ModelContext(legacy)
            let f = Folder(title: "F", index: 0)
            ctx.insert(f)
            ctx.insert(Snippet(title: "S", content: "body", index: 0, folder: f))
            ctx.insert(ClipRecord(typeIdentifiers: ["public.utf8-plain-text"], stringValue: "clip", contentHash: 1))
            try ctx.save()
        }

        let suite = "StoreMigrationOrchestrator-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let dest = try inMemoryContext()
        StoreMigration.migrateIfNeeded(defaults: defaults, oldStoreURL: oldStoreURL, into: dest)

        #expect(defaults.bool(forKey: StoreMigration.flagKey) == true)
        #expect(try dest.fetch(FetchDescriptor<Folder>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<Snippet>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<ClipRecord>()).count == 1)

        // Idempotent: second run does nothing (flag already set).
        StoreMigration.migrateIfNeeded(defaults: defaults, oldStoreURL: oldStoreURL, into: dest)
        #expect(try dest.fetch(FetchDescriptor<Folder>()).count == 1)
    }

    // Migration commits incrementally (folders first, then clips in batches)
    // and retries on the next launch if any step fails. A retry must not
    // re-insert entities a previous partial run already committed.
    @Test func retryAfterPartialFailureDoesNotDuplicate() throws {
        let tempDir = URL.temporaryDirectory.appending(path: "MigrationRetryTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let oldStoreURL = tempDir.appending(path: "ClipMenu.store")

        // Legacy combined store: one folder with a snippet, one orphan, two clips.
        do {
            let legacy = try ModelContainer(
                for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
                configurations: ModelConfiguration(schema: Schema([Folder.self, Snippet.self, ClipRecord.self, ClipImage.self]),
                                                   url: oldStoreURL, cloudKitDatabase: .none))
            let ctx = ModelContext(legacy)
            let f = Folder(title: "F", index: 0)
            ctx.insert(f)
            ctx.insert(Snippet(title: "S", content: "body", index: 0, folder: f))
            ctx.insert(Snippet(title: "Loose", content: "orphan", index: 0, folder: nil))
            ctx.insert(ClipRecord(typeIdentifiers: ["String"], stringValue: "one", contentHash: 1))
            ctx.insert(ClipRecord(typeIdentifiers: ["String"], stringValue: "two", contentHash: 2))
            try ctx.save()
        }

        // Destination simulates a previous run that failed mid-way: the folder,
        // the orphan, and the first clip batch were already committed.
        let dest = try inMemoryContext()
        let committedFolder = Folder(title: "F", index: 0)
        dest.insert(committedFolder)
        dest.insert(Snippet(title: "S", content: "body", index: 0, folder: committedFolder))
        dest.insert(Snippet(title: "Loose", content: "orphan", index: 0, folder: nil))
        dest.insert(ClipRecord(typeIdentifiers: ["String"], stringValue: "one", contentHash: 1))
        try dest.save()

        let suite = "MigrationRetry-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)   // flag unset → retry runs

        StoreMigration.migrateIfNeeded(defaults: defaults, oldStoreURL: oldStoreURL, into: dest)

        #expect(defaults.bool(forKey: StoreMigration.flagKey) == true)
        #expect(try dest.fetch(FetchDescriptor<Folder>()).count == 1)
        #expect(try dest.fetch(FetchDescriptor<Snippet>()).count == 2)
        let clips = try dest.fetch(FetchDescriptor<ClipRecord>())
        #expect(clips.count == 2)
        #expect(Set(clips.map(\.contentHash)) == [1, 2])
    }

    // The pre-2.3 combined store is kept as a migration backup, but explicit
    // history deletion (Clear History, save-history-on-quit OFF) must purge it
    // too — otherwise cleared clips stay readable on disk forever. The backup
    // is only removed after a completed migration.
    @Test func legacyBackupIsDeletedOnlyAfterMigration() throws {
        let tempDir = URL.temporaryDirectory.appending(path: "LegacyBackupTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fm = FileManager.default
        func plantBackupFiles() throws {
            for name in ["ClipMenu.store", "ClipMenu.store-wal", "ClipMenu.store-shm"] {
                try Data([0x01]).write(to: tempDir.appending(path: name))
            }
            try fm.createDirectory(at: tempDir.appending(path: ".ClipMenu.store_SUPPORT"),
                                   withIntermediateDirectories: true)
        }
        func backupExists() -> Bool {
            fm.fileExists(atPath: tempDir.appending(path: "ClipMenu.store").path)
        }

        let suite = "LegacyBackupDelete-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        // Migration not finished → the backup is the migration source; keep it.
        try plantBackupFiles()
        StoreMigration.deleteLegacyBackupIfMigrated(defaults: defaults, folder: tempDir)
        #expect(backupExists())

        // Migration done → explicit deletion removes every backup artifact.
        defaults.set(true, forKey: StoreMigration.flagKey)
        StoreMigration.deleteLegacyBackupIfMigrated(defaults: defaults, folder: tempDir)
        #expect(!backupExists())
        #expect(!fm.fileExists(atPath: tempDir.appending(path: "ClipMenu.store-wal").path))
        #expect(!fm.fileExists(atPath: tempDir.appending(path: "ClipMenu.store-shm").path))
        #expect(!fm.fileExists(atPath: tempDir.appending(path: ".ClipMenu.store_SUPPORT").path))
    }

    @Test func migrateIfNeededWithNoOldStoreJustSetsFlag() throws {
        let suite = "StoreMigrationNoStore-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let dest = try inMemoryContext()
        StoreMigration.migrateIfNeeded(
            defaults: defaults,
            oldStoreURL: URL.temporaryDirectory.appending(path: "does-not-exist-\(UUID().uuidString).store"),
            into: dest)
        #expect(defaults.bool(forKey: StoreMigration.flagKey) == true)
        #expect(try dest.fetch(FetchDescriptor<Folder>()).count == 0)
    }
}
