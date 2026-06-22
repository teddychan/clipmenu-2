import Testing
import Carbon.HIToolbox
@testable import ClipMenu

// Rebinding must reject a combo already assigned to another menu hot-key:
// Carbon registers both non-exclusively, so one keystroke would pop both
// menus back-to-back.

@Suite @MainActor
struct HotKeyRebindTests {

    private let combos: [MainMenuController.MenuHotKey: HotKeyCenter.Combo] = [
        .main: .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)),
        .history: .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | controlKey)),
        .snippets: .init(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(cmdKey | shiftKey)),
    ]

    @Test func comboBoundToAnotherMenuConflicts() {
        let mainCombo = combos[.main]!
        let conflict = MainMenuController.conflictingHotKey(
            for: mainCombo, excluding: .history) { combos[$0]! }
        #expect(conflict == .main)
    }

    @Test func reassigningTheSameMenuItsOwnComboIsAllowed() {
        let mainCombo = combos[.main]!
        let conflict = MainMenuController.conflictingHotKey(
            for: mainCombo, excluding: .main) { combos[$0]! }
        #expect(conflict == nil)
    }

    @Test func freshComboDoesNotConflict() {
        let fresh = HotKeyCenter.Combo(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey))
        let conflict = MainMenuController.conflictingHotKey(
            for: fresh, excluding: .history) { combos[$0]! }
        #expect(conflict == nil)
    }
}
