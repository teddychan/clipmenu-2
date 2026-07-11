# Changelog

Developer-facing notes for ClipMenu. User-facing release notes live in
`app/Sources/ClipMenu/WhatsNewConfig.swift` (shown in the in-app What's New pane).

## Unreleased

### Tests & coverage — phase 2 (SwiftUI + reorder + backup/restore)

Pushed coverage from the logic layer into the SwiftUI/UI layer and the
drag-reorder ("layout movement") and backup/restore code.

- **Test cases: 313 → 374** (+61), across **53 → 59** test files.
- **Line coverage: 39.3% → 74.2%** overall (region 45.8% → 67.3%, function 67.3%).
- **Backup & restore → 100%** (all in ClipMenu's `Premium/`, not DragonKit):
  `BackupManager`, `BackupModels`, `BackupFolder` at 100%; `FolderBackupStore` 97%,
  `BackupRetention` 97%, `SnippetSnapshot` 93%, `SettingsSidecar` 95%. Restore
  error paths (undecodable payload, newer-schema rejection) and the restore UI
  (`RestoreVersionsView`) are covered.
- **Layout movement (drag-reorder):** extracted the snippet editor's reorder /
  index-renumber arithmetic out of `SnippetEditorView` into a pure, testable
  `ManualReorder` helper (`moved` / `afterRemoving` / `nextIndex`) — now **100%**;
  `SnippetEditorView` 0% → 59%.
- **SwiftUI panes via ViewInspector** (new test-only dependency, `ClipMenuTests`
  target only — never linked by the app): `PreferencesPanes` 0% → 76% (incl. the
  Sync & Backup pane), `OnboardingView` 0% → 88%, `MainMenuController` 61%.
- **Test execution is now serial.** Run the suite with `app/scripts/test.sh`
  (wraps `swift test --arch arm64 --no-parallel`). Several suites exercise
  process-global singletons (`NSPasteboard.general`, the shared UserDefaults backup
  baseline); Swift Testing's default cross-suite parallelism races them, and
  `.serialized` only orders tests within a suite — so the canonical run is serial.
- Still not unit-testable (need a running `NSApplication` / real system state):
  window `show()` hosting (`SettingsWindowController`, the window controllers), the
  `@main`/AppDelegate lifecycle (`App`), Carbon hot-key registration, and the
  fire-and-forget backup `Task` against the live store — these are the bulk of the
  remaining ~26%.

### Tests & coverage

Expanded the unit-test suite (Swift Testing) to lock down the app's logic layer.

- **Test cases: 147 → 313** (+166), across **29 → 53** test files. All green.
- **Line coverage: 18.8% → 39.3%** overall (region 21.6% → 37.6%), measured with
  `swift test --enable-code-coverage` + `xcrun llvm-cov`.
- The **non-UI logic layer is now near-exhaustively covered** — 24 source files at
  ≥93%, including:
  - `ClipCapture` (clipboard capture, dedup, trim, thumbnails) 49% → **98.8%**
  - `ActionStore` 65% → **97.9%**, `ScriptableClip` 62% → **97.8%**
  - `ActionEngine` 8% → **93.2%**, `BuiltInActions`, `Paster`, `HotKeyCenter` (pure logic)
  - `MainMenuController` (NSMenu building) 5.8% → **60.9%**
  - `Thumbnailer`, `MenuIconCache`, `StatusItemController` 0% → **95–98%**
  - Backup/premium stack (`BackupManager`, `FolderBackupStore`, `BackupRetention`,
    `BackupModels`, `BackupScheduler`) and `StoreMigration`
  - `HistoryExport`, `Updater`, `AboutConfig`, `WhatsNewConfig`, `DistributionChannel` at **100%**
- New characterization tests assert real behavior only (menu trees, pasteboard
  contents, dedup/thumbnail derivation, Codable round-trips, Carbon⇄Cocoa key
  formatting); no source code was modified.

**Coverage ceiling (documented, not a gap to chase):** the remaining ~60% is code
a headless `swift test` process cannot execute — pure SwiftUI view bodies
(`PreferencesPanes`, `SnippetEditorView`, `OnboardingView`), the `@main`/AppDelegate
lifecycle and window `show()` hosting, and system side-effects (live `CGEvent`
paste, Carbon hot-key registration, cursor-anchored pop-ups). Covering the SwiftUI
views would need the ViewInspector test dependency (~65% ceiling); true ~90% would
require an XCUITest UI-automation target driving a launched app.
