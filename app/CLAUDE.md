> General engineering principles (Think Before Coding, Simplicity First, Surgical
> Changes, Goal-Driven Execution) live in the root `CLAUDE.md` and apply here too.
> This file adds the Swift/app-specific conventions below.

# swift-conventions.md — HOW to build /app

These are engineering conventions (the HOW). They don't decide WHAT the app does —
product direction comes from you. `/legacy` is optional historical reference only,
not a constraint (see root CLAUDE.md).

> Install: save this as `app/CLAUDE.md` so Claude Code auto-loads it inside `/app`,
> OR keep this filename and add a line `@swift-conventions.md` to the root `CLAUDE.md`.

---

## 1. Swift 6 & strict concurrency
- Compile with the Swift 6 language mode; **zero** concurrency warnings is the bar.
- UI types and anything touching AppKit are `@MainActor`. Keep the main actor light.
- Cross-actor values must be `Sendable`. Make model/value types `struct` + `Sendable`.
- Use structured concurrency (`async`/`await`, `Task`, `TaskGroup`). Avoid `DispatchQueue`
  except at C-API boundaries (Carbon, CoreGraphics callbacks) where a run loop is required.
- Only reach for `@preconcurrency` / `nonisolated(unsafe)` when wrapping a legacy C API,
  and isolate that wrapping in one small, commented type — never sprinkle it around.
- No shared mutable global state. Owners are actors or `@MainActor` singletons.

## 2. AppKit vs SwiftUI boundaries
- **SwiftUI** owns the `Settings` scene (one tab per legacy preference tab in SPEC.md).
- **AppKit** owns everything menu/event related:
  - `NSStatusItem` for the menu-bar icon.
  - The history/snippet pop-up is an `NSMenu` shown at the cursor via
    `popUp(positioning:at:in:)`. **Do not** try to do the cursor pop-up with
    `MenuBarExtra` — it can only drop down from the menu bar, not appear at the mouse.
  - Prefer a plain `NSStatusItem` + `NSMenu` over `MenuBarExtra` for full control and lower
    overhead (MenuBarExtra can't do the cursor pop-up we need).
- Bridge SwiftUI settings ↔ a `@MainActor` model object; persist via `UserDefaults`
  (or SwiftData), keeping existing preference keys/defaults stable unless intentionally changing them.

## 3. Clipboard monitoring (the main performance lever)
- macOS has **no clipboard-change notification.** Poll `NSPasteboard.general.changeCount`.
- Polling rules:
  - Run the poll off the main actor (a dedicated actor or background `Task` loop).
  - Start at a **0.25–0.5s** interval; justify any change. Don't busy-loop.
  - Read pasteboard data **only when `changeCount` actually changed** — never every tick.
  - Coalesce: if several types are present, capture per SPEC.md's recorded-type list only.
  - De-dupe consecutive identical clips (match legacy behavior on this).
  - Respect the legacy ignore/exclusion rules before recording.
- Never block the main actor reading or hashing large pasteboard payloads.

## 4. Images & memory
- Never keep full-size images alive for the menu. On capture, generate a **downsampled
  thumbnail** with `CGImageSourceCreateThumbnailAtIndex`
  (`kCGImageSourceCreateThumbnailFromImageAlways` + `kCGImageSourceThumbnailMaxPixelSize`),
  sized to the legacy menu image dimensions from SPEC.md.
- Store the thumbnail for display; store/reference the original separately and lazy-load
  only when the item is actually pasted.
- Cap history to the configured count; evict oldest beyond it. Watch total memory.

## 5. Global hotkeys (Carbon wrapper)
- No first-party Swift global-hotkey API exists. Wrap Carbon `RegisterEventHotKey` +
  `InstallEventHandler` in one small `@MainActor` type.
- The Carbon callback is a bare C function pointer (no captured context). Route it back to
  your Swift handler via a registry keyed by `EventHotKeyID`, not captured closures.
- Unregister on deinit. Keep the hotkey IDs/modifiers mapped to SPEC.md's defaults.

## 6. Paste synthesis & permissions (modern-OS reality)
- To paste into the frontmost app, set `NSPasteboard.general` then synthesize ⌘V with
  `CGEvent` (keycode `9` = V, with `.maskCommand`) posted to `.cghidEventTap`.
- This requires **Accessibility (TCC) permission**. Check `AXIsProcessTrusted()`; if not
  trusted, prompt the user to enable it (don't fail silently).
- If legacy restores the previous pasteboard contents after pasting, replicate that
  save→set→paste→restore sequence exactly.

## 7. Persistence (SwiftData)
- Model the snippet/history schema from SPEC.md (mirror the legacy `.xcdatamodel` shape).
- `ModelContainer` is `Sendable`; `ModelContext` is **not** — do background writes through a
  `ModelActor`, never share a context across actors.
- Don't store large binary blobs inline if it hurts performance; prefer external storage /
  file references for originals, keep thumbnails light.

## 8. App configuration
- Agent app: `LSUIElement = true` (no Dock icon), per CLAUDE.md.
- Login item via `SMAppService.mainApp` (register/unregister) — not the deprecated APIs.
- Hardened runtime + notarization for distribution; minimal entitlements; sandbox if MAS
  is in scope (note any sandbox limitation that affects parity in OPEN-QUESTIONS.md).

## 9. Code style & quality
- Logging via `os.Logger` with subsystem/category. **No `print`.**
- No force-unwraps (`!`) in event/poll/paste hot paths; handle the `nil`/error case.
- Small, single-responsibility types. Name things after what SPEC.md calls them.
- Add a unit test for any pure transform (e.g. the "Actions" text transforms) so behavior is
  pinned by a test, not by inspection.

## 10. Per-feature checklist
- [ ] Strict-concurrency clean (no warnings).
- [ ] Main actor stays light; heavy work is off-main.
- [ ] Images downsampled; no full-size retention for the menu.
- [ ] One logical change per commit, with a clear message.

