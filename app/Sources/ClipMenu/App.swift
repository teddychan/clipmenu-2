import SwiftUI
import SwiftData
import AppKit

// App entry. Agent / menu-bar app: no Dock icon, no main window — only a
// status-bar item (AppKit) plus a SwiftUI Settings scene. LSUIElement is set
// in Resources/Info.plist for the bundled .app; at runtime we also force
// .accessory activation so `swift run` behaves as an agent.

@main
struct ClipMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        // Shared SwiftData store for snippets + clipboard history.
        .modelContainer(AppStore.container)
    }
}

/// Process-wide SwiftData container, shared by the SwiftUI scene and the AppKit
/// menu layer. Two configurations under one container: Snippets (`Folder`/`Snippet`)
/// in a CloudKit-mirrored store, History (`ClipRecord`/`ClipImage`) in a local store,
/// each in its own file. CloudKit activates only when the build carries iCloud
/// entitlements + an embedded provisioning profile; otherwise the cloud build attempt
/// throws and we fall back to a fully-local container so dev/unsigned builds run fine.
@MainActor
enum AppStore {
    /// Application Support directory holding the SwiftData stores. A local debug
    /// build (bundle id `…clipmenu-2.debug`, from scripts/run-debug.sh) uses a
    /// SEPARATE "ClipMenu Debug" folder so it never reads, pollutes, or (on
    /// Uninstall) deletes the installed release's clipboard history + snippets.
    static let folder: URL = {
        let isDebug = (Bundle.main.bundleIdentifier ?? "").hasSuffix(".debug")
        return URL.applicationSupportDirectory.appending(
            path: isDebug ? "ClipMenu Debug" : "ClipMenu", directoryHint: .isDirectory)
    }()

    static let container: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let folder = Self.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snippetsURL = folder.appending(path: "ClipMenu-Snippets.store")
        let historyURL = folder.appending(path: "ClipMenu-History.store")

        let snippetSchema = Schema([Folder.self, Snippet.self])
        let historySchema = Schema([ClipRecord.self, ClipImage.self])

        // Both stores are local. Snippets are protected by folder-based backups
        // (FolderBackupStore + the Sync/Backup pane), not CloudKit mirroring;
        // history is a regenerable cache.
        func make() throws -> ModelContainer {
            let snippetsConfig = ModelConfiguration(
                "Snippets", schema: snippetSchema, url: snippetsURL, cloudKitDatabase: .none)
            let historyConfig = ModelConfiguration(
                "History", schema: historySchema, url: historyURL, cloudKitDatabase: .none)
            return try ModelContainer(
                for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
                configurations: snippetsConfig, historyConfig)
        }

        do {
            return try make()
        } catch {
            // The split stores are regenerable (snippets restore from a backup,
            // history is a cache). If the on-disk schema is incompatible, reset ONLY
            // the new files — never the old combined ClipMenu.store (migration backup).
            NSLog("ClipMenu: resetting incompatible split stores (\(error))")
            for base in ["ClipMenu-Snippets.store", "ClipMenu-History.store"] {
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(at: folder.appending(path: base + suffix))
                }
            }
            do { return try make() }
            catch { fatalError("Failed to create ModelContainer: \(error)") }
        }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItemController = StatusItemController()
    private let mainMenuController = MainMenuController.shared
    private let pasteboardMonitor = PasteboardMonitor()
    private var clipStore: ClipStore?
    private var servicesStarted = false
    /// First-run setup wizard window controller, retained while it's on screen.
    private var onboardingController: OnboardingWindowController?
    /// True once `applicationWillTerminate` fires (incl. a relaunch). The wizard
    /// reads this so a relaunch close doesn't mark onboarding complete.
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon (mirrors legacy LSUIElement, Info.plist:40-41).
        NSApp.setActivationPolicy(.accessory)

        // Hard-default the UI language to English; the Language picker in General
        // prefs overrides it via the "appLanguage" key. Our L() resolves from that
        // key; mirror it to AppleLanguages so system-provided UI (save/open panels,
        // standard menu items) matches. Effective this launch onward.
        UserDefaults.standard.set(
            [UserDefaults.standard.string(forKey: "appLanguage") ?? "en"], forKey: "AppleLanguages")

        // Start Sparkle's auto-updater (direct / Developer ID build only). No-op in
        // the Mac App Store build, where Sparkle is not compiled in and the App Store
        // delivers updates.
        UpdaterUI.start()

        startAppServices()
    }

    /// Bring up the app's actual functionality (status item, hot-keys, clipboard
    /// capture, menus). Runs once, after the access gate is satisfied.
    private func startAppServices() {
        guard !servicesStarted else { return }
        servicesStarted = true

        // One-time: migrate the pre-2.3 combined store into the split snippet/history
        // stores. Accessing AppStore.container builds the (empty) new stores first.
        StoreMigration.migrateIfNeeded(
            oldStoreURL: AppStore.folder.appending(path: "ClipMenu.store"),
            into: AppStore.container.mainContext)

        // Folder-based settings sync: if a backup folder is configured, pull the
        // settings sidecar so changes made on the user's other Macs apply this launch
        // (the folder syncs via Dropbox / iCloud Drive / Google Drive).
        if let backupFolder = BackupFolder.resolvedURL() {
            let scoped = backupFolder.startAccessingSecurityScopedResource()
            SettingsSidecar.read(from: backupFolder.appending(path: SettingsSidecar.fileName), into: .standard)
            if scoped { backupFolder.stopAccessingSecurityScopedResource() }
        }

        // Status-bar item shows the Main menu (MenuController.m:1314). Honor
        // showStatusItem: 0 = none — still reachable via the Main-menu
        // hot-key. Applied at launch (live toggle deferred).
        if UserDefaults.standard.object(forKey: PreferenceKeys.showStatusItem) as? Int ?? 1 != 0 {
            statusItemController.install(menu: mainMenuController.buildMainMenu())
        }

        // Global hot-keys → pop up the matching menu at the cursor, from stored
        // or default combos (AppController.m:601-633): ⌘⇧V Main, ⌘⌃V History,
        // ⌘⇧B Snippets. Rebindable live via the Shortcuts preferences pane.
        mainMenuController.registerAllMenuHotKeys()

        // Clipboard capture: poll changeCount, read snapshots on the main actor,
        // persist ClipRecords off it via the ClipStore actor (ClipsController.m).
        // One-time best-effort import of a legacy Snippets.xml.
        LegacySnippetImport.runOnceIfNeeded()

        // Load the action tree (creates the default actions.plist on first run,
        // mirroring loadActions at launch — AppController.m:292-349).
        _ = ActionStore.load()

        let store = ClipStore(modelContainer: AppStore.container)
        clipStore = store
        Task { await pasteboardMonitor.start(clipStore: store) }
        // One-time: give pre-existing image clips their display thumbnail so the
        // menu shows a picture without faulting the full image (CLAUDE.md §4).
        Task { await store.backfillThumbnails() }

        // An Edit menu so window-level Undo/Redo (and standard text editing)
        // work in the editor/settings windows (§G undo, row 138). LSUIElement
        // apps get no menu by default; legacy had MainMenu.xib.
        installMainMenu()

        // First run: show the setup wizard (which now owns the "Launch at login"
        // choice, superseding the legacy login-item alert). Shown once per install
        // and resumes on the saved step after a relaunch. The main menu is already
        // installed above, so ⌘C/⌘V work in the wizard's fields. Existing users who
        // finished the wizard fall through to the legacy prompt, which is a no-op
        // for them (the wizard set `suppressAlertForLoginItem`).
        if OnboardingGate.shouldShowOnLaunch(
            completed: UserDefaults.standard.bool(forKey: PreferenceKeys.onboardingCompleted)) {
            showOnboarding()
        } else {
            maybePromptToAddLoginItem()
        }

        BackupScheduler.runIfEligible()
    }

    /// Minimal main menu (App + Edit). The Edit ▸ Undo/Redo items route through
    /// the responder chain to the key window's undo manager
    /// (SnippetEditorWindowController.windowWillReturnUndoManager).
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Quit ClipMenu"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(withTitle: L("Undo"),
                         action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: L("Redo"),
                                    action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Cut"),
                         action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: L("Copy"),
                         action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L("Paste"),
                         action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: L("Select All"),
                         action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        HotKeyCenter.shared.unregisterAll()
        // Write the settings sidecar to the backup folder on quit (best-effort) so the
        // latest settings always travel with the synced folder. Snippet versions are
        // captured by the launch-time daily check and the manual "Back Up Now" button
        // (a snippet snapshot is async and can't run during synchronous termination).
        if BackupFolder.automaticBackupEnabled(), let backupFolder = BackupFolder.resolvedURL() {
            let scoped = backupFolder.startAccessingSecurityScopedResource()
            SettingsSidecar.write(from: .standard, to: backupFolder.appending(path: SettingsSidecar.fileName))
            if scoped { backupFolder.stopAccessingSecurityScopedResource() }
        }
        Task { await pasteboardMonitor.stop() }

        // Save-on-quit (AppController.m:351-373): SwiftData persists clips
        // continuously, so "save on quit" is automatic. When saveHistoryOnQuit
        // is OFF, legacy instead deletes the saved history — replicate by
        // clearing the store synchronously on quit (default YES → no-op).
        let saveHistoryOnQuit = UserDefaults.standard.object(forKey: PreferenceKeys.saveHistoryOnQuit) as? Bool ?? true
        if !saveHistoryOnQuit {
            let context = AppStore.container.mainContext
            if let all = try? context.fetch(FetchDescriptor<ClipRecord>()) {
                for clip in all { context.delete(clip) }
                try? context.save()
            }
            // Don't leave the pre-2.3 backup store behind either — it holds the
            // full pre-migration history in plaintext.
            StoreMigration.deleteLegacyBackupIfMigrated(folder: AppStore.folder)
        }
    }

    /// Present the first-run setup wizard. `reset` restarts it at the welcome step
    /// (used by the "Show Setup Guide…" button in About); first-run launch omits it
    /// so the wizard resumes on the saved step after a relaunch.
    func showOnboarding(reset: Bool = false) {
        if reset { UserDefaults.standard.set(0, forKey: PreferenceKeys.onboardingStep) }
        if onboardingController == nil {
            onboardingController = OnboardingWindowController(
                isTerminating: { [weak self] in self?.isTerminating ?? false },
                onClosed: { [weak self] in self?.onboardingController = nil })
        }
        onboardingController?.show()
    }

    /// First launch only: offer to add ClipMenu as a login item, with a
    /// suppression checkbox (AppController.m:556-579). Shown only when not
    /// already a login item and not previously suppressed (AppController.m:323-326).
    private func maybePromptToAddLoginItem() {
        let defaults = UserDefaults.standard
        let alreadyLoginItem = defaults.object(forKey: PreferenceKeys.loginItem) as? Bool ?? false
        let suppressed = defaults.object(forKey: PreferenceKeys.suppressAlertForLoginItem) as? Bool ?? false
        guard !alreadyLoginItem, !suppressed else { return }

        let alert = NSAlert()
        alert.messageText = L("Launch ClipMenu on system startup?")
        alert.informativeText = L("You can change this setting in the Preferences if you want.")
        alert.addButton(withTitle: L("Launch on system startup"))
        alert.addButton(withTitle: L("Don't Launch"))
        alert.showsSuppressionButton = true

        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            defaults.set(true, forKey: PreferenceKeys.loginItem)
            LoginItem.setEnabled(true)
        }
        if alert.suppressionButton?.state == .on {
            defaults.set(true, forKey: PreferenceKeys.suppressAlertForLoginItem)
        }
    }
}

// MARK: - Settings scene

/// The Settings tabs. Raw values persist the last-selected tab
/// (`PreferenceKeys.settingsSelectedTab`); the "About <App>" menu item forces `.about`.
enum SettingsTab: String {
    case general, syncBackup, menu, type, action, shortcuts, about
}

/// Preference tabs: General, Sync & Backup, Menu, Type, Action, Shortcuts, About.
/// There is no separate Updates pane: the auto-update controls live in the General
/// pane (direct build only), next to Launch on Login. The selected tab is remembered
/// across opens; "About <App>" opens straight to the About tab.
struct SettingsView: View {
    @AppStorage(PreferenceKeys.settingsSelectedTab) private var selectedTab = SettingsTab.general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralPreferencesView()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            CloudBackupPreferencesView()
                .tabItem { Label(L("Sync & Backup"), systemImage: "externaldrive.badge.timemachine") }
                .tag(SettingsTab.syncBackup)
            MenuPreferencesView()
                .tabItem { Label(L("Menu"), systemImage: "menubar.rectangle") }
                .tag(SettingsTab.menu)
            TypePreferencesView()
                .tabItem { Label(L("Type"), systemImage: "doc.on.doc") }
                .tag(SettingsTab.type)
            ActionPreferencesView()
                .tabItem { Label(L("Action"), systemImage: "bolt") }
                .tag(SettingsTab.action)
            shortcutsPane
                .tabItem { Label(L("Shortcuts"), systemImage: "command") }
                .tag(SettingsTab.shortcuts)
            AboutPreferencesView()
                .tabItem { Text(L("About")) }
                .tag(SettingsTab.about)
            // No Updates tab: auto-update (Sparkle 2) is a toggle in the General
            // pane, shown only in the direct/Developer ID build (issue #62).
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    /// Shortcuts pane — three hot-key recorders (PrefsWindowController.m:556-613;
    /// labels from English.lproj/Preferences.strings:407-411, 488-489).
    private var shortcutsPane: some View {
        Form {
            LabeledContent(L("Main Menu:")) {
                ShortcutRecorder(hotKey: .main).frame(width: 150, height: 24)
            }
            LabeledContent(L("History Menu:")) {
                ShortcutRecorder(hotKey: .history).frame(width: 150, height: 24)
            }
            LabeledContent(L("Snippets Menu:")) {
                ShortcutRecorder(hotKey: .snippets).frame(width: 150, height: 24)
            }
        }
        .formStyle(.grouped)
    }
}
