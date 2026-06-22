import Testing
import Foundation
@testable import ClipMenu

// Pins the built-in action text transforms (PARITY §F; BuiltInActionController.m
// :185-211). "Paste as HFS File Path" is blocked on a removed API (OQ #11).

@Suite struct BuiltInActionsTests {

    @Test func plainTextIsIdentity() {
        #expect(BuiltInActions.plainText("Hello") == "Hello")
        #expect(BuiltInActions.plainText("") == "")
    }

    @Test func filePathJoinsWithNewline() {
        #expect(BuiltInActions.filePath(filenames: []) == "")
        #expect(BuiltInActions.filePath(filenames: ["/a/b.txt"]) == "/a/b.txt")
        #expect(BuiltInActions.filePath(filenames: ["/a/b.txt", "/c/d.txt"])
                == "/a/b.txt\n/c/d.txt")
    }
}
