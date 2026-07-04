import AppKit
import SwiftUI
import DragonKit

// Uninstall pane (Liquid Glass §5A): confirms INLINE in the settings pane — no
// separate window. DragonKit's `UninstallSettingsPane` can't express ClipMenu's
// extra, default-off "Also delete clipboard history and snippets" choice, so this
// app-owned pane renders the same inline confirmation with that toggle added,
// performs the app-specific cleanup, then hands the shared teardown (login item,
// defaults domains, preference plists, Trash, quit) to `DragonUninstaller`.

struct UninstallPane: SettingsPane {
    let id = "uninstall"
    let title = "Uninstall"
    let systemImage = "trash"
    /// Navigate back to another pane instead of uninstalling.
    let onCancel: () -> Void

    var paneBody: some View { UninstallPaneView(onCancel: onCancel) }
}

private struct UninstallPaneView: View {
    let onCancel: () -> Void
    @State private var deleteUserData = false

    private var appName: String { MainMenuController.canonicalName }

    var body: some View {
        DragonForm {
            DragonSection {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: L("Uninstall %@?"), appName))
                        .font(.headline)
                    Text(String(format: L("%@ will quit and remove itself completely. This will delete:"), appName))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        checkRow(L("The app and its login item"))
                        checkRow(L("All preferences and actions"))
                        checkRow(L("Caches and support files"))
                    }

                    Toggle(L("Also delete clipboard history and snippets"), isOn: $deleteUserData)
                        .toggleStyle(.switch)

                    Text(L("Accessibility and clipboard permissions are removed by macOS in System Settings, not by this app. This cannot be undone."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(role: .destructive) { uninstall() } label: {
                            Text(L("Uninstall"))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        Button(L("Cancel")) { onCancel() }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func checkRow(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    /// App-specific teardown first (Application Support data, caches — things the
    /// shared uninstaller can't know about), then `DragonUninstaller.run`, which
    /// unregisters the login item, wipes the defaults domain + preference plists,
    /// moves the app to the Trash, and quits. Best-effort throughout so a single
    /// failure (e.g. a locked file) can't strand the user with a half-uninstalled
    /// app that never quits.
    private func uninstall() {
        let fm = FileManager.default
        let folder = AppStore.folder

        if deleteUserData {
            // Everything: history + snippet stores, actions.plist, user scripts, and
            // the pre-2.3 plaintext backup store (all under this folder).
            do { try fm.removeItem(at: folder) }
            catch { NSLog("Uninstall: failed to remove Application Support dir: \(error)") }
        } else {
            // Keep the user's clipboard history + snippets; remove only support files.
            try? fm.removeItem(at: folder.appending(path: "actions.plist"))
            try? fm.removeItem(at: folder.appending(path: "script"))
        }

        // Caches + transient state (always).
        let id = Bundle.main.bundleIdentifier ?? "com.dragonapp.clipmenu-2"
        let library = fm.homeDirectoryForCurrentUser.appending(path: "Library")
        try? fm.removeItem(at: library.appending(path: "Caches/\(id)"))
        try? fm.removeItem(at: library.appending(path: "HTTPStorages/\(id)"))

        DragonUninstaller.run(config: UninstallConfig(
            appName: appName,
            checklistItems: [
                L("The app and its login item"),
                L("All preferences and actions"),
                L("Caches and support files"),
            ]))
    }
}
