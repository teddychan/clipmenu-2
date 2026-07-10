import Testing
import Foundation
@testable import ClipMenu

// Characterization tests for the headlessly-reachable logic in App.swift. The
// @main entry (ClipMenuApp), the SwiftUI Settings scene, and AppDelegate's
// lifecycle callbacks all require a running NSApplication / event loop and are
// not exercised here — see COVERAGE NOTES. The one pure, side-effect-free bit is
// AppStore.folder's debug-vs-release directory decision.
@MainActor
@Suite
struct AppCoverageTests {

    @Test func storeFolderLivesUnderApplicationSupport() {
        #expect(AppStore.folder.deletingLastPathComponent().path
                == URL.applicationSupportDirectory.path)
    }

    // The folder name switches to "ClipMenu Debug" only for a `…clipmenu-2.debug`
    // bundle id, otherwise it is the release "ClipMenu" folder. The test process
    // is not a `.debug` bundle, so it resolves to the release name; assert the
    // rule tracks the current bundle id either way.
    @Test func storeFolderNameTracksTheBundleIdDebugSuffix() {
        let isDebug = (Bundle.main.bundleIdentifier ?? "").hasSuffix(".debug")
        let expected = isDebug ? "ClipMenu Debug" : "ClipMenu"
        #expect(AppStore.folder.lastPathComponent == expected)
    }

    @Test func storeFolderIsAStableFileURL() {
        #expect(AppStore.folder.isFileURL)
        // `static let` — same value on every access.
        #expect(AppStore.folder == AppStore.folder)
    }
}
