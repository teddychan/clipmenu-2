import Testing
import Foundation
import AppKit
import SwiftData
@testable import ClipMenu

// Characterization of ActionEngine.apply(_:to:) dispatch for both the ClipRecord
// and Snippet overloads (AppController.m:742-815). The side-effecting paste is
// driven WITHOUT a real ⌘V post: with PreferenceKeys.inputPasteCommand == false
// Paster.paste() no-ops, but Paster.copy(...) still writes NSPasteboard.general —
// so the observable effect of each dispatch branch is the pasteboard's string.
//
// Serialized + save/restore of UserDefaults.standard and NSPasteboard.general.
// The builtin `remove:` branch mutates the process-wide AppStore.container
// (not injectable) and would touch the real on-disk store, so it is left
// uncovered by design (see ActionEngineTests / BuiltInActionsTests for the
// pure/transform side).
@Suite(.serialized) @MainActor
struct ActionEngineApplyCoverageTests {

    // MARK: helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
            configurations: config)
    }

    private func setSentinel(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func pbString() -> String? { NSPasteboard.general.string(forType: .string) }

    /// Run `body` with inputPasteCommand forced off (paste() no-op) and the
    /// pasteboard string saved/restored.
    private func withPasteEnvironment(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let prevPaste = defaults.object(forKey: PreferenceKeys.inputPasteCommand)
        defaults.set(false, forKey: PreferenceKeys.inputPasteCommand)
        let pb = NSPasteboard.general
        let prevString = pb.string(forType: .string)
        defer {
            if let prevPaste { defaults.set(prevPaste, forKey: PreferenceKeys.inputPasteCommand) }
            else { defaults.removeObject(forKey: PreferenceKeys.inputPasteCommand) }
            pb.clearContents()
            if let prevString { pb.setString(prevString, forType: .string) }
        }
        try body()
    }

    // MARK: ClipRecord overload

    @Test func applyToClipEffectBranches() throws {
        try withPasteEnvironment {
            let container = try makeContainer()
            let ctx = ModelContext(container)

            // Paste as Plain Text: the clip's plain string lands on the pasteboard.
            let textClip = ClipRecord(typeIdentifiers: ["String"], stringValue: "hello", contentHash: 1)
            ctx.insert(textClip)
            setSentinel("BEFORE")
            ActionEngine.apply(.builtin("Paste as Plain Text", name: ActionStore.pasteAsPlainText),
                               to: textClip)
            #expect(pbString() == "hello")

            // Paste as File Path: filenames joined by newline.
            let fileClip = ClipRecord(typeIdentifiers: ["Filenames"],
                                      filenames: ["/a/b.txt", "/c/d.txt"], contentHash: 2)
            ctx.insert(fileClip)
            setSentinel("BEFORE")
            ActionEngine.apply(.builtin("Paste as File Path", name: ActionStore.pasteAsFilePath),
                               to: fileClip)
            #expect(pbString() == "/a/b.txt\n/c/d.txt")

            // JS action outcome (string): UPPERCASE.js uppercases clipText, and the
            // outcome is copied to the pasteboard.
            let jsClip = ClipRecord(typeIdentifiers: ["String"], stringValue: "hi", contentHash: 3)
            ctx.insert(jsClip)
            setSentinel("BEFORE")
            ActionEngine.apply(.javaScript("Case/UPPERCASE.js"), to: jsClip)
            #expect(pbString() == "HI")
        }
    }

    @Test func applyToClipNoOpBranches() throws {
        try withPasteEnvironment {
            let container = try makeContainer()
            let ctx = ModelContext(container)
            let clip = ClipRecord(typeIdentifiers: ["String"], stringValue: "keep", contentHash: 10)
            ctx.insert(clip)

            // Folder node (action == nil): not invocable, pasteboard untouched.
            setSentinel("S1")
            ActionEngine.apply(.folder("F", []), to: clip)
            #expect(pbString() == "S1")

            // Unknown builtin selector → default: break.
            setSentinel("S2")
            ActionEngine.apply(.builtin("Bogus", name: "bogus:"), to: clip)
            #expect(pbString() == "S2")

            // JS node with a nil path → guard let path returns early.
            setSentinel("S3")
            ActionEngine.apply(ActionNode(title: "noPath",
                                          action: ActionSpec(type: ActionStore.jsType, name: nil, path: nil),
                                          children: nil),
                               to: clip)
            #expect(pbString() == "S3")

            // JS action that doesn't exist → runDetailed throws, try? → nil → return.
            setSentinel("S4")
            ActionEngine.apply(.javaScript("Nope/DoesNotExist.js"), to: clip)
            #expect(pbString() == "S4")

            // Unknown action type → default: break.
            setSentinel("S5")
            ActionEngine.apply(ActionNode(title: "weird",
                                          action: ActionSpec(type: "weird", name: nil, path: nil),
                                          children: nil),
                               to: clip)
            #expect(pbString() == "S5")
        }
    }

    // MARK: Snippet overload

    @Test func applyToSnippetEffectBranches() throws {
        try withPasteEnvironment {
            let container = try makeContainer()
            let ctx = ModelContext(container)

            // Paste as Plain Text (snippet): the content lands on the pasteboard.
            let snippet = Snippet(title: "t", content: "snippet body", index: 0)
            ctx.insert(snippet)
            setSentinel("BEFORE")
            ActionEngine.apply(.builtin("Paste as Plain Text", name: ActionStore.pasteAsPlainText),
                               to: snippet)
            #expect(pbString() == "snippet body")

            // JS action outcome (string) over the snippet content.
            let jsSnippet = Snippet(title: "u", content: "abc", index: 1)
            ctx.insert(jsSnippet)
            setSentinel("BEFORE")
            ActionEngine.apply(.javaScript("Case/UPPERCASE.js"), to: jsSnippet)
            #expect(pbString() == "ABC")
        }
    }

    @Test func applyToSnippetNoOpBranches() throws {
        try withPasteEnvironment {
            let container = try makeContainer()
            let ctx = ModelContext(container)
            let snippet = Snippet(title: "t", content: "keep", index: 0)
            ctx.insert(snippet)

            // Folder node → not invocable.
            setSentinel("S1")
            ActionEngine.apply(.folder("F", []), to: snippet)
            #expect(pbString() == "S1")

            // The snippet overload has no pasteAsFilePath case → default: break.
            setSentinel("S2")
            ActionEngine.apply(.builtin("Paste as File Path", name: ActionStore.pasteAsFilePath),
                               to: snippet)
            #expect(pbString() == "S2")

            // Unknown builtin selector → default: break.
            setSentinel("S3")
            ActionEngine.apply(.builtin("Bogus", name: "bogus:"), to: snippet)
            #expect(pbString() == "S3")

            // JS node with nil path → early return.
            setSentinel("S4")
            ActionEngine.apply(ActionNode(title: "noPath",
                                          action: ActionSpec(type: ActionStore.jsType, name: nil, path: nil),
                                          children: nil),
                               to: snippet)
            #expect(pbString() == "S4")

            // Missing JS action → try? nil → return.
            setSentinel("S5")
            ActionEngine.apply(.javaScript("Nope/DoesNotExist.js"), to: snippet)
            #expect(pbString() == "S5")

            // Unknown action type → default: break.
            setSentinel("S6")
            ActionEngine.apply(ActionNode(title: "weird",
                                          action: ActionSpec(type: "weird", name: nil, path: nil),
                                          children: nil),
                               to: snippet)
            #expect(pbString() == "S6")
        }
    }
}
