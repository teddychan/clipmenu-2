import Testing
import Foundation
import SwiftData
@testable import ClipMenu

@Suite struct SnippetSnapshotTests {

    private func sample() -> SnippetSnapshot {
        SnippetSnapshot(
            schemaVersion: SnippetSnapshot.currentSchemaVersion,
            folders: [
                .init(title: "Greetings", index: 0, snippetSortRaw: 0, isExpanded: true,
                      snippets: [
                          .init(title: "Hi", content: "Hello", index: 0),
                          .init(title: "Bye", content: "Goodbye", index: 1),
                      ]),
            ],
            orphanSnippets: [])
    }

    @Test func hashIsStableAcrossInputOrder() {
        let a = sample()
        var b = sample()
        b.folders[0].snippets.reverse()
        #expect(a.contentHash == b.contentHash)
    }

    @Test func reorderingIndicesChangesHash() {
        let a = sample()
        var b = sample()
        b.folders[0].snippets[0].index = 5
        #expect(a.contentHash != b.contentHash)
    }

    @Test func contentEditChangesHash() {
        let a = sample()
        var b = sample()
        b.folders[0].snippets[0].content = "Hello!"
        #expect(a.contentHash != b.contentHash)
    }

    @Test func canonicalRoundTrips() throws {
        let a = sample()
        let data = a.canonicalPayload()
        let decoded = try SnippetSnapshot.decode(data)
        #expect(decoded == a)
    }

    @Test func emptyAndOrphanHashing() {
        let empty = SnippetSnapshot(schemaVersion: 1, folders: [], orphanSnippets: [])
        #expect(empty.contentHash == SnippetSnapshot(schemaVersion: 1, folders: [], orphanSnippets: []).contentHash)
        let withOrphan = SnippetSnapshot(
            schemaVersion: 1, folders: [],
            orphanSnippets: [.init(title: "loose", content: "x", index: 0)])
        #expect(empty.contentHash != withOrphan.contentHash)
    }

    @MainActor
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, configurations: config)
        return ModelContext(container)
    }

    @MainActor @Test func captureThenApplyRoundTrips() throws {
        let context = try makeContext()
        let folder = Folder(title: "Greetings", index: 0)
        context.insert(folder)
        context.insert(Snippet(title: "Hi", content: "Hello", index: 0, folder: folder))
        context.insert(Snippet(title: "Bye", content: "Goodbye", index: 1, folder: folder))
        try context.save()

        let snap = try SnippetSnapshot.capture(from: context)
        #expect(snap.folderCount == 1)
        #expect(snap.snippetCount == 2)

        let fresh = try makeContext()
        try SnippetSnapshot.apply(snap, to: fresh)
        try fresh.save()
        let recaptured = try SnippetSnapshot.capture(from: fresh)
        #expect(recaptured.contentHash == snap.contentHash)
    }

    @MainActor @Test func applyReplacesExistingData() throws {
        let context = try makeContext()
        let old = Folder(title: "Old", index: 0)
        context.insert(old)
        context.insert(Snippet(title: "x", content: "x", index: 0, folder: old))
        try context.save()

        let replacement = SnippetSnapshot(
            schemaVersion: SnippetSnapshot.currentSchemaVersion,
            folders: [.init(title: "New", index: 0, snippetSortRaw: 0, isExpanded: true,
                            snippets: [.init(title: "y", content: "y", index: 0)])],
            orphanSnippets: [])
        try SnippetSnapshot.apply(replacement, to: context)
        try context.save()

        let folders = try context.fetch(FetchDescriptor<Folder>())
        #expect(folders.count == 1)
        #expect(folders.first?.title == "New")
        let snippets = try context.fetch(FetchDescriptor<Snippet>())
        #expect(snippets.count == 1)
        #expect(snippets.first?.content == "y")
    }
}
