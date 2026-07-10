import Testing
import Foundation
import AppKit
import ApplicationServices
@testable import ClipMenu

// Characterization tests for the two self-managed NSWindowController-style hosts
// that DON'T sit on DragonKit: OnboardingWindowController and
// SnippetEditorWindowController, plus the OnboardingPermissions helper.
//
// What is reachable headlessly:
//   * OnboardingPermissions: initial state + start/stop lifecycle (a pure poll
//     task, no UI). requestAccessibility()/openAccessibilitySettings() are NOT
//     exercised — they fire a system prompt / open System Settings.
//   * OnboardingWindowController.windowWillClose(_:): the deliberate-vs-relaunch
//     completion contract (delegates to OnboardingGate + markComplete + onClosed).
//     Called directly with a dummy notification — no real window needed.
//   * SnippetEditorWindowController: the singleton and the isWindowVisible guard
//     (false before any show()).
//
// show() on either controller activates the app / makes a window key / flips the
// activation policy / touches the on-disk SwiftData container, so it needs a
// running NSApplication and is not exercised here — see COVERAGE NOTES.
@MainActor
@Suite(.serialized)
struct WindowControllersCoverageTests {

    // MARK: OnboardingPermissions

    @Test func permissionsInitialStateMatchesSystemTrust() {
        let permissions = OnboardingPermissions()
        #expect(permissions.accessibility == AXIsProcessTrusted())
    }

    @Test func permissionsStartAndStopAreIdempotent() {
        let permissions = OnboardingPermissions()
        // start() guards on a nil task, so a second start() is a no-op; stop()
        // must be safe whether or not a poll is running.
        permissions.start()
        permissions.start()
        permissions.stop()
        permissions.stop()
        // Re-start after stop must work again.
        permissions.start()
        permissions.stop()
    }

    // MARK: OnboardingWindowController — completion contract

    @Test func deliberateCloseMarksOnboardingComplete() {
        let completedKey = PreferenceKeys.onboardingCompleted
        let suppressKey = PreferenceKeys.suppressAlertForLoginItem
        let savedCompleted = UserDefaults.standard.object(forKey: completedKey)
        let savedSuppress = UserDefaults.standard.object(forKey: suppressKey)
        defer {
            restore(completedKey, savedCompleted)
            restore(suppressKey, savedSuppress)
        }

        UserDefaults.standard.set(false, forKey: completedKey)
        UserDefaults.standard.set(false, forKey: suppressKey)

        var closedCalled = false
        let controller = OnboardingWindowController(
            isTerminating: { false },
            onClosed: { closedCalled = true })

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        // Not terminating + not finished ⇒ treat as a deliberate close ⇒ mark
        // complete AND suppress the legacy login-item alert.
        #expect(UserDefaults.standard.bool(forKey: completedKey) == true)
        #expect(UserDefaults.standard.bool(forKey: suppressKey) == true)
        #expect(closedCalled)
    }

    @Test func relaunchCloseDoesNotMarkOnboardingComplete() {
        let completedKey = PreferenceKeys.onboardingCompleted
        let suppressKey = PreferenceKeys.suppressAlertForLoginItem
        let savedCompleted = UserDefaults.standard.object(forKey: completedKey)
        let savedSuppress = UserDefaults.standard.object(forKey: suppressKey)
        defer {
            restore(completedKey, savedCompleted)
            restore(suppressKey, savedSuppress)
        }

        UserDefaults.standard.set(false, forKey: completedKey)
        UserDefaults.standard.set(false, forKey: suppressKey)

        var closedCalled = false
        let controller = OnboardingWindowController(
            isTerminating: { true },   // app terminating for a relaunch
            onClosed: { closedCalled = true })

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        // Terminating ⇒ stay incomplete so the next launch resumes the wizard.
        #expect(UserDefaults.standard.bool(forKey: completedKey) == false)
        // onClosed still fires (it runs in a defer regardless of the outcome).
        #expect(closedCalled)
    }

    // MARK: SnippetEditorWindowController

    @Test func snippetEditorSharedIsAStableSingleton() {
        #expect(SnippetEditorWindowController.shared === SnippetEditorWindowController.shared)
    }

    @Test func snippetEditorIsNotVisibleBeforeShow() {
        // The window is lazily created in show(); until then isWindowVisible is
        // the `window?.isVisible ?? false` false branch.
        #expect(SnippetEditorWindowController.shared.isWindowVisible == false)
    }

    // MARK: helpers

    private func restore(_ key: String, _ value: Any?) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}
