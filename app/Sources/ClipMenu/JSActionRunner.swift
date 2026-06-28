import Foundation
import JavaScriptCore

// Runs a bundled (or user) JavaScript action against a clip's text, matching the
// legacy WebView model (ActionController.m:361-470; JavaScriptSupport.m) but on
// JavaScriptCore. The script body is wrapped in a function
// that returns the transformed string; errors are captured like the legacy
// `scriptException` key.
//
// Globals exposed to a script (parity with the legacy WebScriptObject setup):
//   clipText           — the clip's plain string
//   ClipMenu.require(name) -> Bool — load+eval a bundled lib (adds prototypes)
//   ClipMenu.activate()  — no-op (front-process focus is handled at the call site)
//   prompt(msg, def)     — bridges to a native handler (NSAlert at the call site);
//                          returns null when no handler is supplied (e.g. tests)
//
// The `clip` ScriptableClip object (RTF/RTFD actions) and the user action/lib
// directories (~/…/script, searched before the bundled tree) are supported.

enum JSActionError: Error, Equatable {
    case scriptNotFound(String)
    case evaluationFailed
    case scriptException(String)   // legacy scriptExceptionKey
}

enum JSActionRunner {

    /// JS `prompt(message, default)` bridge. Returns the entered string, or nil
    /// on cancel. The real handler shows an NSAlert at the invocation site; tests
    /// inject a value. Nil handler ⇒ prompt returns null (script requiring input
    /// fails as it would on Cancel).
    typealias PromptHandler = @Sendable (_ message: String, _ defaultValue: String) -> String?

    /// Run the action at `relativePath` (e.g. "Case/UPPERCASE.js", relative to
    /// the bundled script/action dir) against `input`. Returns the transformed
    /// string, or nil when the script yields `undefined`/no value (legacy returns
    /// nil = "no change"). Empty input yields nil (ActionController.m:368-371).
    static func run(action relativePath: String, on input: String,
                    prompt: PromptHandler? = nil) throws -> String? {
        guard !input.isEmpty else { return nil }
        guard let scriptContent = actionSource(relativePath) else {
            throw JSActionError.scriptNotFound(relativePath)
        }
        return try evaluate(scriptContent, clipText: input, prompt: prompt)
    }

    /// Run an action and return its full outcome (string or styled RTF), with the
    /// `clip` object backed by `clip` (AppController.m:_invokeJavaScriptAction
    /// 752-815). Used by ActionEngine so JS actions can produce RTF/RTFD clips.
    static func runDetailed(action relativePath: String, clip: JSClipInput,
                            prompt: PromptHandler? = nil) throws -> JSActionOutcome {
        guard !clip.stringValue.isEmpty else { return .none }
        guard let scriptContent = actionSource(relativePath) else {
            throw JSActionError.scriptNotFound(relativePath)
        }
        return try evaluateDetailed(scriptContent, clip: clip, prompt: prompt)
    }

    /// String-only convenience over `evaluateDetailed` (back-compat for the text
    /// actions + tests). Returns nil for RTF / undefined results.
    static func evaluate(_ scriptContent: String, clipText: String,
                         prompt promptHandler: PromptHandler? = nil) throws -> String? {
        if case .string(let s) = try evaluateDetailed(
            scriptContent, clip: JSClipInput(stringValue: clipText), prompt: promptHandler) {
            return s
        }
        return nil
    }

    /// Evaluate raw script source with `clipText` + `clip` bound, returning the
    /// result (mirrors invokeScript: ActionController.m:383-470).
    static func evaluateDetailed(_ scriptContent: String, clip clipInput: JSClipInput,
                                 prompt promptHandler: PromptHandler? = nil) throws -> JSActionOutcome {
        guard let context = JSContext() else { throw JSActionError.evaluationFailed }

        let exceptionKey = "__cmException"
        context.setObject(clipInput.stringValue, forKeyedSubscript: "clipText" as NSString)
        context.setObject("", forKeyedSubscript: exceptionKey as NSString)

        // `clip` object (ScriptableClip): set/addStringAttributes mutate state and
        // produce RTF; a marker lets us detect `return clip;`.
        let clipState = ScriptableClipState(clipInput)
        let clipMarker = "__isClip"
        let clipObject = JSValue(newObjectIn: context)
        clipObject?.setObject(true, forKeyedSubscript: clipMarker as NSString)
        let setAttrs: @convention(block) (JSValue?) -> Void = { arg in
            clipState.change((arg?.toDictionary() as? [String: Any]) ?? [:], mode: .set)
        }
        let addAttrs: @convention(block) (JSValue?) -> Void = { arg in
            clipState.change((arg?.toDictionary() as? [String: Any]) ?? [:], mode: .add)
        }
        clipObject?.setObject(setAttrs, forKeyedSubscript: "setStringAttributes" as NSString)
        clipObject?.setObject(addAttrs, forKeyedSubscript: "addStringAttributes" as NSString)
        context.setObject(clipObject, forKeyedSubscript: "clip" as NSString)

        // Some bundled libs (v8cgi/html, v8cgi/util) end with a CommonJS-style
        // `exports.Foo = Foo;` line. They also define a top-level global (`HTML`,
        // `Util`), which is what the actions actually use — but the bare
        // `exports` reference would throw. Provide it so the libs load cleanly.
        context.evaluateScript("var exports = {};")

        // ClipMenu namespace: require + activate.
        let namespace = JSValue(newObjectIn: context)
        let requireBlock: @convention(block) (String) -> Bool = { name in
            guard let lib = libSource(name) else { return false }
            context.evaluateScript(lib)
            return true
        }
        let activateBlock: @convention(block) () -> Void = {}
        namespace?.setObject(requireBlock, forKeyedSubscript: "require" as NSString)
        namespace?.setObject(activateBlock, forKeyedSubscript: "activate" as NSString)
        context.setObject(namespace, forKeyedSubscript: "ClipMenu" as NSString)

        // prompt(message[, default]) → native handler (NSAlert at the call site,
        // ClipMenu.activate handles front-process focus). No handler ⇒ null.
        let promptBlock: @convention(block) (String, String) -> Any = { message, def in
            promptHandler?(message, def) ?? NSNull()
        }
        context.setObject(promptBlock, forKeyedSubscript: "__cmPrompt" as NSString)
        context.evaluateScript(
            "function prompt(m, d){ return __cmPrompt(String(m), (d === undefined) ? '' : String(d)); }")

        // Wrap exactly like the legacy runner (ActionController.m:387-389).
        let wrapper = "function __wrapper() { try { \(scriptContent) } catch (e) { \(exceptionKey) = e.toString(); return; } }"
        context.evaluateScript(wrapper)
        let result = context.objectForKeyedSubscript("__wrapper")?.call(withArguments: [])

        if let nativeException = context.exception {
            throw JSActionError.scriptException(nativeException.toString() ?? "Script error")
        }
        let scriptException = context.objectForKeyedSubscript(exceptionKey)?.toString() ?? ""
        if !scriptException.isEmpty {
            throw JSActionError.scriptException(scriptException)
        }

        // `return clip;` → the styled clip's outcome (ScriptableClip / 463-465).
        if let result, result.isObject,
           result.objectForKeyedSubscript(clipMarker)?.toBool() == true {
            return clipState.outcome
        }
        guard let result, !result.isUndefined, !result.isNull else { return .none }
        return .string(result.toString() ?? "")
    }

    // MARK: - Bundled resources

    private static var bundledScriptRoot: URL? {
        AppResources.bundle.resourceURL?.appendingPathComponent("script")
    }

    /// User script root: ~/Library/Application Support/ClipMenu/script
    /// (CMUtilities.m:316-336). Searched before the bundled tree so user scripts
    /// can override or add to the built-ins (ActionController.m:593-604). ⚠️SBX:
    /// not sandboxed, so the real home directory is reachable.
    private static var userScriptRoot: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("ClipMenu/script")
    }

    /// First existing/readable file at <root>/<subpath> across the user root then
    /// the bundled root (legacy "user's lib directory is first", _require 110-135).
    private static func source(subpath: String) -> String? {
        for root in [userScriptRoot, bundledScriptRoot].compactMap({ $0 }) {
            guard let url = confinedURL(root: root, subpath: subpath) else { continue }
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        }
        return nil
    }

    /// Resolve <root>/<subpath> and confine it to `root` — a ".." segment in an
    /// action path (from actions.plist) or a require() name must not escape the
    /// script tree, since the resolved file is read and EVALUATED as JavaScript
    /// (and the Developer ID build is not sandboxed). Returns nil on escape.
    /// Pure (lexical, via standardizedFileURL) so it is unit-testable.
    static func confinedURL(root: URL, subpath: String) -> URL? {
        let resolved = root.appendingPathComponent(subpath).standardizedFileURL
        let base = root.standardizedFileURL
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return resolved.path.hasPrefix(basePath) ? resolved : nil
    }

    /// Action script source (script/action/<relativePath>), user dir first.
    static func actionSource(_ relativePath: String) -> String? {
        source(subpath: "action/" + relativePath)
    }

    /// Library source (script/lib/<name>.js), user lib dir first then bundled
    /// (JavaScriptSupport.m:_require, 110-135).
    static func libSource(_ name: String) -> String? {
        source(subpath: "lib/" + (name.hasSuffix(".js") ? name : name + ".js"))
    }
}
