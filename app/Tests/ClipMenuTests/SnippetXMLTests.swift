import Testing
import Foundation
@testable import ClipMenu

// Pins the snippet XML parity (PARITY §G rows 139-140) by a round-trip test
// (CLAUDE.md §9: unit-test pure transforms). Export → parse must preserve folder
// order, snippet order, titles, and content whitespace.

@Suite struct SnippetXMLTests {

    @Test func roundTripPreservesStructureAndWhitespace() {
        let input: [(title: String, snippets: [(title: String, content: String)])] = [
            ("Greetings", [
                ("hello", "Hello, world!"),
                ("multiline", "line 1\n  indented line 2\n"),
            ]),
            ("Empty Folder", []),
            ("Symbols", [("amp", "a & b < c > d \"q\"")]),
        ]

        let data = SnippetXML.export(folders: input)
        let parsed = SnippetXML.parse(data)

        #expect(parsed.count == 3)
        #expect(parsed.map(\.title) == ["Greetings", "Empty Folder", "Symbols"])

        #expect(parsed[0].snippets.map(\.title) == ["hello", "multiline"])
        #expect(parsed[0].snippets[0].content == "Hello, world!")
        // Whitespace inside <content> must survive (NSXMLNodePreserveWhitespace).
        #expect(parsed[0].snippets[1].content == "line 1\n  indented line 2\n")

        #expect(parsed[1].snippets.isEmpty)

        // XML-special characters round-trip through escaping.
        #expect(parsed[2].snippets[0].content == "a & b < c > d \"q\"")
    }

    @Test func exportProducesXMLWithExpectedElements() {
        let data = SnippetXML.export(folders: [("F", [("s", "c")])])
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("<?xml"))
        #expect(text.contains("<folders>"))
        #expect(text.contains("<folder>"))
        #expect(text.contains("<snippet>"))
    }

    // Snippet content is arbitrary pasted text and can contain C0 control
    // characters that are illegal in XML 1.0 (e.g. VT 0x0B from Word/Excel
    // cell line breaks, ESC from terminal output). Export must not produce a
    // document that fails to re-import; invalid scalars are stripped.
    @Test func controlCharactersDoNotPoisonTheExport() {
        let input: [(title: String, snippets: [(title: String, content: String)])] = [
            ("F", [
                ("bell", "a\u{07}b"),
                ("vt", "x\u{0B}y"),
                ("esc", "\u{1B}[0m red"),
                ("kept", "tab\tnewline\n ok"),
            ]),
        ]

        let data = SnippetXML.export(folders: input)
        let parsed = SnippetXML.parse(data)

        #expect(parsed.count == 1)
        #expect(parsed.first?.snippets.map(\.content) ==
                ["ab", "xy", "[0m red", "tab\tnewline\n ok"])
    }

    @Test func parsingGarbageReturnsEmpty() {
        #expect(SnippetXML.parse(Data("not xml".utf8)).isEmpty)
        // Wrong root element is rejected.
        #expect(SnippetXML.parse(Data("<root/>".utf8)).isEmpty)
    }
}
