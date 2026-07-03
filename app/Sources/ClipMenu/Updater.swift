import Foundation

#if SPARKLE
import DragonKitUpdates
#endif

/// Channel-agnostic facade over DragonKit's Sparkle wrapper, so UI code and the
/// app delegate compile in **both** builds with no `#if` scattered through them.
/// In the Sparkle/direct build these forward to a shared `DragonUpdater` (which
/// also backs the Updates settings pane); in the Mac App Store build — where
/// DragonKitUpdates/Sparkle are not linked at all — they are inert.
@MainActor
enum UpdaterUI {
    #if SPARKLE
    /// The app's single updater instance. `UpdatesSettingsPane` binds its
    /// auto-check/auto-download toggles; the menu-bar "Check for updates…" item
    /// goes through `checkNow()`.
    static let updater = DragonUpdater()
    #endif

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
    /// `DragonUpdater` creates Sparkle's `SPUStandardUpdaterController` lazily on
    /// first use, so touch it here to begin the scheduled-check timer.
    static func start() {
        #if SPARKLE
        _ = updater.canCheckForUpdates
        #endif
    }

    /// The user's "automatically check for updates" preference. Sparkle persists
    /// this itself (SUEnableAutomaticChecks), so it is the single source of truth.
    /// No-op getter/setter when unsupported.
    static var automaticallyChecksForUpdates: Bool {
        get {
            #if SPARKLE
            return updater.automaticallyChecksForUpdates
            #else
            return false
            #endif
        }
        set {
            #if SPARKLE
            updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    /// Manual "Check Now" (menu bar item): shows Sparkle's standard UI.
    static func checkNow() {
        #if SPARKLE
        updater.checkForUpdates()
        #endif
    }
}
