import Foundation

/// How this build was distributed, which determines whether auto-paste is
/// possible. The Mac App Store requires App Sandbox, and a sandboxed process
/// cannot post synthetic key events into other apps (auto-paste) — so the
/// App Store build disables that feature. Developer ID / Homebrew builds are
/// not sandboxed and can auto-paste.
///
/// Detection is by sandbox presence rather than a baked-in build flag, so the
/// UI is tied to the actual capability with nothing extra to keep in sync.
enum DistributionChannel {
    case appStore   // sandboxed → auto-paste impossible
    case direct     // Developer ID / Homebrew → auto-paste works

    /// Pure decision from a process environment (injectable for tests).
    /// Sandboxed macOS apps always have `APP_SANDBOX_CONTAINER_ID` set.
    static func detect(environment: [String: String]) -> DistributionChannel {
        environment["APP_SANDBOX_CONTAINER_ID"] != nil ? .appStore : .direct
    }

    /// The channel of the running process.
    static var current: DistributionChannel {
        detect(environment: ProcessInfo.processInfo.environment)
    }
}
