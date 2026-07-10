import AppKit
import Testing
@testable import ClipMenu

// Characterization tests for HistorySearchFieldView, the NSSearchField wrapper
// embedded at the top of the History menu. The view can be constructed
// headlessly; these pin its initial geometry and the keystroke-forwarding
// contract (controlTextDidChange → onChange with the field's current text).
@MainActor
@Suite struct HistorySearchFieldCoverageTests {

    @Test func initialGeometryAndNoHandler() {
        let view = HistorySearchFieldView()
        #expect(view.frame.width == 240)
        #expect(view.frame.height == 28)
        #expect(view.onChange == nil)
        // The wrapped search field is the sole subview.
        #expect(view.subviews.count == 1)
        #expect(view.subviews.first is NSSearchField)
    }

    @Test func resetAndFocusDoNotCrashWithoutAWindow() {
        let view = HistorySearchFieldView()
        view.reset()
        view.focus() // window is nil → makeFirstResponder is a no-op
    }

    @Test func editForwardsCurrentTextToOnChange() {
        let view = HistorySearchFieldView()
        let field = try! #require(view.subviews.first as? NSSearchField)

        var received: String?
        view.onChange = { received = $0 }

        field.stringValue = "hello"
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(received == "hello")

        view.reset()
        view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(received == "")
    }
}
