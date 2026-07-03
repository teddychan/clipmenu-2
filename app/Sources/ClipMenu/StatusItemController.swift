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
        item.autosaveName = "ClipMenuMainStatusItem"
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
