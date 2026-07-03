import SwiftUI
import DragonKit
import AppKit
import Carbon.HIToolbox

// Hot-key capture control for the Shortcuts preferences pane.
// Replaces the legacy ShortcutRecorder framework / SRRecorderControl
// (PrefsWindowController.m:556-613). Captures one key + modifiers, converts to
// Carbon keyCode + modifier mask (the values RegisterEventHotKey and the legacy
// `hotKeys` plist use), and asks MainMenuController to rebind + re-register live.
//
// A modifier is required (matches the legacy recorder, which rejects bare keys);
// Escape cancels recording.

// MARK: - Carbon ⇄ Cocoa helpers

enum KeyComboFormatter {
    /// Cocoa modifier flags → Carbon modifier mask (cmdKey/shiftKey/optionKey/controlKey).
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift)   { mask |= UInt32(shiftKey) }
        if flags.contains(.option)  { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// Human-readable combo, e.g. "⌘⇧V". Modifier glyph order matches macOS.
    static func displayString(for combo: HotKeyCenter.Combo) -> String {
        var s = ""
        if combo.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if combo.modifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if combo.modifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if combo.modifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        s += keyString(forKeyCode: combo.keyCode) ?? "?"
        return s
    }

    /// Key character for a virtual key code via the current keyboard layout.
    /// Port of legacy CMUtilities.m:56-93 (`transformKeyCode`). Display-only:
    /// returns nil on failure (the combo still binds correctly).
    static func keyString(forKeyCode keyCode: UInt32) -> String? {
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }

        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var realLength = 0
        let status = bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &realLength,
                &chars
            )
        }
        guard status == noErr, realLength > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: realLength).uppercased()
    }
}

// MARK: - AppKit recorder control

@MainActor
final class ShortcutRecorderControl: NSView {
    var combo: HotKeyCenter.Combo { didSet { needsDisplay = true } }
    /// Returns whether the rebind was accepted (false: combo already bound to
    /// another menu, or Carbon refused it). On false the control keeps the
    /// previous combo and beeps.
    var onCapture: ((HotKeyCenter.Combo) -> Bool)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
            guard oldValue != isRecording else { return }
            // A registered Carbon hot-key consumes its keystroke system-wide
            // (the app receives kEventHotKeyPressed, not keyDown), so a
            // currently-bound combo could never be recorded. Pause the menu
            // hot-keys for the duration of recording.
            MainMenuController.shared.setMenuHotKeysSuspended(isRecording)
        }
    }

    init(combo: HotKeyCenter.Combo) {
        self.combo = combo
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isRecording = true
        window?.makeFirstResponder(self)
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // If the Settings window closes mid-recording, make sure the global
        // hot-keys come back.
        if window == nil { isRecording = false }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            return
        }

        let modifiers = KeyComboFormatter.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep() // legacy recorder requires a modifier
            return
        }

        let newCombo = HotKeyCenter.Combo(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        isRecording = false
        if onCapture?(newCombo) == true {
            combo = newCombo
        } else {
            NSSound.beep() // rejected: duplicate of another menu's combo, or Carbon refused it
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()

        let text = isRecording
            ? L("Type shortcut…")
            : KeyComboFormatter.displayString(for: combo)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2,
                            y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}

// MARK: - SwiftUI wrapper

struct ShortcutRecorder: NSViewRepresentable {
    let hotKey: MainMenuController.MenuHotKey

    func makeNSView(context: Context) -> ShortcutRecorderControl {
        let view = ShortcutRecorderControl(combo: MainMenuController.shared.currentCombo(for: hotKey))
        view.onCapture = { combo in
            MainMenuController.shared.rebind(hotKey, to: combo)
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderControl, context: Context) {
        nsView.combo = MainMenuController.shared.currentCombo(for: hotKey)
    }
}
