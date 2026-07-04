import AppKit
import SwiftUI
import DragonKit
#if SPARKLE
import DragonKitUpdates
#endif

// The Settings window, on DragonKit's shared shell.
//
// ClipMenu is an LSUIElement agent, so the SwiftUI `Settings` scene can't be
// opened programmatically; DragonKit's `DragonSettingsWindowController` owns a
// reliable self-managed window instead (flips the app to `.regular` while it's
// open so it can become key, back to `.accessory` on close). The pane list is
// data-driven (`SettingsPane` conformers → `SettingsShell`), selection is
// host-owned so menu items can open a specific pane ("About ClipMenu 2" →
// About; "Uninstall…" → Uninstall), and the root re-localizes live via
// `.dragonLocalized()` — mirroring dragon-kit's Example app wiring.

@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    /// Host-owned pane selection. Persisted so reopening Settings returns to the
    /// last-used pane; set before `show()` to land on a specific pane.
    @Observable
    final class Selection {
        var paneID: String? {
            didSet {
                if let paneID {
                    UserDefaults.standard.set(paneID, forKey: PreferenceKeys.settingsSelectedTab)
                }
            }
        }

        init() {
            paneID = UserDefaults.standard.string(forKey: PreferenceKeys.settingsSelectedTab) ?? "general"
        }
    }

    private let selection = Selection()

    private lazy var controller: DragonSettingsWindowController = {
        let controller = DragonSettingsWindowController(
            title: String(format: L("%@ Settings"), AppInfo.displayName),
            rootView: SettingsRoot(
                appName: AppInfo.displayName,
                panesBuilder: { [weak self] in self?.settingsPanes ?? [] },
                selection: selection
            )
            .modelContainer(AppStore.container)
        )
        // Selector-based observers (both notifications post on the main thread).
        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsWindowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: controller.window)
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageChanged(_:)),
            name: .dragonLanguageChanged, object: nil)
        return controller
    }()

    /// DragonKit's controller hands the activation policy back to `.accessory`
    /// when the window closes. If the Snippet editor (which also promotes the app
    /// to `.regular`) is still open, re-assert `.regular` so it keeps its Dock
    /// presence. Async so it runs after DragonKit's own willClose handler.
    @objc private func settingsWindowWillClose(_ notification: Notification) {
        Task { @MainActor in
            if SnippetEditorWindowController.shared.isWindowVisible {
                NSApp.setActivationPolicy(.regular)
            }
        }
    }

    /// The window title is AppKit-owned (not inside the SwiftUI tree), so
    /// re-title it when the language changes.
    @objc private func languageChanged(_ notification: Notification) {
        controller.window?.title = String(format: L("%@ Settings"), AppInfo.displayName)
    }

    /// The pane list, rebuilt whenever the language changes (so injected content
    /// like About / What's New re-localizes). Order = sidebar order.
    private var settingsPanes: [AnySettingsPane] {
        var panes: [AnySettingsPane] = [
            AnySettingsPane(GeneralPane()),
            AnySettingsPane(SyncBackupPane()),
            AnySettingsPane(MenuPane()),
            AnySettingsPane(TypePane()),
            AnySettingsPane(ActionPane()),
            AnySettingsPane(ShortcutsPane()),
        ]
        // The sandboxed App Store build can't use Accessibility (no auto-paste),
        // so it gets no Permissions pane — matching its onboarding.
        if DistributionChannel.current == .direct {
            panes.append(AnySettingsPane(PermissionsSettingsPane(
                permissions: [.accessibility(isRequired: false)])))
        }
        #if SPARKLE
        panes.append(AnySettingsPane(UpdatesSettingsPane(updater: UpdaterUI.updater)))
        #endif
        panes.append(AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewConfig.content)))
        panes.append(AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)))
        panes.append(AnySettingsPane(UninstallSettingsPane(config: uninstallConfig, onCancel: { [weak self] in
            self?.selection.paneID = "general"
        })))
        return panes
    }

    /// What uninstalling removes. The optional toggle (default off) covers the
    /// user's clipboard history + snippets (the whole Application Support folder);
    /// without it only support files (actions.plist, user scripts) and caches go.
    private var uninstallConfig: UninstallConfig {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dragonapp.clipmenu-2"
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return UninstallConfig(
            appName: MainMenuController.canonicalName,
            checklistItems: [
                L("The app and its login item"),
                L("All preferences and actions"),
                L("Caches and support files"),
            ],
            optionalDataToggle: (label: L("Also delete clipboard history and snippets"),
                                 paths: [AppStore.folder]),
            extraCleanupPaths: [
                AppStore.folder.appending(path: "actions.plist"),
                AppStore.folder.appending(path: "script"),
                library.appending(path: "Caches/\(bundleID)"),
                library.appending(path: "HTTPStorages/\(bundleID)"),
            ])
    }

    /// True while the Settings window is on screen.
    var isWindowVisible: Bool { controller.window?.isVisible ?? false }

    func show() {
        // A stale persisted selection (e.g. a pane this build doesn't have, like
        // Updates on the App Store channel) would render an empty detail pane.
        if !settingsPanes.contains(where: { $0.id == selection.paneID }) {
            selection.paneID = "general"
        }
        controller.show()
    }

    /// Open Settings directly on a specific pane (e.g. "about", "uninstall").
    func show(paneID: String) {
        selection.paneID = paneID
        show()
    }
}

/// Settings root wired to the host-owned selection. Observes `LocalizationManager`
/// and rebuilds the panes on a language change, then applies `.dragonLocalized()`
/// so the whole window switches language live — without a restart.
private struct SettingsRoot: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let appName: String
    let panesBuilder: () -> [AnySettingsPane]
    let selection: SettingsWindowController.Selection

    var body: some View {
        // This view observes only the language, so `panesBuilder()` re-runs on a
        // language change — not on every pane selection (SettingsPaneList's job).
        SettingsPaneList(appName: appName, panes: panesBuilder(), selection: selection)
            .dragonLocalized()
    }
}

/// Holds the (language-stable) pane list and binds selection, so switching panes
/// re-renders the sidebar/detail without rebuilding every pane.
private struct SettingsPaneList: View {
    let appName: String
    let panes: [AnySettingsPane]
    @Bindable var selection: SettingsWindowController.Selection

    var body: some View {
        SettingsShell(appName: appName, panes: panes, selection: $selection.paneID)
    }
}
