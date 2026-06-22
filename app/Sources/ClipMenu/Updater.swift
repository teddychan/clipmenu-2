import Foundation

#if SPARKLE
import Sparkle

/// Owns Sparkle's updater for the direct / Developer ID build. Compiled in only
/// when the `SPARKLE` flag is set (see Package.swift) — the Mac App Store build
/// never contains a self-updater, because the App Store delivers its updates and
/// its sandbox forbids one.
///
/// `SPUStandardUpdaterController` gives the standard Sparkle experience for free:
/// scheduled background checks, the "A new version is available" window with
/// release notes, download with progress, and **Install and Relaunch**. We only
/// surface a thin slice to the rest of the app via `UpdaterUI`.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true → Sparkle reads SUFeedURL / SUPublicEDKey from
        // Info.plist and begins its scheduled-check timer immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// The user's "automatically check for updates" preference. Sparkle persists
    /// this itself (SUEnableAutomaticChecks), so it is the single source of truth —
    /// we deliberately do not mirror it into a second UserDefaults key.
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Manual "Check Now": shows Sparkle's UI immediately (progress, then either
    /// "you're up to date" or the update prompt).
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
#endif

/// Channel-agnostic facade over the updater, so UI code (the General pane) and the
/// app delegate compile in **both** builds with no `#if` scattered through them.
/// In the Sparkle/direct build these forward to `UpdaterController`; in the Mac
/// App Store build they are inert.
@MainActor
enum UpdaterUI {
    /// Whether in-app updates exist in this build. True only when Sparkle is
    /// compiled in (the direct / Developer ID build); the Mac App Store build
    /// returns false and shows no update UI.
    static var isSupported: Bool {
        #if SPARKLE
        return true
        #else
        return false
        #endif
    }

    /// Start the updater (scheduled background checks). Call once at launch.
    static func start() {
        #if SPARKLE
        _ = UpdaterController.shared
        #endif
    }

    /// Bound to the General-pane toggle. No-op getter/setter when unsupported.
    static var automaticallyChecksForUpdates: Bool {
        get {
            #if SPARKLE
            return UpdaterController.shared.automaticallyChecksForUpdates
            #else
            return false
            #endif
        }
        set {
            #if SPARKLE
            UpdaterController.shared.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    /// Manual "Check Now" from the General pane.
    static func checkNow() {
        #if SPARKLE
        UpdaterController.shared.checkForUpdates()
        #endif
    }
}
