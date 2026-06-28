import AppKit
import SwiftUI
import SwiftData

// Self-managed Snippet Editor window. Same rationale as SettingsWindowController:
// an LSUIElement agent can't open a SwiftUI scene programmatically, so the
// SnippetEditorView is hosted in a plain NSWindow. Maps to the legacy
// SnippetEditorController window (SnippetEditorController.m showWindow).
//
// Undo: the legacy editor returns the managed-object
// context's undo manager from windowWillReturnUndoManager:
// (SnippetEditorController.m:297-302). We mirror that — enable undo on the
// shared SwiftData context and hand the window that same UndoManager, so the
// Edit ▸ Undo/Redo items (AppDelegate.installMainMenu) operate on snippet edits.
// Clipboard capture uses a separate ModelActor context, so this undo stack only
// tracks edits made in this window.

@MainActor
final class SnippetEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = SnippetEditorWindowController()

    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        if AppStore.container.mainContext.undoManager == nil {
            AppStore.container.mainContext.undoManager = UndoManager()
        }

        if window == nil {
            let hosting = NSHostingController(
                rootView: SnippetEditorView().modelContainer(AppStore.container)
            )
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = L("Snippets")
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
        }

        // An LSUIElement (accessory) app can't be the target of the system
        // Character/Emoji viewer: it inserts the emoji's *name* in brackets
        // (e.g. "[Facepalm]") instead of the glyph. Become a regular foreground
        // app while the editor is open so emoji input works, then revert on close
        // (windowWillClose) to stay a menu-bar agent the rest of the time.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// True while the editor window is on screen.
    var isWindowVisible: Bool { window?.isVisible ?? false }

    /// Revert to the menu-bar-agent activation policy once the editor closes
    /// (the `.regular` policy in `show()` is only needed while it's open) —
    /// but not while the Settings window is still open, or it would lose focus
    /// and drop out of Cmd-Tab mid-use.
    func windowWillClose(_ notification: Notification) {
        if !SettingsWindowController.shared.isWindowVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Route window-level Undo/Redo to the SwiftData context's undo manager
    /// (SnippetEditorController.m:297-302).
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        AppStore.container.mainContext.undoManager
    }
}
