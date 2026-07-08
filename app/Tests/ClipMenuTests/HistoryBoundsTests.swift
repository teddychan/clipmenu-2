import Testing
import Foundation
import SwiftData
@testable import ClipMenu

// The single bounded-history fetch policy that the menu, the history search, and
// the Export… action all share (ClipStore.boundedHistoryDescriptor). Proving the
// cap here proves it for every caller: none of them can ever materialize more
// than `maxHistorySize` clips (CLAUDE.md §2/§4).
@Suite @MainActor
struct HistoryBoundsTests {
    private func inMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    @Test func maxHistorySizeDefaultsTo20() {
        let suite = "HistoryBoundsDefault-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(ClipStore.maxHistorySize(defaults) == 20)
    }

    @Test func boundedDescriptorReturnsNewestMaxHistorySize() throws {
        let context = try inMemoryContext()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0 ..< 5 {
            let date = base.addingTimeInterval(Double(i))
            context.insert(ClipRecord(createdDate: date, lastUsedDate: date,
                                      typeIdentifiers: ["String"], stringValue: "clip\(i)", contentHash: i))
        }
        try context.save()

        let suite = "HistoryBounds-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(3, forKey: PreferenceKeys.maxHistorySize)

        let clips = try context.fetch(ClipStore.boundedHistoryDescriptor(defaults))
        #expect(clips.count == 3)
        // Newest first, oldest two excluded.
        #expect(clips.map(\.contentHash) == [4, 3, 2])
    }

    // trim() deletes exactly what boundedHistoryDescriptor does NOT keep: the clips
    // past the cap, oldest first. Proving the overflow descriptor here proves the
    // on-disk history matches the in-view cap.
    @Test func trimOverflowDescriptorSelectsOldestBeyondCap() throws {
        let context = try inMemoryContext()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for i in 0 ..< 5 {
            let date = base.addingTimeInterval(Double(i))
            context.insert(ClipRecord(createdDate: date, lastUsedDate: date,
                                      typeIdentifiers: ["String"], stringValue: "clip\(i)", contentHash: i))
        }
        try context.save()

        let suite = "TrimOverflow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(3, forKey: PreferenceKeys.maxHistorySize)

        let overflow = try context.fetch(ClipStore.trimOverflowDescriptor(defaults))
        // The two oldest (hashes 0 and 1) are the overflow to drop.
        #expect(overflow.count == 2)
        #expect(Set(overflow.map(\.contentHash)) == [0, 1])
    }

    // Capturing the same content twice must not create a second row: the dedup
    // lookup bumps the existing clip instead (ClipsController.m:619-636).
    @Test func captureDeduplicatesByContentHash() async throws {
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let store = ClipStore(modelContainer: container)
        let snapshot = PasteboardSnapshot(
            typeNames: ["String"], stringValue: "hello", rtfData: nil, pdfData: nil,
            filenames: nil, urlString: nil, imageData: nil, contentHash: 42)

        await store.capture(snapshot)
        await store.capture(snapshot)   // identical → dedup, no second row

        let context = ModelContext(container)
        let count = try context.fetchCount(FetchDescriptor<ClipRecord>())
        #expect(count == 1)
    }
}
