import Testing
import Foundation
@testable import ClipMenu

// Runs real bundled JS actions end-to-end through JSActionRunner (PARITY §F JS
// engine). Proves the JavaScriptCore wrapper, clipText binding, ClipMenu.require
// lib loading, and result return all match the legacy transforms.

@Suite struct JSActionRunnerTests {

    @Test func upperCasePerLine() throws {
        // Case/UPPERCASE.js: split on \n, uppercase each line, rejoin.
        #expect(try JSActionRunner.run(action: "Case/UPPERCASE.js", on: "abc\nDef") == "ABC\nDEF")
    }

    @Test func lowerCasePerLine() throws {
        #expect(try JSActionRunner.run(action: "Case/lowercase.js", on: "ABC\nDeF") == "abc\ndef")
    }

    @Test func reverseRequiresStringLib() throws {
        // Reverse.js: ClipMenu.require('JS-methods/string') then clipText.reverse().
        #expect(try JSActionRunner.run(action: "Reverse.js", on: "abcd") == "dcba")
    }

    @Test func trimUsesLib() throws {
        #expect(try JSActionRunner.run(action: "Trim/Trim.js", on: "  hi  ") == "hi")
    }

    @Test func capitalizeUsesInflection() throws {
        // Case/Capitalize.js: require('inflection'), capitalize each line.
        #expect(try JSActionRunner.run(action: "Case/Capitalize.js", on: "hello world") == "Hello world")
    }

    @Test func emptyInputYieldsNil() throws {
        #expect(try JSActionRunner.run(action: "Case/UPPERCASE.js", on: "") == nil)
    }

    @Test func missingScriptThrows() {
        #expect(throws: JSActionError.self) {
            try JSActionRunner.run(action: "Does/NotExist.js", on: "x")
        }
    }
}
