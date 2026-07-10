import Testing
import AppKit
@testable import ClipMenu

// Characterization coverage for ScriptableClipState directly (the existing
// ScriptableClipBridgeTests drive it only through the JS runner). Pins outcome
// selection and the change(_:mode:) attribute paths: empty-string / no-attrs
// early returns, color / font / underline application, set vs add, and the
// plain-string → RTF vs RTFD-source → RTFD result rule (ScriptableClip.swift).

@Suite struct ScriptableClipStateCoverageTests {

    private func rtfData(_ string: String) -> Data {
        let s = NSAttributedString(string: string)
        return s.rtf(from: NSRange(location: 0, length: s.length), documentAttributes: [:])!
    }

    private func rtfdData(_ string: String) -> Data {
        let s = NSAttributedString(string: string)
        return s.rtfd(from: NSRange(location: 0, length: s.length), documentAttributes: [:])!
    }

    @Test func outcomeIsStringWhenNoStylingApplied() {
        let state = ScriptableClipState(JSClipInput(stringValue: "hi"))
        #expect(state.outcome == .string("hi"))
    }

    @Test func emptyStringSkipsChangeAndStaysString() {
        let state = ScriptableClipState(JSClipInput(stringValue: ""))
        state.change(["color": ["foreground": "red"]], mode: .set)
        #expect(state.outcome == .string(""))
    }

    @Test func noRecognizedAttributesLeavesOutcomeUnchanged() {
        let state = ScriptableClipState(JSClipInput(stringValue: "keep me"))
        // Unresolvable color → attrs stays empty → guard returns before mutating.
        state.change(["color": ["foreground": "definitelynotacolor"]], mode: .set)
        #expect(state.outcome == .string("keep me"))

        // Unrelated keys are ignored entirely.
        state.change(["bogus": "value"], mode: .add)
        #expect(state.outcome == .string("keep me"))
    }

    @Test func colorOnPlainStringProducesRTFNotRTFD() throws {
        let state = ScriptableClipState(JSClipInput(stringValue: "Hello"))
        state.change(["color": ["foreground": "red", "background": "white"]], mode: .set)

        guard case .rtf(let data, let rtfd) = state.outcome else {
            Issue.record("expected .rtf, got \(state.outcome)"); return
        }
        #expect(rtfd == false)   // plain source → RTF, never RTFD
        let attr = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        let fg = (attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.genericRGB)
        #expect(fg?.redComponent == 1 && fg?.greenComponent == 0 && fg?.blueComponent == 0)
        let bg = (attr.attribute(.backgroundColor, at: 0, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.genericRGB)
        #expect(bg?.redComponent == 1 && bg?.greenComponent == 1 && bg?.blueComponent == 1)
    }

    @Test func fontAppliedWithDoubleSize() throws {
        let state = ScriptableClipState(JSClipInput(stringValue: "Fonted"))
        state.change(["font": ["name": "Helvetica", "size": 18.0]], mode: .add)

        guard case .rtf(let data, _) = state.outcome else {
            Issue.record("expected .rtf, got \(state.outcome)"); return
        }
        let attr = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontName == "Helvetica")
        #expect(font?.pointSize == 18)
    }

    @Test func underlineStyleAndPatternAndByWordApplied() throws {
        let state = ScriptableClipState(JSClipInput(stringValue: "Underlined"))
        state.change(["underline": ["style": "double", "pattern": "dash", "byWord": true]],
                     mode: .set)

        guard case .rtf(let data, _) = state.outcome else {
            Issue.record("expected .rtf, got \(state.outcome)"); return
        }
        let attr = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        let raw = (attr.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber)?.intValue
        let expected = NSUnderlineStyle.double.rawValue
            | NSUnderlineStyle.patternDash.rawValue
            | NSUnderlineStyle.byWord.rawValue
        #expect(raw == expected)
    }

    @Test func unknownUnderlineNamesFallBackToDefaults() throws {
        // Unknown style + unknown pattern + no byWord → raw underline value 0,
        // but the attribute is still set (attrs non-empty), so an RTF is produced.
        let state = ScriptableClipState(JSClipInput(stringValue: "x"))
        state.change(["underline": ["style": "squiggle", "pattern": "zigzag"]], mode: .set)

        guard case .rtf(let data, _) = state.outcome else {
            Issue.record("expected .rtf, got \(state.outcome)"); return
        }
        let attr = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        // A raw underline value of 0 (none) is not serialized into the RTF, so it
        // reads back as an absent attribute — the point is the RTF was produced.
        let raw = attr.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? NSNumber
        #expect(raw == nil)
    }

    @Test func singleAndThickUnderlineNamesResolve() throws {
        for name in ["single", "thick"] {
            let state = ScriptableClipState(JSClipInput(stringValue: "u"))
            state.change(["underline": ["style": name]], mode: .set)
            guard case .rtf = state.outcome else {
                Issue.record("expected .rtf for style \(name), got \(state.outcome)"); continue
            }
        }
    }

    @Test func rtfSourceStaysRTF() {
        let state = ScriptableClipState(
            JSClipInput(stringValue: "Rich", rtfData: rtfData("Rich"), isRTFD: false))
        state.change(["color": ["foreground": "red"]], mode: .add)
        guard case .rtf(_, let rtfd) = state.outcome else {
            Issue.record("expected .rtf, got \(state.outcome)"); return
        }
        #expect(rtfd == false)
    }

    @Test func rtfdSourceStaysRTFD() {
        let state = ScriptableClipState(
            JSClipInput(stringValue: "RichD", rtfData: rtfdData("RichD"), isRTFD: true))
        state.change(["color": ["foreground": "red"]], mode: .set)
        guard case .rtf(_, let rtfd) = state.outcome else {
            Issue.record("expected .rtf, got \(state.outcome)"); return
        }
        #expect(rtfd == true)   // an RTFD source produces an RTFD result
    }
}
