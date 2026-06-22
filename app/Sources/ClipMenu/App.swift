import SwiftUI
import SwiftData
import AppKit

// App entry. Agent / menu-bar app: no Dock icon, no main window — only a
// status-bar item (AppKit) plus a SwiftUI Settings scene. LSUIElement is set
// in Resources/Info.plist for the bundled .app; at runtime we also force
// .accessory activation so `swift run` behaves as an agent.
// Maps to ARCHITECTURE.md §2 `@main App` + `AppDelegate`.

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
    /// The iCloud container backing synced snippets (must match the entitlement).
    static let cloudContainerID = "iCloud.com.dragonapp.clipmenu-2"

    /// Application Support directory holding the SwiftData stores.
    static let folder = URL.applicationSupportDirectory.appending(path: "ClipMenu", directoryHint: .isDirectory)

    /// Whether iCloud sync is enabled (default on). Read at launch; applied next launch.
    static var isCloudSyncEnabled: Bool {
        UserDefaults.standard.object(forKey: PreferenceKeys.iCloudSyncEnabled) as? Bool ?? true
    }

    /// True when the snippets store is actually CloudKit-mirrored this launch.
    private(set) static var isCloudKitActive = false

    /// Cached StoreKit entitlement for the paid iCloud-sync subscription
    /// (written by `PremiumStore`). iCloud sync is a $9.99/yr subscription.
    static var isSubscriptionActive: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.subscriptionActive)
    }

    /// Pure gate (testable): CloudKit mirroring activates only in the sandboxed
    /// Mac App Store build, when the user enabled sync AND holds the subscription.
    /// The Developer ID build is never App Store, so iCloud is off there.
    static func shouldActivateCloud(channelIsAppStore: Bool, syncEnabled: Bool, subscribed: Bool) -> Bool {
        channelIsAppStore && syncEnabled && subscribed
    }

    /// Pure gate (testable): the Mac App Store build is a paid app, so it requires an
    /// active subscription/trial to use. The Developer ID / direct build is free.
    static func hasAppAccess(channelIsAppStore: Bool, subscribed: Bool) -> Bool {
        !channelIsAppStore || subscribed
    }

    /// Pure gate (testable): whether to relaunch once to bring CloudKit up. The
    /// SwiftData container is built once at launch (the Settings scene's
    /// `.modelContainer`); on a fresh install the user isn't subscribed yet, so it's
    /// built as the LOCAL store and can't switch to CloudKit when the trial starts
    /// later in the same session. A single relaunch rebuilds it with iCloud.
    /// `alreadyRelaunched` guards against a loop when CloudKit still can't come up
    /// (e.g. the Production schema isn't deployed yet).
    static func shouldRelaunchForCloudActivation(
        channelIsAppStore: Bool, syncEnabled: Bool, subscribed: Bool,
        cloudActive: Bool, alreadyRelaunched: Bool) -> Bool {
        channelIsAppStore && syncEnabled && subscribed && !cloudActive && !alreadyRelaunched
    }

    /// Dev-only escape hatch (set by scripts/build-dev-icloud.sh) to populate the
    /// CloudKit *Development* schema from a signed local build. Forces the
    /// CloudKit-mirrored store on regardless of channel/subscription. Never set in
    /// shipping builds, and a no-op unless the build also carries iCloud entitlements.
    static var devCloudKitSchemaRequested: Bool {
        ProcessInfo.processInfo.environment["CLIPMENU_DEV_CLOUDKIT_SCHEMA"] == "1"
    }

    #if PREMIUM
    /// Dev-only: create both CloudKit Development schemas so they can be deployed to
    /// Production: the SwiftData-mirrored snippet schema (CD_Folder / CD_Snippet) and
    /// the raw-CloudKit backup schema (Backups zone + SnippetBackup record type).
    /// Safe to delete the seeded records afterward.
    static func seedCloudKitSchemaSample() {
        let context = container.mainContext

        // 1) Snippet sync schema — insert a sample Folder+Snippet so SwiftData exports.
        let folders = (try? context.fetch(FetchDescriptor<Folder>())) ?? []
        if folders.isEmpty {   // existing data already exports the schema
            let folder = Folder(title: "iCloud Schema Init", index: 0)
            context.insert(folder)
            context.insert(Snippet(title: "schema", content: "schema", index: 0, folder: folder))
            try? context.save()
        }
        NSLog("ClipMenu: dev CloudKit schema seed saved. Keep the app running ~1 minute while it uploads, then check CloudKit Console → Development → Record Types for CD_Folder / CD_Snippet and Deploy to Production.")

        // 2) Backup schema — the backup store is gated to the App Store build and never
        //    runs here, so write one version explicitly to create the Backups zone and
        //    SnippetBackup record type in the Development environment.
        Task { @MainActor in
            let store = CloudKitBackupStore(containerID: cloudContainerID)
            let manager = BackupManager(store: store, context: container.mainContext,
                                        deviceName: "schema-seed", appVersion: AppInfo.version)
            do {
                try await manager.backUpNow(kind: .manual, force: true)
                NSLog("ClipMenu: dev SnippetBackup schema seed uploaded. Check CloudKit Console → Development → Record Types for SnippetBackup, then Deploy to Production.")
            } catch {
                NSLog("ClipMenu: SnippetBackup schema seed failed: \(error)")
            }
        }
    }
    #endif

    static let container: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let folder = Self.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let snippetsURL = folder.appending(path: "ClipMenu-Snippets.store")
        let historyURL = folder.appending(path: "ClipMenu-History.store")

        let snippetSchema = Schema([Folder.self, Snippet.self])
        let historySchema = Schema([ClipRecord.self, ClipImage.self])

        func make(cloud: Bool) throws -> ModelContainer {
            let snippetsConfig = ModelConfiguration(
                "Snippets", schema: snippetSchema, url: snippetsURL,
                cloudKitDatabase: cloud ? .private(cloudContainerID) : .none)
            let historyConfig = ModelConfiguration(
                "History", schema: historySchema, url: historyURL,
                cloudKitDatabase: .none)
            return try ModelContainer(
                for: Folder.self, Snippet.self, ClipRecord.self, ClipImage.self,
                configurations: snippetsConfig, historyConfig)
        }

        // `devCloudKitSchemaRequested` forces the CloudKit-mirrored store on so a signed
        // development build can create the CloudKit Development schema (later deployed to
        // Production). Normal builds use the channel + subscription gate.
        let wantCloud = devCloudKitSchemaRequested || shouldActivateCloud(
            channelIsAppStore: DistributionChannel.current == .appStore,
            syncEnabled: isCloudSyncEnabled,
            subscribed: isSubscriptionActive)
        if wantCloud {
            do {
                let container = try make(cloud: true)
                isCloudKitActive = true
                return container
            } catch {
                NSLog("ClipMenu: CloudKit unavailable, using local store (\(error))")
            }
        }
        do {
            return try make(cloud: false)
        } catch {
            // The split stores are regenerable (snippets re-sync from CloudKit, history
            // is a cache). If the on-disk schema is incompatible, reset ONLY the new
            // files — never the old combined ClipMenu.store, which is the migration backup.
            NSLog("ClipMenu: resetting incompatible split stores; using local-only this launch (\(error))")
            for base in ["ClipMenu-Snippets.store", "ClipMenu-History.store"] {
                for suffix in ["", "-wal", "-shm"] {
                    try? FileManager.default.removeItem(at: folder.appending(path: base + suffix))
                }
            }
            do { return try make(cloud: false) }
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
    #if PREMIUM
    private var paywallGate: PaywallWindowController?
    #endif
    private var servicesStarted = false

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
        // delivers updates. Runs regardless of the paywall: the updater belongs to
        // the free direct build, which has no paywall.
        UpdaterUI.start()

        #if PREMIUM
        // Mac App Store build is a paid app (30-day trial → $9.99/yr). Start StoreKit
        // and gate the whole app behind an active subscription/trial. The Developer ID
        // build is free and always has access.
        if DistributionChannel.current == .appStore {
            PremiumStore.shared.onChange = { [weak self] in self?.evaluateAccessGate() }
            PremiumStore.shared.start()
        }
        evaluateAccessGate()
        #else
        // Free / open-source build: no paywall, start the app's services immediately.
        startAppServices()
        #endif
    }

    #if PREMIUM
    /// Show the paywall gate when the App Store build has no entitlement; otherwise
    /// start the app's services. Re-entrant: called at launch and whenever the StoreKit
    /// entitlement changes. The gate is only raised before services start (i.e. at
    /// launch) — a mid-session lapse lets the user finish the session and is re-gated
    /// on the next launch.
    private func evaluateAccessGate() {
        let hasAccess = AppStore.hasAppAccess(
            channelIsAppStore: DistributionChannel.current == .appStore,
            subscribed: PremiumStore.shared.isSubscribed)
        if hasAccess {
            // If the subscription was just activated this session, the launch-built
            // container is still the local store — relaunch once to rebuild it with
            // CloudKit before starting services (no-op on every later launch).
            if relaunchForCloudActivationIfNeeded() { return }
            paywallGate?.dismiss()
            paywallGate = nil
            startAppServices()
        } else {
            // Not entitled: reset the one-shot guard so a later (re)subscribe can
            // trigger the cloud-activation relaunch again.
            UserDefaults.standard.set(false, forKey: PreferenceKeys.cloudActivationRelaunched)
            if !servicesStarted, paywallGate == nil {
                let gate = PaywallWindowController(onUnlock: { [weak self] in self?.evaluateAccessGate() })
                paywallGate = gate
                gate.show()
            }
        }
    }

    /// Relaunch once to switch the launch-built local store over to CloudKit after the
    /// subscription becomes active mid-session. Returns true if a relaunch was started
    /// (caller should bail). Guarded by `cloudActivationRelaunched` so it can never loop.
    private func relaunchForCloudActivationIfNeeded() -> Bool {
        let defaults = UserDefaults.standard
        guard AppStore.shouldRelaunchForCloudActivation(
            channelIsAppStore: DistributionChannel.current == .appStore,
            syncEnabled: AppStore.isCloudSyncEnabled,
            subscribed: PremiumStore.shared.isSubscribed,
            cloudActive: AppStore.isCloudKitActive,
            alreadyRelaunched: defaults.bool(forKey: PreferenceKeys.cloudActivationRelaunched))
        else { return false }
        defaults.set(true, forKey: PreferenceKeys.cloudActivationRelaunched)
        AppRelaunch.relaunch()
        return true
    }
    #endif

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

        #if PREMIUM
        // Start iCloud settings sync only when CloudKit is actually active this launch.
        // In the App Store build iCloud is included with the subscription and on by
        // default; the Developer ID build has no iCloud, so this stays off there.
        if AppStore.isCloudKitActive {
            SettingsSync.shared.start()
            CloudSyncMonitor.shared.start()
        }
        #endif

        // Status-bar item shows the Main menu (MenuController.m:1314). Honor
        // showStatusItem: 0 = none (OQ#12) — still reachable via the Main-menu
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
        // One-time best-effort import of a legacy Snippets.xml (OQ#6).
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

        // First-run prompt to add as a login item (AppController.m:323-326).
        maybePromptToAddLoginItem()

        #if PREMIUM
        // Dev-only: when generating the CloudKit Development schema, seed a sample so
        // SwiftData exports and creates the CD_* record types (scripts/build-dev-icloud.sh).
        if AppStore.devCloudKitSchemaRequested {
            AppStore.seedCloudKitSchemaSample()
        }

        BackupScheduler.runIfEligible()
        #endif
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
        HotKeyCenter.shared.unregisterAll()
        #if PREMIUM
        SettingsSync.shared.stop()
        #endif
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

/// Preference tabs: General, iCloud, Menu, Type, Action, Shortcuts, Backup, About.
/// iCloud is the 2nd tab (both builds): in the App Store build it surfaces the
/// subscription / in-app purchase + sync status; in the direct build it points to
/// the Mac App Store edition. There is no separate Updates pane: the auto-update
/// controls live in the General pane (direct build only), next to Launch on Login.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            CloudBackupPreferencesView()
                .tabItem { Label(L("iCloud & Backup"), systemImage: "icloud") }
            MenuPreferencesView()
                .tabItem { Label(L("Menu"), systemImage: "menubar.rectangle") }
            TypePreferencesView()
                .tabItem { Label(L("Type"), systemImage: "doc.on.doc") }
            ActionPreferencesView()
                .tabItem { Label(L("Action"), systemImage: "bolt") }
            shortcutsPane
                .tabItem { Label(L("Shortcuts"), systemImage: "command") }
            AboutPreferencesView()
                .tabItem { Text(L("About")) }
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
