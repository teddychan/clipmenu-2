import Testing
import AppKit
import Foundation
@testable import ClipMenu

// Characterization coverage for the @MainActor built-in effect functions
// (BuiltInActions.swift:30-43). Only the deterministically observable half — the
// copy-to-pasteboard step — is asserted; the subsequent Paster.paste() is
// disabled via the inputPasteCommand pref so no synthetic ⌘V / Accessibility
// prompt is attempted. remove(_:) / remove(snippet:) mutate the app-wide
// AppStore.container singleton (no injectable context) and are NOT covered here.
//
// Serialized: touches UserDefaults.standard and the shared NSPasteboard.general.
@Suite(.serialized) @MainActor struct BuiltInActionsEffectCoverageTests {

    private func withPasteDisabled(_ body: () -> Void) {
        let key = PreferenceKeys.inputPasteCommand
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)   // Paster.paste() no-ops
        defer { UserDefaults.standard.set(previous, forKey: key) }
        body()
    }

    @Test func pasteAsPlainTextCopiesClipStringToPasteboard() {
        withPasteDisabled {
            let clip = ClipRecord(typeIdentifiers: ["String"], stringValue: "plain value")
            BuiltInActions.pasteAsPlainText(clip)
            #expect(NSPasteboard.general.string(forType: .string) == "plain value")
        }
    }

    @Test func pasteAsPlainTextWithNilStringCopiesEmpty() {
        withPasteDisabled {
            let clip = ClipRecord(typeIdentifiers: ["String"], stringValue: nil)
            BuiltInActions.pasteAsPlainText(clip)
            #expect(NSPasteboard.general.string(forType: .string) == "")
        }
    }

    @Test func pasteAsPlainTextCopiesSnippetContent() {
        withPasteDisabled {
            let snippet = Snippet(title: "t", content: "snippet body")
            BuiltInActions.pasteAsPlainText(snippet: snippet)
            #expect(NSPasteboard.general.string(forType: .string) == "snippet body")
        }
    }

    @Test func pasteAsFilePathJoinsFilenamesOntoPasteboard() {
        withPasteDisabled {
            let clip = ClipRecord(typeIdentifiers: ["Filenames"],
                                  filenames: ["/a/one.txt", "/b/two.txt"])
            BuiltInActions.pasteAsFilePath(clip)
            #expect(NSPasteboard.general.string(forType: .string) == "/a/one.txt\n/b/two.txt")
        }
    }

    @Test func pasteAsFilePathWithNilFilenamesCopiesEmpty() {
        withPasteDisabled {
            let clip = ClipRecord(typeIdentifiers: ["Filenames"], filenames: nil)
            BuiltInActions.pasteAsFilePath(clip)
            #expect(NSPasteboard.general.string(forType: .string) == "")
        }
    }

    @Test func newLineConstantIsLineFeed() {
        #expect(BuiltInActions.newLine == "\n")
    }
}
