import Testing
import Foundation
@testable import ClipMenu

// Characterization of LegacySnippetImport.runOnceIfNeeded()'s guard paths
// (SnippetsController.m:83-92). The full import mutates the process-wide
// AppStore.container and reads a hard-coded ~/Library/Application Support path —
// neither injectable — so this pins only the safe, deterministic guards: the
// once-only UserDefaults flag, and (when no legacy file is present) the
// early return that still stamps the flag.
//
// Serialized + save/restore of the didImportLegacySnippets flag.
@Suite(.serialized) @MainActor
struct LegacySnippetImportCoverageTests {

    private let flagKey = "didImportLegacySnippets"

    private func withSavedFlag(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let prev = defaults.object(forKey: flagKey)
        defer {
            if let prev { defaults.set(prev, forKey: flagKey) }
            else { defaults.removeObject(forKey: flagKey) }
        }
        try body()
    }

    @Test func alreadyImportedIsANoOpAndKeepsFlagSet() throws {
        try withSavedFlag {
            UserDefaults.standard.set(true, forKey: flagKey)
            // The flag guard returns before any file/store access.
            LegacySnippetImport.runOnceIfNeeded()
            #expect(UserDefaults.standard.bool(forKey: flagKey))
        }
    }

    @Test func runStampsFlagWhenNoLegacyFilePresent() throws {
        try withSavedFlag {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            let legacyURL = try #require(appSupport?.appendingPathComponent("ClipMenu/Snippets.xml"))

            // Only exercise the import entry point when there's nothing to import,
            // so the test never mutates the real snippet store.
            if !FileManager.default.fileExists(atPath: legacyURL.path) {
                UserDefaults.standard.set(false, forKey: flagKey)
                LegacySnippetImport.runOnceIfNeeded()
                // The `defer { set(true) }` stamps the flag on every return path.
                #expect(UserDefaults.standard.bool(forKey: flagKey))
            }
        }
    }
}
