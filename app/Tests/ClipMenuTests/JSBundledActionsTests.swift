import Testing
import Foundation
@testable import ClipMenu

// Per-family output-parity checks for the bundled JS actions, run end-to-end
// through JSActionRunner (PARITY §F-detail). Deterministic inputs / known
// vectors only; prompt-based (Surround with Tags…), markdown (showdown), the
// char2dec/dec2char and Japanese-conversion families are verified in later
// batches.

@Suite struct JSBundledActionsTests {

    private func run(_ path: String, _ input: String) throws -> String? {
        try JSActionRunner.run(action: path, on: input)
    }

    // MARK: Case / Trim

    @Test func titleCase() throws {
        #expect(try run("Case/Title Case.js", "hello world") == "Hello World")
    }

    @Test func ltrimRtrim() throws {
        #expect(try run("Trim/LTrim.js", "  hi  ") == "hi  ")
        #expect(try run("Trim/RTrim.js", "  hi  ") == "  hi")
    }

    @Test func collapseSpaces() throws {
        #expect(try run("Collapse Spaces.js", "a   b  c") == "a b c")
        #expect(try run("Collapse Spaces.js", "  x   y  ") == "x y")
    }

    // MARK: Surround

    @Test func surroundAscii() throws {
        #expect(try run("Surround with/( ).js", "x") == "(x)")
        #expect(try run("Surround with/[ ].js", "x") == "[x]")
    }

    @Test func surroundJapanese() throws {
        #expect(try run("Surround with (Japanese)/「 」.js", "x") == "「x」")
    }

    // MARK: HTML

    @Test func htmlEscapeUnescapeRoundTrip() throws {
        #expect(try run("HTML/Escape HTML characters.js", "<a>") == "&lt;a&gt;")
        #expect(try run("HTML/Unescape HTML characters.js", "&lt;a&gt;") == "<a>")
    }

    @Test func uriComponent() throws {
        #expect(try run("HTML/Encode URI component.js", "a b&c") == "a%20b%26c")
        #expect(try run("HTML/Decode URI component.js", "a%20b%26c") == "a b&c")
    }

    @Test func stripTags() throws {
        #expect(try run("HTML/Strip Tags.js", "<b>hi</b>") == "hi")
    }

    // MARK: Crypt (known vectors)

    @Test func base64RoundTrip() throws {
        #expect(try run("Crypt/Encode to Base64.js", "abc") == "YWJj")
        #expect(try run("Crypt/Decode from Base64.js", "YWJj") == "abc")
    }

    @Test func md5OfABC() throws {
        #expect(try run("Crypt/Calculate MD5 hash.js", "abc")
                == "900150983cd24fb0d6963f7d28e17f72")
    }

    @Test func sha1OfABC() throws {
        #expect(try run("Crypt/Calculate SHA-1 hash.js", "abc")
                == "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    // MARK: Markdown (showdown)

    @Test func markdownToHTML() throws {
        #expect(try run("HTML/Convert Markdown to HTML.js", "# Hi") == "<h1>Hi</h1>")
    }

    // MARK: Char ↔ Decimal (JS-methods/char)

    @Test func charToDecimalNCR() throws {
        // char2dec → decimal numeric character references.
        #expect(try run("HTML/Convert Character to Decimal.js", "AB") == "&#65;&#66;")
    }

    @Test func decimalNCRToChar() throws {
        #expect(try run("HTML/Convert Decimal to Character.js", "&#65;&#66;") == "AB")
    }

    // MARK: Japanese (fhconvert)

    @Test func zenkakuHankakuAlphanumeric() throws {
        #expect(try run("Japanese/Convert Hankaku alphanumeric characters to Zenkaku.js", "A") == "Ａ")
        #expect(try run("Japanese/Convert Zenkaku alphanumeric characters to Hankaku.js", "Ａ") == "A")
        // Round-trip preserves a mixed string.
        let h2f = try run("Japanese/Convert Hankaku alphanumeric characters to Zenkaku.js", "Abc123")
        #expect(try run("Japanese/Convert Zenkaku alphanumeric characters to Hankaku.js", h2f ?? "") == "Abc123")
    }

    @Test func hiraganaKatakana() throws {
        #expect(try run("Japanese/Convert Hiragana to Katakana.js", "あいう") == "アイウ")
        #expect(try run("Japanese/Convert Katakana to Hiragana.js", "アイウ") == "あいう")
    }

    @Test func hankakuZenkakuKatakana() throws {
        #expect(try run("Japanese/Convert Hankaku katakana to Zenkaku katakana.js", "ｱｲｳ") == "アイウ")
        #expect(try run("Japanese/Convert Zenkaku katakana to Hankaku katakana.js", "アイウ") == "ｱｲｳ")
    }

    // MARK: Surround with Tags… (prompt bridge)

    @Test func surroundWithTagsUsesPrompt() throws {
        let result = try JSActionRunner.run(
            action: "HTML/Surround with Tags....js", on: "x",
            prompt: { _, _ in "div" })
        #expect(result == "<div>x</div>")
    }

    @Test func surroundWithTagsCancelThrows() {
        // No handler ⇒ prompt returns null ⇒ script throws "Invalid input".
        #expect(throws: JSActionError.self) {
            try JSActionRunner.run(action: "HTML/Surround with Tags....js", on: "x")
        }
    }
}
