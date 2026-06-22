import Testing
@testable import ClipMenu

// Pins the auto-update facade's channel gating. Sparkle (auto-update) is compiled
// in only for the direct / Developer ID build, via the SPARKLE flag set when the
// manifest sees CLIPMENU_SPARKLE=1 (see Package.swift). The Mac App Store build
// must never contain a self-updater, so UpdaterUI.isSupported must track that flag
// exactly — not be accidentally hardcoded — and the unsupported build must be a
// safe no-op. The test target builds without the flag, so SPARKLE is undefined here.
@MainActor
@Suite struct UpdaterUITests {

    @Test func isSupportedTracksTheSparkleBuildFlag() {
        #if SPARKLE
        #expect(UpdaterUI.isSupported)
        #else
        #expect(!UpdaterUI.isSupported)
        #endif
    }

    // In a build without Sparkle (the Mac App Store build, and this test target),
    // the facade reports unsupported and every entry point is an inert no-op.
    @Test func unsupportedBuildIsInert() {
        #if !SPARKLE
        #expect(UpdaterUI.isSupported == false)
        #expect(UpdaterUI.automaticallyChecksForUpdates == false)
        UpdaterUI.start()       // must not crash or start an updater
        UpdaterUI.checkNow()    // must not crash or present any UI
        UpdaterUI.automaticallyChecksForUpdates = true   // setter is a no-op
        #expect(UpdaterUI.automaticallyChecksForUpdates == false)
        #endif
    }
}
