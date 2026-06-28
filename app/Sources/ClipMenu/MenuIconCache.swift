import AppKit
import UniformTypeIdentifiers

// Menu icons for folders, snippets, and actions (the menu does not show
// per-clip-type icons). Legacy icon system MenuController.m:1333-1483.
//
// Folder/snippet icons come from `NSWorkspace.icon(for:)` on a representative
// `UTType`; the action/JavaScript icons are SF Symbols (a single modern style
// instead of the 2008 bitmaps).
//
// Icons are cached and only rebuilt when menuIconSize changes (legacy cached the
// same set in _resetIconCaches, rebuilt on prefs close).

@MainActor
final class MenuIconCache {
    private var size: Int = 0
    private var cachedFolderIcon: NSImage?
    private var cachedSnippetIcon: NSImage?
    private var cachedActionIcon: NSImage?
    private var cachedJavaScriptIcon: NSImage?

    /// Closed-folder icon for overflow ("N - M") and snippet folder submenus
    /// (legacy _cacheFolderIcon, kGenericFolderIcon).
    var folderIcon: NSImage {
        refreshIfNeeded()
        if let cachedFolderIcon { return cachedFolderIcon }
        let icon = sizedIcon(for: .folder)
        cachedFolderIcon = icon
        return icon
    }

    /// Snippet icon (legacy _cacheSnippetIcon, kClippingTextTypeIcon ≈ plain text).
    var snippetIcon: NSImage {
        refreshIfNeeded()
        if let cachedSnippetIcon { return cachedSnippetIcon }
        let icon = sizedIcon(for: .plainText)
        cachedSnippetIcon = icon
        return icon
    }

    /// Built-in action icon (legacy `actionIcon`). Modern SF Symbol
    /// (a single modern style instead of the 2008 bitmaps).
    var actionIcon: NSImage {
        refreshIfNeeded()
        if let cachedActionIcon { return cachedActionIcon }
        let icon = sizedSymbol("bolt")
        cachedActionIcon = icon
        return icon
    }

    /// JavaScript action icon (legacy `javaScriptIcon`).
    var javaScriptIcon: NSImage {
        refreshIfNeeded()
        if let cachedJavaScriptIcon { return cachedJavaScriptIcon }
        let icon = sizedSymbol("curlybraces")
        cachedJavaScriptIcon = icon
        return icon
    }

    // MARK: - Private

    private func refreshIfNeeded() {
        let current = UserDefaults.standard.object(forKey: PreferenceKeys.menuIconSize) as? Int ?? 16
        guard current != size else { return }
        size = current
        cachedFolderIcon = nil
        cachedSnippetIcon = nil
        cachedActionIcon = nil
        cachedJavaScriptIcon = nil
    }

    private func sizedSymbol(_ name: String) -> NSImage {
        let icon = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    private func sizedIcon(for type: UTType) -> NSImage {
        let icon = NSWorkspace.shared.icon(for: type)
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
