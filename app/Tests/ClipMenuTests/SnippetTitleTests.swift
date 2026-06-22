import Testing
import Foundation
@testable import ClipMenu

// Pins Snippet.derivedTitle(fromContent:) — the label auto-derived from a new
// snippet's content (first non-empty line, capped to 10 words / 60 chars).

@Suite struct SnippetTitleTests {

    @Test func emptyContentHasNoDerivedTitle() {
        #expect(Snippet.derivedTitle(fromContent: "") == nil)
    }

    @Test func whitespaceAndNewlinesOnlyHaveNoDerivedTitle() {
        #expect(Snippet.derivedTitle(fromContent: "   \n\n\t  ") == nil)
    }

    @Test func singleLineIsUsedVerbatim() {
        #expect(Snippet.derivedTitle(fromContent: "test 4") == "test 4")
    }

    @Test func usesFirstLineOfMultilineContent() {
        #expect(Snippet.derivedTitle(fromContent: "first line\nsecond line") == "first line")
    }

    @Test func skipsLeadingBlankLines() {
        #expect(Snippet.derivedTitle(fromContent: "\n\n  hello world") == "hello world")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(Snippet.derivedTitle(fromContent: "   padded   ") == "padded")
    }

    @Test func capsAtTenWords() {
        let content = "one two three four five six seven eight nine ten eleven twelve"
        #expect(Snippet.derivedTitle(fromContent: content)
            == "one two three four five six seven eight nine ten")
    }

    @Test func capsLongSingleWordAtSixtyChars() {
        let long = String(repeating: "a", count: 100)
        let derived = Snippet.derivedTitle(fromContent: long)
        #expect(derived?.count == 60)
    }
}
