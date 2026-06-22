import Testing
import AppKit
@testable import ClipMenu

// CSS color resolver (NSColor+String.m) + the JS `clip` RTF bridge
// (ScriptableClip.m:139-339; PARITY §F rows 86/87).

@Suite struct CSSColorTests {

    private func rgb(_ color: NSColor?) -> (CGFloat, CGFloat, CGFloat)? {
        guard let c = color?.usingColorSpace(.genericRGB) else { return nil }
        return (c.redComponent, c.greenComponent, c.blueComponent)
    }

    @Test func namedColors() {
        #expect(rgb(CSSColor.color("red"))! == (1, 0, 0))
        #expect(rgb(CSSColor.color("white"))! == (1, 1, 1))
        #expect(rgb(CSSColor.color("black"))! == (0, 0, 0))
    }

    @Test func hexAndRGB() {
        #expect(rgb(CSSColor.color("#00ff00"))! == (0, 1, 0))
        #expect(rgb(CSSColor.color("0000ff"))! == (0, 0, 1))
        let (r, g, b) = rgb(CSSColor.color("rgb(255, 0, 0)"))!
        #expect(r == 1 && g == 0 && b == 0)
    }

    @Test func unknownIsNil() {
        #expect(CSSColor.color("definitelynotacolor") == nil)
        #expect(CSSColor.color("") == nil)
    }
}

@Suite struct ScriptableClipBridgeTests {

    @Test func clipSetStringAttributesProducesRTF() throws {
        let script = """
        clip.setStringAttributes({ font: { name: 'Helvetica', size: 24 },
                                   color: { foreground: 'red' } });
        return clip;
        """
        let outcome = try JSActionRunner.evaluateDetailed(
            script, clip: JSClipInput(stringValue: "Hi"))

        guard case .rtf(let data, let rtfd) = outcome else {
            Issue.record("expected .rtf, got \(outcome)"); return
        }
        #expect(rtfd == false)   // a plain-string source becomes RTF (not RTFD)

        let attr = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontName == "Helvetica")
        #expect(font?.pointSize == 24)
        let color = (attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)?
            .usingColorSpace(.genericRGB)
        #expect(color?.redComponent == 1)
        #expect(color?.greenComponent == 0)
    }

    @Test func stringActionStillReturnsString() throws {
        let outcome = try JSActionRunner.evaluateDetailed(
            "return clipText.toUpperCase();", clip: JSClipInput(stringValue: "hi"))
        #expect(outcome == .string("HI"))
    }

    @Test func noReturnIsNone() throws {
        let outcome = try JSActionRunner.evaluateDetailed(
            "var x = 1;", clip: JSClipInput(stringValue: "hi"))
        #expect(outcome == .none)
    }
}
