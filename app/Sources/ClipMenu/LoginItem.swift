import ServiceManagement

// Launch-at-login via SMAppService. Replaces the legacy NMLoginItems /
// LSSharedFileList code (AppController.m:581-597,
// NMLoginItems.m) with the modern, sandbox-safe API (CLAUDE.md §8).

@MainActor
enum LoginItem {
    /// Whether the app is currently registered as a login item.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Register/unregister the app as a login item (legacy _toggleAddingToLoginItems,
    /// AppController.m:581-591).
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LoginItem: failed to set login-item state to \(enabled): \(error)")
        }
    }
}
