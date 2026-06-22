import Testing
@testable import ClipMenu

// Pins the pure gate that decides CloudKit activation. iCloud sync is a paid
// Mac App Store feature (v2.6.0), so it turns on only in the sandboxed App Store
// build AND when the user enabled sync AND holds the subscription.
@Suite @MainActor struct PremiumGateTests {

    @Test func activatesWhenAppStoreSyncOnAndSubscribed() {
        #expect(AppStore.shouldActivateCloud(channelIsAppStore: true, syncEnabled: true, subscribed: true))
    }

    @Test func offWhenNotSubscribed() {
        #expect(!AppStore.shouldActivateCloud(channelIsAppStore: true, syncEnabled: true, subscribed: false))
    }

    @Test func offWhenSyncDisabled() {
        #expect(!AppStore.shouldActivateCloud(channelIsAppStore: true, syncEnabled: false, subscribed: true))
    }

    @Test func offOnDirectBuildEvenIfSubscribed() {
        // Developer ID / direct build never gets iCloud (no StoreKit, no entitlement).
        #expect(!AppStore.shouldActivateCloud(channelIsAppStore: false, syncEnabled: true, subscribed: true))
    }

    // App access: the Mac App Store build is a paid app (30-day trial → $9.99/yr,
    // subscription required); the Developer ID / direct build is always free.
    @Test func appStoreBuildNeedsSubscriptionForAccess() {
        #expect(AppStore.hasAppAccess(channelIsAppStore: true, subscribed: true))
        #expect(!AppStore.hasAppAccess(channelIsAppStore: true, subscribed: false))
    }

    @Test func directBuildAlwaysHasAccess() {
        #expect(AppStore.hasAppAccess(channelIsAppStore: false, subscribed: false))
        #expect(AppStore.hasAppAccess(channelIsAppStore: false, subscribed: true))
    }

    // Cloud-activation relaunch: when the trial is started mid-session the launch-built
    // container is still local, so the app relaunches ONCE to rebuild it with CloudKit.
    @Test func relaunchesOnceWhenSubscribedButContainerStillLocal() {
        #expect(AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, subscribed: true,
            cloudActive: false, alreadyRelaunched: false))
    }

    @Test func noRelaunchWhenCloudAlreadyActive() {
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, subscribed: true,
            cloudActive: true, alreadyRelaunched: false))
    }

    @Test func noRelaunchLoopWhenAlreadyRelaunched() {
        // The guard that prevents a loop when CloudKit still can't come up (e.g. the
        // Production schema isn't deployed): once relaunched, never again this install.
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, subscribed: true,
            cloudActive: false, alreadyRelaunched: true))
    }

    @Test func noRelaunchWhenNotEligible() {
        // Direct build, not subscribed, or sync disabled — never relaunch.
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: false, syncEnabled: true, subscribed: true,
            cloudActive: false, alreadyRelaunched: false))
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: true, subscribed: false,
            cloudActive: false, alreadyRelaunched: false))
        #expect(!AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: true, syncEnabled: false, subscribed: true,
            cloudActive: false, alreadyRelaunched: false))
    }
}
