import Testing
import Foundation
import SwiftData
@testable import ClipMenu

// Verifies the SwiftData half of snippet-editor undo (PARITY §G row 138): a
// context with an UndoManager registers model changes and reverts them on
// undo()/redo(). This does NOT exercise the ⌘Z / Edit-menu responder routing
// (GUI-only); SnippetEditorWindowController.windowWillReturnUndoManager hands
// this same manager to the window.

@MainActor
@Suite struct SnippetUndoTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, configurations: config)
        let context = ModelContext(container)
        let undo = UndoManager()
        undo.groupsByEvent = false   // no run loop in tests; group manually
        context.undoManager = undo
        return context
    }

    @Test func undoRevertsFolderInsertAndRedoRestoresIt() throws {
        let context = try makeContext()
        let undo = try #require(context.undoManager)

        undo.beginUndoGrouping()
        context.insert(Folder(title: "Greetings", index: 0))
        context.processPendingChanges()
        undo.endUndoGrouping()

        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == 1)

        undo.undo()
        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == 0)

        undo.redo()
        #expect(try context.fetchCount(FetchDescriptor<Folder>()) == 1)
    }

    @Test func undoRevertsTitleEdit() throws {
        let context = try makeContext()
        let undo = try #require(context.undoManager)

        let folder = Folder(title: "Old", index: 0)
        context.insert(folder)
        context.processPendingChanges()

        undo.beginUndoGrouping()
        folder.title = "New"
        context.processPendingChanges()
        undo.endUndoGrouping()

        #expect(folder.title == "New")
        undo.undo()
        #expect(folder.title == "Old")
    }
}
