import AppKit
import SwiftUI

// Self-managed Settings window.
//
// ClipMenu is an LSUIElement agent, so SwiftUI does not install an app main
// menu and `NSApp.sendAction("showSettingsWindow:")` has no responder in the
// chain — the SwiftUI `Settings` scene can't be opened programmatically. We
// host the same `SettingsView` in an ordinary NSWindow instead, which works
// regardless of activation policy. (Maps to the legacy DBPrefsWindowController
// preferences window; PrefsWindowController.m:505-517 showWindow + activate.)

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// True while the Settings window is on screen.
    var isWindowVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView().modelContainer(AppStore.container)
            )
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = String(format: L("%@ Settings"), AppInfo.displayName)
            // Resizable so panes that don't fit can be enlarged; the grouped
            // Forms scroll when the window is smaller than their content.
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self

            // Open large enough for the tallest pane (Menu), but never taller
            // than the screen's usable height (leave a margin for the menu bar).
            let desired = NSSize(width: 560, height: 640)
            let visibleHeight = (newWindow.screen ?? NSScreen.main)?.visibleFrame.height ?? desired.height
            let height = max(420, min(desired.height, visibleHeight - 40))
            newWindow.setContentSize(NSSize(width: desired.width, height: height))
            newWindow.center()
            window = newWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// If the Snippet editor promoted the app to `.regular` and is now closed,
    /// closing Settings must hand the menu-bar-agent policy back — otherwise
    /// the app would keep a Dock icon after both windows are gone.
    func windowWillClose(_ notification: Notification) {
        if !SnippetEditorWindowController.shared.isWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
