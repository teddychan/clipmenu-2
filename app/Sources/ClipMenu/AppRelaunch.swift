import AppKit
import os

/// Quits and reopens the app so a relaunch-only preference change (e.g. the UI
/// language, which `L()` resolves once at process start) takes effect.
///
/// Asks the workspace to launch a fresh instance of this same bundle, then
/// terminates the current one. We use `NSWorkspace.openApplication` rather than
/// spawning `/bin/sh … open`, because `Process`/`posix_spawn` is forbidden under
/// App Sandbox (Mac App Store). `createsNewApplicationInstance` forces a new
/// process even though one is already running; we terminate the old instance in
/// the completion handler so the menu-bar agent comes back cleanly.
///
/// Caveat: unlike the old shell helper (which waited for this process to exit
/// before re-opening), the two instances overlap briefly. Verify the global
/// hotkey still works after a language-change relaunch on a real (signed) build.
/// If the launch can't be requested we leave the app running rather than
/// quitting into nothing.
enum AppRelaunch {
    private static let log = Logger(subsystem: "com.dragonapp.clipmenu-2", category: "relaunch")

    @MainActor
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
            Task { @MainActor in
                if let error {
                    log.error("Relaunch failed to open new instance: \(error.localizedDescription)")
                    NSSound.beep()
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }
}
