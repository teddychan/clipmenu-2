import AppKit
import Testing
@testable import ClipMenu

// Characterization tests for StatusItemController. NSStatusItem can be
// constructed in the test process without a running app, so these exercise the
// install / update lifecycle and its guard clauses. There is no public getter
// for the underlying item, so the assertions are that the documented behavior
// (idempotent install, no-op update before install) runs without crashing.
@MainActor
@Suite struct StatusItemControllerCoverageTests {

    @Test func updateBeforeInstallIsANoOp() {
        let controller = StatusItemController()
        // statusItem is nil, so this must not crash.
        controller.update(menu: NSMenu())
    }

    @Test func installAttachesAMenu() {
        let controller = StatusItemController()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "History", action: nil, keyEquivalent: ""))
        controller.install(menu: menu)
        // A second install is guarded and must be an inert no-op (no second
        // status item created, no crash).
        controller.install(menu: NSMenu())
    }

    @Test func updateAfterInstallSwapsTheMenu() {
        let controller = StatusItemController()
        controller.install(menu: NSMenu())
        let replacement = NSMenu()
        replacement.addItem(NSMenuItem(title: "Snippets", action: nil, keyEquivalent: ""))
        controller.update(menu: replacement)
    }
}
