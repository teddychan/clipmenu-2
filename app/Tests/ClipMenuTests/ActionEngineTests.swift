import Testing
@testable import ClipMenu

// Pins ActionEngine's node→action dispatch (PARITY §F; AppController.m:742-815).
// Side-effecting paste/remove paths are covered by BuiltInActions/JSActionRunner
// tests; here we verify the node→JS wiring and that folders/non-JS yield nil.

@Suite struct ActionEngineTests {

    @Test func defaultCaseFolderNodesRunViaEngine() throws {
        let nodes = ActionStore.defaultNodes()
        let caseFolder = try #require(nodes.first { $0.title == "Case" })
        let upper = try #require(caseFolder.children?.first { $0.title == "UPPERCASE.js" })
        #expect(try ActionEngine.javaScriptResult(for: upper, input: "hi\nthere") == "HI\nTHERE")
    }

    @Test func builtinAndFolderNodesHaveNoJSResult() throws {
        let nodes = ActionStore.defaultNodes()
        let plainText = try #require(nodes.first { $0.title == "Paste as Plain Text" })
        let caseFolder = try #require(nodes.first { $0.title == "Case" })
        #expect(try ActionEngine.javaScriptResult(for: plainText, input: "x") == nil)
        #expect(try ActionEngine.javaScriptResult(for: caseFolder, input: "x") == nil)
    }
}
