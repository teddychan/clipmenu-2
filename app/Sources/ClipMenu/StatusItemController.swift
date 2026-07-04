import AppKit

// Owns the menu-bar NSStatusItem and its menu.
// Legacy MenuController
// status-item code, MenuController.m:1236-1316). The status item displays the
// Main menu (MenuController.m:1314); the 13 icon styles are a later row.

@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?

    func install(menu: NSMenu) {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Give the item a stable, named autosave identity (Apple's recommendation)
        // rather than AppKit's auto-generated "Item-0". macOS persists a status
        // item's menu-bar position under "NSStatusItem Preferred Position <name>";
        // the anonymous "Item-0" slot can be left corrupted/off-screen by a
        // menu-bar manager (e.g. Ice) and then survives restarts, hiding the icon.
        // A named key isolates us from that stale state.
        //
        // The identity is namespaced by bundle id, not a shared constant. On macOS 26
        // "Allow in the Menu Bar" (System Settings › Control Center) keys an item's
        // show/hide state by this autosave name AND lists each item under its
        // "responsible" launching app. A debug build (com.dragonapp.clipmenu-2.debug)
        // that a coding agent compiles and runs gets its item attributed to that agent
        // (Codex, Claude Code, …); if it shared the release build's autosave name,
        // toggling the agent's row would also hide the installed release icon — because
        // both write the same shared show/hide flag. Per-bundle-id names keep release
        // and debug builds independent. Changing this string also forces macOS to
        // re-place the item fresh, escaping any stale/off-screen slot (the WindowServer's
        // menu-bar layout memory survives defaults deletes and ControlCenter restarts).
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dragonapp.clipmenu-2"
        item.autosaveName = "ClipMenuMainStatusItem-\(bundleID)"
        if let button = item.button {
            // Fall back to a text title if the icon can't be loaded, so the
            // status item never renders zero-width / invisible.
            if let image = Self.menuBarImage() {
                button.image = image
            } else {
                button.title = "✄"
            }
            button.toolTip = AppInfo.displayName
        }
        item.menu = menu
        statusItem = item
    }

    /// Swap the installed item's menu (e.g. rebuilt with new localized titles
    /// after a live language change). No-op when the item isn't installed.
    func update(menu: NSMenu) {
        statusItem?.menu = menu
    }

    /// The bundled menu-bar icon (paperlist clipboard): a vector PDF template
    /// drawn at the standard 18pt status-bar height. A PDF keeps the glyph crisp
    /// at any display scale (Apple's recommendation for status items); template
    /// mode lets macOS tint it for light/dark menu bars and the highlighted state.
    private static func menuBarImage() -> NSImage? {
        guard let url = AppResources.bundle.url(forResource: "MenuBarIcon", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
