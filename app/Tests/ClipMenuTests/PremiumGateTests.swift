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

    // Cloud-deactivation relaunch (P1): the synchronous launch path trusts the
    // cached `iCloudUnlocked` bool to bring cloud up before StoreKit verifies it.
    // When the verified entitlement turns out NOT owned (tampered cache, refund,
    // revocation) but cloud is already active this launch, relaunch ONCE to tear
    // it back down to the local store.
    @Test func deactivatesWhenCloudActiveButNotOwned() {
        #expect(AppStore.shouldRelaunchForCloudDeactivation(
            channelIsAppStore: true, cloudActive: true, purchased: false))
    }

    @Test func noDeactivationWhenOwned() {
        // A real, verified purchase: leave cloud up.
        #expect(!AppStore.shouldRelaunchForCloudDeactivation(
            channelIsAppStore: true, cloudActive: true, purchased: true))
    }

    @Test func noDeactivationWhenCloudInactive() {
        // Nothing to tear down — the launch path never brought cloud up.
        #expect(!AppStore.shouldRelaunchForCloudDeactivation(
            channelIsAppStore: true, cloudActive: false, purchased: false))
    }

    @Test func noDeactivationOnDirectBuild() {
        // The direct build has no CloudKit at all.
        #expect(!AppStore.shouldRelaunchForCloudDeactivation(
            channelIsAppStore: false, cloudActive: true, purchased: false))
    }
}
