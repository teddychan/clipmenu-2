import Testing
import Foundation
import SwiftData
@testable import ClipMenu

// While a history menu is open, the capture pipeline keeps running and
// ClipStore.trim() can delete the oldest row from a sibling context. Clicking
// that menu item must not paste from (or fault) a deleted model — the click
// re-resolves the record against the store first.

@Suite @MainActor
struct LiveClipResolutionTests {

    @Test func resolvesExistingClipAndRejectsDeletedOne() throws {
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let menuContext = ModelContext(container)

        let clip = ClipRecord(typeIdentifiers: ["String"], stringValue: "hello", contentHash: 1)
        menuContext.insert(clip)
        try menuContext.save()

        // Still in the store → resolves.
        #expect(MainMenuController.liveClip(matching: clip, in: menuContext) != nil)

        // A sibling context (the ClipStore actor's, in production) trims the row.
        let trimContext = ModelContext(container)
        let all = try trimContext.fetch(FetchDescriptor<ClipRecord>())
        for record in all { trimContext.delete(record) }
        try trimContext.save()

        // The menu's stale reference must no longer resolve.
        #expect(MainMenuController.liveClip(matching: clip, in: menuContext) == nil)
    }
}
