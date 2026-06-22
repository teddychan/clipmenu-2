import Testing
@testable import ClipMenu

// Pins the App-Store-vs-direct decision. Sandboxed macOS apps always have
// APP_SANDBOX_CONTAINER_ID in their environment; direct/Developer ID builds
// do not. The decision is factored into a pure function so both branches are
// testable without an actual sandbox.
@Suite struct DistributionChannelTests {

    @Test func sandboxedEnvironmentIsAppStore() {
        let env = ["APP_SANDBOX_CONTAINER_ID": "ABCDE12345.com.dragonapp.clipmenu-2"]
        #expect(DistributionChannel.detect(environment: env) == .appStore)
    }

    @Test func nonSandboxedEnvironmentIsDirect() {
        #expect(DistributionChannel.detect(environment: [:]) == .direct)
    }
}
