import Testing
import Foundation
@testable import ClipMenu

// Characterization tests for SettingsWindowController's headlessly-reachable
// surface: the process singleton, and the host-owned pane Selection (which is
// the only piece that reads/writes UserDefaults and does not touch a window or
// SwiftUI). The DragonKit-backed window itself (title, activation-policy flips,
// show/close, isWindowVisible) needs a running NSApplication + SwiftUI body
// evaluation, so it is exercised at runtime, not here — see COVERAGE NOTES.
//
// Serialized + save/restore because Selection persists to
// UserDefaults.standard[settingsSelectedTab].
@MainActor
@Suite(.serialized)
struct SettingsWindowControllerCoverageTests {

    @Test func sharedIsAStableSingleton() {
        #expect(SettingsWindowController.shared === SettingsWindowController.shared)
    }

    @Test func selectionDefaultsToGeneralWhenUnset() {
        let key = PreferenceKeys.settingsSelectedTab
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.removeObject(forKey: key)
        let selection = SettingsWindowController.Selection()
        #expect(selection.paneID == "general")
    }

    @Test func selectionReadsThePersistedPane() {
        let key = PreferenceKeys.settingsSelectedTab
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("menu", forKey: key)
        let selection = SettingsWindowController.Selection()
        #expect(selection.paneID == "menu")
    }

    @Test func settingPaneIDPersistsIt() {
        let key = PreferenceKeys.settingsSelectedTab
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        let selection = SettingsWindowController.Selection()
        selection.paneID = "about"
        #expect(UserDefaults.standard.string(forKey: key) == "about")
    }

    // Assigning nil does NOT persist (the didSet only writes non-nil values), so
    // the previously persisted pane survives — reopening lands on the last real
    // pane rather than an empty selection.
    @Test func settingPaneIDToNilLeavesPersistedValueUntouched() {
        let key = PreferenceKeys.settingsSelectedTab
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("shortcuts", forKey: key)
        let selection = SettingsWindowController.Selection()
        selection.paneID = nil
        #expect(UserDefaults.standard.string(forKey: key) == "shortcuts")
    }
}
