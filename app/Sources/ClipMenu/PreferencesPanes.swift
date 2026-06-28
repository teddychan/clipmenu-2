import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - General pane

struct GeneralPreferencesView: View {
    @AppStorage(PreferenceKeys.appLanguage) private var appLanguage = "en"
    @State private var appLanguageAtAppear = "en"
    @AppStorage(PreferenceKeys.loginItem) private var loginItem = false
    @AppStorage(PreferenceKeys.inputPasteCommand) private var inputPasteCommand = true
    @AppStorage(PreferenceKeys.reorderClipsAfterPasting) private var reorderAfterPasting = true
    @AppStorage(PreferenceKeys.maxHistorySize) private var maxHistorySize = 20
    @AppStorage(PreferenceKeys.timeInterval) private var timeInterval = 0.75
    @AppStorage(PreferenceKeys.saveHistoryOnQuit) private var saveHistoryOnQuit = true
    @AppStorage(PreferenceKeys.showStatusItem) private var showStatusItem = 1
    @State private var showExcludeSheet = false
    @State private var showAutoPasteInfo = false
    // Mirrors Sparkle's automatic-check preference (direct build only). Synced from
    // UpdaterUI on appear and written back on change; Sparkle owns the stored value.
    @State private var autoCheckForUpdates = false

    var body: some View {
        Form {
            Section {
                Picker(L("Language"), selection: $appLanguage) {
                    Text("English").tag("en")
                    Text("Español").tag("es")
                    Text("Français").tag("fr")
                    Text("日本語").tag("ja")
                    Text("한국어").tag("ko")
                    Text("简体中文").tag("zh-Hans")
                    Text("繁體中文").tag("zh-Hant")
                }
                if appLanguage != appLanguageAtAppear {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Restart ClipMenu to apply the language change."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(L("Restart Now")) { AppRelaunch.relaunch() }
                    }
                }
            }
            Section {
                Toggle(L("Launch on Login"), isOn: $loginItem)
                // Auto-update (Sparkle) — direct/Developer ID build only. The Mac App
                // Store build delivers updates through the Store, so these rows are
                // absent there (UpdaterUI.isSupported == false). Issue #62.
                if UpdaterUI.isSupported {
                    Toggle(L("Automatically check for updates"), isOn: $autoCheckForUpdates)
                    Button(L("Check for Updates Now…")) { UpdaterUI.checkNow() }
                }
                if DistributionChannel.current == .appStore {
                    // Sandboxed App Store build can't auto-paste: show the toggle
                    // disabled and off, with an ⓘ popover explaining why and where
                    // to get the auto-paste (direct/Homebrew) build.
                    HStack(spacing: 6) {
                        Toggle(L("Input \"⌘ + V\" after menu item selection"), isOn: .constant(false))
                            .disabled(true)
                        Button {
                            showAutoPasteInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("About automatic paste"))
                        .help(L("About automatic paste"))
                        .popover(isPresented: $showAutoPasteInfo, arrowEdge: .trailing) {
                            AutoPasteInfoPopover()
                        }
                    }
                } else {
                    Toggle(L("Input \"⌘ + V\" after menu item selection"), isOn: $inputPasteCommand)
                }
            }
            Section {
                Picker(L("Sort history order by:"), selection: $reorderAfterPasting) {
                    Text(L("Date created")).tag(false)
                    Text(L("Date last used")).tag(true)
                }
                LabeledContent(L("Max clipboard history size:")) {
                    HStack {
                        TextField("", value: $maxHistorySize, format: .number).frame(width: 60)
                        Text(L("items"))
                    }
                }
                VStack(alignment: .leading) {
                    Text(L("Time interval to observe the clipboard:"))
                    Slider(value: $timeInterval, in: 0...1, step: 0.25) {
                        Text(L("Time interval"))
                    } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("1") }
                }
                Toggle(L("Save clipboard history on quit"), isOn: $saveHistoryOnQuit)
            }
            Section {
                Picker(L("Status Bar icon style:"), selection: $showStatusItem) {
                    Text(L("None")).tag(0)
                    Text(L("Show")).tag(1)
                }
            }
            Section(L("Exclude Applications")) {
                Button(L("Define Exclude Options…")) { showExcludeSheet = true }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loginItem = LoginItem.isEnabled   // reconcile with actual state
            appLanguageAtAppear = appLanguage
            autoCheckForUpdates = UpdaterUI.automaticallyChecksForUpdates
        }
        .onChange(of: loginItem) { _, newValue in LoginItem.setEnabled(newValue) }
        .onChange(of: autoCheckForUpdates) { _, newValue in
            UpdaterUI.automaticallyChecksForUpdates = newValue
        }
        .onChange(of: appLanguage) { _, newValue in
            // Mirror the in-app choice to the OS-level override so system-provided UI
            // (save/open panels, standard menu items) matches after the next launch.
            UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
        }
        .sheet(isPresented: $showExcludeSheet) { ExcludeAppsView() }
    }
}

// MARK: - Backup pane (snippet versions + history export)

/// Backup preferences. Two clearly-separated sections so users never confuse the
/// snippet version history (iCloud) with the one-shot clipboard-history export.
struct BackupPreferencesView: View {
    @AppStorage("exportHistoryAsSingleFile") private var exportAsSingleFile = true
    @AppStorage("tagOfSeparatorForExportHistoryToFile") private var separatorTag = 1

    @State private var status: String = ""
    @State private var working = false
    @State private var showRestore = false

    private var backupAvailable: Bool { BackupScheduler.isEligible }

    var body: some View {
        Group {
            if backupAvailable {
                Section(L("Snippet Versions in iCloud")) {
                    Text(L("ClipMenu keeps your last 20 backups of your snippets and folders in your private iCloud. You can restore any version; your current data is backed up first."))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        Button(L("Back up now")) { Task { await backUpNow() } }
                            .disabled(working)
                        Button(L("Restore from iCloud…")) { showRestore = true }
                            .disabled(working)
                        if working { ProgressView().controlSize(.small) }
                    }
                    if !status.isEmpty {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                    Text(L("Backups use your private iCloud (encrypted in transit and at rest). Turn on Advanced Data Protection for end-to-end encryption."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section(L("Clipboard History Export")) {
                Picker("", selection: $exportAsSingleFile) {
                    Text(L("Single file")).tag(true)
                    Text(L("Multiple files")).tag(false)
                }
                .labelsHidden()
                Picker(L("separator:"), selection: $separatorTag) {
                    Text(L("None")).tag(0)
                    Text(L("New Line")).tag(1)
                    Text(L("Carriage Return and New Line")).tag(2)
                    Text(L("Carriage Return")).tag(3)
                    Text(L("Tab")).tag(4)
                    Text(L("Space")).tag(5)
                }
                .disabled(!exportAsSingleFile)
                Button(L("Export…"), action: export)
            }
        }
        .sheet(isPresented: $showRestore) {
            RestoreVersionsView(manager: BackupScheduler.makeManager())
        }
    }

    private func backUpNow() async {
        working = true; defer { working = false }
        do {
            switch try await BackupScheduler.makeManager().backUpNow(kind: .manual) {
            case .created: status = L("Backup saved.")
            case .noChanges: status = L("No changes since the last backup.")
            }
        } catch {
            status = L("iCloud backup failed. Try again later.")
        }
    }

    /// Export… (PrefsWindowController.m:482-499): save panel (single file) or
    /// folder chooser (multiple files), then HistoryExport.
    private func export() {
        let context = AppStore.container.mainContext
        // Export the same bounded, visible history the menu shows — not every row
        // ever stored — so it can't leak old clips past maxHistorySize (CLAUDE.md §2).
        let clips = (try? context.fetch(ClipStore.boundedHistoryDescriptor())) ?? []

        if exportAsSingleFile {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = "ClipMenu History.txt"
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let strings = clips.compactMap(\.stringValue)
            HistoryExport.writeSingleFile(clipStrings: strings, separatorTag: separatorTag, to: url)
        } else {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            guard panel.runModal() == .OK, let dir = panel.url else { return }
            HistoryExport.writeMultipleFiles(
                orderedClipStrings: clips.map(\.stringValue), toDirectory: dir)
        }
    }
}

/// Lists stored backup versions newest-first and restores the chosen one.
struct RestoreVersionsView: View {
    let manager: BackupManager
    @Environment(\.dismiss) private var dismiss

    @State private var versions: [BackupVersionMeta] = []
    @State private var loading = true
    @State private var restoring = false
    @State private var selectedID: String?
    @State private var error: String = ""

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()

    private var selected: BackupVersionMeta? { versions.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Restore from iCloud")).font(.headline)

            if restoring {
                HStack { ProgressView().controlSize(.small); Text(L("Restoring…")) }
            } else if loading {
                ProgressView()
            } else if versions.isEmpty {
                Text(L("No backups yet.")).foregroundStyle(.secondary)
            } else {
                List(selection: $selectedID) {
                    ForEach(versions) { v in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.dateFormat.string(from: v.effectiveDate))
                            Text("\(kindLabel(v.kind)) · \(v.folderCount) \(L("folders")) · \(v.snippetCount) \(L("snippets")) · \(v.deviceName)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(v.id)
                    }
                }
                .frame(minHeight: 200)
            }

            if !error.isEmpty { Text(error).font(.callout).foregroundStyle(.red) }

            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.disabled(restoring)
                Button(L("Restore")) { confirmAndRestore() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || restoring || newerThanApp(selected))
            }
        }
        .padding(20)
        .frame(width: 440)
        .task { await load() }
    }

    /// Confirm with an AppKit alert before the destructive replace. SwiftUI's
    /// `.confirmationDialog` does not reliably present from inside a `.sheet` on
    /// macOS, so we use `NSAlert` — the confirmation pattern used elsewhere here.
    private func confirmAndRestore() {
        guard let v = selected else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Restore this backup?")
        alert.informativeText = confirmMessage(v)
        alert.addButton(withTitle: L("Restore"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await restore() }
    }

    /// Detail shown in the restore confirmation: which version, and that the
    /// current snippets are safely backed up before the destructive replace.
    private func confirmMessage(_ v: BackupVersionMeta) -> String {
        let when = Self.dateFormat.string(from: v.effectiveDate)
        let detail = "\(kindLabel(v.kind)) · \(v.folderCount) \(L("folders")) · \(v.snippetCount) \(L("snippets")) · \(v.deviceName)"
        return "\(when)\n\(detail)\n\n" + L("This replaces all your current snippets and folders. Your current snippets are backed up first.")
    }

    private func kindLabel(_ kind: BackupKind) -> String {
        switch kind {
        case .auto: return L("Automatic")
        case .manual: return L("Manual")
        case .preRestore: return L("Before restore")
        }
    }

    private func newerThanApp(_ v: BackupVersionMeta?) -> Bool {
        guard let v else { return false }
        return v.schemaVersion > SnippetSnapshot.currentSchemaVersion
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { versions = try await manager.listForUI() }
        catch _ { error = L("Couldn't load backups from iCloud.") }
    }

    private func restore() async {
        guard let v = selected else { return }
        restoring = true; defer { restoring = false }
        do { try await manager.restore(v); dismiss() }
        catch let e as BackupError {
            switch e {
            case .preRestoreFailed:
                error = L("Couldn't save a safety backup, so the restore was cancelled.")
            case .unsupportedSchemaVersion:
                error = L("This version was made on a newer app version and can't be restored.")
            case .validationFailed:
                error = L("Restore failed. Your current data was not changed.")
            }
        } catch _ {
            error = L("Restore failed. Your current data was not changed.")
        }
    }
}

// MARK: - iCloud & Backup pane (combined tab)

/// The single "iCloud & Backup" Settings tab. Hosts the iCloud sync-status section
/// (`CloudPreferencesView`) and the snippet-versions + history-export sections
/// (`BackupPreferencesView`) in one grouped `Form`, so sync status, versioned
/// backup, and history export all live in one place (previously two separate tabs,
/// which confused users).
struct CloudBackupPreferencesView: View {
    var body: some View {
        Form {
            CloudPreferencesView()
            BackupPreferencesView()
        }
        .formStyle(.grouped)
    }
}

// MARK: - iCloud pane (sync status)

/// iCloud preferences — the 2nd tab, shown in every build. iCloud sync is free; this
/// pane shows live sync status (last sync time + synced snippet/folder counts), or a
/// note that iCloud is unavailable and storage is local-only (offline, or a build
/// without iCloud entitlements / an embedded provisioning profile).
struct CloudPreferencesView: View {
    // iCloud sync status: last successful sync time + live counts of the records that
    // actually sync (snippets + folders; clipboard history is local-only).
    @ObservedObject private var syncMonitor = CloudSyncMonitor.shared
    @Query private var snippets: [Snippet]
    @Query private var folders: [Folder]

    var body: some View {
        Section(L("iCloud")) { syncStatusSection }
    }

    @ViewBuilder private var syncStatusSection: some View {
        if AppStore.isCloudKitActive {
            VStack(alignment: .leading, spacing: 4) {
                Label(L("Syncing via iCloud"), systemImage: "checkmark.icloud")
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastSyncedText)
                    Text(syncedCountText)
                }
                .padding(.leading, 20)   // align under the label text, past the icon
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Label(L("iCloud unavailable — using local storage only"),
                  systemImage: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: Sync status text

    /// Date/time part of the "Last synced" line: YYYY-MMM-DD HH:MM:SS (e.g.
    /// 2026-Jun-07 14:32:05). Fixed POSIX locale so the month abbreviation is stable
    /// English; the time-zone abbreviation is appended via `TimeZone.abbreviation(for:)`,
    /// which yields "HKT"/"JST"/etc. where `DateFormatter`'s `zzz` falls back to offsets.
    private static let syncDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MMM-dd HH:mm:ss"
        return formatter
    }()

    private static func formattedSyncDate(_ date: Date) -> String {
        let zone = TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier
        return "\(syncDateFormatter.string(from: date)) \(zone)"
    }

    private var lastSyncedText: String {
        let value = syncMonitor.lastSyncDate.map(Self.formattedSyncDate)
            ?? L("Waiting for first sync…")
        return String(format: L("Last synced: %@"), value)
    }

    private var syncedCountText: String {
        let snippetCount = snippets.count
        let folderCount = folders.count
        if snippetCount == 0 && folderCount == 0 {
            return L("No snippets synced yet")
        }
        let snippetPart = String(format: L(snippetCount == 1 ? "%d snippet" : "%d snippets"), snippetCount)
        let folderPart = String(format: L(folderCount == 1 ? "%d folder" : "%d folders"), folderCount)
        return String(format: L("%1$@, %2$@ synced"), snippetPart, folderPart)
    }
}

// Preferences panes. SwiftUI forms bound to the exact legacy UserDefaults keys
// and defaults (AppController.m:131-188; labels English.lproj/Preferences.strings).
// Legacy PrefsWindowController panes. @AppStorage defaults match the legacy registered
// defaults, so behavior is identical whether or not the user opens Settings.

// MARK: - Exclude-apps sheet (PrefsWindowController.m:378-478,789-877)

/// "Exclude these applications:" — apps whose frontmost clipboard activity is not
/// captured. Persisted as the `excludeApps` array of {bundleIdentifier, name},
/// which PasteboardReader gates on (AppController.m:_defaultExcludeList).
struct ExcludeAppsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apps: [[String: String]] = ExcludeAppsView.load()
    @State private var selection: String?   // bundle identifier

    private static let key = "excludeApps"

    static func load() -> [[String: String]] {
        UserDefaults.standard.array(forKey: key) as? [[String: String]]
            ?? [["bundleIdentifier": "org.openoffice.script", "name": "OpenOffice.org"]]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Exclude these applications:")).font(.headline)
            List(selection: $selection) {
                ForEach(apps, id: \.self) { app in
                    Label(app["name"] ?? app["bundleIdentifier"] ?? "?", systemImage: "app.dashed")
                        .tag(app["bundleIdentifier"] ?? "")
                }
            }
            .frame(minWidth: 320, minHeight: 200)
            HStack {
                Menu {
                    ForEach(runningApps(), id: \.id) { app in
                        Button(app.name) { add(bundleID: app.id, name: app.name) }
                    }
                    Divider()
                    Button(L("Other…")) { addViaPanel() }
                } label: { Image(systemName: "plus") }
                .frame(width: 44)

                Button(action: removeSelected) { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
                Button(L("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private func runningApps() -> [(id: String, name: String)] {
        let regular = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let mapped = regular.compactMap { app -> (String, String)? in
            guard let id = app.bundleIdentifier else { return nil }
            return (id, app.localizedName ?? id)
        }
        // De-dupe by bundle id, sorted by name.
        var seen = Set<String>()
        return mapped.filter { seen.insert($0.0).inserted }
            .map { (id: $0.0, name: $0.1) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func add(bundleID: String, name: String) {
        guard !apps.contains(where: { $0["bundleIdentifier"] == bundleID }) else { return }
        apps.append(["bundleIdentifier": bundleID, "name": name])
        persist()
    }

    /// "Other…" — choose an .app and read its bundle id (789-877).
    private func addViaPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        add(bundleID: id, name: name)
    }

    private func removeSelected() {
        guard let id = selection else { return }
        apps.removeAll { $0["bundleIdentifier"] == id }
        selection = nil
        persist()
    }

    private func persist() { UserDefaults.standard.set(apps, forKey: Self.key) }
}

// MARK: - About pane

/// About pane: app icon, name, version, the open-source/GitHub link, license,
/// and credits. Static product info — nothing here is persisted.
struct AboutPreferencesView: View {
    private static let githubURL = URL(string: "https://github.com/teddychan/clipmenu-2")!

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                }
                VStack(spacing: 4) {
                    Text(AppInfo.displayName).font(.title2).bold()
                    Text(AppInfo.versionDescription).foregroundStyle(.secondary)
                }

                VStack(spacing: 6) {
                    Text(L("This application is open source and can be found on GitHub:"))
                    Link("github.com/teddychan/clipmenu-2", destination: Self.githubURL)
                }
                .multilineTextAlignment(.center)

                Text(L("Released under the MIT License."))
                    .foregroundStyle(.secondary)

                Button(L("Show Setup Guide…")) {
                    (NSApp.delegate as? AppDelegate)?.showOnboarding(reset: true)
                }

                Divider().frame(maxWidth: 260)

                VStack(spacing: 12) {
                    Text(L("Contributors")).font(.headline)
                    credit(role: L("Creator"), name: "Teddy Chan")
                    credit(role: L("Original ClipMenu"), name: "Naotaka Morimoto")
                }

                Text(AppInfo.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
        }
    }

    private func credit(role: String, name: String) -> some View {
        VStack(spacing: 2) {
            Text(role).font(.subheadline).italic().foregroundStyle(.secondary)
            Text(name)
        }
    }
}

// MARK: - Menu pane

struct MenuPreferencesView: View {
    @AppStorage(PreferenceKeys.numberOfItemsPlaceInline) private var inlineCount = 0
    @AppStorage(PreferenceKeys.numberOfItemsPlaceInsideFolder) private var perFolder = 10
    @AppStorage(PreferenceKeys.maxMenuItemTitleLength) private var maxTitleLength = 20
    @AppStorage(PreferenceKeys.menuItemsAreMarkedWithNumbers) private var markWithNumbers = true
    @AppStorage(PreferenceKeys.addNumericKeyEquivalents) private var numericKeyEquivalents = false
    @AppStorage(PreferenceKeys.showLabelsInMenu) private var showLabels = true
    @AppStorage(PreferenceKeys.addClearHistoryMenuItem) private var addClearHistory = true
    @AppStorage(PreferenceKeys.showAlertBeforeClearHistory) private var alertBeforeClear = true
    @AppStorage(PreferenceKeys.showToolTipOnMenuItem) private var showToolTip = true
    @AppStorage(PreferenceKeys.maxLengthOfToolTipKey) private var maxToolTipLength = 200
    @AppStorage(PreferenceKeys.changeFontSize) private var changeFontSize = false
    @AppStorage(PreferenceKeys.howToChangeFontSize) private var howToChangeFontSize = 0
    @AppStorage(PreferenceKeys.selectedFontSize) private var selectedFontSize = 14
    @AppStorage(PreferenceKeys.showImageInTheMenu) private var showImage = true
    @AppStorage(PreferenceKeys.thumbnailWidth) private var thumbnailWidth = 100
    @AppStorage(PreferenceKeys.thumbnailHeight) private var thumbnailHeight = 32
    @AppStorage(PreferenceKeys.showIconInTheMenu) private var showIcon = true
    @AppStorage(PreferenceKeys.menuIconSize) private var menuIconSize = 16
    @AppStorage(PreferenceKeys.positionOfSnippets) private var positionOfSnippets = 2
    @AppStorage(PreferenceKeys.groupSnippetsInFolder) private var groupSnippetsInFolder = true

    private static let fontSizes = Array(9...24) + [36, 48, 64, 72, 96]

    var body: some View {
        Form {
            Section(L("Clipboard History")) {
                LabeledContent(L("Number of items place inline:")) {
                    TextField("", value: $inlineCount, format: .number).frame(width: 60)
                }
                LabeledContent(L("Number of items place inside a folder:")) {
                    TextField("", value: $perFolder, format: .number).frame(width: 60)
                }
                LabeledContent(L("Number of characters in the menu:")) {
                    TextField("", value: $maxTitleLength, format: .number).frame(width: 60)
                }
                Toggle(L("Mark menu items with numbers"), isOn: $markWithNumbers)
                Toggle(L("Add key equivalents to numeric keys"), isOn: $numericKeyEquivalents)
                Toggle(L("Show labels to indicate item types"), isOn: $showLabels)
                Toggle(L("Add a menu item to clear clipboard history"), isOn: $addClearHistory)
                Toggle(L("Show alert panel before clear history"), isOn: $alertBeforeClear)
                Toggle(L("Show tool tip on a menu item"), isOn: $showToolTip)
                LabeledContent(L("Max length of tool tip string:")) {
                    TextField("", value: $maxToolTipLength, format: .number).frame(width: 60)
                }
            }

            Section(L("Appearance")) {
                Toggle(L("Change font size in the menu"), isOn: $changeFontSize)
                Picker(L("Font size:"), selection: $howToChangeFontSize) {
                    Text(L("Fit to the icon size")).tag(0)
                    Text(L("Select")).tag(1)
                }
                .disabled(!changeFontSize)
                Picker(L("Size:"), selection: $selectedFontSize) {
                    ForEach(Self.fontSizes, id: \.self) { Text("\($0) pt").tag($0) }
                }
                .disabled(!changeFontSize || howToChangeFontSize != 1)
            }

            Section(L("Icon")) {
                Toggle(L("Show Icon in the Menu"), isOn: $showIcon)
                Picker(L("Icon size:"), selection: $menuIconSize) {
                    Text("16").tag(16)
                    Text("32").tag(32)
                    Text("48").tag(48)
                }
                .disabled(!showIcon)
                Toggle(L("Show Image"), isOn: $showImage)
                LabeledContent(L("Width:")) {
                    TextField("", value: $thumbnailWidth, format: .number).frame(width: 60)
                }
                LabeledContent(L("Height:")) {
                    TextField("", value: $thumbnailHeight, format: .number).frame(width: 60)
                }
            }

            Section {
                Picker(L("Snippets' position:"), selection: $positionOfSnippets) {
                    Text(L("None")).tag(0)
                    Text(L("Above the clipboard history")).tag(1)
                    Text(L("Below the clipboard history")).tag(2)
                }
                Toggle(L("Group snippets under one menu"), isOn: $groupSnippetsInFolder)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Type pane

/// "Select clipboard types to store:" — the 7 live store-type toggles
/// (Preferences.strings:1097-1104). Bound to the `storeTypes` [String:Bool]
/// UserDefaults dict that PasteboardReader gates capture on (AppController.m:142,
/// 48-58; ClipsController.m:670-678). The legacy PICT Image toggle is removed —
/// PICT is dead on modern macOS.
struct TypePreferencesView: View {
    /// Legacy type name (storeTypes key) → display label, in xib order.
    private static let types: [(name: String, label: String)] = [
        ("String", "Plain Text"),
        ("RTF", "Rich Text Format (RTF)"),
        ("PDF", "PDF"),
        ("Filenames", "Filenames"),
        ("URL", "URL"),
        ("TIFF", "TIFF Image"),
        ("RTFD", "Rich Text Format Directory (RTFD)"),
    ]

    @State private var store: [String: Bool]

    init() {
        let saved = UserDefaults.standard.dictionary(forKey: PreferenceKeys.storeTypes) as? [String: Bool] ?? [:]
        var initial: [String: Bool] = [:]
        for type in Self.types { initial[type.name] = saved[type.name] ?? true }
        _store = State(initialValue: initial)
    }

    var body: some View {
        Form {
            Section(L("Select clipboard types to store:")) {
                ForEach(Self.types, id: \.name) { type in
                    Toggle(L(type.label), isOn: Binding(
                        get: { store[type.name] ?? true },
                        set: { store[type.name] = $0; persist() }
                    ))
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Persist the whole dict (all 7 keys) so PasteboardReader.storeTypes() reads
    /// a complete picture.
    private func persist() {
        UserDefaults.standard.set(store, forKey: PreferenceKeys.storeTypes)
    }
}

// MARK: - Action pane

/// Action preferences: enable, invoke-immediately, and the per-modifier click
/// behavior pickers (AppController.m:184-186 defaults; PrefsWindowController.m:
/// 655-696 picker = None / Pop up Action Menu / a specific action).
struct ActionPreferencesView: View {
    @AppStorage(PreferenceKeys.enableAction) private var enableAction = true
    @AppStorage(PreferenceKeys.invokeActionImmediately) private var invokeImmediately = false
    @AppStorage(PreferenceKeys.controlClickBehavior) private var controlBehavior = "popUpActionMenu"
    @AppStorage(PreferenceKeys.shiftClickBehavior) private var shiftBehavior = ""
    @AppStorage(PreferenceKeys.optionClickBehavior) private var optionBehavior = ""
    @AppStorage(PreferenceKeys.commandClickBehavior) private var commandBehavior = ""

    private let leaves = ActionStore.flattenedLeaves()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(L("Enable Action"), isOn: $enableAction)
                    Toggle(L("Invoke the first action immediately if there is only one action"),
                           isOn: $invokeImmediately)
                }
                Section(L("Click behavior")) {
                    behaviorPicker(L("Control-click / right-click:"), $controlBehavior)
                    behaviorPicker(L("Shift-click:"), $shiftBehavior)
                    behaviorPicker(L("Option-click:"), $optionBehavior)
                    behaviorPicker(L("Command-click:"), $commandBehavior)
                }
                .disabled(!enableAction)
            }
            .formStyle(.grouped)
            .frame(height: 230)

            Divider()
            ActionTreeEditorView().padding(8)
        }
    }

    private func behaviorPicker(_ label: String, _ selection: Binding<String>) -> some View {
        Picker(label, selection: selection) {
            Text(L("None")).tag("")
            Text(L("Pop up Action Menu")).tag("popUpActionMenu")
            Divider()
            ForEach(leaves, id: \.id) { leaf in
                Text(leaf.title).tag(leaf.id)
            }
        }
    }
}

/// Action-tree editor (ActionNodeController.m): a palette
/// (Built-in / Script / User Script) on the left whose selection is added to the
/// user's action tree on the right; remove + drag-reorder there. Persists to
/// ActionStore (actions.plist).
struct ActionTreeEditorView: View {
    @State private var userNodes: [ActionNode] = ActionStore.load()
    @State private var segment = 0
    @State private var paletteSelection: ActionNode.ID?
    @State private var treeSelection: ActionNode.ID?

    private var palette: [ActionNode] {
        switch segment {
        case 1:  return ActionStore.bundledNodes()
        case 2:  return ActionStore.usersNodes()
        default: return ActionStore.builtinNodes()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Actions")).font(.headline)
            HStack(spacing: 8) {
                VStack(spacing: 4) {
                    Picker("", selection: $segment) {
                        Text(L("Built-in")).tag(0)
                        Text(L("Script")).tag(1)
                        Text(L("User Script")).tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    List(selection: $paletteSelection) {
                        OutlineGroup(palette, children: \.children) { node in
                            Text(node.title).tag(node.id)
                        }
                    }
                }
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Button(action: add) { Image(systemName: "arrow.right") }
                            .disabled(paletteSelection == nil)
                        Button(action: remove) { Image(systemName: "minus") }
                            .disabled(treeSelection == nil)
                        Spacer()
                    }
                    List(selection: $treeSelection) {
                        ForEach(userNodes) { node in
                            if let children = node.children {
                                DisclosureGroup {
                                    ForEach(children) { Text($0.title) }
                                } label: { Label(node.title, systemImage: "folder").tag(node.id) }
                            } else {
                                Text(node.title).tag(node.id)
                            }
                        }
                        .onMove { from, to in
                            userNodes.move(fromOffsets: from, toOffset: to)
                            persist()
                        }
                    }
                }
            }
            .frame(minHeight: 180)
        }
    }

    /// add: copy the selected palette node into the user tree (append, with fresh
    /// ids) — ActionNodeController.m:546-557.
    private func add() {
        guard let id = paletteSelection, let node = find(id, in: palette) else { return }
        userNodes.append(freshCopy(node))
        persist()
    }

    /// remove: delete the selected top-level node (ActionNodeController.m:559-570).
    private func remove() {
        guard let id = treeSelection else { return }
        userNodes.removeAll { $0.id == id }
        treeSelection = nil
        persist()
    }

    private func persist() { ActionStore.save(userNodes) }

    private func find(_ id: ActionNode.ID, in nodes: [ActionNode]) -> ActionNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = find(id, in: children) { return found }
        }
        return nil
    }

    /// Deep-copy with fresh identities so added copies are distinct rows.
    private func freshCopy(_ node: ActionNode) -> ActionNode {
        ActionNode(title: node.title, action: node.action, children: node.children?.map(freshCopy))
    }
}

// MARK: - Auto-paste info popover (App Store build)

/// Explains why the App Store build can't auto-paste and links to the
/// direct/Homebrew build that can. Shown from the disabled paste toggle's ⓘ.
private struct AutoPasteInfoPopover: View {
    private static let downloadURL = URL(string: "https://github.com/teddychan/clipmenu-2/releases")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("About automatic paste"))
                .font(.headline)
            Text(L("When you pick a clip, this version copies it to the clipboard. Mac App Store apps run in a sandbox and aren't allowed to paste into other apps for you, so you press ⌘V yourself."))
                .fixedSize(horizontal: false, vertical: true)
            Text(L("To paste automatically after selecting a clip, download ClipMenu from GitHub or install it with Homebrew."))
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            Link(L("Download ClipMenu"), destination: Self.downloadURL)
        }
        .padding()
        .frame(width: 320)
    }
}
