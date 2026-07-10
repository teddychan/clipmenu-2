import Testing
import Foundation
import Carbon.HIToolbox
@testable import ClipMenu

// Characterization tests for HotKeyCenter's pure/config surface: the Combo value
// type, the legacy default combos, and the stored-shortcut parse path. The
// Carbon RegisterEventHotKey path and its C event callback (kEventHotKeyPressed →
// handle(id:)) cannot be exercised deterministically headlessly — no real global
// keystroke is delivered in the test process — so we only assert that
// register/unregister/unregisterAll run without side effects (nothing fires), and
// document the callback dispatch itself as uncoverable.
@Suite @MainActor
struct HotKeyCenterCoverageTests {

    // MARK: Combo value type

    @Test func comboInitStoresFields() {
        let combo = HotKeyCenter.Combo(keyCode: 9, modifiers: UInt32(cmdKey | shiftKey))
        #expect(combo.keyCode == 9)
        #expect(combo.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test func comboEqualityAndHashing() {
        let a = HotKeyCenter.Combo(keyCode: 9, modifiers: 256)
        let b = HotKeyCenter.Combo(keyCode: 9, modifiers: 256)
        let c = HotKeyCenter.Combo(keyCode: 9, modifiers: 512)
        let d = HotKeyCenter.Combo(keyCode: 11, modifiers: 256)
        #expect(a == b)
        #expect(a != c)
        #expect(a != d)
        // Hashable: equal combos collapse in a Set, distinct ones don't.
        #expect(Set([a, b, c, d]).count == 3)
    }

    // MARK: Legacy default combos

    @Test func defaultCombosMatchLegacySchema() {
        #expect(MainMenuController.MenuHotKey.main.defaultCombo
                == HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)))
        #expect(MainMenuController.MenuHotKey.history.defaultCombo
                == HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)))
        #expect(MainMenuController.MenuHotKey.snippets.defaultCombo
                == HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | shiftKey)))
    }

    // MARK: register / unregister (no real keystroke ⇒ handler never fires)

    @Test func registerThenUnregisterIsAnInertLifecycle() {
        var fired = false
        let combo = HotKeyCenter.Combo(
            keyCode: UInt32(kVK_F19),
            modifiers: UInt32(cmdKey | controlKey | optionKey)
        )
        let id = HotKeyCenter.shared.register(combo) { fired = true }
        // Whether Carbon accepts the combo or not, unregister must be safe.
        if let id { HotKeyCenter.shared.unregister(id) }
        // Unregistering an id that was never registered is a no-op.
        HotKeyCenter.shared.unregister(999_999)
        HotKeyCenter.shared.unregisterAll()
        // No synthetic event is posted in the test process, so the action never runs.
        #expect(fired == false)
    }

    // MARK: Stored-shortcut parse/format (currentCombo ⇄ hotKeys defaults)

    @Suite(.serialized) @MainActor
    struct StoredComboTests {
        @Test func currentComboFallsBackToDefaultWhenNothingStored() {
            let key = PreferenceKeys.hotKeys
            let saved = UserDefaults.standard.dictionary(forKey: key)
            defer {
                if let saved { UserDefaults.standard.set(saved, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            UserDefaults.standard.removeObject(forKey: key)
            #expect(MainMenuController.shared.currentCombo(for: .main)
                    == MainMenuController.MenuHotKey.main.defaultCombo)
        }

        @Test func currentComboReadsStoredLegacyEntry() {
            let key = PreferenceKeys.hotKeys
            let saved = UserDefaults.standard.dictionary(forKey: key)
            defer {
                if let saved { UserDefaults.standard.set(saved, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            // Legacy plist schema: {identifier: {keyCode, modifiers}}.
            let stored: [String: Any] = [
                MainMenuController.MenuHotKey.history.rawValue: ["keyCode": 40, "modifiers": 4352],
            ]
            UserDefaults.standard.set(stored, forKey: key)
            #expect(MainMenuController.shared.currentCombo(for: .history)
                    == HotKeyCenter.Combo(keyCode: 40, modifiers: 4352))
        }
    }
}
