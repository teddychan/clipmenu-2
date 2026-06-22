import Testing
import Foundation
@testable import ClipMenu

// Action paths come from actions.plist / behavior ids and require() names from
// scripts. A "../" segment must not escape the script tree — the resolved file
// is read and EVALUATED as JavaScript, so traversal means arbitrary local
// files get eval'd (the Developer ID build is not sandboxed).

@Suite struct JSScriptPathTests {
    private let root = URL(fileURLWithPath: "/Users/me/Library/Application Support/ClipMenu/script")

    @Test func plainSubpathResolvesInsideRoot() {
        let url = JSActionRunner.confinedURL(root: root, subpath: "action/Reverse.js")
        #expect(url?.path == root.appendingPathComponent("action/Reverse.js").path)
    }

    @Test func nestedSubpathIsAllowed() {
        let url = JSActionRunner.confinedURL(root: root, subpath: "lib/sub/util.js")
        #expect(url != nil)
    }

    @Test func traversalOutsideRootIsRejected() {
        #expect(JSActionRunner.confinedURL(root: root, subpath: "action/../../../../etc/hosts") == nil)
        #expect(JSActionRunner.confinedURL(root: root, subpath: "lib/../../../../../etc/passwd") == nil)
        // A sibling-prefix path must not be mistaken for containment.
        #expect(JSActionRunner.confinedURL(root: root, subpath: "../script-evil/x.js") == nil)
    }
}
