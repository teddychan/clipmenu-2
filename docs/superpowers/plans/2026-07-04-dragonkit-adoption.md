# DragonKit Adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ClipMenu 2's bespoke settings shell, About, What's New, Permissions, Uninstall, Updates, Localization, and LoginItem implementations with the shared DragonKit v1.1.0 SwiftPM package, keeping all app feature logic (clipboard, snippets, actions, folder-based backup engine) intact.

**Architecture:** Depend on `teddychan/dragon-kit` at `from: "1.1.0"` (never vendored). App code supplies only content/config (AboutConfig, WhatsNewConfig, permission list, UninstallConfig, pane bodies); DragonKit owns shared layout/behavior. Settings become `SettingsPane` conformers rendered by `SettingsShell` with host-owned selection inside a `DragonSettingsWindowController`, mirroring `dragon-kit/Example/Sources/DragonAppTemplate/AppDelegate.swift`. Localization moves to DragonKit's `L()`/`LocalizationManager` (7 languages, live switching, no restart).

**Tech Stack:** SwiftPM (swift-tools 6.0), Swift 6 language mode, macOS 26, DragonKit 1.1.0, DragonKitUpdates (Sparkle 2) in direct builds only.

---

## Screen → module mapping

| Current (bespoke) | DragonKit replacement | App-supplied config |
|---|---|---|
| `SettingsView` TabView + `SettingsWindowController` (App.swift:305–353, SettingsWindowController.swift) | `SettingsShell` (host-owned selection) + `DragonSettingsWindowController`; root mirrors Example's `SampleSettingsRoot` (`.dragonLocalized()`, panes rebuilt on language change) | Pane list + selection persisted under `PreferenceKeys.settingsSelectedTab` |
| General / Sync & Backup / Menu / Type / Action / Shortcuts pane views (PreferencesPanes.swift, App.swift shortcutsPane) | Each becomes a `SettingsPane` conformer; bodies use `DragonForm` / `DragonSection` / `.dragonAnnotation` | Existing @AppStorage-bound content, unchanged logic |
| `AboutPreferencesView` (PreferencesPanes.swift:500–566) | `AboutSettingsPane` + `AboutContent` | `AboutConfig.swift`: version from Info.plist, links (dragonapp.com/clipmenu, GitHub issues), credits (Teddy Chan / Naotaka Morimoto / MIT), copyright. "Show Setup Guide…" moves to General; "Check for updates" moves to Updates pane |
| *(none — Sparkle showed release notes)* | `WhatsNewSettingsPane` + `WhatsNewContent` | `WhatsNewConfig.swift` with 2.17.0 notes |
| *(none in Settings — onboarding wizard only)* | `PermissionsSettingsPane(permissions: [.accessibility(isRequired: false)])`, direct build only (MAS build cannot use AX paste) | Onboarding wizard untouched |
| `UninstallView.swift` window + `MainMenuController.performUninstall` | App-owned `UninstallPane` (inline confirm, DragonForm look, keeps the app-specific "Also delete clipboard history and snippets" toggle) whose confirm does app-specific cleanup (Application Support, Caches, HTTPStorages) **then** `DragonUninstaller.run(config:)` for the shared teardown | `UninstallConfig(appName:bundleID:checklistItems:)` |
| `Updater.swift` `UpdaterController` (SPUStandardUpdaterController wrapper) | `DragonUpdater` + `UpdatesSettingsPane` (`import DragonKitUpdates`, `#if SPARKLE` only) | `UpdaterUI` facade kept (tests + MAS no-ops), now backed by a shared `DragonUpdater` |
| `Localization.swift` `L()` (process-fixed, restart to change) | DragonKit `L()` + `LocalizationManager` + `LanguagePicker` + `.dragonLocalized()` — **live** switching | `appStringsBundle = AppResources.bundle`; one-time `appLanguage` → `DragonKit.language` migration; AppleLanguages mirror kept |
| `LoginItem.swift` | DragonKit `LoginItem` (same SMAppService semantics) | — |

## Deliberate deviations (flagged, per think-before-coding)

1. **Backup & Restore stays app-owned.** DragonKit's `BackupSettingsPane`/`DragonBackup` snapshots a UserDefaults suite; ClipMenu's v2.15 folder-based snippet backup (.clipbackup versions, retention, security-scoped bookmarks, restore UI, settings sidecar) cannot be expressed by it, and replacing it would delete a shipped feature. Only the pane container is restyled (DragonForm). → dragon-kit roadmap item.
2. **`DragonSettingsStore` not adopted.** ClipMenu's settings are ~40 flat UserDefaults keys bound via @AppStorage and synced by SettingsSidecar/backup; converting to one Codable suite is a feature-logic rewrite, out of scope per constraints.
3. **Uninstall user-data toggle kept in-app.** `UninstallConfig` has no extra-paths/toggle hook; the app pane wraps DragonKit's engine instead of forking it. → dragon-kit enhancement: optional user-data toggle + extra cleanup paths.
4. **Settings window now flips to `.regular` while open** (DragonKit standard). App-side guard re-asserts `.regular` when the snippet editor is still visible after Settings closes (DragonSettingsWindowController is `final` and unconditionally returns to `.accessory`).
5. **Release CI (`teddychan/dragon-release-ci`) must copy all `*.bundle`** (it hardcodes `ClipMenu_ClipMenu.bundle`; DragonKit adds `DragonKit_DragonKit.bundle` with the kit's localized strings). Out-of-repo change, flagged as follow-up. This repo's `scripts/run.sh`, `scripts/run-debug.sh`, `.github/workflows/release-mas.yml` are fixed here.

---

### Task 1: Depend on DragonKit

**Files:** Modify `app/Package.swift`

- [ ] Add `.package(url: "https://github.com/teddychan/dragon-kit", from: "1.1.0")` to base `packageDependencies` and `.product(name: "DragonKit", package: "dragon-kit")` to base `clipMenuDependencies`.
- [ ] Under `if sparkleEnabled`: replace the direct Sparkle package/product with `.product(name: "DragonKitUpdates", package: "dragon-kit")` (it pulls Sparkle transitively). Keep `.define("SPARKLE")` and the rpath linker flag. Update the header comment (offline-resolve claim no longer holds; MAS build still links no Sparkle).
- [ ] Verify: `swift package resolve` succeeds.

### Task 2: Localization migration (biggest churn — compiler-guided)

**Files:** Delete `app/Sources/ClipMenu/Localization.swift`; modify `App.swift`, `Models.swift`, `SnippetEditorView.swift`, `PreferencesPanes.swift`, `OnboardingView.swift`, `OnboardingWindowController.swift`, `AppInfo.swift`, plus `import DragonKit` wherever `L()` is used.

- [ ] Delete `Localization.swift`. Add `import DragonKit` to every file the compiler flags for `L`.
- [ ] `AppDelegate.applicationDidFinishLaunching`: set `LocalizationManager.shared.appStringsBundle = AppResources.bundle`; one-time migration — if `DragonKit.language` is unset, `setLanguage(DragonLanguage(rawValue: defaults.string(forKey: "appLanguage") ?? "en") ?? .en)` (preserves the historical hard-English default). Mirror to `AppleLanguages` on launch and on `.dragonLanguageChanged` (replaces the old mirror block).
- [ ] `Models.swift`: DragonKit's `L` is `@MainActor` — default args in nonisolated inits can't call it. Change defaults to English literals `"untitled folder"` / `"untitled snippet"`, and pass `L(...)` explicitly at the MainActor creation sites (`SnippetEditorView.swift:263`, `:285`, and any derived-title fallback).
- [ ] `GeneralPreferencesView`: replace the bespoke language `Picker` + restart prompt + AppleLanguages `.onChange` with a `LanguagePicker()` row.
- [ ] Onboarding welcome step: bind its styled picker to `LocalizationManager.shared` (`DragonLanguage` selection), drop the relaunch path (`onLanguageChange` plumbing, `AppRelaunch.relaunch()` at OnboardingWindowController.swift:110); apply `.dragonLocalized()` at the wizard root so it re-renders live.
- [ ] `AppDelegate`: observe `.dragonLanguageChanged` → rebuild status-item menu + `NSApp.mainMenu` (StatusItemController gains `update(menu:)`).
- [ ] Verify: `swift build` clean; language switch is live in Settings and menus.

### Task 3: Settings shell + window controller

**Files:** Rewrite `app/Sources/ClipMenu/SettingsWindowController.swift`; modify `App.swift` (delete `SettingsView`/`SettingsTab`, Settings scene → `EmptyView()`); modify `PreferencesPanes.swift` (pane conformers); modify `MainMenuController.swift` (open-specific-pane wiring).

- [ ] Wrap each existing pane view in a `SettingsPane` conformer (`id` values: `general`, `syncBackup`, `menu`, `type`, `action`, `shortcuts`; `title` = existing localization keys; existing SF Symbols). Convert `Form{}.formStyle(.grouped)` → `DragonForm`, `Section` → `DragonSection`.
- [ ] `SettingsWindowController` keeps its name/`shared`/`show()`/`isWindowVisible` API but wraps `DragonSettingsWindowController` + an `@Observable` `paneID` selection persisted to `PreferenceKeys.settingsSelectedTab`; add `show(paneID:)`. Root view mirrors Example's `SampleSettingsRoot` (observes `LocalizationManager`, rebuilds panes, `.dragonLocalized()`, `.modelContainer(AppStore.container)`).
- [ ] Snippet-editor guard: observe `NSWindow.willCloseNotification` for the settings window; async re-assert `.regular` if `SnippetEditorWindowController.shared.isWindowVisible`.
- [ ] `MainMenuController.showAbout` → `SettingsWindowController.shared.show(paneID: "about")`; `showPreferences` → `show()`.
- [ ] Verify: `swift build`; window opens, all panes render, About lands on About.

### Task 4: About + What's New + Permissions panes

**Files:** Create `app/Sources/ClipMenu/AboutConfig.swift`, `app/Sources/ClipMenu/WhatsNewConfig.swift`; modify `PreferencesPanes.swift` (delete `AboutPreferencesView`; General gains "Setup" section with "Show Setup Guide…"); modify `app/Info.plist` (bump to 2.17.0).

- [ ] `AboutConfig.content`: name `AppInfo.displayName`, version from Info.plist (`AppInfo.version`/`build`), copyright `AppInfo.copyright`, links = Website (dragonapp.com/clipmenu) + Support on GitHub (issues), credits = Created by / Original ClipMenu / License.
- [ ] `WhatsNewConfig.content`: v2.17.0 notes (DragonKit shell, live language switching, new Permissions/What's New/Updates panes, inline uninstall).
- [ ] Pane list gains `PermissionsSettingsPane(permissions: [.accessibility(isRequired: false)])` when `DistributionChannel.current != .appStore`, `WhatsNewSettingsPane`, `AboutSettingsPane`.
- [ ] Verify: About shows correct version/links; What's New renders.

### Task 5: Updates over DragonKitUpdates

**Files:** Rewrite `app/Sources/ClipMenu/Updater.swift`; modify `PreferencesPanes.swift` (General loses update rows), pane list (`UpdatesSettingsPane` under `#if SPARKLE`), `MainMenuController.swift` (menu item unchanged, backed by facade).

- [ ] `#if SPARKLE`: `import DragonKitUpdates`; `UpdaterUI` gains `static let updater = DragonUpdater()`; `start()` touches it so scheduled checks begin at launch; `checkNow()` = `updater.checkForUpdates()`; `isSupported` unchanged. Delete `UpdaterController`.
- [ ] Add `AnySettingsPane(UpdatesSettingsPane(updater: UpdaterUI.updater))` under `#if SPARKLE`.
- [ ] Verify: `CLIPMENU_SPARKLE=1 swift build` and plain `swift build` both pass; `swift test` (UpdaterUITests) passes.

### Task 6: Uninstall

**Files:** Delete `app/Sources/ClipMenu/UninstallView.swift`; create `UninstallPane` (own file); modify `MainMenuController.swift`.

- [ ] `UninstallPane: SettingsPane` (id `uninstall`, icon `trash`): DragonForm-styled inline confirm — checklist (3 existing items), the "Also delete clipboard history and snippets" toggle, permissions note, red Uninstall + Cancel (`onCancel` → back to `general`).
- [ ] Confirm action: app-specific cleanup first (Application Support per toggle, Caches, HTTPStorages — logic moved verbatim from `MainMenuController.performUninstall`), then `DragonUninstaller.run(config:)` (login item, defaults domains, plists + post-exit cleanup, Trash, terminate).
- [ ] Menu "Uninstall …" item → `SettingsWindowController.shared.show(paneID: "uninstall")`; delete `performUninstall`/`uninstall` window path.
- [ ] Verify: build; pane renders; **no live uninstall run** (destructive) — code-review the path instead.

### Task 7: LoginItem

**Files:** Delete `app/Sources/ClipMenu/LoginItem.swift`.

- [ ] Delete; call sites (`App.swift`, `PreferencesPanes.swift`, onboarding) resolve to DragonKit's identical `LoginItem` via `import DragonKit`.
- [ ] Verify: `swift build`.

### Task 8: Bundle-assembly scripts + MAS CI

**Files:** Modify `app/scripts/run.sh`, `app/scripts/run-debug.sh`, `.github/workflows/release-mas.yml`.

- [ ] Generalize the single hardcoded `ClipMenu_ClipMenu.bundle` copy to copy every `*.bundle` in the SwiftPM bin dir (ClipMenu + DragonKit resource bundles); MAS workflow: give **each** nested bundle a CFBundleIdentifier (validator 90276).
- [ ] Flag `dragon-release-ci` follow-up (external repo).
- [ ] Verify: `./scripts/run-debug.sh` produces an app whose `Contents/Resources` holds both bundles; DragonKit pane titles show localized (not raw `DragonKit.pane.*` keys).

### Task 9: Full verification + commits

- [ ] `swift build && swift test` (both with and without `CLIPMENU_SPARKLE=1`).
- [ ] `app/scripts/run-debug.sh` smoke test: menu bar icon, Settings panes, About pane, live language switch, menu rebuild.
- [ ] Commit per task; do **not** push / open a PR without owner confirmation.
