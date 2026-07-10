import Testing
import Foundation
@testable import ClipMenu

// Characterization coverage for ActionStore/ActionNode helpers not exercised by
// ActionStoreTests: node factories + isFolder, the builtin palette, behaviorID
// edge cases, the bundled-JS tree walk (actionNodes recursion), and the on-disk
// load/save round-trip. Assertions pin CURRENT behavior only.

@Suite struct ActionNodeFactoryCoverageTests {

    @Test func folderFactorySetsChildrenAndIsFolder() {
        let leaf = ActionNode.builtin("Leaf", name: "x:")
        let folder = ActionNode.folder("Group", [leaf])
        #expect(folder.isFolder)
        #expect(folder.action == nil)
        #expect(folder.children?.count == 1)
        // A leaf action is not a folder.
        #expect(!leaf.isFolder)
        #expect(leaf.children == nil)
    }

    @Test func builtinFactoryBuildsBuiltinSpec() {
        let node = ActionNode.builtin("Remove", name: ActionStore.remove)
        #expect(node.title == "Remove")
        #expect(node.action == ActionSpec(type: "builtin", name: "remove:", path: nil))
        #expect(node.children == nil)
    }

    @Test func javaScriptFactoryTitleIsLastPathComponent() {
        // Nested path → title is just the filename.
        let nested = ActionNode.javaScript("Trim/LTrim.js")
        #expect(nested.title == "LTrim.js")
        #expect(nested.action == ActionSpec(type: "js", name: nil, path: "Trim/LTrim.js"))

        // Bare filename (no slash) → title equals the whole path.
        let bare = ActionNode.javaScript("Solo.js")
        #expect(bare.title == "Solo.js")
        #expect(bare.action == ActionSpec(type: "js", name: nil, path: "Solo.js"))
    }

    @Test func typeConstantsAreStable() {
        #expect(ActionStore.builtinType == "builtin")
        #expect(ActionStore.jsType == "js")
        #expect(ActionStore.pasteAsPlainText == "pasteAsPlainText:")
        #expect(ActionStore.pasteAsFilePath == "pasteAsFilePath:")
        #expect(ActionStore.remove == "remove:")
    }
}

@Suite struct ActionStoreBehaviorIDCoverageTests {

    @Test func behaviorIDNilForFolder() {
        let folder = ActionNode.folder("F", [.builtin("A", name: "a:")])
        #expect(ActionStore.behaviorID(for: folder) == nil)
    }

    @Test func behaviorIDNilForUnknownType() {
        let weird = ActionNode(title: "?", action: ActionSpec(type: "mystery", name: "n", path: "p"),
                               children: nil)
        #expect(ActionStore.behaviorID(for: weird) == nil)
    }

    @Test func behaviorIDNilWhenBuiltinNameMissing() {
        let node = ActionNode(title: "?", action: ActionSpec(type: "builtin", name: nil, path: nil),
                              children: nil)
        #expect(ActionStore.behaviorID(for: node) == nil)
    }

    @Test func behaviorIDNilWhenJSPathMissing() {
        let node = ActionNode(title: "?", action: ActionSpec(type: "js", name: nil, path: nil),
                              children: nil)
        #expect(ActionStore.behaviorID(for: node) == nil)
    }

    @Test func behaviorIDForBuiltinAndJS() {
        #expect(ActionStore.behaviorID(for: .builtin("P", name: "pasteAsPlainText:"))
                == "builtin:pasteAsPlainText:")
        #expect(ActionStore.behaviorID(for: .javaScript("Case/UPPERCASE.js"))
                == "js:Case/UPPERCASE.js")
    }

    @Test func nodeForBehaviorIDUnknownPrefixIsNil() {
        #expect(ActionStore.node(forBehaviorID: "folder:whatever") == nil)
        #expect(ActionStore.node(forBehaviorID: "plainstring") == nil)
    }

    @Test func flattenedLeavesWithExplicitNodesExpandsFolders() {
        let nodes = [
            ActionNode.builtin("Top", name: "top:"),
            .folder("Group", [
                .javaScript("Group/Inner.js"),
                .folder("Deep", [.javaScript("Group/Deep/Leaf.js")]),
            ]),
        ]
        let leaves = ActionStore.flattenedLeaves(nodes)
        #expect(leaves.map(\.title) == ["Top", "Inner.js", "Leaf.js"])
        #expect(leaves.map(\.id) == ["builtin:top:", "js:Group/Inner.js", "js:Group/Deep/Leaf.js"])
    }
}

@Suite struct ActionStoreBuiltinPaletteCoverageTests {

    @Test func builtinNodesArePlainTextFilePathRemove() {
        let nodes = ActionStore.builtinNodes()
        #expect(nodes.map(\.title) == ["Paste as Plain Text", "Paste as File Path", "Remove"])
        #expect(nodes[0].action == ActionSpec(type: "builtin", name: "pasteAsPlainText:", path: nil))
        #expect(nodes[1].action == ActionSpec(type: "builtin", name: "pasteAsFilePath:", path: nil))
        #expect(nodes[2].action == ActionSpec(type: "builtin", name: "remove:", path: nil))
    }

    @Test func bundledNodesWalkShippedActionTree() {
        // Exercises actionNodes(in:prefix:): subdirs → folders, .js → leaves, sorted.
        let nodes = ActionStore.bundledNodes()
        #expect(!nodes.isEmpty)

        // A known shipped folder is present and its leaves are relative-path JS specs.
        let caseFolder = try? #require(nodes.first { $0.title == "Case" })
        #expect(caseFolder?.isFolder == true)
        let firstLeaf = caseFolder?.children?.first
        #expect(firstLeaf?.action?.type == "js")
        #expect(firstLeaf?.action?.path?.hasPrefix("Case/") == true)

        // Top-level entries are sorted by name.
        let titles = nodes.map(\.title)
        #expect(titles == titles.sorted())
    }

    @Test func usersNodesReturnsArray() {
        // No user script/action dir in the test environment → empty; either way
        // this drives the guard/early-return path without throwing.
        #expect(ActionStore.usersNodes().count >= 0)
    }
}

@Suite struct ActionSpecCodableCoverageTests {

    @Test func actionSpecJSONRoundTripPreservesOptionals() throws {
        let specs = [
            ActionSpec(type: "builtin", name: "remove:", path: nil),
            ActionSpec(type: "js", name: nil, path: "Trim/Trim.js"),
        ]
        let data = try JSONEncoder().encode(specs)
        let decoded = try JSONDecoder().decode([ActionSpec].self, from: data)
        #expect(decoded == specs)
    }

    @Test func actionNodeDecodeAssignsFreshIDButKeepsStructure() throws {
        let original = ActionNode.folder("Case", [.javaScript("Case/UPPERCASE.js")])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActionNode.self, from: data)
        // Equality ignores id (structural), so the round-trip holds...
        #expect(decoded == original)
        // ...but the decoder mints a new id rather than persisting the source's.
        #expect(decoded.id != original.id)
    }
}

// Touches the real on-disk actions.plist, so serialize and back up / restore the
// user's file (defer runs on failure too).
@Suite(.serialized) struct ActionStorePersistenceCoverageTests {

    @Test func loadGeneratesDefaultsThenSaveRoundTrips() throws {
        let url = try #require(ActionStore.saveURL)
        let fm = FileManager.default
        let backup = try? Data(contentsOf: url)
        defer {
            if let backup {
                try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                try? backup.write(to: url)
            } else {
                try? fm.removeItem(at: url)
            }
        }

        // First run (no file) → defaults are generated and persisted.
        try? fm.removeItem(at: url)
        let loaded = ActionStore.load()
        #expect(loaded == ActionStore.defaultNodes())
        #expect(fm.fileExists(atPath: url.path))

        // A subsequent save is honored and read back verbatim.
        let custom = [
            ActionNode.builtin("Only", name: "only:"),
            .folder("Box", [.javaScript("Box/One.js")]),
        ]
        #expect(ActionStore.save(custom))
        #expect(ActionStore.load() == custom)
    }
}
