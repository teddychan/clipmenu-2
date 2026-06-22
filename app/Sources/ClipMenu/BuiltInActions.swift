import Foundation
import SwiftData

// The four built-in actions (PARITY §F; BuiltInActionController.m:175-234).
// The text transforms are pure and unit-tested; the effect functions perform
// the copy+paste (via Paster) or the store removal. Invocation from the Actions
// menu (§C41) and modifier-click behaviors (§E) is wired in a later batch.

enum BuiltInActions {
    static let newLine = "\n"   // constants.h:32 kNewLine

    // MARK: - Pure transforms (nonisolated; pinned by tests)

    /// Paste as Plain Text (185-201): the clip's plain string (snippets pass
    /// their content). Identity transform — the value is pasted as plain text.
    static func plainText(_ string: String) -> String { string }

    /// Paste as File Path (203-211): filenames joined by newline.
    static func filePath(filenames: [String]) -> String {
        filenames.joined(separator: newLine)
    }

    // NOTE: "Paste as HFS File Path" (213-234) is DROPPED (OPEN-QUESTIONS #11,
    // user decision 2026-05-31). It used CFURLCopyFileSystemPath(kCFURLHFSPathStyle),
    // which the modern SDK marks *unavailable* (Carbon File Manager removed), and
    // HFS colon-paths are extinct. "Paste as File Path" (POSIX) is retained.

    // MARK: - Effects (main actor)

    @MainActor static func pasteAsPlainText(_ clip: ClipRecord) {
        Paster.copy(string: plainText(clip.stringValue ?? ""))
        Paster.paste()
    }

    @MainActor static func pasteAsPlainText(snippet: Snippet) {
        Paster.copy(string: plainText(snippet.content))
        Paster.paste()
    }

    @MainActor static func pasteAsFilePath(_ clip: ClipRecord) {
        Paster.copy(string: filePath(filenames: clip.filenames ?? []))
        Paster.paste()
    }

    /// Remove a clip from history (BuiltInActionController.m:175-183).
    @MainActor static func remove(_ clip: ClipRecord) {
        let context = AppStore.container.mainContext
        context.delete(clip)
        try? context.save()
    }

    /// Remove a snippet (BuiltInActionController.m:175-183, snippet branch).
    @MainActor static func remove(snippet: Snippet) {
        let context = AppStore.container.mainContext
        context.delete(snippet)
        try? context.save()
    }
}
