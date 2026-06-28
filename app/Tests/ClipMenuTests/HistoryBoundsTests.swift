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
}
