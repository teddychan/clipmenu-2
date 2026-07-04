import AppKit
import DragonKit

/// The search field shown as the top item of the History menu (⌘⌃V), letting the
/// user type to filter the clipboard history live. It lives in its own NSView so
/// it can be set as an `NSMenuItem.view`, and reports each keystroke through
/// `onChange`.
///
/// NSMenu has no built-in "filter as you type" affordance, so the History menu
/// embeds this view at the top and rebuilds the clip rows below it on every edit
/// (see `MainMenuController.historyQueryDidChange`). The view instance is reused
/// across rebuilds so the field keeps key focus while the user is typing.
@MainActor
final class HistorySearchFieldView: NSView, NSSearchFieldDelegate {
    private let field = NSSearchField()

    /// Called on every edit with the current (untrimmed) query text.
    var onChange: ((String) -> Void)?

    /// Sized to a typical menu width; the menu stretches the row to fit anyway.
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        field.translatesAutoresizingMaskIntoConstraints = false
        field.delegate = self
        // Fire the delegate per keystroke (not only on Return) so filtering is live.
        field.sendsWholeSearchString = false
        field.sendsSearchStringImmediately = true
        field.placeholderString = L("Search…")
        field.focusRingType = .none
        addSubview(field)
        NSLayoutConstraint.activate([
            // Indent to clear the menu's icon gutter; trailing inset matches.
            field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            field.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Empty the field — called each time the menu opens so search starts fresh.
    func reset() { field.stringValue = "" }

    /// Make the field key so typing goes to it as soon as the menu opens. The
    /// host menu runs in a tracking run-loop mode; calling this once the menu's
    /// window exists routes keystrokes here instead of to type-select.
    func focus() { window?.makeFirstResponder(field) }

    func controlTextDidChange(_ obj: Notification) {
        onChange?(field.stringValue)
    }
}
