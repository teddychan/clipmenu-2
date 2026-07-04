import AppKit

// Owns the menu-bar NSStatusItem and its menu.
// Legacy MenuController
// status-item code, MenuController.m:1236-1316). The status item displays the
// Main menu (MenuController.m:1314); the 13 icon styles are a later row.

@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    private var visibilityObservation: NSKeyValueObservation?

    func install(menu: NSMenu) {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Give the item a stable, named autosave identity (Apple's recommendation)
        // rather than AppKit's auto-generated "Item-0". macOS persists a status
        // item's menu-bar position under "NSStatusItem Preferred Position <name>";
        // anonymous "Item-N" slots can be left corrupted/off-screen by macOS menu
        // bar customization state and then survive restarts, hiding the icon. A
        // named key isolates us from that stale state.
        //
        // The name is versioned: on macOS 26 the WindowServer's own menu-bar layout
        // memory (separate from the app's prefs, and NOT cleared by deleting the
        // "NSStatusItem Preferred Position" default, quitting menu-bar managers, or
        // restarting ControlCenter/SystemUIServer) can pin a name to an off-screen
        // slot that no reset recovers. Bumping the identity is the only reliable way
        // to force macOS to place the item fresh in the normal zone. Reset the
        // automatically chosen anonymous name first so any stale visibility tied
        // to it is cleared before we assign ClipMenu's stable identity.
        item.autosaveName = nil
        item.autosaveName = "ClipMenuMainStatusItemV3"
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
        item.isVisible = true
        statusItem = item
        visibilityObservation = item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            Task { @MainActor [weak self] in
                self?.restoreVisibilityIfNeeded()
            }
        }
    }

    /// Swap the installed item's menu (e.g. rebuilt with new localized titles
    /// after a live language change). No-op when the item isn't installed.
    func update(menu: NSMenu) {
        statusItem?.menu = menu
        statusItem?.isVisible = true
    }

    /// Remove the status item when the user chooses the legacy "None" style.
    func remove() {
        guard let statusItem else { return }
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func restoreVisibilityIfNeeded() {
        let shouldShow = UserDefaults.standard.object(forKey: PreferenceKeys.showStatusItem) as? Int ?? 1
        guard shouldShow != 0, statusItem?.isVisible == false else { return }
        statusItem?.isVisible = true
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
