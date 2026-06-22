import Foundation

/// User-visible product name, e.g. "ClipMenu 2".
///
/// The name tracks the app's major version. It is applied per-build to the
/// bundle's Info.plist (CFBundleDisplayName) by scripts/run.sh, which derives
/// it from CFBundleShortVersionString. Reading it back here keeps in-app text
/// (status-item tooltip, Settings window title) consistent with whatever the
/// build named the app, without duplicating the version→name rule.
///
/// Falls back to CFBundleName, then a bare "ClipMenu", when run outside a
/// configured bundle (e.g. `swift run`).
enum AppInfo {
    static var displayName: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? "ClipMenu"
    }

    /// Marketing version, e.g. "2.2.1" (CFBundleShortVersionString).
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// Build number (CFBundleVersion).
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }

    /// "Version 2.2.1", or "Version 2.2.1 (123)" when the build differs from the
    /// marketing version. Shown in the About pane.
    static var versionDescription: String {
        build.isEmpty || build == version
            ? String(format: L("Version %@"), version)
            : String(format: L("Version %@ (%@)"), version, build)
    }

    /// Copyright line for the About pane. Mirrors LICENSE.
    static var copyright: String {
        "© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan"
    }
}
