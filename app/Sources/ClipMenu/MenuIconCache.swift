import AppKit
import UniformTypeIdentifiers

// Per-type menu icons. Maps to ARCHITECTURE.md `MenuIconCache`; legacy icon
// system MenuController.m:1333-1483 + Clip.m:144-189 (fileTypeIconForPboardType).
//
// MODERNIZATION (OQ#9, user decision 2026-05-31): the legacy icons come from the
// obsolete `NSWorkspace iconForFileType:` with HFS type codes ('TEXT','clpu',
// 'gurl') / extensions per a per-type config. Those APIs/icons don't exist on
// modern macOS, so each of the 7 live types maps to a representative `UTType`
// and we use `NSWorkspace.icon(for:)`. The legacy per-type code/extension config
// is dropped for now and will be revisited with the §J Type preferences pane.
//
// Icons are cached and only rebuilt when menuIconSize changes (legacy cached the
// same set in _resetIconCaches, rebuilt on prefs close).

@MainActor
final class MenuIconCache {
    private var size: Int = 0
    private var typeIcons: [String: NSImage] = [:]
    private var cachedFolderIcon: NSImage?
    private var cachedSnippetIcon: NSImage?
    private var cachedActionIcon: NSImage?
    private var cachedJavaScriptIcon: NSImage?

    /// Icon for a clip whose primary type has the given legacy name
    /// (String/RTF/RTFD/PDF/Filenames/URL/TIFF).
    func icon(forTypeName name: String?) -> NSImage? {
        refreshIfNeeded()
        guard let name, let type = Self.utType(forName: name) else { return nil }
        if let cached = typeIcons[name] { return cached }
        let icon = sizedIcon(for: type)
        typeIcons[name] = icon
        return icon
    }

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

    /// Built-in action icon (legacy `actionIcon`). Modern SF Symbol per OQ#12
    /// (single modern style instead of the 2008 bitmaps).
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
        typeIcons.removeAll()
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

    private static func utType(forName name: String) -> UTType? {
        switch name {
        case "String":    return .plainText
        case "RTF":       return .rtf
        case "RTFD":      return UTType("com.apple.rtfd") ?? .rtf
        case "PDF":       return .pdf
        case "Filenames": return .folder
        case "URL":       return .url
        case "TIFF":      return .tiff
        default:          return nil
        }
    }
}
