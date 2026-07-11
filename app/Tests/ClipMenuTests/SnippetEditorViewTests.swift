import Testing
import SwiftUI
import SwiftData
import ViewInspector
import DragonKit
@testable import ClipMenu

// ViewInspector coverage for SnippetEditorView (issue #31): the 3-column snippet
// editor (folders / snippets / detail). SnippetEditorView drives its data through
// @Environment(\.modelContext) + @Query(sort: \Folder.index), so the view is
// hosted with an in-memory ModelContainer via ViewHosting so those dynamic
// properties resolve, then inspected.
//
// Deterministic-snapshot note: under ViewHosting, `@Query` DOES populate on the
// first render (folder rows appear), but `@State` mutated in `.onAppear`
// (selectedFolderID = first folder) is NOT reflected in the initial `inspect()`
// snapshot. So selection is always nil when inspected — the snippets/detail
// columns reliably render their empty states, and there is no external hook to
// set the selection @State. That fixes what is coverable (see coverage notes at
// the bottom of this file for what is not).
//
// Localized strings come from DragonKit's L(...); the tests call L(...) so they
// assert whatever the test bundle actually returns (the base English key here).

// MARK: - Hosted view-body coverage

@MainActor
@Suite(.serialized) struct SnippetEditorViewChromeTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// Runs `body` with the @AppStorage folder-sort key ("snippetEditor.folderSort")
    /// pinned to `raw`, restoring the previous value afterwards. SnippetEditorView
    /// reads this key via @AppStorage, so pinning it keeps hosted renders
    /// deterministic regardless of what a prior run or the real app left behind.
    private func withFolderSort(_ raw: Int, _ body: () throws -> Void) rethrows {
        let key = "snippetEditor.folderSort"
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(raw, forKey: key)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try body()
    }

    @Test func bodyIsThreeColumnHSplitView() throws {
        try withFolderSort(0) {
            let view = SnippetEditorView().modelContainer(try makeContainer())
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            let split = try view.inspect().find(ViewType.HSplitView.self)
            #expect(split.count == 3)
        }
    }

    @Test func columnHeadersRender() throws {
        try withFolderSort(0) {
            let view = SnippetEditorView().modelContainer(try makeContainer())
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            // Folders column header, snippets column header (no folder selected →
            // the "Snippets" fallback title), and the detail column header.
            #expect(throws: Never.self) { try view.inspect().find(text: L("Folders")) }
            #expect(throws: Never.self) { try view.inspect().find(text: L("Snippets")) }
            #expect(throws: Never.self) { try view.inspect().find(text: L("Snippet")) }
        }
    }

    @Test func emptyStatesRenderWhenNothingSelected() throws {
        try withFolderSort(0) {
            let view = SnippetEditorView().modelContainer(try makeContainer())
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            // ContentUnavailableView for both the snippets and detail columns.
            #expect(throws: Never.self) { try view.inspect().find(text: L("No Folder Selected")) }
            #expect(throws: Never.self) { try view.inspect().find(text: L("No Snippet Selected")) }
        }
    }

    @Test func footersExposeTheirButtons() throws {
        try withFolderSort(0) {
            let view = SnippetEditorView().modelContainer(try makeContainer())
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            // Folders footer, snippets footer, detail footer.
            #expect(throws: Never.self) { try view.inspect().find(button: L("New Folder")) }
            #expect(throws: Never.self) { try view.inspect().find(button: L("New Snippet")) }
            #expect(throws: Never.self) { try view.inspect().find(button: L("Import…")) }
            #expect(throws: Never.self) { try view.inspect().find(button: L("Export…")) }
            // "Delete" appears in both the folders and snippets footers.
            let deletes = try view.inspect().findAll(ViewType.Button.self).filter {
                (try? $0.labelView().text().string()) == L("Delete")
            }
            #expect(deletes.count >= 2)
        }
    }

    @Test func folderSortMenuListsEveryOptionLabel() throws {
        try withFolderSort(0) {
            let view = SnippetEditorView().modelContainer(try makeContainer())
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            // The folders column header hosts a sort Menu whose content is one
            // Button per SnippetSort case (sortLabel covers all three cases).
            #expect(throws: Never.self) { try view.inspect().find(ViewType.Menu.self) }
            #expect(throws: Never.self) { try view.inspect().find(text: L("Manual (drag)")) }
            #expect(throws: Never.self) { try view.inspect().find(text: L("Name (A → Z)")) }
            #expect(throws: Never.self) { try view.inspect().find(text: L("Name (Z → A)")) }
        }
    }

    @Test func folderSortPreferenceDrivesTheMenuLabel() throws {
        // folderSortRaw = 2 → .nameDescending: the sort Menu's own label (the
        // current selection) becomes "Name (Z → A)", exercising the folderSort
        // computed getter with a non-default raw value and the `option == current`
        // checkmark branch on a non-first option.
        try withFolderSort(2) {
            let view = SnippetEditorView().modelContainer(try makeContainer())
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            #expect(throws: Never.self) { try view.inspect().find(text: L("Name (Z → A)")) }
        }
    }

    @Test func folderRowsRenderTitlesFromQuery() throws {
        try withFolderSort(0) {
            let container = try makeContainer()
            container.mainContext.insert(Folder(title: "Alpha", index: 0))
            container.mainContext.insert(Folder(title: "Beta", index: 1))
            try container.mainContext.save()
            let view = SnippetEditorView().modelContainer(container)
            ViewHosting.host(view: view)
            defer { ViewHosting.expel() }
            // @Query populates → folderRow renders each folder's FolderNameField in
            // its non-editing (Text) branch.
            #expect(throws: Never.self) { try view.inspect().find(text: "Alpha") }
            #expect(throws: Never.self) { try view.inspect().find(text: "Beta") }
            // No row is in edit mode (editingFolderID is nil), so FolderNameField
            // shows Text, never its TextField branch.
            #expect((try? view.inspect().find(ViewType.TextField.self)) == nil)
        }
    }
}

// MARK: - SnippetRef (Transferable payload) round-trip

@MainActor
@Suite struct SnippetRefCodableTests {

    @Test func codableRoundTripPreservesPersistentID() throws {
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let snippet = Snippet(title: "x", content: "y", index: 0)
        container.mainContext.insert(snippet)
        try container.mainContext.save()

        let ref = SnippetRef(id: snippet.persistentModelID)
        let encoded = try JSONEncoder().encode(ref)
        let decoded = try JSONDecoder().decode(SnippetRef.self, from: encoded)
        #expect(decoded.id == ref.id)
    }
}
