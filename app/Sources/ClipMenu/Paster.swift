import AppKit
import ApplicationServices

// Copy a clip/snippet back to the pasteboard and paste it into the frontmost app.
// Maps to ARCHITECTURE.md `Paster`; legacy ClipsController.m:503-566 (copy*) +
// CMUtilities.m:95-172 (paste / postCommandV) + AppController.m:493-528.
//
// Modern-OS reality (CLAUDE.md §6): synthesizing ⌘V needs Accessibility (TCC).
// We check AXIsProcessTrusted() and prompt to enable it rather than fail
// silently. The ⌘V key event (keycode 9 = V, .maskCommand) is posted to
// .cghidEventTap. Legacy did not restore the previous pasteboard, so neither
// do we — the selected clip stays on the pasteboard (and re-sorts to the top
// via de-dup, matching legacy).

@MainActor
enum Paster {
    /// The deprecated multi-path filenames pasteboard type (still honored by macOS
    /// for compatibility); legacy used NSFilenamesPboardType (an array of paths).
    private static let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    /// Write all of a clip's representations to the general pasteboard
    /// (ClipsController.m:510-560).
    static func copy(_ clip: ClipRecord) {
        let pboard = NSPasteboard.general
        let offered = offeredTypeNames(for: clip.typeIdentifiers)
        let types = offered.compactMap(pasteboardType(forName:))
        pboard.declareTypes(types, owner: nil)

        let names = Set(offered)
        if names.contains("String"), let value = clip.stringValue {
            pboard.setString(value, forType: .string)
        }
        if names.contains("RTFD"), let data = clip.rtfData {
            pboard.setData(data, forType: .rtfd)
        }
        if names.contains("RTF"), let data = clip.rtfData {
            pboard.setData(data, forType: .rtf)
        }
        if names.contains("PDF"), let data = clip.pdfData {
            pboard.setData(data, forType: .pdf)
        }
        if names.contains("Filenames"), let filenames = clip.filenames {
            pboard.setPropertyList(filenames, forType: filenamesType)
        }
        if names.contains("URL"), let urlString = clip.urlString {
            pboard.setString(urlString, forType: .URL)
        }
        if names.contains("TIFF"), let data = clip.image?.data {
            pboard.setData(data, forType: .tiff)
        }
    }

    /// The types a clip can faithfully offer on paste. A clip stores ONE
    /// rich-text blob, and capture prefers RTFD when both RTF and RTFD were on
    /// the source pasteboard (ClipCapture: "RTFD wins") — flat-RTFD bytes are
    /// not valid RTF, so when RTFD is present the RTF type is dropped rather
    /// than declared with the wrong payload.
    static func offeredTypeNames(for typeIdentifiers: [String]) -> [String] {
        typeIdentifiers.contains("RTFD")
            ? typeIdentifiers.filter { $0 != "RTF" }
            : typeIdentifiers
    }

    /// Write a plain string (snippet content) — ClipsController.m:503-508.
    static func copy(string: String) {
        let pboard = NSPasteboard.general
        pboard.declareTypes([.string], owner: nil)
        pboard.setString(string, forType: .string)
    }

    /// Write a styled (RTF/RTFD) clip produced by a JS action's ScriptableClip
    /// (ActionController.m:809-811 copyClipToPasteboard of the result clip).
    static func copy(rtfData: Data, isRTFD: Bool) {
        let pboard = NSPasteboard.general
        let type: NSPasteboard.PasteboardType = isRTFD ? .rtfd : .rtf
        pboard.declareTypes([type], owner: nil)
        pboard.setData(rtfData, forType: type)
    }

    /// Synthesize ⌘V into the frontmost app, when inputPasteCommand is on
    /// (default YES, AppController.m:133). Returns false if paste was skipped
    /// (App Store/sandboxed build, pref off, or Accessibility not granted).
    @discardableResult
    static func paste() -> Bool {
        // The App Store (sandboxed) build cannot post synthetic key events into
        // other apps; never attempt it. The inputPasteCommand pref can arrive
        // `true` via iCloud settings sync from a direct-build install, so this
        // guard — not just the disabled Settings toggle — is what guarantees we
        // don't try a sandbox-blocked CGEvent post.
        guard DistributionChannel.current == .direct else { return false }
        guard UserDefaults.standard.object(forKey: PreferenceKeys.inputPasteCommand) as? Bool ?? true else {
            return false
        }
        guard ensureAccessibilityTrusted() else { return false }
        return postCommandV()
    }

    /// True if trusted for Accessibility; otherwise shows the system prompt
    /// (CLAUDE.md §6) and returns false for this attempt.
    private static func ensureAccessibilityTrusted() -> Bool {
        if AXIsProcessTrusted() { return true }
        // Use the documented key value directly; referencing the imported C
        // global `kAXTrustedCheckOptionPrompt` is rejected under Swift 6 strict
        // concurrency (mutable global). Value is stable.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private static func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    private static func pasteboardType(forName name: String) -> NSPasteboard.PasteboardType? {
        switch name {
        case "String":    return .string
        case "RTF":       return .rtf
        case "RTFD":      return .rtfd
        case "PDF":       return .pdf
        case "Filenames": return filenamesType
        case "URL":       return .URL
        case "TIFF":      return .tiff
        default:          return nil
        }
    }
}
