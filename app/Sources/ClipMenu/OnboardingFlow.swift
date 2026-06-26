import Foundation

/// The first-run setup wizard's steps, in order. The same five steps run in both
/// builds; only the *content* of `.permissions` (and the auto-paste row in
/// `.features`) differs by `DistributionChannel`, so the step list itself is
/// build-independent. `rawValue` is the persisted resume index (`onboardingStep`).
enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome      // app intro + language picker
    case permissions  // build-aware: MAS reassurance / direct-build Accessibility
    case history      // items to keep, save-on-quit, store images
    case features     // launch at login, auto-paste (direct), global shortcuts
    case done         // "you're all set"
}

/// What the footer's primary button should do/say on a given step. Kept as a
/// pure decision (no `L()` here) so it's unit-testable; the view maps it to a
/// localized title.
enum OnboardingPrimaryAction: Sendable {
    case advance   // "Continue"
    case skip      // "Skip this step" (direct-build Accessibility, not yet granted)
    case finish    // "Open ClipMenu" (last step)
}

/// Pure, testable decisions for the wizard. No UI, no globals — every input is a
/// parameter, mirroring the `AppStore.shouldActivate…` gate style in `App.swift`.
enum OnboardingGate {
    /// Whether to present the wizard on launch.
    static func shouldShowOnLaunch(completed: Bool) -> Bool { !completed }

    /// Clamp a (possibly stale or out-of-range) persisted index back onto a real
    /// step, so a corrupted/old default can never crash the `switch`.
    static func resumeStep(savedIndex: Int) -> OnboardingStep {
        let last = OnboardingStep.allCases.count - 1
        return OnboardingStep(rawValue: min(max(0, savedIndex), last)) ?? .welcome
    }

    /// The make-or-break rule for resume-after-restart: mark the wizard complete
    /// only when the window closes *deliberately* (finish or red-X), never when
    /// the app is being terminated for a relaunch (e.g. a language change). On a
    /// relaunch `onboardingCompleted` stays false, so the next launch reopens on
    /// the saved step.
    static func shouldMarkCompleteOnClose(isTerminating: Bool, alreadyFinished: Bool) -> Bool {
        if isTerminating { return false }
        return !alreadyFinished
    }

    /// Primary-button action for `step`. The direct build's Accessibility step is
    /// non-blocking: the button reads "Skip" until the permission is granted, then
    /// "Continue" (matching Vorssaint). The MAS build has nothing to grant, so it
    /// always advances.
    static func primaryAction(
        step: OnboardingStep,
        channel: DistributionChannel,
        accessibilityGranted: Bool
    ) -> OnboardingPrimaryAction {
        if step == .done { return .finish }
        if step == .permissions, channel == .direct, !accessibilityGranted { return .skip }
        return .advance
    }
}
