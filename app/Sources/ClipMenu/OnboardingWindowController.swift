import AppKit
import SwiftUI
import ApplicationServices

// Hosts the first-run setup wizard (`OnboardingView`) in a self-managed dark
// NSWindow, and owns the resume-after-relaunch contract. Modeled on Vorssaint's
// onboarding: keep the menu-bar agent's `.accessory` policy, just activate the
// app and bring the window to front; mark the wizard complete only on a
// *deliberate* close, never when the app is terminating for a relaunch.

/// Live Accessibility-permission state for the direct build's permission step.
/// Polled on a coalesced loop so "Not granted → Granted" flips on its own after
/// the user grants it in System Settings. Harmless (and unused) in the sandboxed
/// App Store build, which has no permission step.
@MainActor
final class OnboardingPermissions: ObservableObject {
    @Published private(set) var accessibility = AXIsProcessTrusted()
    private var pollTask: Task<Void, Never>?

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        if accessibility != trusted { accessibility = trusted }
    }

    /// Fire the system Accessibility prompt (adds ClipMenu to the list).
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Deep-link straight to the Accessibility pane in System Settings.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let permissions = OnboardingPermissions()
    /// Reads the app's terminating state, so a relaunch close doesn't mark complete.
    private let isTerminating: () -> Bool
    /// Called after the window closes, so the AppDelegate can drop its reference.
    private let onClosed: () -> Void

    private var finished = false
    /// Set when we ourselves trigger a relaunch (language change): the imminent
    /// window close must not count as completion, regardless of termination timing.
    private var suppressCompleteOnClose = false

    init(isTerminating: @escaping () -> Bool, onClosed: @escaping () -> Void) {
        self.isTerminating = isTerminating
        self.onClosed = onClosed
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: OnboardingView(
                permissions: permissions,
                onFinish: { [weak self] in self?.userFinished() },
                onLanguageChange: { [weak self] in self?.relaunchForLanguageChange() }))
            let newWindow = NSWindow(contentViewController: host)
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            newWindow.isReleasedWhenClosed = false
            newWindow.isRestorable = false
            newWindow.isMovableByWindowBackground = true
            newWindow.appearance = NSAppearance(named: .darkAqua)
            newWindow.backgroundColor = NSColor(red: 0x1b / 255, green: 0x1b / 255, blue: 0x1d / 255, alpha: 1)
            newWindow.setContentSize(NSSize(width: 560, height: 620))
            newWindow.center()
            newWindow.delegate = self
            window = newWindow
        }
        permissions.start()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Reached the end ("Open ClipMenu"): mark complete and close.
    private func userFinished() {
        guard !finished else { return }
        finished = true
        markComplete()
        window?.close()
    }

    /// Language picker changed: relaunch so `L()` re-resolves in the new language.
    /// The persisted `onboardingStep` makes the fresh launch resume on this step.
    private func relaunchForLanguageChange() {
        suppressCompleteOnClose = true
        AppRelaunch.relaunch()
    }

    func windowWillClose(_ notification: Notification) {
        permissions.stop()
        defer { onClosed() }
        if suppressCompleteOnClose { return }
        if OnboardingGate.shouldMarkCompleteOnClose(
            isTerminating: isTerminating(), alreadyFinished: finished) {
            markComplete()
        }
    }

    /// Persist completion. Also suppress the legacy login-item alert, which the
    /// wizard's "Launch at login" row now supersedes.
    private func markComplete() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: PreferenceKeys.onboardingCompleted)
        defaults.set(true, forKey: PreferenceKeys.suppressAlertForLoginItem)
    }
}
