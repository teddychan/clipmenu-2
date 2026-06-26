import Testing
@testable import ClipMenu

// Pins the pure gate that decides CloudKit activation. iCloud sync is free in every
// build and on by default, so CloudKit mirroring is requested whenever the user has
// sync enabled. When the build can't bring CloudKit up (no entitlement/profile, or
// offline), `AppStore.makeContainer` falls back to a local store at runtime — that's
// not part of this pure gate.
@Suite @MainActor struct CloudGateTests {

    @Test func activatesWhenSyncEnabled() {
        #expect(AppStore.shouldActivateCloud(syncEnabled: true))
    }

    @Test func offWhenSyncDisabled() {
        #expect(!AppStore.shouldActivateCloud(syncEnabled: false))
    }
}
