import Testing
@testable import ClipMenu

// Pins the pure decisions behind the first-run setup wizard: launch gating, the
// resume-index clamp, the deliberate-vs-relaunch completion rule, and the
// primary-button action (which is the only place the build channel changes the
// flow's behavior).
@Suite struct OnboardingGateTests {

    @Test func showsOnlyUntilCompleted() {
        #expect(OnboardingGate.shouldShowOnLaunch(completed: false) == true)
        #expect(OnboardingGate.shouldShowOnLaunch(completed: true) == false)
    }

    @Test func resumeStepClampsToValidRange() {
        #expect(OnboardingGate.resumeStep(savedIndex: 0) == .welcome)
        #expect(OnboardingGate.resumeStep(savedIndex: 2) == .history)
        // Last real step is `.done`; anything beyond clamps to it.
        #expect(OnboardingGate.resumeStep(savedIndex: 99) == .done)
        // Negative / corrupt values clamp to the first step rather than crashing.
        #expect(OnboardingGate.resumeStep(savedIndex: -5) == .welcome)
    }

    @Test func marksCompleteOnlyOnDeliberateClose() {
        // Relaunch (e.g. language change): app is terminating → keep it incomplete
        // so the next launch resumes on the saved step.
        #expect(OnboardingGate.shouldMarkCompleteOnClose(isTerminating: true, alreadyFinished: false) == false)
        // Deliberate red-X close without finishing → treat as "skip": mark complete.
        #expect(OnboardingGate.shouldMarkCompleteOnClose(isTerminating: false, alreadyFinished: false) == true)
        // Already finished via the button → don't double-mark.
        #expect(OnboardingGate.shouldMarkCompleteOnClose(isTerminating: false, alreadyFinished: true) == false)
    }

    @Test func lastStepFinishesInEitherBuild() {
        for channel in [DistributionChannel.appStore, .direct] {
            #expect(OnboardingGate.primaryAction(step: .done, channel: channel, accessibilityGranted: false) == .finish)
        }
    }

    @Test func appStorePermissionStepAlwaysAdvances() {
        // The sandboxed build has nothing to grant — never a "Skip".
        #expect(OnboardingGate.primaryAction(step: .permissions, channel: .appStore, accessibilityGranted: false) == .advance)
    }

    @Test func directPermissionStepSkipsUntilGranted() {
        #expect(OnboardingGate.primaryAction(step: .permissions, channel: .direct, accessibilityGranted: false) == .skip)
        #expect(OnboardingGate.primaryAction(step: .permissions, channel: .direct, accessibilityGranted: true) == .advance)
    }

    @Test func nonPermissionStepsAdvance() {
        for step in [OnboardingStep.welcome, .history, .features] {
            #expect(OnboardingGate.primaryAction(step: step, channel: .direct, accessibilityGranted: false) == .advance)
        }
    }
}
