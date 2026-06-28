import Foundation

// Dispatch an action node onto a target clip/snippet (legacy
// AppController.m:_invokeBuiltinAction 742-750, _invokeJavaScriptAction 752-815).
//   - builtin: route the selector name to BuiltInActions
//   - js: run the script on the target's text, then copy+paste the result
// The JS result computation is pure/testable; `apply…` performs the side effects
// (paste / store removal). Folders are not invocable. Wired to the Actions menu
// (§C41) / modifier-click behaviors (§E) next.

enum ActionEngine {

    /// JS result for a node against `input` (nil for non-JS nodes or no result).
    /// Pure relative to the store — used by `apply` and by tests.
    static func javaScriptResult(for node: ActionNode, input: String,
                                 prompt: JSActionRunner.PromptHandler? = nil) throws -> String? {
        guard let spec = node.action, spec.type == ActionStore.jsType, let path = spec.path
        else { return nil }
        return try JSActionRunner.run(action: path, on: input, prompt: prompt)
    }

    /// Apply a leaf action node to a clip (AppController.m:_invokeAction path).
    @MainActor
    static func apply(_ node: ActionNode, to clip: ClipRecord,
                      prompt: JSActionRunner.PromptHandler? = nil) {
        guard let spec = node.action else { return }   // folders aren't invoked
        switch spec.type {
        case ActionStore.builtinType:
            switch spec.name {
            case ActionStore.pasteAsPlainText: BuiltInActions.pasteAsPlainText(clip)
            case ActionStore.pasteAsFilePath:  BuiltInActions.pasteAsFilePath(clip)
            case ActionStore.remove:           BuiltInActions.remove(clip)
            default: break
            }
        case ActionStore.jsType:
            guard let path = spec.path else { return }
            let input = JSClipInput(stringValue: clip.stringValue ?? "",
                                    rtfData: clip.rtfData,
                                    isRTFD: clip.typeIdentifiers.contains("RTFD"))
            guard let outcome = try? JSActionRunner.runDetailed(
                action: path, clip: input, prompt: prompt) else { return }
            paste(outcome)
        default:
            break
        }
    }

    /// Paste a JS action's outcome: a styled RTF/RTFD clip or plain text
    /// (AppController.m:809-815). `.none` ⇒ no change.
    @MainActor
    private static func paste(_ outcome: JSActionOutcome) {
        switch outcome {
        case .string(let text):
            Paster.copy(string: text)
            Paster.paste()
        case .rtf(let data, let rtfd):
            Paster.copy(rtfData: data, isRTFD: rtfd)
            Paster.paste()
        case .none:
            break
        }
    }

    /// Apply a leaf action node to a snippet (index < 0 path: text is the snippet
    /// content; the built-in target is the snippet itself).
    @MainActor
    static func apply(_ node: ActionNode, to snippet: Snippet,
                      prompt: JSActionRunner.PromptHandler? = nil) {
        guard let spec = node.action else { return }
        switch spec.type {
        case ActionStore.builtinType:
            switch spec.name {
            case ActionStore.pasteAsPlainText: BuiltInActions.pasteAsPlainText(snippet: snippet)
            case ActionStore.remove:           BuiltInActions.remove(snippet: snippet)
            default: break
            }
        case ActionStore.jsType:
            guard let path = spec.path else { return }
            let input = JSClipInput(stringValue: snippet.content)
            guard let outcome = try? JSActionRunner.runDetailed(
                action: path, clip: input, prompt: prompt) else { return }
            paste(outcome)
        default:
            break
        }
    }
}
