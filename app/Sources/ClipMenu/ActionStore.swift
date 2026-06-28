import Foundation

// Action tree model + persistence (ActionController.m:181-271 save/
// load, 523-555 default set; ActionFactory.m:12-13 type keys;
// BuiltInActionController.m:17-20 selectors).
//
// A node is either a folder (title + children) or a leaf action (title + spec).
// Persisted to `actions.plist` (XML) in Application Support, regenerated from the
// default set on first run. Consumed by the Actions menu / engine (§C41, later).

struct ActionSpec: Codable, Sendable, Equatable {
    var type: String      // "builtin" | "js" (CMBuiltinActionTypeKey / CMJavaScriptActionTypeKey)
    var name: String?     // builtin selector, e.g. "pasteAsPlainText:"
    var path: String?     // JS action path relative to script/action, e.g. "Case/Capitalize.js"
}

struct ActionNode: Codable, Sendable, Equatable, Identifiable {
    let id: UUID                  // SwiftUI identity only (not persisted/compared)
    var title: String
    var action: ActionSpec?       // non-nil ⇒ leaf action
    var children: [ActionNode]?   // non-nil ⇒ folder

    init(title: String, action: ActionSpec?, children: [ActionNode]?, id: UUID = UUID()) {
        self.id = id
        self.title = title
        self.action = action
        self.children = children
    }

    var isFolder: Bool { children != nil }

    // Persisted shape excludes `id` (matches the legacy plist).
    private enum CodingKeys: String, CodingKey { case title, action, children }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        title = try c.decode(String.self, forKey: .title)
        action = try c.decodeIfPresent(ActionSpec.self, forKey: .action)
        children = try c.decodeIfPresent([ActionNode].self, forKey: .children)
    }

    // Equality by structure (ignore id), so persistence/round-trip tests hold.
    static func == (lhs: ActionNode, rhs: ActionNode) -> Bool {
        lhs.title == rhs.title && lhs.action == rhs.action && lhs.children == rhs.children
    }

    static func folder(_ title: String, _ children: [ActionNode]) -> ActionNode {
        ActionNode(title: title, action: nil, children: children)
    }

    static func builtin(_ title: String, name: String) -> ActionNode {
        ActionNode(title: title, action: ActionSpec(type: ActionStore.builtinType, name: name, path: nil),
                   children: nil)
    }

    /// JS leaf. Title is the filename (incl. .js), matching the legacy node title
    /// (ActionController.m:_javaScriptFileInfoWithName — `filename = lastObject`).
    static func javaScript(_ path: String) -> ActionNode {
        let filename = path.components(separatedBy: "/").last ?? path
        return ActionNode(title: filename,
                          action: ActionSpec(type: ActionStore.jsType, name: nil, path: path),
                          children: nil)
    }
}

enum ActionStore {
    static let builtinType = "builtin"   // ActionFactory.m:12
    static let jsType = "js"             // ActionFactory.m:13

    // Built-in selectors (BuiltInActionController.m:17-20).
    static let pasteAsPlainText = "pasteAsPlainText:"
    static let pasteAsFilePath  = "pasteAsFilePath:"
    static let remove           = "remove:"

    /// First-run default action set (ActionController.m:523-555): Paste as Plain
    /// Text, Case (4 JS), Trim (3 JS), Remove — in this order.
    static func defaultNodes() -> [ActionNode] {
        [
            .builtin("Paste as Plain Text", name: pasteAsPlainText),
            .folder("Case", [
                .javaScript("Case/Capitalize.js"),
                .javaScript("Case/lowercase.js"),
                .javaScript("Case/Title Case.js"),
                .javaScript("Case/UPPERCASE.js"),
            ]),
            .folder("Trim", [
                .javaScript("Trim/LTrim.js"),
                .javaScript("Trim/RTrim.js"),
                .javaScript("Trim/Trim.js"),
            ]),
            .builtin("Remove", name: remove),
        ]
    }

    /// actions.plist in Application Support (ActionController.m:_saveFilePath).
    static var saveURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ClipMenu/actions.plist")
    }

    /// Load the action tree; on first run (no file) generate + save the defaults
    /// (ActionController.m:loadActions 218-271).
    static func load() -> [ActionNode] {
        if let url = saveURL, let data = try? Data(contentsOf: url),
           let nodes = try? PropertyListDecoder().decode([ActionNode].self, from: data) {
            return nodes
        }
        let defaults = defaultNodes()
        save(defaults)
        return defaults
    }

    // MARK: - Editor palettes (ActionNodeController.m:186-188; 3 reserved segments)

    /// Built-in actions palette (BuiltInActionController.m; HFS dropped).
    static func builtinNodes() -> [ActionNode] {
        [
            .builtin("Paste as Plain Text", name: pasteAsPlainText),
            .builtin("Paste as File Path", name: pasteAsFilePath),
            .builtin("Remove", name: remove),
        ]
    }

    /// Bundled JS actions palette — the shipped script/action tree.
    static func bundledNodes() -> [ActionNode] {
        guard let root = AppResources.bundle.resourceURL?
            .appendingPathComponent("script/action") else { return [] }
        return actionNodes(in: root, prefix: "")
    }

    /// User JS actions palette — ~/Library/Application Support/ClipMenu/script/action.
    static func usersNodes() -> [ActionNode] {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ClipMenu/script/action")
        guard let root, FileManager.default.fileExists(atPath: root.path) else { return [] }
        return actionNodes(in: root, prefix: "")
    }

    /// Build a node tree from an action directory: subdirs → folders, `.js` → leaves
    /// (path relative to the action dir), sorted by name.
    private static func actionNodes(in dir: URL, prefix: String) -> [ActionNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }
        var out: [ActionNode] = []
        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                let children = actionNodes(in: url, prefix: prefix + url.lastPathComponent + "/")
                if !children.isEmpty { out.append(.folder(url.lastPathComponent, children)) }
            } else if url.pathExtension == "js" {
                out.append(.javaScript(prefix + url.lastPathComponent))
            }
        }
        return out
    }

    // MARK: - Modifier-behavior identifiers (Action pane pickers, §J/§E)

    /// Stable id for a leaf action used as a click behavior: "builtin:<name>" or
    /// "js:<path>". nil for folders. Pairs with `node(forBehaviorID:)`.
    static func behaviorID(for node: ActionNode) -> String? {
        guard let spec = node.action else { return nil }
        switch spec.type {
        case builtinType: return spec.name.map { "builtin:\($0)" }
        case jsType:      return spec.path.map { "js:\($0)" }
        default:          return nil
        }
    }

    /// Flattened leaf actions (folders expanded), for the modifier-behavior
    /// pickers (PrefsWindowController.m:_actionsFromNodes / 655-696).
    static func flattenedLeaves(_ nodes: [ActionNode]? = nil) -> [(title: String, id: String)] {
        var out: [(String, String)] = []
        for node in nodes ?? load() {
            if let children = node.children {
                out.append(contentsOf: flattenedLeaves(children))
            } else if let id = behaviorID(for: node) {
                out.append((node.title, id))
            }
        }
        return out
    }

    /// Resolve a behavior id back to a synthetic leaf node for invocation.
    static func node(forBehaviorID id: String) -> ActionNode? {
        if id.hasPrefix("builtin:") {
            let name = String(id.dropFirst("builtin:".count))
            return ActionNode(title: name, action: ActionSpec(type: builtinType, name: name, path: nil),
                              children: nil)
        }
        if id.hasPrefix("js:") {
            return .javaScript(String(id.dropFirst("js:".count)))
        }
        return nil
    }

    /// Persist the tree as an XML plist (ActionController.m:saveActions 181-217).
    @discardableResult
    static func save(_ nodes: [ActionNode]) -> Bool {
        guard let url = saveURL else { return false }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        guard let data = try? encoder.encode(nodes) else { return false }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }
}
