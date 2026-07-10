import Testing
import Foundation
import AppKit
import Carbon.HIToolbox
@testable import ClipMenu

// Characterization of the Shortcuts-pane hot-key recorder (ShortcutRecorderView).
// Covers the pure Carbon⇄Cocoa formatter helpers and the deterministic,
// headless-safe corners of ShortcutRecorderControl (init, first-responder,
// non-recording keyDown, drawing). The recording keyDown/mouseDown paths mutate
// the process-wide MainMenuController/HotKeyCenter singletons (real Carbon
// RegisterEventHotKey), so they are left uncovered here.
//
// SERIALIZED at the parent level (applies to nested suites too): several helpers
// call the Text Input Source / UCKeyTranslate keyboard-layout APIs, which are not
// thread-safe — running two such tests in parallel aborts the process. This suite
// holds every TIS-touching test so none of them ever run concurrently.
@Suite(.serialized)
struct ShortcutRecorderViewCoverageTests {

    @Suite struct KeyComboFormatterTests {

        @Test func carbonModifiersMapEachCocoaFlag() {
            #expect(KeyComboFormatter.carbonModifiers(from: []) == 0)
            #expect(KeyComboFormatter.carbonModifiers(from: .command) == UInt32(cmdKey))
            #expect(KeyComboFormatter.carbonModifiers(from: .shift) == UInt32(shiftKey))
            #expect(KeyComboFormatter.carbonModifiers(from: .option) == UInt32(optionKey))
            #expect(KeyComboFormatter.carbonModifiers(from: .control) == UInt32(controlKey))
        }

        @Test func carbonModifiersCombineFlags() {
            let all: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
            #expect(KeyComboFormatter.carbonModifiers(from: all)
                    == UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey))
            #expect(KeyComboFormatter.carbonModifiers(from: [.command, .shift])
                    == UInt32(cmdKey | shiftKey))
            // Non-hot-key flags (e.g. .function / .capsLock) contribute nothing.
            #expect(KeyComboFormatter.carbonModifiers(from: [.function, .capsLock]) == 0)
        }

        @Test func displayStringOrdersModifierGlyphsControlOptionShiftCommand() {
            let mods = UInt32(controlKey | optionKey | shiftKey | cmdKey)
            let combo = HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: mods)
            let s = KeyComboFormatter.displayString(for: combo)
            // macOS glyph order: ⌃⌥⇧⌘ then the key character.
            #expect(s.hasPrefix("⌃⌥⇧⌘"))
            #expect(s.count > 4)   // at least the four glyphs + a key (or "?")
        }

        @Test func displayStringSingleModifier() {
            let combo = HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey))
            let s = KeyComboFormatter.displayString(for: combo)
            #expect(s.hasPrefix("⌘"))
            #expect(!s.contains("⌃"))
            #expect(!s.contains("⇧"))
        }

        @Test func keyStringIsNilOrUppercased() {
            // Layout-dependent (TIS): don't pin the exact glyph, only that a non-nil
            // result is already uppercased (draw() relies on this) and never crashes.
            let s = KeyComboFormatter.keyString(forKeyCode: UInt32(kVK_ANSI_V))
            #expect(s == nil || s == s?.uppercased())
        }
    }

    @Suite @MainActor struct ShortcutRecorderControlCoverageTests {

        @Test func initStoresComboAndWantsLayer() {
            let combo = HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
            let control = ShortcutRecorderControl(combo: combo)
            #expect(control.combo == combo)
            #expect(control.wantsLayer)
            #expect(control.acceptsFirstResponder)
        }

        @Test func settingComboUpdatesValue() {
            let control = ShortcutRecorderControl(
                combo: .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey)))
            let next = HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | optionKey))
            control.combo = next
            #expect(control.combo == next)
        }

        @Test func resignFirstResponderReturnsTrueWhenNotRecording() {
            // Not recording ⇒ the isRecording setter's guard short-circuits before it
            // would touch the menu hot-keys, so this is a safe headless no-op.
            let control = ShortcutRecorderControl(
                combo: .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey)))
            #expect(control.resignFirstResponder())
        }

        @Test func keyDownWhileNotRecordingLeavesComboUnchanged() throws {
            let combo = HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey))
            let control = ShortcutRecorderControl(combo: combo)
            let event = try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "b", charactersIgnoringModifiers: "b",
                isARepeat: false, keyCode: UInt16(kVK_ANSI_B)))
            // Not recording ⇒ keyDown falls through to super and must not capture.
            control.keyDown(with: event)
            #expect(control.combo == combo)
        }

        @Test func drawRendersWithoutCrashing() {
            let control = ShortcutRecorderControl(
                combo: .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)))
            control.frame = NSRect(x: 0, y: 0, width: 120, height: 24)
            // Exercise draw() in an offscreen context (isRecording == false, feedback
            // nil ⇒ the current-shortcut display path, which calls displayString → TIS).
            let image = NSImage(size: control.bounds.size)
            image.lockFocus()
            control.draw(control.bounds)
            image.unlockFocus()
            #expect(control.bounds.width == 120)
        }
    }
}
