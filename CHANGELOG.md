# Changelog

Developer-facing notes for ClipMenu. User-facing release notes live in
`app/Sources/ClipMenu/WhatsNewConfig.swift` (shown in the in-app What's New pane).

## Unreleased

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
