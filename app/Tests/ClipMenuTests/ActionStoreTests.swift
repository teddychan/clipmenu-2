import Testing
import Foundation
@testable import ClipMenu

// Pins the default action set + plist round-trip (PARITY §F rows 80, 89;
// ActionController.m:523-555 default set, 181-271 persistence).

@Suite struct ActionStoreTests {

    @Test func defaultSetMatchesLegacyOrderAndSpecs() {
        let nodes = ActionStore.defaultNodes()
        #expect(nodes.map(\.title) == ["Paste as Plain Text", "Case", "Trim", "Remove"])

        // Built-ins carry the legacy selectors.
        #expect(nodes[0].action == ActionSpec(type: "builtin", name: "pasteAsPlainText:", path: nil))
        #expect(nodes[3].action == ActionSpec(type: "builtin", name: "remove:", path: nil))

        // Case folder: 4 JS leaves, titles are filenames, paths are relative.
        let caseFolder = nodes[1]
        #expect(caseFolder.isFolder)
        #expect(caseFolder.children?.map(\.title)
                == ["Capitalize.js", "lowercase.js", "Title Case.js", "UPPERCASE.js"])
        #expect(caseFolder.children?.first?.action
                == ActionSpec(type: "js", name: nil, path: "Case/Capitalize.js"))

        // Trim folder: 3 JS leaves.
        #expect(nodes[2].children?.map(\.title) == ["LTrim.js", "RTrim.js", "Trim.js"])
    }

    @Test func behaviorIDRoundTrip() {
        // Flattened leaves expose folders' children; ids resolve back to nodes.
        let leaves = ActionStore.flattenedLeaves()
        let titles = leaves.map(\.title)
        #expect(titles.contains("Paste as Plain Text"))
        #expect(titles.contains("UPPERCASE.js"))   // from the Case folder
        #expect(titles.contains("Remove"))

        // builtin id round-trips to a builtin spec.
        let plainID = "builtin:pasteAsPlainText:"
        #expect(leaves.contains { $0.id == plainID })
        #expect(ActionStore.node(forBehaviorID: plainID)?.action
                == ActionSpec(type: "builtin", name: "pasteAsPlainText:", path: nil))

        // js id round-trips to a js spec.
        let upperID = "js:Case/UPPERCASE.js"
        #expect(ActionStore.node(forBehaviorID: upperID)?.action
                == ActionSpec(type: "js", name: nil, path: "Case/UPPERCASE.js"))

        #expect(ActionStore.node(forBehaviorID: "") == nil)
    }

    @Test func plistRoundTrip() throws {
        let nodes = ActionStore.defaultNodes()
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(nodes)
        let decoded = try PropertyListDecoder().decode([ActionNode].self, from: data)
        #expect(decoded == nodes)
    }
}
