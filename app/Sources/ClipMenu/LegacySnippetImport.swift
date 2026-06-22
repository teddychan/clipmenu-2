import Foundation
import SwiftData

// One-time best-effort import of a legacy snippets file on first launch (OQ#6;
// SnippetsController.m:83-92). The new SwiftData store is authoritative; if a
// `~/Library/Application Support/ClipMenu/Snippets.xml` is present and the store
// is still empty, import it via the same XML schema the editor uses (SnippetXML).
//
// Caveat: this parses the editor's <folders> export schema. The legacy app's
// Core Data XML *store* is a different on-disk format; if the file isn't the
// editor schema, SnippetXML.parse yields nothing and this is a safe no-op (the
// editor's Import… can still bring in any exported .xml — no data is stranded).

@MainActor
enum LegacySnippetImport {
    private static let didImportKey = "didImportLegacySnippets"

    /// Runs at most once (guarded by a UserDefaults flag), and only into an
    /// empty snippet store so it never clobbers user-created snippets.
    static func runOnceIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: didImportKey) else { return }
        defer { defaults.set(true, forKey: didImportKey) }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first
        guard let legacyURL = appSupport?
                .appendingPathComponent("ClipMenu/Snippets.xml"),
              FileManager.default.fileExists(atPath: legacyURL.path),
              let data = try? Data(contentsOf: legacyURL)
        else { return }

        let parsed = SnippetXML.parse(data)
        guard !parsed.isEmpty else { return }

        let context = AppStore.container.mainContext
        let existing = (try? context.fetchCount(FetchDescriptor<Folder>())) ?? 0
        guard existing == 0 else { return }

        for (folderIndex, parsedFolder) in parsed.enumerated() {
            let folder = Folder(title: parsedFolder.title, index: folderIndex)
            context.insert(folder)
            for (i, parsedSnippet) in parsedFolder.snippets.enumerated() {
                context.insert(Snippet(
                    title: parsedSnippet.title, content: parsedSnippet.content,
                    index: i, folder: folder))
            }
        }
        try? context.save()
    }
}
