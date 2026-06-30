import AppKit
import SwiftUI

// Standardized Uninstall confirmation (Liquid Glass §5A). A destructive sheet that
// names exactly what it removes, with a default-off toggle to ALSO delete the
// user's clipboard history + snippets. Buttons: Uninstall (red, destructive, LEFT)
// and Cancel (the default, RIGHT) so Return/Esc both land on the safe choice.

/// Hosts `UninstallView` in a small window (ClipMenu is an LSUIElement agent, so a
/// SwiftUI sheet needs a host window — same pattern as `SettingsWindowController`).
@MainActor
final class UninstallWindowController {
    static let shared = UninstallWindowController()
    private var window: NSWindow?

    /// Present the confirmation. `onConfirm(deleteUserData)` runs only if the user
    /// chooses Uninstall.
    func present(appName: String, onConfirm: @escaping (Bool) -> Void) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = UninstallView(
            appName: appName,
            onCancel: { [weak self] in self?.window?.close() },
            onUninstall: { [weak self] deleteUserData in
                self?.window?.close()
                onConfirm(deleteUserData)
            })
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable]
        win.title = ""
        win.isReleasedWhenClosed = false
        win.center()
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

struct UninstallView: View {
    let appName: String
    let onCancel: () -> Void
    let onUninstall: (Bool) -> Void

    @State private var deleteUserData = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 9))
                Text(String(format: L("Uninstall %@?"), appName))
                    .font(.title2).bold()
            }

            Text(String(format: L("%@ will quit and remove itself completely. This will delete:"), appName))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                checkRow(L("The app and its login item"))
                checkRow(L("All preferences and actions"))
                checkRow(L("Caches and support files"))
            }

            Toggle(L("Also delete clipboard history and snippets"), isOn: $deleteUserData)
                .toggleStyle(.switch)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

            Text(L("Accessibility and clipboard permissions are removed by macOS in System Settings, not by this app. This cannot be undone."))
                .font(.caption).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(role: .destructive) { onUninstall(deleteUserData) } label: {
                    Text(L("Uninstall")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button(L("Cancel")) { onCancel() }
                    .keyboardShortcut(.defaultAction)   // Return/Esc → the safe choice
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 420)
    }

    private func checkRow(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}
