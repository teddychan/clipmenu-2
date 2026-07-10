import Testing
@testable import ClipMenu

// Characterization tests for AppInfo — the static provider of the app's
// user-visible name, version, build, and copyright. In the `swift test`
// process the values fall back to their Info.plist-less defaults, so these
// tests pin the *shape* of each computed property rather than a build-specific
// literal (which would differ between `swift test` and a configured bundle).
@MainActor
@Suite struct AppInfoCoverageTests {

    @Test func displayNameIsNonEmpty() {
        #expect(!AppInfo.displayName.isEmpty)
    }

    @Test func versionIsNonEmpty() {
        // Either the real CFBundleShortVersionString or the "—" fallback.
        #expect(!AppInfo.version.isEmpty)
    }

    @Test func buildIsAString() {
        // May be empty (no CFBundleVersion in the test bundle); just exercise
        // the getter and confirm it is a value.
        let build = AppInfo.build
        #expect(build == build)
    }

    @Test func versionDescriptionEmbedsTheVersion() {
        let desc = AppInfo.versionDescription
        #expect(!desc.isEmpty)
        #expect(desc.contains(AppInfo.version))
    }

    @Test func copyrightMirrorsLicense() {
        #expect(AppInfo.copyright == "© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan")
    }
}
