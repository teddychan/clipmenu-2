import Testing
@testable import ClipMenu

// Pins the pure gate that decides CloudKit activation. iCloud sync is a paid
// Mac App Store feature (a one-time $9.99 purchase), so it turns on only in the
// sandboxed App Store build AND when the user enabled sync AND owns the unlock.
// The app itself is free in both builds — there is no whole-app access gate.
@Suite @MainActor struct PremiumGateTests {

    @Test func activatesWhenAppStoreSyncOnAndPurchased() {
        #expect(AppStore.shouldActivateCloud(channelIsAppStore: true, syncEnabled: true, purchased: true))
    }

    @Test func offWhenNotPurchased() {
        #expect(!AppStore.shouldActivateCloud(channelIsAppStore: true, syncEnabled: true, purchased: false))
    }

    @Test func offWhenSyncDisabled() {
        #expect(!AppStore.shouldActivateCloud(channelIsAppStore: true, syncEnabled: false, purchased: true))
    }

    @Test func offOnDirectBuildEvenIfPurchased() {
        // Developer ID / direct build never gets iCloud (no StoreKit, no entitlement).
        #expect(!AppStore.shouldActivateCloud(channelIsAppStore: false, syncEnabled: true, purchased: true))
    }

    // Cloud-activation relaunch: when the unlock is purchased mid-session the launch-built
    // container is still local, so the app relaunches ONCE to rebuild it with CloudKit.
    @Test func relaunchesOnceWhenPurchasedButContainerStillLocal() {
        #expect(AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, purchased: true,
            cloudActive: false, alreadyRelaunched: false))
    }

    @Test func noRelaunchWhenCloudAlreadyActive() {
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, purchased: true,
            cloudActive: true, alreadyRelaunched: false))
    }

    @Test func noRelaunchLoopWhenAlreadyRelaunched() {
        // The guard that prevents a loop when CloudKit still can't come up (e.g. the
        // Production schema isn't deployed): once relaunched, never again this install.
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, purchased: true,
            cloudActive: false, alreadyRelaunched: true))
    }

    @Test func noRelaunchWhenNotEligible() {
        // Direct build, not purchased, or sync disabled — never relaunch.
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: false, syncEnabled: true, purchased: true,
            cloudActive: false, alreadyRelaunched: false))
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, purchased: false,
            cloudActive: false, alreadyRelaunched: false))
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: false, purchased: true,
            cloudActive: false, alreadyRelaunched: false))
    }
}
